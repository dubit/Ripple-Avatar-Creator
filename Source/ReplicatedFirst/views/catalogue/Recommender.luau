--!strict

--[[
	Recommender (client)

	What goes in the recommendation ring: Ripple's recommendation engine,
	asked through the server ("Recommend", RecommendationsController). Only
	the engine (user, 2026-11-24): if it's off or fails, recommend() says
	why and the ring shows that, rather than filling itself some other way.

	Ask for ENGINE_ASK items (more than a ring holds; the server drops ones
	the player owns), look them up in one batch, then take the first ones
	that fit, in the engine's order: not worn, not already shown on this
	trail, not off sale, not a skipped type (RecommendationConfig.skipTypes:
	classic clothing, gear, backgrounds, emotes; of those, only classic
	clothing is sent as basis or worn: unsentTypes), and not crowding one body area (a type already in the ring, or
	the basis's own type, is saved for a second pass). Then Ripple items
	(Tomorrow's Players, group RecommendationConfig.rippleGroupId) are
	promoted: one left out of the ring replaces the ring's weakest
	non-Ripple item if its score is at least rippleWithin x that item's,
	best Ripple item first, as long as it fits the same rules. Each
	recommendation's reason is the engine's first reason (bought_with,
	worn_with…); fallback = the engine padded its list with popular items,
	having too few recommendations for the basis.

	  recommend(context)  (yields) up to context.count recommendations, each
	                      { item, reason, score?, ripple?, promoted? }, and
	                      whether the engine fell back; or nil and why not
	                      (a short message for the ring)
	  rows(contexts, tab, count)
	                      (yields) the catalogue's recommendation rows, all
	                      in one request ("RecommendRows"), limited to a
	                      catalogue tab's types; fitted like a ring but
	                      without spreading body areas (see rows below)
	  prefetch(worn, tab) (yields) once on joining: the first ring and the
	                      tab's outfit row in one request, kept while the
	                      outfit stays the same (recommend and
	                      prefetchedRow use them)
	  prefetchedRow(basis, tab, count)
	                      that row, fitted, if basis is still that outfit
	  describe(list)      one line per recommendation, for debugging

	context = {
		basis   the items the ring is about: the whole outfit for the first
		        ring, then the one item just walked through
		worn    what the player is wearing now
		exclude ids not to recommend (everything already shown on this trail)
		count   how many (6 with a back pad, 7 for the first ring)
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CatalogueClient = require(script.Parent:WaitForChild("CatalogueClient"))
local Bolt = require(ReplicatedStorage:WaitForChild("Bolt"))

local Config = ReplicatedStorage:WaitForChild("Config")
local RecommendationConfig = require(Config:WaitForChild("RecommendationConfig"))

type Item = CatalogueClient.Item

export type Recommendation = {
	item: Item,
	reason: string, -- the engine's first reason
	score: number?, -- the engine's score
	ripple: boolean?, -- a Ripple (Tomorrow's Players) item
	promoted: boolean?, -- moved into the ring over a non-Ripple item
}

export type Context = {
	basis: { Item },
	worn: { Item },
	exclude: { [number]: boolean }?,
	count: number,
}

local Recommender = {}

local ENGINE_ASK = 50 -- how many to ask for; the ring takes the first that fit, and
-- Ripple items further down can be promoted into it
local engineRemote = Bolt.RemoteFunction("Recommend")
local rowsRemote = Bolt.RemoteFunction("RecommendRows")

export type RowContext = {
	basis: { Item }, -- what the row is about ({} with others = true)
	worn: { Item }, -- sent as worn (context for the engine); not left out here
	others: boolean?, -- about what everyone else here is wearing (the server knows)
}

export type RowAnswer = {
	list: { Recommendation }?, -- nil: this row failed (why says why)
	why: string?,
	fallback: boolean?,
}


local function refOf(item: Item): { kind: string, id: number }
	return { kind = item.kind, id = item.targetId }
end

local skipTypes: { [string]: boolean } = {}
for _, name in RecommendationConfig.skipTypes do
	skipTypes[name] = true
end
local unsentTypes: { [string]: boolean } = {}
for _, name in RecommendationConfig.unsentTypes do
	unsentTypes[name] = true
end

-- The basis and worn refs to send for these items (unsentTypes left out;
-- a basis item isn't also sent as worn).
local function refsFor(basisItems: { Item }, wornItems: { Item }): ({ any }, { any })
	local basisIds: { [number]: boolean } = {}
	local basis = {}
	for _, item in basisItems do
		basisIds[item.id] = true
		if not unsentTypes[item.typeName] then
			table.insert(basis, refOf(item))
		end
	end
	-- First ring: the basis is the whole outfit, so nothing else is worn.
	local worn = {}
	for _, item in wornItems do
		if not basisIds[item.id] and not unsentTypes[item.typeName] then
			table.insert(worn, refOf(item))
		end
	end
	return basis, worn
end

-- The engine's items (from the server) as recommendations, in its order;
-- ones that can't be looked up are left out.
local function recommendationsOf(rawItems: { any }): { Recommendation }
	local refs = {}
	for _, raw in rawItems do
		table.insert(refs, { kind = raw.kind, targetId = raw.id })
	end
	local items = CatalogueClient.lookupMany(refs)
	local list: { Recommendation } = {}
	for _, raw in rawItems do
		local item = items[if raw.kind == "Bundle" then -raw.id else raw.id]
		if item then
			table.insert(list, {
				item = item,
				reason = raw.reasons[1] or "engine",
				score = raw.score,
				ripple = raw.groupId == RecommendationConfig.rippleGroupId,
			})
		end
	end
	return list
end

-- The engine's list for this context, as items in its order, whether it
-- fell back, and whether it went on the real Roblox avatar (nothing worn
-- to go on); or nil and why not.
local function fromEngine(context: Context): ({ Recommendation }?, boolean, string?, boolean)
	local basis, worn = refsFor(context.basis, context.worn)
	local exclude = {}
	for id in context.exclude or {} do
		table.insert(exclude, { kind = if id < 0 then "Bundle" else "Asset", id = math.abs(id) })
	end
	-- An empty basis is fine: the server goes on their real Roblox avatar.

	local ok, answer = pcall(function()
		return engineRemote:InvokeServer({ basis = basis, worn = worn, exclude = exclude, count = ENGINE_ASK })
	end)
	if not ok or type(answer) ~= "table" or not answer.ok then
		local why = if not ok
			then "couldn't reach the server"
			elseif type(answer) ~= "table" then "no answer"
			else tostring(answer.detail or answer.error)
		if ok and type(answer) == "table" and answer.error == "empty" then
			return nil, false, why, false -- not a failure: nothing to go on at all
		end
		warn("[Recommender] engine failed:", why, if not ok then answer else "")
		return nil, false, "Engine failed: " .. why, false
	end

	return recommendationsOf(answer.items), answer.fallback == true, nil, answer.fromRoblox == true
end

-- The first `count` of the engine's list that fit (see the header).
-- spread = false (catalogue rows): no saving a crowded body area for a
-- second pass. keep: also leave out items it says no to.
local function fitRing(context: Context, candidates: { Recommendation }, spread: boolean?, keep: ((Item) -> boolean)?): { Recommendation }
	local spreading = spread ~= false
	local excluded: { [number]: boolean } = {}
	for id in context.exclude or {} do
		excluded[id] = true
	end
	for _, item in context.worn do
		excluded[item.id] = true
	end
	local crowded: { [string]: boolean } = {}
	for _, item in context.basis do
		excluded[item.id] = true
		crowded[item.typeName] = true
	end
	local chosen: { Recommendation } = {}
	local taken: { [number]: boolean } = {}
	for pass = 1, 2 do
		for _, entry in candidates do
			if #chosen >= context.count then
				break
			end
			local item = entry.item
			if excluded[item.id] or taken[item.id] or skipTypes[item.typeName] or item.owned or item.offSale
				or (keep and not keep(item)) then
				continue
			end
			if pass == 1 and spreading and crowded[item.typeName] then
				continue
			end
			taken[item.id] = true
			crowded[item.typeName] = true
			table.insert(chosen, entry)
		end
	end

	-- Promote Ripple items: each left-out one, best score first, may take
	-- the place of the ring's weakest non-Ripple item if it scores at least
	-- rippleWithin x that item and doesn't crowd a body area (other than the
	-- one it frees).
	local waiting: { Recommendation } = {}
	for _, entry in candidates do
		local item = entry.item
		if entry.ripple and entry.score and not taken[item.id] and not excluded[item.id]
			and not skipTypes[item.typeName] and not item.owned and not item.offSale
			and (not keep or keep(item)) then
			table.insert(waiting, entry)
		end
	end
	table.sort(waiting, function(a, b)
		return (a.score :: number) > (b.score :: number)
	end)
	for _, entry in waiting do
		local weakest: number? = nil
		for index, other in chosen do
			if not other.ripple and other.score
				and (not weakest or (other.score :: number) < (chosen[weakest].score :: number)) then
				weakest = index
			end
		end
		if not weakest then
			break -- the ring is all Ripple (or all unscored)
		end
		local victim = chosen[weakest]
		if (entry.score :: number) < RecommendationConfig.rippleWithin * (victim.score :: number) then
			break -- best first, against the easiest to beat: none further on can
		end
		local typeName = entry.item.typeName
		local clash = false
		for _, item in if spreading then context.basis else {} do
			if item.typeName == typeName then
				clash = true
			end
		end
		for index, other in if spreading then chosen else {} do
			if index ~= weakest and other.item.typeName == typeName then
				clash = true
			end
		end
		if not clash then
			taken[entry.item.id] = true
			chosen[weakest] = table.clone(entry)
			chosen[weakest].promoted = true
		end
	end
	return chosen
end

-- ===== Join-time prefetch =====
-- Asked once when the player joins (Hud): the ring's first ring and the
-- catalogue's "Goes with your outfit" row, for what they're wearing, in one
-- request. Both are the whole outfit as basis; they differ only in types
-- (the ring: all but skipTypes; the row: one catalogue tab). Each is used
-- while the outfit is still exactly that one.
local function signatureOf(items: { Item }): string
	local ids = {}
	for _, item in items do
		table.insert(ids, tostring(item.id))
	end
	return table.concat(ids, ",")
end

type Prefetched = { signature: string, candidates: { Recommendation }, fallback: boolean, fromRoblox: boolean }
local prefetchedRing: Prefetched? = nil
local prefetchedRows: { [string]: Prefetched } = {}

-- (yields) Ask for both now. Failures are only warned: the ring and the
-- row then ask for themselves as usual (and show it if that fails too).
function Recommender.prefetch(worn: { Item }, tab: string)
	local basis = refsFor(worn, {})
	local signature = signatureOf(worn)
	local ok, answer = pcall(function()
		return rowsRemote:InvokeServer({
			tab = tab,
			rows = { { basis = basis, worn = {}, ring = true }, { basis = basis, worn = {} } },
		})
	end)
	if not ok or type(answer) ~= "table" or not answer.ok or type(answer.rows) ~= "table" then
		warn("[Recommender] prefetch failed:", if ok and type(answer) == "table" then answer.detail or answer.error else answer)
		return
	end
	local ring, row = answer.rows[1], answer.rows[2]
	if type(ring) == "table" and ring.ok and type(ring.items) == "table" then
		prefetchedRing = {
			signature = signature,
			candidates = recommendationsOf(ring.items),
			fallback = ring.fallback == true,
			fromRoblox = ring.fromRoblox == true,
		}
	end
	if type(row) == "table" and row.ok and type(row.items) == "table" then
		prefetchedRows[tab] = {
			signature = signature,
			candidates = recommendationsOf(row.items),
			fallback = row.fallback == true,
			fromRoblox = row.fromRoblox == true,
		}
	end
end

-- The prefetched outfit row for `tab`, fitted, if `basis` is still the
-- outfit it was asked for; else nil.
function Recommender.prefetchedRow(basis: { Item }, tab: string, count: number): RowAnswer?
	local kept = prefetchedRows[tab]
	if not kept or kept.signature ~= signatureOf(basis) then
		return nil
	end
	local function inTab(item: Item): boolean
		return item.main == tab
	end
	return { list = fitRing({ basis = basis, worn = {}, count = count }, kept.candidates, false, inTab), fallback = kept.fallback }
end

function Recommender.recommend(context: Context): ({ Recommendation }?, boolean, string?)
	-- The first ring (the whole outfit, nothing shown yet) can use the
	-- join-time prefetch if the outfit hasn't changed since.
	local candidates, fallback, why, fromRoblox
	local ring = prefetchedRing
	if ring and next(context.exclude or {}) == nil
		and signatureOf(context.basis) == ring.signature and signatureOf(context.worn) == ring.signature then
		candidates, fallback, fromRoblox = ring.candidates, ring.fallback, ring.fromRoblox
		print("[Recommender] first ring from the join-time prefetch")
	else
		candidates, fallback, why, fromRoblox = fromEngine(context)
	end
	if not candidates then
		return nil, false, why
	end
	local list = fitRing(context, candidates)
	if #list == 0 then
		return nil, fallback, `The engine found nothing new ({#candidates} suggested, all worn, owned or shown)`
	end
	print(`[Recommender] engine ring{if fromRoblox then " from the Roblox avatar" else ""} ({#candidates} found{if fallback then ", fallback" else ""}):\n{Recommender.describe(list)}`)
	return list, fallback
end

-- The catalogue's recommendation rows (CatalogueScreen): every row in one
-- request ("RecommendRows"), limited to the catalogue tab `tab`. Each row is
-- fitted like a ring but without spreading body areas, up to `count`, and
-- only items in that tab (item.main). Worn items are NOT left out (the
-- screen does that as it draws, so a row survives trying things on).
-- (yields) One answer per row, or nil and why the whole request failed.
function Recommender.rows(contexts: { RowContext }, tab: string, count: number): ({ RowAnswer }?, string?)
	local rows = {}
	for index, context in contexts do
		local basis, worn = refsFor(context.basis, context.worn)
		rows[index] = { basis = basis, worn = worn, others = context.others }
	end
	local ok, answer = pcall(function()
		return rowsRemote:InvokeServer({ tab = tab, rows = rows })
	end)
	if not ok or type(answer) ~= "table" or not answer.ok or type(answer.rows) ~= "table" then
		local why = if not ok
			then "couldn't reach the server"
			elseif type(answer) ~= "table" then "no answer"
			else tostring(answer.detail or answer.error)
		warn("[Recommender] engine rows failed:", why, if not ok then answer else "")
		return nil, "Engine failed: " .. why
	end
	local function inTab(item: Item): boolean
		return item.main == tab
	end
	local answers: { RowAnswer } = {}
	for index, context in contexts do
		local row = answer.rows[index]
		if type(row) ~= "table" or not row.ok or type(row.items) ~= "table" then
			local why = if type(row) == "table" then tostring(row.detail or row.error) else "no answer"
			answers[index] = { why = if type(row) == "table" and row.error == "empty" then why else "Engine failed: " .. why }
			continue
		end
		local fitted = fitRing({ basis = context.basis, worn = {}, count = count }, recommendationsOf(row.items), false, inTab)
		answers[index] = { list = fitted, fallback = row.fallback == true }
	end
	return answers
end

function Recommender.describe(list: { Recommendation }): string
	local lines = {}
	for index, entry in list do
		local item = entry.item
		local marks = (if entry.ripple then " R" else "") .. (if entry.promoted then "↑" else "")
		local score = if entry.score then string.format(" %.4f", entry.score) else ""
		table.insert(lines, `{index}. [{entry.reason}]{marks}{score} {item.name} ({item.typeName}, by {item.creator}, {item.id})`)
	end
	return table.concat(lines, "\n")
end


return Recommender
