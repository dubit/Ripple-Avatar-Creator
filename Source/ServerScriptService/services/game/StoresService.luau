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
		  sales = { ["Asset:123"] = n },   bought through this store
		  hidden?, hiddenReason? }

	The owner lays out the page as rows (PLAN 19.1):
		{ id = "r1", kind = "featured", items = { "Asset:123", ... } }
		                               always first, filled by the owner
		{ id, kind = "items", name, items = { key } }
		{ id, kind = "outfits", name, outfits = { code } }
		{ id, kind = "bestsellers" | "newArrivals" | "collections" }   made
		                               from every item; at most one of each
	An item (or outfit) can be in several rows; it leaves the store when
	it's in none. A store from before rows gets them on its next read
	(rowsOf): Featured (its first items), "Items" (all of them), the
	automatic rows, and "Outfits" if it has any.

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

	A store page (view) has the rows, and fills the automatic ones: New
	arrivals (latest added first), Bestsellers (most bought through the
	store, then most favourited on Roblox) and rule-based Collections from
	StoresConfig (price, category, types). New arrivals and Bestsellers
	order every item: the page's carousels show the first
	StoresConfig.sectionSize, See all the rest. Item details come from Roblox (AvatarEditorService, batched and
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
	  Inside edit's fn (the record as it's being changed):
		rowsOf(record) -> { Row }               (adding them to an old store)
		addItem(record, rowId, item) -> string?          nil, or why not
		                                        ("norow", "dupe", "full")
		removeItem(record, rowId, key)
		addOutfit(record, rowId, code) -> string?
		removeOutfit(record, rowId, code)
		addRow(record, kind, name?) -> (string?, string?)   its id, or why not
		                                        ("full", "dupe", "bad")
		renameRow(record, rowId, name) -> string?
		removeRow(record, rowId) -> string?
		moveRow(record, rowId, by) -> string?   by -1 (up) or 1 (down)
	  And:
		cleanRowName(player, text) -> (string?, string?)
		keyOf(item) -> string                   "Asset:123"
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

export type Row = {
	id: string,
	kind: "featured" | "items" | "outfits" | "bestsellers" | "newArrivals" | "collections",
	name: string?,
	items: { string }?, -- item keys ("Asset:123")
	outfits: { string }?, -- outfit codes
}

-- A row as a page sends it: items as indices into Page.items.
export type PageRow = {
	id: string,
	kind: string,
	name: string?,
	items: { number }?,
	outfits: { string }?,
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

local AUTO = { bestsellers = true, newArrivals = true, collections = true }
local ROW_KINDS = { items = true, outfits = true, bestsellers = true, newArrivals = true, collections = true }

local function newRow(record: any, kind: string, name: string?): Row
	record.nextRow = (tonumber(record.nextRow) or 0) + 1
	local row: Row = { id = "r" .. record.nextRow, kind = kind :: any, name = name }
	if kind == "featured" or kind == "items" then
		row.items = {}
	elseif kind == "outfits" then
		row.outfits = {}
	end
	return row
end

function StoresService.rowsOf(record: any): { Row }
	if type(record.rows) == "table" then
		return record.rows
	end
	-- Before rows: Featured (the first few), everything, the automatic
	-- rows, and the outfits.
	local rows = {}
	local keys = {}
	for _, item in record.items or {} do
		table.insert(keys, keyOf(item))
	end
	local featured = newRow(record, "featured")
	featured.items = table.move(keys, 1, math.min(#keys, PREVIEW_ITEMS), 1, {})
	table.insert(rows, featured)
	local all = newRow(record, "items", "Items")
	all.items = table.clone(keys)
	table.insert(rows, all)
	for _, kind in { "newArrivals", "bestsellers", "collections" } do
		table.insert(rows, newRow(record, kind))
	end
	if #(record.outfits or {}) > 0 then
		local outfits = newRow(record, "outfits", "Outfits")
		outfits.outfits = table.clone(record.outfits)
		table.insert(rows, outfits)
	end
	record.rows = rows
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

function StoresService.addRow(record: any, kind: any, name: string?): (string?, string?)
	if type(kind) ~= "string" or not ROW_KINDS[kind] then
		return nil, "bad"
	end
	local rows = StoresService.rowsOf(record)
	if #rows >= StoresConfig.maxRows then
		return nil, "full"
	end
	if AUTO[kind] then
		for _, row in rows do
			if row.kind == kind then
				return nil, "dupe"
			end
		end
	elseif not name then
		return nil, "bad"
	end
	local row = newRow(record, kind, if AUTO[kind] then nil else name)
	table.insert(rows, row)
	return row.id, nil
end

function StoresService.renameRow(record: any, rowId: any, name: string): string?
	local row = findRow(record, rowId)
	if not row or (row.kind ~= "items" and row.kind ~= "outfits") then
		return "norow"
	end
	row.name = name
	return nil
end

function StoresService.removeRow(record: any, rowId: any): string?
	local row, index = findRow(record, rowId)
	if not row or not index or row.kind == "featured" then
		return "norow"
	end
	table.remove(record.rows, index)
	prune(record)
	return nil
end

-- Featured stays first.
function StoresService.moveRow(record: any, rowId: any, by: any): string?
	local row, index = findRow(record, rowId)
	if not row or not index or row.kind == "featured" or (by ~= 1 and by ~= -1) then
		return "norow"
	end
	local rows = record.rows
	local target = index + by
	if target < 1 or target > #rows or rows[target].kind == "featured" then
		return nil -- already at the end
	end
	rows[index], rows[target] = rows[target], rows[index]
	return nil
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
			{ id = "r1", kind = "featured", items = {} },
			{ id = "r2", kind = "items", name = "Items", items = {} },
			{ id = "r3", kind = "newArrivals" },
			{ id = "r4", kind = "bestsellers" },
			{ id = "r5", kind = "collections" },
		},
		nextRow = 5,
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
			-- Its picture: the Featured items, else the first ones.
			local rows = StoresService.rowsOf(table.clone(record))
			if rows[1] and rows[1].kind == "featured" and rows[1].items and #rows[1].items > 0 then
				local byKey = {}
				for _, item in items do
					byKey[keyOf(item)] = item
				end
				local preview = {}
				for _, key in rows[1].items do
					if byKey[key] and #preview < PREVIEW_ITEMS then
						table.insert(preview, byKey[key])
					end
				end
				for _, item in items do
					if #preview >= PREVIEW_ITEMS then
						break
					end
					if not table.find(rows[1].items, keyOf(item)) then
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

	-- Rows, items as positions in the item list.
	local position: { [string]: number } = {}
	for index, item in items do
		position[keyOf(item)] = index
	end
	local rows: { PageRow } = {}
	local featured = {}
	-- (A record that hasn't been edited since rows came in gets them here,
	-- on a copy: reading never writes.)
	for _, row in StoresService.rowsOf(table.clone(record)) do
		local pageRow: PageRow = { id = row.id, kind = row.kind, name = row.name }
		if row.items then
			local indices = {}
			for _, key in row.items do
				if position[key] then
					table.insert(indices, position[key])
				end
			end
			pageRow.items = indices
			if row.kind == "featured" then
				featured = indices
			end
		elseif row.outfits then
			pageRow.outfits = table.clone(row.outfits)
		end
		table.insert(rows, pageRow)
	end

	local newArrivals = {}
	for index = count, 1, -1 do
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
	local bestsellers = order

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
		rows = rows,
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
