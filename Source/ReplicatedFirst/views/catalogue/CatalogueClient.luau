--!strict

--[[
	CatalogueClient (client, Pattern A — no server component)

	Searches the Roblox catalogue directly from this client
	(AvatarEditorService:SearchCatalog), so each player browses on their own
	rate-limit budget instead of sharing the server's (a few active browsers
	would exhaust one shared budget; see PLAN.md open question 10). Item
	try-on is still validated by the server (Task 5).

	  search(query)      first page for a query (yields); cached per query
	  loadMore(query)    next page appended to that query's results (yields)
	  item(id)           any item this client has seen, by id
	  similar(item, n)   up to n seen items from the same category
	  parseLink(text)    target id + kind from a marketplace link or bare id
	  lookup(id, kind?)  one item by its real id (yields); a nil kind tries an
	                     asset, then a bundle. Fails for non-avatar items.
	  remember(worn)     the item for a worn entry ({ targetId, kind,
	                     typeName, name, owned? } from the Avatar state): a
	                     stub straight away if unseen, filled in from the
	                     catalogue in the background
	  changed            signal: a remembered item's details arrived

	Item ids: assets keep their asset id; bundles are negated (-bundleId), as
	asset and bundle ids can collide. `targetId` + `kind` carry the real id.

	When the catalogue throttles us (HTTP 429) every call waits out
	CatalogueConfig.backoffSeconds and retries once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

local CatalogueConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CatalogueConfig"))

local CatalogueClient = {}

export type Item = {
	id: number,
	kind: "Asset" | "Bundle",
	targetId: number,
	name: string,
	main: string, -- top-level category (CatalogueConfig.categories[].name)
	sub: string, -- chip name within it
	typeName: string, -- AvatarAssetType / BundleType name
	price: number, -- Robux to buy now; for a sold-out Limited, its lowest resale
	limited: boolean, -- Limited / collectible
	resale: boolean, -- `price` is the lowest resale price
	creator: string,
	description: string,
	favourites: number,
	thumbnail: string,
	colour: string, -- dominant colour name; "" until ItemColour has read the thumbnail
	colours: { string }, -- every colour with a big enough share (ItemColour)
	owned: boolean, -- false until ownership checks land (Task 11)
}

export type Query = {
	category: string,
	chip: string?, -- nil = "All"
	-- Search these type names instead of the category/chip's (e.g. every
	-- wearable at once); category/chip are then just labels.
	types: { assetTypes: { string }?, bundleTypes: { string }? }?,
	keyword: string?,
	minPrice: number?, -- Robux; nil = no bound
	maxPrice: number?,
	sort: string?, -- Enum.CatalogSortType name; nil = CatalogueConfig.sort
	sortWindow: string?, -- Enum.CatalogSortAggregation name; nil = CatalogueConfig.sortAggregation
	creator: string?, -- creator name; nil / "" = anyone
	salesType: string?, -- Enum.SalesTypeFilter name; nil = All
	includeOffSale: boolean?, -- nil = CatalogueConfig.includeOffSale
}

export type Result = {
	items: { Item },
	exhausted: boolean, -- no more pages
}

type Entry = {
	items: { Item },
	pages: CatalogPages?,
	exhausted: boolean,
	fetchedAt: number,
}

-- typeName -> where it sits in the menu (first chip that lists it).
local placement: { [string]: { main: string, sub: string } } = {}
for _, category in CatalogueConfig.categories do
	for _, chip in category.chips do
		for _, name in chip.assetTypes or {} do
			placement[name] = placement[name] or { main = category.name, sub = chip.name }
		end
		for _, name in chip.bundleTypes or {} do
			placement[name] = placement[name] or { main = category.name, sub = chip.name }
		end
	end
end

local seen: { [number]: Item } = {}

local changedEvent = Instance.new("BindableEvent")
CatalogueClient.changed = changedEvent.Event
local cache: { [string]: Entry } = {}
local blockedUntil = 0

local function enumItems(enum: Enum, names: { string }, into: { EnumItem })
	for _, name in names do
		local ok, value = pcall(function()
			return (enum :: any)[name]
		end)
		if ok and value then
			table.insert(into, value)
		else
			warn(`[CatalogueClient] Unknown {enum} "{name}" in CatalogueConfig`)
		end
	end
end

local function chipsFor(query: Query): { any }
	for _, category in CatalogueConfig.categories do
		if category.name == query.category then
			if query.chip == nil then
				return category.chips
			end
			for _, chip in category.chips do
				if chip.name == query.chip then
					return { chip }
				end
			end
		end
	end
	error(`[CatalogueClient] Unknown category/chip {query.category}/{tostring(query.chip)}`)
end

local function paramsFor(query: Query): CatalogSearchParams
	local assetTypes, bundleTypes = {}, {}
	if query.types then
		enumItems(Enum.AvatarAssetType, query.types.assetTypes or {}, assetTypes)
		enumItems(Enum.BundleType, query.types.bundleTypes or {}, bundleTypes)
	else
		for _, chip in chipsFor(query) do
			enumItems(Enum.AvatarAssetType, chip.assetTypes or {}, assetTypes)
			enumItems(Enum.BundleType, chip.bundleTypes or {}, bundleTypes)
		end
	end
	local params = CatalogSearchParams.new()
	params.AssetTypes = assetTypes :: any
	params.BundleTypes = bundleTypes :: any
	params.SearchKeyword = query.keyword or ""
	params.SortType = (Enum.CatalogSortType :: any)[query.sort or CatalogueConfig.sort]
	params.SortAggregation = (Enum.CatalogSortAggregation :: any)[query.sortWindow or CatalogueConfig.sortAggregation]
	params.SalesTypeFilter = (Enum.SalesTypeFilter :: any)[query.salesType or "All"]
	params.IncludeOffSale = if query.includeOffSale ~= nil then query.includeOffSale else CatalogueConfig.includeOffSale
	params.CreatorName = query.creator or ""
	if query.minPrice then
		params.MinPrice = query.minPrice
	end
	if query.maxPrice then
		params.MaxPrice = query.maxPrice
	end
	params.Limit = CatalogueConfig.pageSize
	return params
end

local function keyFor(query: Query): string
	return table.concat({
		query.category,
		query.chip or "All",
		if query.types then table.concat(query.types.assetTypes or {}, ",") .. "/" .. table.concat(query.types.bundleTypes or {}, ",") else "",
		string.lower(query.keyword or ""),
		tostring(query.minPrice),
		tostring(query.maxPrice),
		query.sort or "",
		query.sortWindow or "",
		string.lower(query.creator or ""),
		query.salesType or "",
		tostring(query.includeOffSale),
	}, "|")
end

local function typeNameOf(value: any): string
	-- Results carry the type as a string or an EnumItem depending on the field.
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	return tostring(value)
end

-- What it costs to buy now. A Limited (collectible) whose original stock has
-- sold out reports Price 0; its real price is the lowest resale.
local function priceOf(raw: any): (number, boolean, boolean)
	local limited = false
	for _, restriction in raw.ItemRestrictions or {} do
		local name = tostring(restriction)
		if name == "Collectible" or name == "Limited" or name == "LimitedUnique" then
			limited = true
		end
	end
	local base = raw.Price or 0
	local lowest = raw.LowestPrice or raw.LowestResalePrice or 0
	if limited then
		local units = raw.UnitsAvailableForConsumption
		local soldOut = units ~= nil and units <= 0
		if (soldOut or base <= 0) and lowest > 0 then
			return lowest, true, true
		end
	end
	return if base > 0 then base else math.max(lowest, 0), limited, false
end

local function toItem(raw: any): Item
	local isBundle = raw.ItemType == "Bundle" or raw.ItemType == Enum.AvatarItemType.Bundle
	local typeName = typeNameOf(if isBundle then raw.BundleType else raw.AssetType)
	local where = placement[typeName] or { main = "", sub = typeName }
	local size = CatalogueConfig.thumbnailSize
	local price, limited, resale = priceOf(raw)
	local item: Item = {
		id = if isBundle then -raw.Id else raw.Id,
		kind = if isBundle then "Bundle" else "Asset",
		targetId = raw.Id,
		name = raw.Name,
		main = where.main,
		sub = where.sub,
		typeName = typeName,
		price = price,
		limited = limited,
		resale = resale,
		creator = raw.CreatorName or "",
		description = raw.Description or "",
		favourites = raw.FavoriteCount or 0,
		thumbnail = `rbxthumb://type={if isBundle then "BundleThumbnail" else "Asset"}&id={raw.Id}&w={size}&h={size}`,
		colour = "",
		colours = {},
		owned = false,
	}
	-- Keep the existing object, so anything holding it stays current (and
	-- keep colours ItemColour has already worked out).
	local existing = seen[item.id]
	if existing then
		for k, v in item :: any do
			if k ~= "colour" and k ~= "colours" then
				(existing :: any)[k] = v
			end
		end
		return existing
	end
	seen[item.id] = item
	return item
end

local function appendPage(entry: Entry, page: { any })
	local have = {}
	for _, item in entry.items do
		have[item.id] = true
	end
	for _, raw in page do
		local item = toItem(raw)
		if not have[item.id] then
			have[item.id] = true
			table.insert(entry.items, item)
		end
	end
end

-- Runs a catalogue call, waiting out (and retrying once after) a throttle.
local function call<T>(fn: () -> T): (boolean, T | string)
	for attempt = 1, 2 do
		local wait = blockedUntil - os.clock()
		if wait > 0 then
			task.wait(wait)
		end
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		local message = tostring(result)
		if string.find(message, "429", 1, true) and attempt == 1 then
			blockedUntil = os.clock() + CatalogueConfig.backoffSeconds
		else
			return false, message
		end
	end
	return false, "throttled"
end

local function result(entry: Entry): Result
	return { items = entry.items, exhausted = entry.exhausted }
end

-- First page for a query. Yields; returns (ok, Result or error message).
function CatalogueClient.search(query: Query): (boolean, Result | string)
	local key = keyFor(query)
	local cached = cache[key]
	if cached and os.clock() - cached.fetchedAt < CatalogueConfig.cacheSeconds then
		return true, result(cached)
	end
	local params = paramsFor(query)
	local ok, pages = call(function()
		return AvatarEditorService:SearchCatalog(params)
	end)
	if not ok then
		return false, pages :: string
	end
	local catalogPages = pages :: CatalogPages
	local entry: Entry = { items = {}, pages = catalogPages, exhausted = catalogPages.IsFinished, fetchedAt = os.clock() }
	appendPage(entry, catalogPages:GetCurrentPage())
	cache[key] = entry
	return true, result(entry)
end

-- Appends the next page to a query already searched. Yields.
function CatalogueClient.loadMore(query: Query): (boolean, Result | string)
	local entry = cache[keyFor(query)]
	if not entry or not entry.pages then
		return CatalogueClient.search(query)
	end
	if entry.exhausted then
		return true, result(entry)
	end
	local pages = entry.pages :: CatalogPages
	local ok, err = call(function()
		pages:AdvanceToNextPageAsync()
		return true
	end)
	if not ok then
		return false, err :: string
	end
	appendPage(entry, pages:GetCurrentPage())
	entry.exhausted = pages.IsFinished
	return true, result(entry)
end

-- Marketplace links ("roblox.com/catalog/123/…", "roblox.com/bundles/45/…")
-- or a bare id. A bare id's kind is unknown (nil): lookup tries both.
function CatalogueClient.parseLink(text: string): (number?, ("Asset" | "Bundle")?)
	local lowered = string.lower(text)
	local asset = string.match(lowered, "/catalog/(%d+)")
	if asset then
		return tonumber(asset), "Asset"
	end
	local bundle = string.match(lowered, "/bundles/(%d+)")
	if bundle then
		return tonumber(bundle), "Bundle"
	end
	local bare = string.match(lowered, "^%s*(%d+)%s*$")
	if bare then
		return tonumber(bare), nil
	end
	return nil, nil
end

-- One item by its real id. Yields; returns (ok, Item or error message).
function CatalogueClient.lookup(targetId: number, kind: ("Asset" | "Bundle")?): (boolean, Item | string)
	local kinds: { "Asset" | "Bundle" } = if kind then { kind } else { "Asset", "Bundle" }
	local lastError = "not found"
	for _, k in kinds do
		local known = seen[if k == "Bundle" then -targetId else targetId]
		if known then
			return true, known
		end
		local itemType = if k == "Bundle" then Enum.AvatarItemType.Bundle else Enum.AvatarItemType.Asset
		local ok, raw = call(function()
			return AvatarEditorService:GetItemDetails(targetId, itemType)
		end)
		if ok then
			local details = raw :: any
			details.Id = details.Id or targetId
			details.ItemType = k
			local item = toItem(details)
			if item.main ~= "" then
				return true, item
			end
			lastError = "not an avatar item"
		else
			lastError = raw :: string
		end
	end
	return false, lastError
end

-- An item for something the player is wearing, which this client may never
-- have seen in a search (e.g. from their own avatar). Returns at once.
function CatalogueClient.remember(worn: { targetId: number, kind: "Asset" | "Bundle", typeName: string, name: string, owned: boolean? }): Item
	local id = if worn.kind == "Bundle" then -worn.targetId else worn.targetId
	local known = seen[id]
	if known then
		if worn.owned then
			known.owned = true
		end
		return known
	end
	local where = placement[worn.typeName] or { main = "", sub = worn.typeName }
	local size = CatalogueConfig.thumbnailSize
	local item: Item = {
		id = id,
		kind = worn.kind,
		targetId = worn.targetId,
		name = if worn.name ~= "" then worn.name else worn.typeName,
		main = where.main,
		sub = where.sub,
		typeName = worn.typeName,
		price = 0,
		limited = false,
		resale = false,
		creator = "",
		description = "",
		favourites = 0,
		thumbnail = `rbxthumb://type={if worn.kind == "Bundle" then "BundleThumbnail" else "Asset"}&id={worn.targetId}&w={size}&h={size}`,
		colour = "",
		colours = {},
		owned = worn.owned == true,
	}
	seen[id] = item
	-- Fill in price, creator and the rest (updates this same object).
	task.spawn(function()
		local itemType = if worn.kind == "Bundle" then Enum.AvatarItemType.Bundle else Enum.AvatarItemType.Asset
		local ok, raw = call(function()
			return AvatarEditorService:GetItemDetails(worn.targetId, itemType)
		end)
		if ok then
			local details = raw :: any
			details.Id = details.Id or worn.targetId
			details.ItemType = worn.kind
			toItem(details)
			if worn.owned then
				item.owned = true -- toItem resets it; ownership checks are Task 11
			end
			changedEvent:Fire()
		end
	end)
	return item
end

-- Several items by their real ids, in two batch calls at most (assets,
-- bundles). Yields; returns the ones found, keyed by catalogue id (a
-- bundle's negated). Ones already seen in a search come from the cache.
function CatalogueClient.lookupMany(refs: { { kind: "Asset" | "Bundle", targetId: number } }): { [number]: Item }
	local found: { [number]: Item } = {}
	local wanted: { [string]: { number } } = { Asset = {}, Bundle = {} }
	for _, ref in refs do
		local id = if ref.kind == "Bundle" then -ref.targetId else ref.targetId
		local known = seen[id]
		if known and known.main ~= "" then
			found[id] = known
		else
			table.insert(wanted[ref.kind], ref.targetId)
		end
	end
	for kind, ids in wanted do
		if #ids == 0 then
			continue
		end
		local itemType = if kind == "Bundle" then Enum.AvatarItemType.Bundle else Enum.AvatarItemType.Asset
		local ok, raw = call(function()
			return AvatarEditorService:GetBatchItemDetails(ids, itemType)
		end)
		if not ok or type(raw) ~= "table" then
			warn("[CatalogueClient] batch lookup failed:", raw)
			continue
		end
		for _, details in raw :: { any } do
			if type(details) == "table" and details.Id then
				details.ItemType = kind
				local item = toItem(details)
				if item.main ~= "" then
					found[item.id] = item
				end
			end
		end
	end
	return found
end

function CatalogueClient.item(id: number): Item?
	return seen[id]
end

function CatalogueClient.similar(item: Item, count: number): { Item }
	local sameSub, sameMain = {}, {}
	for _, other in seen do
		if other.id ~= item.id and other.main == item.main then
			table.insert(if other.sub == item.sub then sameSub else sameMain, other)
		end
	end
	local list = {}
	for _, group in { sameSub, sameMain } do
		for _, other in group do
			if #list >= count then
				return list
			end
			table.insert(list, other)
		end
	end
	return list
end

return CatalogueClient
