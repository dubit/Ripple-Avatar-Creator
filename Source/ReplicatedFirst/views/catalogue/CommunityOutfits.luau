--!strict

--[[
	CommunityOutfits (client)

	The Community tab's outfits, a list per ordering, loaded a page at a time
	over the "BrowseCommunity" remote function (Bolt; CommunityController).
	Orderings: "popular" | "trending" | "newest" (everyone's, kept for
	STALE_SECONDS) and "favourited" | "recent" | "mine" (the player's own
	lists, reloaded whenever the list changes: pass its `key`).

	Each card is also handed to SharedCodes, so its page opens at once.

	Wears show at once: wearing someone else's Community outfit is counted
	here (noteWear) over the server's count, which takes over once it has
	caught up (counts reach it within a minute: CommunityService).

	API:
		SORTS                       the chips, in order: { id, label }
		load(sort, key?)            make sure page 1 is loaded (and fresh)
		more(sort)                  load the next page, if there is one
		get(sort) -> List           { cards, more, loading, error? }
		reset()                     forget every list (after sharing or
		                            reporting)
		noteWear(code, seen)        you wore it; `seen` is the count shown
		wears(code, server) -> number   the count to show: the server's, or
		                            yours added to what you'd seen
		changed                     signal: a list changed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bolt = require(ReplicatedStorage:WaitForChild("Bolt"))
local CatalogueClient = require(script.Parent:WaitForChild("CatalogueClient"))
local SharedCodes = require(script.Parent:WaitForChild("SharedCodes"))
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))
local BodyScale = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("BodyScale"))

local CommunityOutfits = {}

export type Card = SharedCodes.Shared & {
	mine: boolean,
	wears: number,
	favourites: number,
}

export type List = {
	cards: { Card },
	more: boolean,
	loading: boolean,
	error: string?, -- "busy" | "failed"
}

CommunityOutfits.SORTS = {
	{ id = "popular", label = "Popular" },
	{ id = "trending", label = "Trending" },
	{ id = "newest", label = "Newest" },
	{ id = "favourited", label = "Favourited" },
	{ id = "recent", label = "Recent" },
	{ id = "mine", label = "Mine" },
}

local STALE_SECONDS = 60
local RETRY_SECONDS = 10 -- a failed list waits this long before loading again
local PERSONAL = { favourited = true, recent = true, mine = true }

type State = List & { page: number, at: number, failedAt: number, key: string, generation: number }

local remote = Bolt.RemoteFunction("BrowseCommunity")
local changedEvent = Instance.new("BindableEvent")
CommunityOutfits.changed = changedEvent.Event

local lists: { [string]: State } = {}
local worn: { [string]: { seen: number, added: number } } = {}

local function toCard(raw: any): Card?
	if type(raw) ~= "table" or type(raw.code) ~= "string" then
		return nil
	end
	local items = {}
	for _, entry in raw.items or {} do
		table.insert(items, CatalogueClient.remember(entry).id)
	end
	local card: Card = {
		code = raw.code,
		kind = "outfit",
		name = tostring(raw.name or "Outfit"),
		by = tostring(raw.by or ""),
		ownerId = 0,
		items = items,
		skin = SkinColours.normalise(raw.skin),
		scale = BodyScale.normalise(raw.scale),
		mine = raw.mine == true,
		wears = tonumber(raw.wears) or 0,
		favourites = tonumber(raw.favourites) or 0,
		community = { wears = tonumber(raw.wears) or 0, favourites = tonumber(raw.favourites) or 0 },
	} :: any
	SharedCodes.remember(card)
	return card
end

local function fetch(sort: string, state: State)
	local generation = state.generation
	local page = state.page + 1
	state.loading = true
	changedEvent:Fire()
	local ok, result = pcall(function()
		return remote:InvokeServer(sort, page)
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

function CommunityOutfits.load(sort: string, key: string?)
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

function CommunityOutfits.more(sort: string)
	local state = lists[sort]
	if state and state.more and not state.loading then
		state.loading = true
		task.defer(fetch, sort, state)
	end
end

function CommunityOutfits.get(sort: string): List
	return lists[sort] or { cards = {}, more = false, loading = true, error = nil }
end

function CommunityOutfits.noteWear(code: string, seen: number)
	local entry = worn[code]
	if entry and seen <= entry.seen + entry.added then
		entry.added += 1
	else
		worn[code] = { seen = seen, added = 1 }
	end
	changedEvent:Fire()
end

function CommunityOutfits.wears(code: string, server: number): number
	local entry = worn[code]
	if not entry then
		return server
	end
	return math.max(server, entry.seen + entry.added)
end

function CommunityOutfits.reset()
	for sort, state in lists do
		state.generation += 1 -- a load still running is dropped
		lists[sort] = nil
	end
	changedEvent:Fire()
end

return CommunityOutfits
