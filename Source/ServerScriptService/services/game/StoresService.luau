--!strict

--[[
	StoresService (loop-based: flushes counts every FLUSH_SECONDS)

	Stores players make, for everyone, across servers. A store is a
	curated set of catalogue items and outfits, kept as a shared record
	(SharedContentService, kind "store") under a 6-character code from the
	same pool as outfits. Unlike an outfit's frozen copy, a store is edited
	in place: its code, visits and favourites stay with it for good.

		{ kind = "store", ownerId, ownerName, created, updated, name,
		  items = { { targetId, kind, typeName, name } },   every item in
		                               the store once, in the order added
		  outfits = { code },          every Community outfit (their own
		                               codes) once
		  rows = { Row },              the page, in the owner's order
		  nextRow,                     for row ids
		  published, publishedAt?, visits, favourites,
		  hidden?, hiddenReason? }

	The owner lays out the page as rows (PLAN 19.1), each one:
		{ id = "r1", content = "items" | "outfits",
		  source = "manual" | "search", style, name, limit,
		  items = { "Asset:123", ... } | outfits = { code },   manual rows,
		                               in the owner's order
		  search = { ... } }           search rows: a catalogue query
		                               (cleanSearch) or a Community sort
	Styles: "square" | "wide" | "hero" | "single" | "grid" | "tile"
	(outfits rows: square, grid, tile). `limit` caps what the row shows
	(a tile opens all of it); a hero row shows 2 to 6 (HERO_LIMIT). A search row's items are found by each
	viewer's client from its search, so they aren't the store's items:
	the store's limits are about the manual ones.
	An item (or outfit) can be in several manual rows; it leaves the store
	when it's in none. Older stores get rows on their next read (rowsOf):
	Featured (single, its first items), "Items" (all), "Outfits".

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
	Visits and favourites are counted per server and written every
	FLUSH_SECONDS (and on shutdown). StoresController decides what counts (a
	visit once a day per player, never the owner's).

	A store page (view) has the rows, a manual row's items as the owner put
	them in. Pages are cached per server for VIEW_SECONDS, and dropped when
	this server edits the store. (Purchases through a store go to analytics
	with its code: PurchaseController.)

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
		countVisit(code) / countFavourite(code, delta)
		flush()
		page(sort, index) -> ({ string }, boolean)   "popular" | "toprated"
		                                        | "newest"
		cards(codes, viewer) -> { Card }        visible ones only (a viewer's
		                                        own drafts included)
		view(code, viewer) -> Page?             nil if it can't be opened
		findByName(text) -> string?             a published store's code
		report(player, code) -> boolean
		isStore(record) / isListed(record) -> boolean
	  Inside edit's fn (the record as it's being changed):
		rowsOf(record) -> { Row }               (bringing an old store's up
		                                        to date)
		addItem(record, rowId, item) -> string?          nil, or why not
		                                        ("norow", "dupe", "full")
		removeItem(record, rowId, key)
		addOutfit(record, rowId, code) -> string?
		removeOutfit(record, rowId, code)
		addRow(record, spec) -> (string?, string?)   its id, or why not
		                                        ("full", "bad")
		editRow(record, rowId, spec) -> string?   style, limit, name
		setSearch(record, rowId, search) -> string?
		renameRow(record, rowId, name) -> string?
		removeRow(record, rowId) -> string?
		moveRow(record, rowId, by) -> string?   by -1 (up) or 1 (down)
	  And:
		cleanRowName(player, text) -> (string?, string?)
		cleanSpec(raw) -> RowSpec?              a row's settings, checked
		cleanSearch(content, raw) -> table?     a search row's search, checked
		keyOf(item) -> string                   "Asset:123"
]]

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

export type Row = {
	id: string,
	content: "items" | "outfits",
	source: "manual" | "search",
	style: string,
	name: string,
	limit: number,
	items: { string }?, -- manual items rows: item keys ("Asset:123"), in order
	outfits: { string }?, -- manual outfits rows: outfit codes
	search: { [string]: any }?, -- search rows
}

-- What the owner sets on a row (AddRow / EditRow).
export type RowSpec = {
	content: "items" | "outfits",
	source: "manual" | "search",
	style: string,
	name: string?,
	limit: number,
}

-- A row as a page sends it: a manual row's items as indices into
-- Page.items.
export type PageRow = {
	id: string,
	content: string,
	source: string,
	style: string,
	name: string,
	limit: number,
	items: { number }?,
	outfits: { string }?,
	search: { [string]: any }?,
}

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
	rows: { PageRow },
}

local FLUSH_SECONDS = 60
local REPORTS_TO_HIDE = 3
local PREVIEW_ITEMS = 4
local VIEW_SECONDS = 60

local RANKINGS = {
	popular = "StoresPopular",
	toprated = "StoresTopRated",
	newest = "StoresNewest",
}

local names: DataStore? = nil
local pending: { [string]: { visits: number, favourites: number } } = {}
local views: { [string]: { page: Page, at: number } } = {}

local function keyOf(item: Item): string
	return item.kind .. ":" .. item.targetId
end
StoresService.keyOf = keyOf

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

-- Rows ------------------------------------------------------------------------

local STYLES = { square = true, wide = true, hero = true, single = true, grid = true, tile = true }
local OUTFIT_STYLES = { square = true, grid = true, tile = true }
local HERO_LIMIT = { min = 2, max = 6 } -- a hero row doesn't scroll
local ROWS_VERSION = 3
local OUTFIT_SORTS = { popular = true, trending = true, newest = true }

local function newRow(record: any, spec: RowSpec): Row
	record.nextRow = (tonumber(record.nextRow) or 0) + 1
	local row: Row = {
		id = "r" .. record.nextRow,
		content = spec.content,
		source = spec.source,
		style = spec.style,
		name = spec.name or (if spec.content == "outfits" then "Outfits" else "Items"),
		limit = spec.limit,
	}
	if spec.source == "manual" then
		if spec.content == "items" then
			row.items = {}
		else
			row.outfits = {}
		end
	else
		row.search = if spec.content == "outfits" then { sort = "popular" } else {}
	end
	return row
end

local function manual(record: any, content: "items" | "outfits", style: string, name: string, list: { string }): Row
	local row = newRow(record, {
		content = content,
		source = "manual",
		style = style,
		name = name,
		limit = StoresConfig.rowLimit.default,
	})
	if content == "items" then
		row.items = list
	else
		row.outfits = list
	end
	return row
end

-- Rows as the page has them now. Older shapes come up to date: no rows
-- (Featured, Items, Outfits from the store's items); the first rows
-- (Featured / named rows kept; Bestsellers, New arrivals and Collections
-- dropped); or version 2 (orders dropped, Tall is Hero, 2 to 6).
function StoresService.rowsOf(record: any): { Row }
	if type(record.rows) == "table" and record.rowsVersion == ROWS_VERSION then
		return record.rows
	end
	record.sales = nil -- (counted for the Bestselling order, gone with it)
	if type(record.rows) == "table" and record.rowsVersion == 2 then
		for _, row in record.rows do
			row.order = nil
			if row.style == "tall" then
				row.style = "hero"
			end
			if row.style == "hero" then
				row.limit = math.clamp(tonumber(row.limit) or HERO_LIMIT.max, HERO_LIMIT.min, HERO_LIMIT.max)
			end
		end
		record.rowsVersion = ROWS_VERSION
		return record.rows
	end
	local rows: { Row } = {}
	if type(record.rows) == "table" then
		for _, old in record.rows do
			if old.kind == "featured" then
				table.insert(rows, manual(record, "items", "single", "Featured", old.items or {}))
			elseif old.kind == "items" then
				table.insert(rows, manual(record, "items", "square", tostring(old.name or "Items"), old.items or {}))
			elseif old.kind == "outfits" then
				table.insert(rows, manual(record, "outfits", "square", tostring(old.name or "Outfits"), old.outfits or {}))
			end
		end
	else
		local keys = {}
		for _, item in record.items or {} do
			table.insert(keys, keyOf(item))
		end
		table.insert(rows, manual(record, "items", "single", "Featured", table.move(keys, 1, math.min(#keys, PREVIEW_ITEMS), 1, {})))
		table.insert(rows, manual(record, "items", "square", "Items", keys))
		if #(record.outfits or {}) > 0 then
			table.insert(rows, manual(record, "outfits", "square", "Outfits", table.clone(record.outfits)))
		end
	end
	record.rows = rows
	record.rowsVersion = ROWS_VERSION
	return rows
end

local function findRow(record: any, rowId: any): (Row?, number?)
	for index, row in StoresService.rowsOf(record) do
		if row.id == rowId then
			return row, index
		end
	end
	return nil, nil
end

local function inAnyRow(record: any, field: string, value: string): boolean
	for _, row in StoresService.rowsOf(record) do
		local list = (row :: any)[field]
		if list and table.find(list, value) then
			return true
		end
	end
	return false
end

function StoresService.addItem(record: any, rowId: any, item: Item): string?
	local row = findRow(record, rowId)
	if not row or not row.items then
		return "norow"
	end
	local key = keyOf(item)
	if table.find(row.items, key) then
		return "dupe"
	end
	record.items = record.items or {}
	local known = false
	for _, existing in record.items do
		if keyOf(existing) == key then
			known = true
			break
		end
	end
	if not known then
		if #record.items >= StoresConfig.maxItems then
			return "full"
		end
		table.insert(record.items, { targetId = item.targetId, kind = item.kind, typeName = item.typeName, name = item.name })
	end
	table.insert(row.items, key)
	return nil
end

-- Drop items and outfits that are in no row any more.
local function prune(record: any)
	for index = #(record.items or {}), 1, -1 do
		if not inAnyRow(record, "items", keyOf(record.items[index])) then
			table.remove(record.items, index)
		end
	end
	for index = #(record.outfits or {}), 1, -1 do
		if not inAnyRow(record, "outfits", record.outfits[index]) then
			table.remove(record.outfits, index)
		end
	end
end

function StoresService.removeItem(record: any, rowId: any, key: string)
	local row = findRow(record, rowId)
	local index = row and row.items and table.find(row.items, key)
	if row and row.items and index then
		table.remove(row.items, index)
		prune(record)
	end
end

function StoresService.addOutfit(record: any, rowId: any, code: string): string?
	local row = findRow(record, rowId)
	if not row or not row.outfits then
		return "norow"
	end
	if table.find(row.outfits, code) then
		return "dupe"
	end
	record.outfits = record.outfits or {}
	if not table.find(record.outfits, code) then
		if #record.outfits >= StoresConfig.maxOutfits then
			return "full"
		end
		table.insert(record.outfits, code)
	end
	table.insert(row.outfits, code)
	return nil
end

function StoresService.removeOutfit(record: any, rowId: any, code: string)
	local row = findRow(record, rowId)
	local index = row and row.outfits and table.find(row.outfits, code)
	if row and row.outfits and index then
		table.remove(row.outfits, index)
		prune(record)
	end
end

-- A row's settings from a request, checked; nil if they don't make sense.
-- (The name is checked separately: cleanRowName.)
function StoresService.cleanSpec(raw: any): RowSpec?
	if type(raw) ~= "table" then
		return nil
	end
	local content = raw.content
	local source = raw.source
	local style = raw.style
	if content ~= "items" and content ~= "outfits" then
		return nil
	end
	if source ~= "manual" and source ~= "search" then
		return nil
	end
	if type(style) ~= "string" or not (if content == "outfits" then OUTFIT_STYLES else STYLES)[style] then
		return nil
	end
	local limit = tonumber(raw.limit) or StoresConfig.rowLimit.default
	if style == "hero" then
		limit = math.clamp(math.floor(limit), HERO_LIMIT.min, HERO_LIMIT.max)
	else
		limit = math.clamp(math.floor(limit), 1, StoresConfig.rowLimit.max)
	end
	return { content = content, source = source, style = style, name = nil, limit = limit }
end

function StoresService.addRow(record: any, spec: RowSpec): (string?, string?)
	local rows = StoresService.rowsOf(record)
	if #rows >= StoresConfig.maxRows then
		return nil, "full"
	end
	local row = newRow(record, spec)
	table.insert(rows, row)
	return row.id, nil
end

-- Style, limit and name (content and source stay as made).
function StoresService.editRow(record: any, rowId: any, spec: RowSpec): string?
	local row = findRow(record, rowId)
	if not row then
		return "norow"
	end
	if spec.content ~= row.content or spec.source ~= row.source then
		return "bad"
	end
	row.style = spec.style
	row.limit = spec.limit
	if spec.name then
		row.name = spec.name
	end
	return nil
end

function StoresService.setSearch(record: any, rowId: any, search: { [string]: any }): string?
	local row = findRow(record, rowId)
	if not row or row.source ~= "search" then
		return "norow"
	end
	if type(search) ~= "table" then
		return "bad"
	end
	row.search = search
	return nil
end

function StoresService.renameRow(record: any, rowId: any, name: string): string?
	local row = findRow(record, rowId)
	if not row then
		return "norow"
	end
	row.name = name
	return nil
end

function StoresService.removeRow(record: any, rowId: any): string?
	local row, index = findRow(record, rowId)
	if not row or not index then
		return "norow"
	end
	table.remove(record.rows, index)
	prune(record)
	return nil
end

function StoresService.moveRow(record: any, rowId: any, by: any): string?
	local row, index = findRow(record, rowId)
	if not row or not index or (by ~= 1 and by ~= -1) then
		return "norow"
	end
	local rows = record.rows
	local target = index + by
	if target < 1 or target > #rows then
		return nil -- already at the end
	end
	rows[index], rows[target] = rows[target], rows[index]
	return nil
end

-- Any search rows (a store with one has something to show without items).
local function hasSearch(record: any): boolean
	for _, row in StoresService.rowsOf(record) do
		if row.source == "search" then
			return true
		end
	end
	return false
end

local function enumName(enum: Enum, value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	for _, item in enum:GetEnumItems() do
		if item.Name == value then
			return value
		end
	end
	return nil
end

local function shortText(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local text = string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")
	if text == "" or #text > 50 then
		return nil
	end
	return text
end

local function price(value: any): number?
	local n = tonumber(value)
	if not n or n ~= n or n < 0 then
		return nil
	end
	return math.floor(n)
end

-- A search row's search, checked: for items, the Catalogue's browse
-- (CatalogueClient.Query fields plus its colour); for outfits, a Community
-- sort. nil if it doesn't make sense.
function StoresService.cleanSearch(content: any, raw: any): { [string]: any }?
	if type(raw) ~= "table" then
		return nil
	end
	if content == "outfits" then
		return if OUTFIT_SORTS[raw.sort] then { sort = raw.sort } else nil
	end
	local category: any = nil
	for _, candidate in CatalogueConfig.categories do
		if candidate.name == raw.category and not candidate.special then
			category = candidate
		end
	end
	if not category then
		return nil
	end
	local chip: string? = nil
	if raw.chip ~= nil and raw.chip ~= "All" then
		for _, candidate in category.chips do
			if candidate.name == raw.chip and not candidate.special then
				chip = candidate.name
			end
		end
		if not chip then
			return nil
		end
	end
	local colour = if type(raw.colour) == "string" and table.find(CatalogueConfig.colours, raw.colour) then raw.colour else nil
	return {
		category = category.name,
		chip = chip,
		keyword = shortText(raw.keyword),
		minPrice = price(raw.minPrice),
		maxPrice = price(raw.maxPrice),
		sort = enumName(Enum.CatalogSortType, raw.sort),
		sortWindow = enumName(Enum.CatalogSortAggregation, raw.sortWindow),
		creator = shortText(raw.creator),
		salesType = enumName(Enum.SalesTypeFilter, raw.salesType),
		includeOffSale = if type(raw.includeOffSale) == "boolean" then raw.includeOffSale else nil,
		colour = colour,
	}
end

function StoresService.cleanRowName(player: Player, text: any): (string?, string?)
	if type(text) ~= "string" then
		return nil, "bad"
	end
	local name = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	name = string.gsub(name, "%s+", " ")
	local length = utf8.len(name) or #name
	if length < StoresConfig.rowNameLength.min or length > StoresConfig.rowNameLength.max then
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
		rows = {
			{ id = "r1", content = "items", source = "manual", style = "single", name = "Featured", limit = StoresConfig.rowLimit.default, items = {} },
			{ id = "r2", content = "items", source = "manual", style = "square", name = "Items", limit = StoresConfig.rowLimit.default, items = {} },
		},
		rowsVersion = ROWS_VERSION,
		nextRow = 2,
		published = false,
		visits = 0,
		favourites = 0,
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
		StoresService.rowsOf(record)
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
		if #(record.items or {}) + #(record.outfits or {}) < StoresConfig.minItems and not hasSearch(record) then
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
		entry = { visits = 0, favourites = 0 }
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
			-- Its picture: the first manual items row's items, then the rest.
			local first: { string }? = nil
			for _, row in StoresService.rowsOf(table.clone(record)) do
				if row.items and #row.items > 0 then
					first = row.items
					break
				end
			end
			if first then
				local byKey = {}
				for _, item in items do
					byKey[keyOf(item)] = item
				end
				local preview = {}
				for _, key in first do
					if byKey[key] and #preview < PREVIEW_ITEMS then
						table.insert(preview, byKey[key])
					end
				end
				for _, item in items do
					if #preview >= PREVIEW_ITEMS then
						break
					end
					if not table.find(first, keyOf(item)) then
						table.insert(preview, item)
					end
				end
				items = preview
			end
			local count = #(record.items or {})
			table.insert(cards, {
				code = code,
				name = tostring(record.name or "Store"),
				by = tostring(record.ownerName or ""),
				mine = viewer ~= nil and record.ownerId == viewer.UserId,
				published = record.published == true,
				hidden = record.hidden == true,
				visits = tonumber(record.visits) or 0,
				favourites = tonumber(record.favourites) or 0,
				itemCount = count,
				preview = table.move(items, 1, math.min(#items, PREVIEW_ITEMS), 1, {}),
			})
		end
	end
	return cards
end

local function build(code: string, record: any): Page
	local items = itemsOf(record)
	local position: { [string]: number } = {}
	for index, item in items do
		position[keyOf(item)] = index
	end

	-- (A record that hasn't been edited since rows changed shape gets them
	-- here, on a copy: reading never writes.)
	local rows: { PageRow } = {}
	for _, row in StoresService.rowsOf(table.clone(record)) do
		local pageRow: PageRow = {
			id = row.id,
			content = row.content,
			source = row.source,
			style = row.style,
			name = row.name,
			limit = row.limit,
			search = row.search,
		}
		if row.items then
			local indices = {}
			for _, key in row.items do
				if position[key] then
					table.insert(indices, position[key])
				end
			end
			pageRow.items = indices
		elseif row.outfits then
			pageRow.outfits = table.clone(row.outfits)
		end
		table.insert(rows, pageRow)
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
		rows = rows,
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
