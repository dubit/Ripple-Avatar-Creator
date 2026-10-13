--!strict

--[[
	StoresService (loop-based: flushes counts every FLUSH_SECONDS)

	Stores players make, for everyone, across servers. A store is a
	curated set of catalogue items and outfits, kept as a shared record
	(SharedContentService, kind "store") under a 6-character code from the
	same pool as outfits. Unlike an outfit's frozen copy, a store is edited
	in place: its code, visits and favourites stay with it for good.

		{ kind = "store", ownerId, ownerName, created, updated, name,
		  items = { { targetId, kind, typeName, name } },   in the order added
		  outfits = { code },          Community outfits (their own codes)
		  published, publishedAt?, visits, favourites,
		  sales = { ["Asset:123"] = n },   bought through this store
		  hidden?, hiddenReason? }

	An unpublished store is a draft: only its owner can open it. Publishing
	needs StoresConfig.minItems items.

	Names are 3–30 characters (StoresConfig.nameLength), must pass Roblox
	text filtering unchanged, and are unique (StoreNames store, keyed by the
	lowercased name), so a store can be found by its exact name. A name is
	freed when its store is renamed or deleted.

	Ordering: three rankings (RankedPages) of published stores:
	  · StoresPopular   total visits
	  · StoresTopRated  favourites (the store's star, like Community outfits)
	  · StoresNewest    first publish time
	Visits, favourites and sales are counted per server and written every
	FLUSH_SECONDS (and on shutdown). StoresController decides what counts (a
	visit once a day per player, never the owner's).

	A store page (view) puts the store's items into sections, from
	StoresConfig: Featured (the first items), New arrivals (the latest
	added), Bestsellers (most bought through the store, then most
	favourited on Roblox) and rule-based Collections (price, category,
	types). Item details come from Roblox (AvatarEditorService, batched and
	cached for DETAIL_SECONDS); pages are cached per server for
	VIEW_SECONDS, and dropped when this server edits the store.

	Moderation: as Community. Players report a store (once each,
	SharedContentService.report); at REPORTS_TO_HIDE it's hidden (off every
	list; its owner still sees it) until an admin restores it. Admins
	(CommunityService.isAdmin) hide, restore or take down (delete) by code.

	API:
		cleanName(player, text) -> (string?, string?)   the name, or why not
		create(player, name) -> (string?, string?)      a new draft's code,
		                                        or why not ("taken", "busy")
		rename(code, ownerId, name) -> string?          nil, or why not
		edit(code, ownerId, fn) -> record?      change a store in place (its
		                                        owner only); `fn` returns
		                                        false to leave it
		publish(code, ownerId) -> string?       nil, or why not
		unpublish(code, ownerId) -> boolean
		delete(code, ownerId?) -> boolean       nil ownerId: admin takedown
		hide(code, reason) / restore(code)
		countVisit(code) / countFavourite(code, delta) / countSales(code, keys)
		flush()
		page(sort, index) -> ({ string }, boolean)   "popular" | "toprated"
		                                        | "newest"
		cards(codes, viewer) -> { Card }        visible ones only (a viewer's
		                                        own drafts included)
		view(code, viewer) -> Page?             nil if it can't be opened
		findByName(text) -> string?             a published store's code
		report(player, code) -> boolean
		isStore(record) / isListed(record) -> boolean
]]

local AvatarEditorService = game:GetService("AvatarEditorService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedContentService = require(script.Parent.SharedContentService)
local CommunityService = require(script.Parent.CommunityService)
local RankedPages = require(script.Parent.RankedPages)

local StoresConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoresConfig"))
local CatalogueConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CatalogueConfig"))

local StoresService = {}

export type Item = { targetId: number, kind: "Asset" | "Bundle", typeName: string, name: string }

export type Card = {
	code: string,
	name: string,
	by: string,
	mine: boolean,
	published: boolean,
	hidden: boolean, -- only ever true on the owner's own card
	visits: number,
	favourites: number,
	itemCount: number,
	preview: { Item }, -- the first few items, for the card's thumbnails
}

export type Section = { name: string, items: { number } } -- indices into Page.items

export type Page = {
	code: string,
	name: string,
	by: string,
	ownerId: number,
	mine: boolean,
	published: boolean,
	hidden: boolean,
	visits: number,
	favourites: number,
	items: { Item },
	outfits: { CommunityService.Card },
	featured: { number },
	bestsellers: { number },
	newArrivals: { number },
	collections: { Section },
}

local FLUSH_SECONDS = 60
local REPORTS_TO_HIDE = 3
local PREVIEW_ITEMS = 4
local VIEW_SECONDS = 60
local DETAIL_SECONDS = 600
local DETAIL_BATCH = 50

local RANKINGS = {
	popular = "StoresPopular",
	toprated = "StoresTopRated",
	newest = "StoresNewest",
}

local names: DataStore? = nil
local pending: { [string]: { visits: number, favourites: number, sales: { [string]: number } } } = {}
local views: { [string]: { page: Page, at: number } } = {}
local details: { [string]: { price: number?, favourites: number, at: number } } = {}

-- CatalogueConfig category name -> its asset / bundle type names.
local categoryTypes: { [string]: { assets: { [string]: boolean }, bundles: { [string]: boolean } } } = {}
for _, category in CatalogueConfig.categories do
	local types = { assets = {}, bundles = {} }
	for _, chip in category.chips do
		for _, name in (chip :: any).assetTypes or {} do
			types.assets[name] = true
		end
		for _, name in (chip :: any).bundleTypes or {} do
			types.bundles[name] = true
		end
	end
	categoryTypes[category.name] = types
end

local function keyOf(item: Item): string
	return item.kind .. ":" .. item.targetId
end

local function nameStore(): DataStore?
	if names == nil then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore("StoreNames")
		end)
		if ok then
			names = result
		else
			warn("[StoresService] No StoreNames DataStore:", result)
		end
	end
	return names
end

local function nameKey(name: string): string
	return string.lower((string.gsub(name, "%s+", " ")))
end

function StoresService.isStore(record: any): boolean
	return type(record) == "table" and record.kind == "store"
end

function StoresService.isListed(record: any): boolean
	return StoresService.isStore(record) and record.published == true and record.hidden ~= true
end

local function canSee(record: any, viewer: Player?): boolean
	if not StoresService.isStore(record) then
		return false
	end
	if viewer and record.ownerId == viewer.UserId then
		return true
	end
	return StoresService.isListed(record)
end

-- Rankings ------------------------------------------------------------------

local function delist(code: string)
	for _, name in RANKINGS do
		RankedPages.remove(name, code)
		RankedPages.forget(name)
	end
end

local function relist(code: string, record: any)
	RankedPages.set(RANKINGS.newest, code, tonumber(record.publishedAt) or os.time())
	RankedPages.set(RANKINGS.popular, code, tonumber(record.visits) or 0)
	RankedPages.set(RANKINGS.toprated, code, tonumber(record.favourites) or 0)
	for _, name in RANKINGS do
		RankedPages.forget(name)
	end
end

-- Names ---------------------------------------------------------------------

function StoresService.cleanName(player: Player, text: any): (string?, string?)
	if type(text) ~= "string" then
		return nil, "bad"
	end
	local name = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	name = string.gsub(name, "%s+", " ")
	local length = utf8.len(name) or #name
	if length < StoresConfig.nameLength.min or length > StoresConfig.nameLength.max then
		return nil, "length"
	end
	local filtered = SharedContentService.filterName(player, name)
	if filtered == nil then
		return nil, "busy"
	end
	if filtered ~= name then
		return nil, "filtered"
	end
	return name, nil
end

-- Claim a name for a store. A name held by a store that's gone (or since
-- renamed) is free again.
local function claimName(name: string, code: string): string?
	local ds = nameStore()
	if not ds then
		return "busy"
	end
	local key = nameKey(name)
	local ok, holder = pcall(function()
		return ds:GetAsync(key)
	end)
	if not ok then
		return "busy"
	end
	if holder and holder ~= code then
		local record = SharedContentService.lookup(holder)
		if StoresService.isStore(record) and nameKey(tostring(record.name)) == key then
			return "taken"
		end
	end
	local taken = false
	local updated = pcall(function()
		ds:UpdateAsync(key, function(old: any)
			if old ~= nil and old ~= holder and old ~= code then
				taken = true -- someone claimed it meanwhile
				return nil
			end
			return code
		end)
	end)
	if not updated then
		return "busy"
	end
	return if taken then "taken" else nil
end

local function releaseName(name: string, code: string)
	local ds = nameStore()
	if not ds then
		return
	end
	-- (A store claiming the name in between could lose its hold on it: rare,
	-- and only means two stores might share a name.)
	pcall(function()
		local key = nameKey(name)
		if ds:GetAsync(key) == code then
			ds:RemoveAsync(key)
		end
	end)
end

function StoresService.findByName(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local name = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	if #name == 0 then
		return nil
	end
	local ds = nameStore()
	if not ds then
		return nil
	end
	local ok, code = pcall(function()
		return ds:GetAsync(nameKey(name))
	end)
	if not ok or type(code) ~= "string" then
		return nil
	end
	local record = SharedContentService.lookup(code)
	if StoresService.isListed(record) and nameKey(tostring(record.name)) == nameKey(name) then
		return code
	end
	return nil
end

-- Making and editing ----------------------------------------------------------

function StoresService.create(player: Player, name: string): (string?, string?)
	local now = os.time()
	local code = SharedContentService.claim({
		kind = "store",
		ownerId = player.UserId,
		ownerName = player.Name,
		created = now,
		updated = now,
		name = name,
		items = {},
		outfits = {},
		published = false,
		visits = 0,
		favourites = 0,
		sales = {},
	})
	if not code then
		return nil, "busy"
	end
	local problem = claimName(name, code)
	if problem then
		SharedContentService.remove(code)
		return nil, problem
	end
	return code, nil
end

function StoresService.edit(code: string, ownerId: number, fn: (record: any) -> boolean?): any?
	local record = SharedContentService.modify(code, function(record: any)
		if not StoresService.isStore(record) or record.ownerId ~= ownerId then
			return false
		end
		if fn(record) == false then
			return false
		end
		record.updated = os.time()
		return true
	end)
	if record then
		views[code] = nil
	end
	return record
end

function StoresService.rename(code: string, ownerId: number, name: string): string?
	local record = SharedContentService.lookup(code)
	if not StoresService.isStore(record) or record.ownerId ~= ownerId then
		return "bad"
	end
	local old = tostring(record.name)
	if old == name then
		return nil
	end
	if nameKey(old) ~= nameKey(name) then
		local problem = claimName(name, code)
		if problem then
			return problem
		end
	end
	local updated = StoresService.edit(code, ownerId, function(current: any)
		current.name = name
		return true
	end)
	if not updated then
		return "busy"
	end
	if nameKey(old) ~= nameKey(name) then
		releaseName(old, code)
	end
	return nil
end

function StoresService.publish(code: string, ownerId: number): string?
	local problem: string? = nil
	local record = StoresService.edit(code, ownerId, function(record: any)
		if record.hidden then
			problem = "hidden"
			return false
		end
		if #(record.items or {}) < StoresConfig.minItems then
			problem = "items"
			return false
		end
		if record.published then
			return false
		end
		record.published = true
		record.publishedAt = record.publishedAt or os.time()
		return true
	end)
	if problem then
		return problem
	end
	if record then
		relist(code, record)
	end
	return nil
end

function StoresService.unpublish(code: string, ownerId: number): boolean
	local record = StoresService.edit(code, ownerId, function(record: any)
		if not record.published then
			return false
		end
		record.published = false
		return true
	end)
	if record then
		delist(code)
	end
	return record ~= nil
end

function StoresService.delete(code: string, ownerId: number?): boolean
	local record = SharedContentService.lookup(code)
	if not StoresService.isStore(record) or (ownerId and record.ownerId ~= ownerId) then
		return false
	end
	delist(code)
	releaseName(tostring(record.name), code)
	SharedContentService.remove(code)
	views[code] = nil
	pending[code] = nil
	return true
end

-- Moderation ------------------------------------------------------------------

function StoresService.hide(code: string, reason: string)
	local record = SharedContentService.modify(code, function(record: any)
		if not StoresService.isStore(record) or record.hidden then
			return false
		end
		record.hidden = true
		record.hiddenReason = reason
		return true
	end)
	if record then
		delist(code)
		views[code] = nil
		warn(string.format("[StoresService] Hid %s (%s): %q", code, reason, tostring(record.name)))
	end
end

function StoresService.restore(code: string)
	local record = SharedContentService.modify(code, function(record: any)
		if not StoresService.isStore(record) or not record.hidden then
			return false
		end
		record.hidden = nil
		record.hiddenReason = nil
		return true
	end)
	if record then
		views[code] = nil
		if record.published then
			relist(code, record)
		end
	end
end

function StoresService.report(player: Player, code: string): boolean
	local added, count = SharedContentService.report(player, code)
	if added and count >= REPORTS_TO_HIDE then
		StoresService.hide(code, "reports")
	end
	return added
end

-- Counts ------------------------------------------------------------------------

local function pendingFor(code: string)
	local entry = pending[code]
	if not entry then
		entry = { visits = 0, favourites = 0, sales = {} }
		pending[code] = entry
	end
	return entry
end

function StoresService.countVisit(code: string)
	pendingFor(code).visits += 1
end

function StoresService.countFavourite(code: string, delta: number)
	pendingFor(code).favourites += delta
end

function StoresService.countSales(code: string, keys: { string })
	local sales = pendingFor(code).sales
	for _, key in keys do
		sales[key] = (sales[key] or 0) + 1
	end
end

function StoresService.flush()
	local batch = pending
	pending = {}
	for code, delta in batch do
		if not StoresService.isStore(SharedContentService.lookup(code)) then
			continue
		end
		local updated = SharedContentService.modify(code, function(current: any)
			if not StoresService.isStore(current) then
				return false
			end
			current.visits = math.max(0, (tonumber(current.visits) or 0) + delta.visits)
			current.favourites = math.max(0, (tonumber(current.favourites) or 0) + delta.favourites)
			current.sales = if type(current.sales) == "table" then current.sales else {}
			local inStore = {}
			for _, item in current.items or {} do
				inStore[keyOf(item)] = true
			end
			for key, n in delta.sales do
				if inStore[key] then
					current.sales[key] = (tonumber(current.sales[key]) or 0) + n
				end
			end
			return true
		end)
		if updated and StoresService.isListed(updated) then
			RankedPages.increment(RANKINGS.popular, code, delta.visits)
			RankedPages.increment(RANKINGS.toprated, code, delta.favourites)
		end
	end
end

-- Browsing ------------------------------------------------------------------------

function StoresService.page(sort: string, index: number): ({ string }, boolean)
	local name = RANKINGS[sort]
	if not name then
		return {}, false
	end
	return RankedPages.page(name, index)
end

-- Records for these codes, looked up side by side.
local function lookupAll(codes: { string }): { any }
	local records: { any } = table.create(#codes)
	local remaining = #codes
	if remaining == 0 then
		return records
	end
	local thread = coroutine.running()
	for index, code in codes do
		task.spawn(function()
			records[index] = SharedContentService.lookup(code)
			remaining -= 1
			if remaining == 0 and coroutine.status(thread) == "suspended" then
				task.spawn(thread)
			end
		end)
	end
	if remaining > 0 then
		coroutine.yield()
	end
	return records
end

local function itemsOf(record: any): { Item }
	local items = {}
	for _, item in record.items or {} do
		table.insert(items, { targetId = item.targetId, kind = item.kind, typeName = item.typeName, name = item.name })
	end
	return items
end

function StoresService.cards(codes: { string }, viewer: Player?): { Card }
	local records = lookupAll(codes)
	local cards: { Card } = {}
	for index, code in codes do
		local record = records[index]
		if canSee(record, viewer) then
			local items = itemsOf(record)
			table.insert(cards, {
				code = code,
				name = tostring(record.name or "Store"),
				by = tostring(record.ownerName or ""),
				mine = viewer ~= nil and record.ownerId == viewer.UserId,
				published = record.published == true,
				hidden = record.hidden == true,
				visits = tonumber(record.visits) or 0,
				favourites = tonumber(record.favourites) or 0,
				itemCount = #items,
				preview = table.move(items, 1, math.min(#items, PREVIEW_ITEMS), 1, {}),
			})
		end
	end
	return cards
end

-- Roblox's price and favourite count for each item (cached; nil price when
-- it isn't for sale).
local function detailsFor(items: { Item })
	local now = os.clock()
	local wanted: { [string]: { number } } = { Asset = {}, Bundle = {} }
	for _, item in items do
		local cached = details[keyOf(item)]
		if not cached or now - cached.at > DETAIL_SECONDS then
			table.insert(wanted[item.kind], item.targetId)
		end
	end
	for kind, ids in wanted do
		local itemType = if kind == "Bundle" then Enum.AvatarItemType.Bundle else Enum.AvatarItemType.Asset
		for first = 1, #ids, DETAIL_BATCH do
			local chunk = table.move(ids, first, math.min(#ids, first + DETAIL_BATCH - 1), 1, {})
			local ok, result = pcall(function()
				return AvatarEditorService:GetBatchItemDetails(chunk, itemType)
			end)
			if not ok then
				warn("[StoresService] Item details failed:", result)
				continue
			end
			for _, info in result :: any do
				local id = tonumber(info.Id)
				if id then
					local price = tonumber(info.Price) or tonumber(info.LowestPrice)
					details[kind .. ":" .. id] = {
						price = if info.IsPurchasable == false then nil else price,
						favourites = tonumber(info.FavoriteCount) or 0,
						at = now,
					}
				end
			end
		end
	end
end

local function matches(rule: any, item: Item): boolean
	local detail = details[keyOf(item)]
	if rule.minPrice or rule.maxPrice then
		local price = detail and detail.price
		if price == nil then
			return false
		end
		if (rule.minPrice and price < rule.minPrice) or (rule.maxPrice and price > rule.maxPrice) then
			return false
		end
	end
	if rule.category then
		local types = categoryTypes[rule.category]
		local set = types and (if item.kind == "Bundle" then types.bundles else types.assets)
		if not set or not set[item.typeName] then
			return false
		end
	end
	if rule.assetTypes and (item.kind ~= "Asset" or not table.find(rule.assetTypes, item.typeName)) then
		return false
	end
	if rule.bundleTypes and (item.kind ~= "Bundle" or not table.find(rule.bundleTypes, item.typeName)) then
		return false
	end
	return true
end

local function build(code: string, record: any): Page
	local items = itemsOf(record)
	detailsFor(items)
	local count = #items
	local size = StoresConfig.sectionSize

	local featured = {}
	for index = 1, math.min(count, StoresConfig.featured) do
		table.insert(featured, index)
	end

	local newArrivals = {}
	for index = count, math.max(1, count - size + 1), -1 do
		table.insert(newArrivals, index)
	end

	local sales = if type(record.sales) == "table" then record.sales else {}
	local order = {}
	for index = 1, count do
		order[index] = index
	end
	table.sort(order, function(a: number, b: number): boolean
		local ka, kb = keyOf(items[a]), keyOf(items[b])
		local sa, sb = tonumber(sales[ka]) or 0, tonumber(sales[kb]) or 0
		if sa ~= sb then
			return sa > sb
		end
		local fa = (details[ka] and details[ka].favourites) or 0
		local fb = (details[kb] and details[kb].favourites) or 0
		if fa ~= fb then
			return fa > fb
		end
		return a < b
	end)
	local bestsellers = table.move(order, 1, math.min(count, size), 1, {})

	local collections: { Section } = {}
	for _, rule in StoresConfig.collections do
		if #collections >= StoresConfig.maxCollections then
			break
		end
		local matching = {}
		for index, item in items do
			if matches(rule, item) then
				table.insert(matching, index)
			end
		end
		if #matching >= StoresConfig.collectionMinItems and #matching < count then
			table.insert(collections, { name = rule.name, items = matching })
		end
	end

	return {
		code = code,
		name = tostring(record.name or "Store"),
		by = tostring(record.ownerName or ""),
		ownerId = tonumber(record.ownerId) or 0,
		mine = false,
		published = record.published == true,
		hidden = record.hidden == true,
		visits = tonumber(record.visits) or 0,
		favourites = tonumber(record.favourites) or 0,
		items = items,
		outfits = {},
		featured = featured,
		bestsellers = bestsellers,
		newArrivals = newArrivals,
		collections = collections,
	}
end

function StoresService.view(code: string, viewer: Player?): Page?
	local record = SharedContentService.lookup(code)
	if not canSee(record, viewer) then
		return nil
	end
	local cached = views[code]
	local page: Page
	if cached and os.clock() - cached.at < VIEW_SECONDS then
		page = cached.page
	else
		page = build(code, record)
		views[code] = { page = page, at = os.clock() }
	end
	local result = table.clone(page)
	result.mine = viewer ~= nil and page.ownerId == viewer.UserId
	result.outfits = CommunityService.cards(record.outfits or {}, viewer)
	return result
end

function StoresService.init()
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			StoresService.flush()
		end
	end)
	game:BindToClose(StoresService.flush)
	Players.PlayerRemoving:Connect(function()
		if #Players:GetPlayers() <= 1 then
			task.spawn(StoresService.flush)
		end
	end)
end

return StoresService
