--!strict

--[[
	StoresClient (client)

	Stores for the Stores tab (StoresController):
	  · lists, a page at a time over the "BrowseStores" remote function
	    (Bolt): "popular" | "toprated" (everyone's published stores, kept for
	    STALE_SECONDS) and "favourites" | "mine" (the player's own lists,
	    reloaded whenever the list changes: pass its `key`)
	  · store pages over "GetStore" (a code, or a published store's exact
	    name), cached for PAGE_SECONDS

	Items arrive as { targetId, kind, typeName, name } and are handed to
	CatalogueClient.remember, so cards hold item ids like everywhere else
	(their prices and thumbnails fill in from the catalogue). A page's
	sections arrive as positions in its item list and become item ids here.
	Its outfits are Community outfit cards (CommunityOutfits.toCard).
	Its rows (the owner's layout, StoresService) come in order, each items
	or outfits, filled by hand (its items in its order) or by a search
	(found by the page, from `search`), with a style and a limit.

	API:
		SORTS                        the tabs, in order: { id, label }
		load(sort, key?) / more(sort) / get(sort) -> List
		reset()                      forget every list and page (after
		                             starring, reporting)
		find(text) -> (Page?, error?)   yields; a code or an exact name;
		                             error "notfound" | "busy" | "failed"
		cached(code) -> Page?        a page already loaded
		act(action, ...) -> (ok, code?, error?, row?)   yields; a StoresController
		                             action over "StoreAction" (Create,
		                             AddItem, Publish, …). On success the
		                             store's page and the lists are dropped
		                             so they load again as they are now
		changed                      signal: a list or page changed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bolt = require(ReplicatedStorage:WaitForChild("Bolt"))
local CatalogueClient = require(script.Parent:WaitForChild("CatalogueClient"))
local CommunityOutfits = require(script.Parent:WaitForChild("CommunityOutfits"))

local StoresClient = {}

export type Card = {
	code: string,
	name: string,
	by: string,
	mine: boolean,
	published: boolean,
	hidden: boolean, -- hidden after reports (only ever on your own)
	visits: number,
	favourites: number,
	itemCount: number,
	preview: { number }, -- item ids, the first few
}

export type Section = { name: string, items: { number } }

export type Row = {
	id: string,
	content: string, -- "items" | "outfits"
	source: string, -- "manual" | "search"
	style: string, -- "square" | "wide" | "tall" | "single" | "grid" | "tile"
	name: string,
	limit: number,
	order: string?, -- manual: "added" | "newest" | "bestselling"
	items: { number }?, -- manual items rows: item ids, in order
	outfits: { CommunityOutfits.Card }?, -- manual outfits rows: their (listed) outfits
	outfitCodes: { string }?, -- manual outfits rows: all their codes
	search: { [string]: any }?, -- search rows: a catalogue browse, or { sort }
}

export type Page = {
	code: string,
	name: string,
	by: string,
	mine: boolean,
	published: boolean,
	hidden: boolean,
	visits: number,
	favourites: number,
	favourited: boolean, -- starred by this player when it loaded
	items: { number }, -- in the order the owner added them
	outfits: { CommunityOutfits.Card },
	rows: { Row },
}

export type List = {
	cards: { Card },
	more: boolean,
	loading: boolean,
	error: string?, -- "busy" | "failed"
}

StoresClient.SORTS = {
	{ id = "popular", label = "Popular" },
	{ id = "toprated", label = "Top rated" },
	{ id = "favourites", label = "Favourites" },
	{ id = "mine", label = "My stores" },
}

local STALE_SECONDS = 60
local RETRY_SECONDS = 10 -- a failed list waits this long before loading again
local PAGE_SECONDS = 30
local PERSONAL = { favourites = true, mine = true }

type State = List & { page: number, at: number, failedAt: number, key: string, generation: number }

local browseRemote = Bolt.RemoteFunction("BrowseStores")
local storeRemote = Bolt.RemoteFunction("GetStore")
local actionRemote = Bolt.RemoteFunction("StoreAction")
local changedEvent = Instance.new("BindableEvent")
StoresClient.changed = changedEvent.Event

local lists: { [string]: State } = {}
local pages: { [string]: { page: Page, at: number } } = {}

local function itemIds(raw: any): { number }
	local ids = {}
	for _, entry in if type(raw) == "table" then raw else {} do
		if type(entry) == "table" and type(entry.targetId) == "number" then
			table.insert(ids, CatalogueClient.remember(entry).id)
		end
	end
	return ids
end

local function toCard(raw: any): Card?
	if type(raw) ~= "table" or type(raw.code) ~= "string" then
		return nil
	end
	return {
		code = raw.code,
		name = tostring(raw.name or "Store"),
		by = tostring(raw.by or ""),
		mine = raw.mine == true,
		published = raw.published == true,
		hidden = raw.hidden == true,
		visits = tonumber(raw.visits) or 0,
		favourites = tonumber(raw.favourites) or 0,
		itemCount = tonumber(raw.itemCount) or 0,
		preview = itemIds(raw.preview),
	}
end

local function toPage(raw: any): Page
	local items = itemIds(raw.items)
	-- Positions in the item list -> item ids.
	local function pick(positions: any): { number }
		local ids = {}
		for _, position in if type(positions) == "table" then positions else {} do
			local id = items[tonumber(position) or 0]
			if id then
				table.insert(ids, id)
			end
		end
		return ids
	end
	local outfits = {}
	for _, card in if type(raw.outfits) == "table" then raw.outfits else {} do
		local outfit = CommunityOutfits.toCard(card)
		if outfit then
			table.insert(outfits, outfit)
		end
	end
	local byCode: { [string]: CommunityOutfits.Card } = {}
	for _, outfit in outfits do
		byCode[outfit.code] = outfit
	end
	local rows: { Row } = {}
	for _, row in if type(raw.rows) == "table" then raw.rows else {} do
		if type(row) == "table" and type(row.id) == "string" and type(row.content) == "string" then
			local entry: Row = {
				id = row.id,
				content = row.content,
				source = tostring(row.source or "manual"),
				style = tostring(row.style or "square"),
				name = tostring(row.name or ""),
				limit = tonumber(row.limit) or 20,
				order = if type(row.order) == "string" then row.order else nil,
				search = if type(row.search) == "table" then row.search else nil,
			}
			if type(row.items) == "table" then
				entry.items = pick(row.items)
			end
			if type(row.outfits) == "table" then
				local codes, cards = {}, {}
				for _, code in row.outfits do
					if type(code) == "string" then
						table.insert(codes, code)
						if byCode[code] then
							table.insert(cards, byCode[code])
						end
					end
				end
				entry.outfitCodes = codes
				entry.outfits = cards
			end
			table.insert(rows, entry)
		end
	end
	return {
		code = tostring(raw.code),
		name = tostring(raw.name or "Store"),
		by = tostring(raw.by or ""),
		mine = raw.mine == true,
		published = raw.published == true,
		hidden = raw.hidden == true,
		visits = tonumber(raw.visits) or 0,
		favourites = tonumber(raw.favourites) or 0,
		favourited = raw.favourited == true,
		items = items,
		outfits = outfits,
		rows = rows,
	}
end

local function fetch(sort: string, state: State)
	local generation = state.generation
	local page = state.page + 1
	state.loading = true
	changedEvent:Fire()
	local ok, result = pcall(function()
		return browseRemote:InvokeServer(sort, page)
	end)
	if lists[sort] ~= state or state.generation ~= generation then
		return -- replaced while loading
	end
	state.loading = false
	if not ok or type(result) ~= "table" or not result.ok then
		state.error = if ok and type(result) == "table" and result.error == "busy" then "busy" else "failed"
		state.failedAt = os.clock()
		state.more = false
	else
		state.error = nil
		state.page = page
		state.more = result.more == true
		for _, raw in result.cards or {} do
			local card = toCard(raw)
			if card then
				table.insert(state.cards, card)
			end
		end
	end
	changedEvent:Fire()
end

local function fresh(sort: string, key: string): State
	local old = lists[sort]
	local state: State = {
		cards = {},
		more = false,
		loading = true, -- until the first page arrives
		error = nil,
		page = 0,
		at = os.clock(),
		failedAt = 0,
		key = key,
		generation = (if old then old.generation else 0) + 1,
	}
	lists[sort] = state
	return state
end

function StoresClient.load(sort: string, key: string?)
	local state = lists[sort]
	local wanted = key or ""
	local stale = state ~= nil
		and (
			state.key ~= wanted
			or (state.error ~= nil and os.clock() - state.failedAt > RETRY_SECONDS)
			or (not PERSONAL[sort] and os.clock() - state.at > STALE_SECONDS)
		)
	if state and not stale then
		return
	end
	task.defer(fetch, sort, fresh(sort, wanted))
end

function StoresClient.more(sort: string)
	local state = lists[sort]
	if state and state.more and not state.loading then
		state.loading = true
		task.defer(fetch, sort, state)
	end
end

function StoresClient.get(sort: string): List
	return lists[sort] or { cards = {}, more = false, loading = true, error = nil }
end

function StoresClient.cached(code: string): Page?
	local entry = pages[code]
	if entry and os.clock() - entry.at < PAGE_SECONDS then
		return entry.page
	end
	return nil
end

function StoresClient.find(text: string): (Page?, string?)
	local key = string.upper((string.gsub(text, "^%s*(.-)%s*$", "%1")))
	local cached = StoresClient.cached(key)
	if cached then
		return cached, nil
	end
	local ok, result = pcall(function()
		return storeRemote:InvokeServer(text)
	end)
	if not ok or type(result) ~= "table" then
		return nil, "failed"
	end
	if not result.ok or type(result.store) ~= "table" then
		return nil, if result.error == "busy" then "busy" else "notfound"
	end
	local page = toPage(result.store)
	pages[page.code] = { page = page, at = os.clock() }
	return page, nil
end

function StoresClient.act(action: string, ...: any): (boolean, string?, string?, string?)
	local args = table.pack(...)
	local ok, result = pcall(function()
		return actionRemote:InvokeServer(action, table.unpack(args, 1, args.n))
	end)
	if not ok or type(result) ~= "table" then
		return false, nil, "busy"
	end
	if not result.ok then
		return false, nil, if type(result.error) == "string" then result.error else "busy"
	end
	local code = if type(result.code) == "string" then result.code else nil
	if code then
		pages[code] = nil
	end
	for sort, state in lists do
		state.generation += 1
		lists[sort] = nil
	end
	changedEvent:Fire()
	return true, code, nil, if type(result.row) == "string" then result.row else nil
end

function StoresClient.reset()
	for sort, state in lists do
		state.generation += 1 -- a load still running is dropped
		lists[sort] = nil
	end
	table.clear(pages)
	changedEvent:Fire()
end

return StoresClient
