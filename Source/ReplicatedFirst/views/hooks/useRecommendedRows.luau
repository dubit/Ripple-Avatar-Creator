--!strict

--[[
	useRecommendedRows

	The catalogue's recommendation rows (CatalogueScreen, Clothing › All
	only, user 2026-11-26), top to bottom:

	  outfit     "Goes with your outfit": everything you're wearing (nothing
	             worn: your Roblox avatar, as the ring does)
	  tried      "Because you tried on <item>": the item put on last
	  basket     "Goes with your basket"
	  favourites "Picked from your favourites": your latest FAVOURITES_MAX
	  others     "Inspired by players here": what everyone else in the
	             server is wearing (the server knows; only with someone here)

	A row with nothing to go on isn't shown. Every row comes from the
	recommendation engine (Recommender.rows: one request for all of them).
	To go easy on the engine (user: "i don't want to hit our recommendation
	all the time"):
	  · it's only asked while `active` (the rows are on screen)
	  · answers are kept for the session, per row, with what they were
	    based on; a row is asked again only when that changes (so trying
	    something on re-asks outfit and tried, not basket or favourites)
	  · changes settle for SETTLE seconds first (a burst of try-ons is one
	    request), and only the changed rows go in it
	Worn items aren't sent for basket / favourites / others: the screen
	leaves out what you're wearing as it draws, so wearing doesn't re-ask
	them.

	Returns the rows to show, each { key, title, status = "loading" |
	"ready" | "failed", list (the engine's fitted items, best first), why
	(failed) }. The engine failing is shown on the row, never hidden
	(no silent fallbacks).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local views = script.Parent.Parent
local CatalogueClient = require(views:WaitForChild("catalogue"):WaitForChild("CatalogueClient"))
local Recommender = require(views:WaitForChild("catalogue"):WaitForChild("Recommender"))
local useBoltState = require(script.Parent:WaitForChild("useBoltState"))

type Item = CatalogueClient.Item

export type Row = {
	key: string,
	title: string,
	status: "loading" | "ready" | "failed",
	list: { Item },
	why: string?,
}

local TAB = "Clothing" -- the engine only suggests this tab's types
local ASK = 40 -- fitted items kept per row (the screen shows fewer, after dropping worn / repeats)
local SETTLE = 1 -- seconds a change waits before asking
local FAVOURITES_MAX = 20

-- What a row is based on: ids for the basis (CatalogueClient ids) and for
-- worn, or others; `basedOn` is all of that as a string (the cache key).
type Spec = {
	key: string,
	title: string,
	basisIds: { number },
	wornIds: { number },
	others: boolean?,
	basedOn: string,
}

type Kept = { basedOn: string, status: "loading" | "ready" | "failed", list: { Item }, why: string? }

-- Session memory, per row key (survives the panel closing).
local kept: { [string]: Kept } = {}
-- What each row is being asked for right now (basedOn), so it isn't asked twice.
local asked: { [string]: string } = {}

local function idsOfKeys(keys: { string }): { number }
	local ids = {}
	for _, key in keys do
		local kind, id = string.match(key, "^(%a+):(%d+)$")
		local n = tonumber(id)
		if n then
			table.insert(ids, if kind == "Bundle" then -n else n)
		end
	end
	return ids
end

-- Items for ids: from memory, looking up (yields) the ones not known yet.
local function itemsFor(ids: { number }): { Item }
	local missing = {}
	for _, id in ids do
		if not CatalogueClient.item(id) then
			table.insert(missing, { kind = if id < 0 then "Bundle" else "Asset", targetId = math.abs(id) } :: any)
		end
	end
	if #missing > 0 then
		CatalogueClient.lookupMany(missing)
	end
	local items = {}
	for _, id in ids do
		local item = CatalogueClient.item(id)
		if item then
			table.insert(items, item)
		end
	end
	return items
end

local function specsFor(worn: { number }, basket: { number }, favourites: { number }, others: { number }): { Spec }
	local specs: { Spec } = {}
	local function add(key: string, title: string, basisIds: { number }, wornIds: { number }, isOthers: boolean?)
		local basedOn = table.concat(basisIds, ",") .. "|" .. table.concat(wornIds, ",") .. (if isOthers then "|others" else "")
		table.insert(specs, { key = key, title = title, basisIds = basisIds, wornIds = wornIds, others = isOthers, basedOn = basedOn })
	end
	add("outfit", "Goes with your outfit", worn, {})
	local last = worn[#worn]
	local lastItem = last and CatalogueClient.item(last)
	if lastItem then
		add("tried", `Because you tried on {lastItem.name}`, { last }, worn)
	end
	if #basket > 0 then
		add("basket", "Goes with your basket", basket, {})
	end
	if #favourites > 0 then
		add("favourites", "Picked from your favourites", favourites, {})
	end
	if #others > 0 then
		-- Who's here (not what they wear: that changes too often to follow).
		add("others", "Inspired by players here", {}, others, true)
	end
	return specs
end

local function useRecommendedRows(look: { worn: { number }, basket: { number } }, active: boolean): { Row }
	local favouritesState = useBoltState(Network.State.Favourites, { ownerId = "", items = {} } :: any)
	local _, setVersion = React.useState(0)
	local function bump()
		setVersion(function(v: number)
			return v + 1
		end)
	end

	-- Everyone else here (the others row), kept up to date.
	local others, setOthers = React.useState({} :: { number })
	React.useEffect(function()
		local function refresh()
			local ids = {}
			for _, player in Players:GetPlayers() do
				if player ~= Players.LocalPlayer then
					table.insert(ids, player.UserId)
				end
			end
			table.sort(ids)
			setOthers(ids)
		end
		refresh()
		local added = Players.PlayerAdded:Connect(refresh)
		local removing = Players.PlayerRemoving:Connect(function()
			task.defer(refresh)
		end)
		return function()
			added:Disconnect()
			removing:Disconnect()
		end
	end, {})

	local favouriteKeys = favouritesState.items or {}
	local favourites = idsOfKeys({ table.unpack(favouriteKeys, math.max(1, #favouriteKeys - FAVOURITES_MAX + 1)) })
	local specs = specsFor(look.worn, look.basket, favourites, others)

	-- Ask for the rows whose basis changed, once things settle.
	local signature = {}
	for _, spec in specs do
		table.insert(signature, spec.key .. "=" .. spec.basedOn)
	end
	local signatureText = table.concat(signature, ";")
	local latest = React.useRef(specs)
	latest.current = specs
	React.useEffect(function()
		if not active then
			return
		end
		local started = false
		local function stale(spec: Spec): boolean
			local entry = kept[spec.key]
			return (not entry or entry.basedOn ~= spec.basedOn) and asked[spec.key] ~= spec.basedOn
		end
		-- The outfit row may already be here: asked for when they joined
		-- (Recommender.prefetch, from Hud), if the outfit is unchanged.
		for _, spec in specs do
			if spec.key == "outfit" and stale(spec) then
				local basis = {}
				for _, id in spec.basisIds do
					local item = CatalogueClient.item(id)
					if item then
						table.insert(basis, item)
					end
				end
				local answer = Recommender.prefetchedRow(basis, TAB, ASK)
				if answer and answer.list then
					local items = {}
					for _, recommendation in answer.list do
						table.insert(items, recommendation.item)
					end
					kept[spec.key] = { basedOn = spec.basedOn, status = "ready", list = items }
					task.defer(bump)
				end
			end
		end
		-- Rows never asked for show a spinner at once; changed ones keep
		-- their old items until the new ones come.
		local anyStale = false
		for _, spec in specs do
			if stale(spec) then
				anyStale = true
			end
		end
		if not anyStale then
			return
		end
		local timer = task.delay(SETTLE, function()
			started = true
			local asking: { Spec } = {}
			for _, spec in latest.current do
				if stale(spec) then
					table.insert(asking, spec)
				end
			end
			if #asking == 0 then
				return
			end
			for _, spec in asking do
				asked[spec.key] = spec.basedOn
			end
			local contexts: { Recommender.RowContext } = {}
			for index, spec in asking do
				contexts[index] = { basis = itemsFor(spec.basisIds), worn = itemsFor(spec.wornIds), others = spec.others }
			end
			local answers, why = Recommender.rows(contexts, TAB, ASK)
			for index, spec in asking do
				if asked[spec.key] == spec.basedOn then
					asked[spec.key] = nil
				end
				local answer = answers and answers[index]
				if answer and answer.list then
					local items = {}
					for _, recommendation in answer.list do
						table.insert(items, recommendation.item)
					end
					kept[spec.key] = { basedOn = spec.basedOn, status = "ready", list = items }
				else
					local reason = if answer then answer.why else why
					local old = kept[spec.key]
					kept[spec.key] = { basedOn = spec.basedOn, status = "failed", list = if old then old.list else {}, why = reason }
				end
			end
			bump()
		end)
		return function()
			-- Not yet asked: wait for the next change instead. Once asking,
			-- let it finish (its answers are kept by what they were based on).
			if not started then
				task.cancel(timer)
			end
		end
	end, { signatureText, active } :: { any })

	local rows: { Row } = {}
	for _, spec in specs do
		local entry = kept[spec.key]
		if not entry then
			table.insert(rows, { key = spec.key, title = spec.title, status = "loading", list = {} })
		elseif entry.status == "failed" then
			table.insert(rows, { key = spec.key, title = spec.title, status = "failed", list = {}, why = entry.why })
		else
			table.insert(rows, { key = spec.key, title = spec.title, status = "ready", list = entry.list })
		end
	end
	return rows
end

return useRecommendedRows
