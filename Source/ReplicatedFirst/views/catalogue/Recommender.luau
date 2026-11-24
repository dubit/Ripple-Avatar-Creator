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
	trail, not off sale, not a skipped type (RecommendationConfig.skipTypes: classic
	clothing, gear, backgrounds, emotes, which aren't sent as basis or worn
	either), and not crowding one body area (a type already in the ring, or
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

local function refOf(item: Item): { kind: string, id: number }
	return { kind = item.kind, id = item.targetId }
end

local skipTypes: { [string]: boolean } = {}
for _, name in RecommendationConfig.skipTypes do
	skipTypes[name] = true
end

-- The engine's list for this context, as items in its order, and whether
-- it fell back; or nil and why not.
local function fromEngine(context: Context): ({ Recommendation }?, boolean, string?)
	local basisIds: { [number]: boolean } = {}
	local basis = {}
	for _, item in context.basis do
		basisIds[item.id] = true
		if not skipTypes[item.typeName] then
			table.insert(basis, refOf(item))
		end
	end
	-- First ring: the basis is the whole outfit, so nothing else is worn.
	local worn = {}
	for _, item in context.worn do
		if not basisIds[item.id] and not skipTypes[item.typeName] then
			table.insert(worn, refOf(item))
		end
	end
	local exclude = {}
	for id in context.exclude or {} do
		table.insert(exclude, { kind = if id < 0 then "Bundle" else "Asset", id = math.abs(id) })
	end
	if #basis == 0 then
		return nil, false, "Nothing to go on: only classic clothing, gear or emotes"
	end

	local ok, answer = pcall(function()
		return engineRemote:InvokeServer({ basis = basis, worn = worn, exclude = exclude, count = ENGINE_ASK })
	end)
	if not ok or type(answer) ~= "table" or not answer.ok then
		local why = if not ok
			then "couldn't reach the server"
			elseif type(answer) ~= "table" then "no answer"
			else tostring(answer.detail or answer.error)
		warn("[Recommender] engine failed:", why, if not ok then answer else "")
		return nil, false, "Engine failed: " .. why
	end

	local refs = {}
	for _, raw in answer.items do
		table.insert(refs, { kind = raw.kind, targetId = raw.id })
	end
	local items = CatalogueClient.lookupMany(refs)
	local list: { Recommendation } = {}
	for _, raw in answer.items do
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
	return list, answer.fallback == true
end

-- The first `count` of the engine's list that fit (see the header).
local function fitRing(context: Context, candidates: { Recommendation }): { Recommendation }
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
			if excluded[item.id] or taken[item.id] or skipTypes[item.typeName] or item.owned or item.offSale then
				continue
			end
			if pass == 1 and crowded[item.typeName] then
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
			and not skipTypes[item.typeName] and not item.owned and not item.offSale then
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
		for _, item in context.basis do
			if item.typeName == typeName then
				clash = true
			end
		end
		for index, other in chosen do
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

function Recommender.recommend(context: Context): ({ Recommendation }?, boolean, string?)
	local candidates, fallback, why = fromEngine(context)
	if not candidates then
		return nil, false, why
	end
	local list = fitRing(context, candidates)
	if #list == 0 then
		return nil, fallback, `The engine found nothing new ({#candidates} suggested, all worn, owned or shown)`
	end
	print(`[Recommender] engine ring ({#candidates} found{if fallback then ", fallback" else ""}):\n{Recommender.describe(list)}`)
	return list, fallback
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
