--!strict

--[[
	Recommender (client)

	What goes in the recommendation ring. First choice is Ripple's
	recommendation engine, asked through the server ("Recommend",
	RecommendationsController); if that's off or fails, a heuristic over
	the catalogue search (below) makes the ring instead, and it also tops up
	a ring the engine left short.

	The engine: ask for ENGINE_ASK items (more than a ring holds; the
	server drops ones the player owns), look them up in one batch, then take
	the first ones that fit, in the engine's order: not worn, not already
	shown on this trail, not a skipped type (RecommendationConfig.skipTypes:
	classic clothing, gear, backgrounds, emotes, which aren't sent as basis
	or worn either), and not crowding one
	body area (a type already in the ring, or the basis's own type, is
	saved for a second pass). Then Ripple items (Tomorrow's Players, group
	RecommendationConfig.rippleGroupId) are promoted: one left out of the
	ring replaces the ring's weakest non-Ripple item if its score is at
	least rippleWithin x that item's, best Ripple item first, as long as it
	fits the same rules. Each recommendation's reason is the engine's
	first reason (bought_with, worn_with…); boosted = a Ripple item the
	engine pushed up; fallback = the engine padded its list with popular
	items, having too few recommendations for the basis.

	  recommend(context)  up to context.count recommendations (yields), each
	                      { item, reason, boosted? }, and whether the engine
	                      fell back (nil when the heuristic made the ring)
	  describe(list)      one line per recommendation, for debugging

	  recommend(context)  up to context.count recommendations (yields), each
	                      { item, reason }
	  describe(list)      one line per recommendation, for debugging

	context = {
		basis   the items the ring is about: the whole outfit for the first
		        ring, then the one item just walked through
		worn    what the player is wearing now
		exclude ids not to recommend (everything already shown on this trail)
		count   how many (6 with a back pad, 7 for the first ring)
	}

	The heuristic: each slot of a ring has a reason
	(RecommendationConfig.recipe, in order):
	  creator   the basis's creator, bestselling
	  complete  a part of the outfit nothing covers yet (a hat, shoes…),
	            searched with the basis's style words
	  style     the basis's style words, any wearable, most favourited
	  wildcard  popular this week in an uncovered part, no keyword
	A slot that can't be done (no creator, no style words) falls through to
	the next kind; one that comes back empty is retried without its keyword,
	then filled from whatever the other searches found ("fill").

	Searches go through CatalogueClient (its cache, its 429 backoff, this
	client's own rate limit), run side by side, at most
	RecommendationConfig.maxSearches per ring.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CatalogueClient = require(script.Parent:WaitForChild("CatalogueClient"))
local Bolt = require(ReplicatedStorage:WaitForChild("Bolt"))

local Config = ReplicatedStorage:WaitForChild("Config")
local CatalogueConfig = require(Config:WaitForChild("CatalogueConfig"))
local RecommendationConfig = require(Config:WaitForChild("RecommendationConfig"))

type Item = CatalogueClient.Item
type Query = CatalogueClient.Query
type Area = typeof(RecommendationConfig.areas[1])

export type Recommendation = {
	item: Item,
	reason: string, -- the engine's first reason, or the heuristic's slot
	boosted: boolean?, -- the engine pushed it up (a Ripple item)
	score: number?, -- the engine's score (nil from the heuristic)
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

local random = Random.new()

local function chipOf(categoryName: string, chipName: string): any
	for _, category in CatalogueConfig.categories do
		if category.name == categoryName then
			for _, chip in category.chips do
				if chip.name == chipName then
					return chip
				end
			end
		end
	end
	return nil
end

-- Every type the areas search, for searches across all wearables.
local wearableTypes = { assetTypes = {} :: { string }, bundleTypes = {} :: { string } }
do
	local have: { [string]: boolean } = {}
	for _, area in RecommendationConfig.areas do
		for _, chipName in area.chips do
			local chip = chipOf(area.category, chipName)
			if not chip then
				warn(`[Recommender] Unknown chip {area.category}/{chipName} in RecommendationConfig`)
				continue
			end
			for _, name in chip.assetTypes or {} do
				if not have[name] then
					have[name] = true
					table.insert(wearableTypes.assetTypes, name)
				end
			end
			for _, name in chip.bundleTypes or {} do
				if not have[name] then
					have[name] = true
					table.insert(wearableTypes.bundleTypes, name)
				end
			end
		end
	end
end

local function setOf(list: { string }): { [string]: boolean }
	local set = {}
	for _, value in list do
		set[string.lower(value)] = true
	end
	return set
end

local styleSet = setOf(RecommendationConfig.styleWords)
local colourSet = setOf(RecommendationConfig.colourWords)
local ignoredCreators = setOf(RecommendationConfig.ignoreCreators)

-- Style words first, then colours; most frequent first, ties to the latest
-- item (items run oldest first).
local function wordsOf(items: { Item }): { string }
	local score: { [string]: number } = {}
	for index, item in items do
		for word in string.gmatch(string.lower(item.name), "%w+") do
			if styleSet[word] or colourSet[word] then
				score[word] = (score[word] or 0) + 1 + index / 1000
			end
		end
	end
	local styles, colours = {}, {}
	for word in score do
		table.insert(if styleSet[word] then styles else colours, word)
	end
	local function byScore(a: string, b: string): boolean
		return score[a] > score[b]
	end
	table.sort(styles, byScore)
	table.sort(colours, byScore)
	for _, word in colours do
		table.insert(styles, word)
	end
	return styles
end

-- The most frequent creator that means something; ties to the latest item.
local function creatorOf(items: { Item }): string?
	local score: { [string]: number } = {}
	local best, bestScore = nil, 0
	for index, item in items do
		local name = item.creator
		if name ~= "" and not ignoredCreators[string.lower(name)] then
			score[name] = (score[name] or 0) + 1 + index / 1000
			if score[name] > bestScore then
				best, bestScore = name, score[name]
			end
		end
	end
	return best
end

-- Areas nothing in `items` covers, in a random order that favours the
-- heavier areas (weighted shuffle: sort by u^(1/weight)).
local function openAreas(items: { Item }): { Area }
	local worn: { [string]: boolean } = {}
	for _, item in items do
		worn[item.typeName] = true
	end
	local open = {}
	for _, area in RecommendationConfig.areas do
		local covered = false
		for _, typeName in area.covers do
			if worn[typeName] then
				covered = true
				break
			end
		end
		if not covered then
			table.insert(open, area)
		end
	end
	local key: { [Area]: number } = {}
	for _, area in open do
		key[area] = random:NextNumber() ^ (1 / math.max(area.weight or 1, 0.01))
	end
	table.sort(open, function(a: Area, b: Area): boolean
		return key[a] > key[b]
	end)
	return open
end

local function areaQuery(area: Area, keyword: string?, sort: string?, window: string?): Query
	return {
		category = area.category,
		chip = area.chips[random:NextInteger(1, #area.chips)],
		keyword = keyword,
		sort = sort,
		sortWindow = window,
	}
end

local function keyOf(query: Query): string
	return table.concat({
		query.category,
		query.chip or "",
		query.keyword or "",
		query.creator or "",
		query.sort or "",
		query.sortWindow or "",
	}, "|")
end

-- Runs the queries side by side; each result is a list (empty on failure).
local function runAll(queries: { Query }): { { Item } }
	local results: { { Item } } = {}
	local pending = #queries
	local thread = coroutine.running()
	local waiting = false
	for index, query in queries do
		task.spawn(function()
			local ok, result = CatalogueClient.search(query)
			results[index] = if ok then (result :: CatalogueClient.Result).items else {}
			if not ok then
				warn(`[Recommender] Search failed ({keyOf(query)}): {result}`)
			end
			pending -= 1
			if pending == 0 and waiting then
				task.spawn(thread)
			end
		end)
	end
	if pending > 0 then
		waiting = true
		coroutine.yield()
	end
	return results
end

type Slot = {
	reason: string,
	query: Query?,
	key: string?,
	fallback: Query?, -- the same search without its keyword
	item: Item?,
}

local function heuristic(context: Context): { Recommendation }
	local count = math.max(0, context.count)
	local recipe = RecommendationConfig.recipe

	local excluded: { [number]: boolean } = {}
	for id in context.exclude or {} do
		excluded[id] = true
	end
	for _, item in context.worn do
		excluded[item.id] = true
	end
	for _, item in context.basis do
		excluded[item.id] = true
	end

	local words = wordsOf(context.basis)
	local creator = creatorOf(context.basis)
	local covering = table.clone(context.worn)
	for _, item in context.basis do
		table.insert(covering, item)
	end
	local open = openAreas(covering)
	local areaCursor = 0
	local completes = 0
	local function nextArea(): Area
		areaCursor += 1
		if areaCursor <= #open then
			return open[areaCursor]
		end
		local areas = RecommendationConfig.areas
		return areas[random:NextInteger(1, #areas)]
	end

	-- Plan: a query per slot (slots of one kind share theirs).
	local slots: { Slot } = {}
	local shared: { [string]: Query } = {}
	for index = 1, count do
		local reason = recipe[((index - 1) % #recipe) + 1]
		local slot: Slot = { reason = reason }
		if slot.reason == "creator" and not creator then
			slot.reason = "style"
		end
		if slot.reason == "style" and not words[1] then
			slot.reason = "complete"
		end
		if slot.reason == "creator" then
			slot.query = shared.creator or {
				category = "Wearables",
				types = wearableTypes,
				creator = creator,
				sort = RecommendationConfig.creatorSort,
				sortWindow = "AllTime",
			}
			shared.creator = slot.query
		elseif slot.reason == "style" then
			slot.query = shared.style or {
				category = "Wearables",
				types = wearableTypes,
				keyword = words[1],
				sort = RecommendationConfig.styleSort,
				sortWindow = "AllTime",
			}
			shared.style = slot.query
		elseif slot.reason == "complete" then
			completes += 1
			local area = nextArea()
			local keyword = words[completes] or words[1]
			slot.query = areaQuery(area, keyword)
			if keyword then
				slot.fallback = areaQuery(area, nil, RecommendationConfig.styleSort, "AllTime")
			end
		else
			slot.reason = "wildcard"
			slot.query = areaQuery(nextArea(), nil, RecommendationConfig.wildcardSort, RecommendationConfig.wildcardWindow)
		end
		table.insert(slots, slot)
	end

	-- Run each distinct search once, within the budget.
	local budget = RecommendationConfig.maxSearches
	local found: { [string]: { Item } } = {}
	local function run(list: { Slot }, field: "query" | "fallback")
		local queries, keys = {}, {}
		local queued: { [string]: boolean } = {}
		for _, slot in list do
			local query = slot[field]
			if query then
				local key = keyOf(query)
				slot.key = key
				if not found[key] and not queued[key] and #queries < budget then
					queued[key] = true
					table.insert(queries, query)
					table.insert(keys, key)
				end
			end
		end
		budget -= #queries
		local results = runAll(queries)
		for index, key in keys do
			found[key] = results[index]
		end
	end

	local used: { [number]: boolean } = {}
	-- Prefer types not already in the ring, nor the basis's own (a creator's
	-- recolours of the item just chosen are the least useful picks).
	local usedTypes: { [string]: boolean } = {}
	for _, item in context.basis do
		usedTypes[item.typeName] = true
	end
	-- An item of a type already in the ring (or the basis's) is a spare: used
	-- only once a slot has nothing else, and at most once per ring.
	local spares, spareLimit = 0, 1
	local function take(items: { Item }, allowSpare: boolean): Item?
		local top, spare = {}, {}
		for _, item in items do
			if #top + #spare >= RecommendationConfig.pickFrom then
				break
			end
			if not excluded[item.id] and not used[item.id] and item.main ~= "" then
				table.insert(if usedTypes[item.typeName] then spare else top, item)
			end
		end
		local pool = top
		if #pool == 0 then
			if not allowSpare or spares >= spareLimit or #spare == 0 then
				return nil
			end
			pool = spare
			spares += 1
		end
		local item = pool[random:NextInteger(1, #pool)]
		used[item.id] = true
		usedTypes[item.typeName] = true
		return item
	end
	local function fill(list: { Slot }, allowSpare: boolean)
		for _, slot in list do
			if not slot.item and slot.key and found[slot.key] then
				slot.item = take(found[slot.key], allowSpare)
			end
		end
	end

	run(slots, "query")
	fill(slots, false)

	-- Empty slots with a keyword: try again without it.
	local retry = {}
	for _, slot in slots do
		if not slot.item and slot.fallback then
			table.insert(retry, slot)
		end
	end
	if #retry > 0 and budget > 0 then
		run(retry, "fallback")
		fill(retry, false)
	end

	-- Anything still empty: whatever the other searches found, a new type
	-- first, then (once) a spare from its own search, then any spare.
	-- Last of all, any number of spares (a short ring is worse than a recolour).
	for pass = 1, 3 do
		local allowSpare = pass > 1
		if pass == 2 then
			fill(slots, true)
		elseif pass == 3 then
			spareLimit = math.huge
		end
		for _, slot in slots do
			if not slot.item then
				for _, items in found do
					local item = take(items, allowSpare)
					if item then
						slot.item = item
						slot.reason = "fill"
						break
					end
				end
			end
		end
	end

	local list: { Recommendation } = {}
	for _, slot in slots do
		if slot.item then
			table.insert(list, { item = slot.item, reason = slot.reason })
		end
	end
	return list
end

-- ===== The engine =====

local ENGINE_ASK = 20 -- how many to ask for; the ring takes the first that fit
local engineRemote = Bolt.RemoteFunction("Recommend")

local function refOf(item: Item): { kind: string, id: number }
	return { kind = item.kind, id = item.targetId }
end

local skipTypes: { [string]: boolean } = {}
for _, name in RecommendationConfig.skipTypes do
	skipTypes[name] = true
end

-- The engine's list for this context, as items in its order, or nil if
-- the engine is off or failed.
local function fromEngine(context: Context): ({ Recommendation }?, boolean)
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

	local ok, answer = pcall(function()
		return engineRemote:InvokeServer({ basis = basis, worn = worn, exclude = exclude, count = ENGINE_ASK })
	end)
	if not ok or type(answer) ~= "table" or not answer.ok then
		if ok and type(answer) == "table" and answer.error ~= "disabled" then
			warn("[Recommender] engine unavailable (" .. tostring(answer.error) .. "): using the heuristic")
		elseif not ok then
			warn("[Recommender] engine call failed:", answer)
		end
		return nil, false
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
				boosted = raw.boosted,
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
			if excluded[item.id] or taken[item.id] or skipTypes[item.typeName] or item.owned then
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
			and not skipTypes[item.typeName] and not item.owned then
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

-- Drops skipped types and owned items from the heuristic's picks.
local function usable(list: { Recommendation }): { Recommendation }
	local kept = {}
	for _, entry in list do
		if not skipTypes[entry.item.typeName] and not entry.item.owned then
			table.insert(kept, entry)
		end
	end
	return kept
end

function Recommender.recommend(context: Context): ({ Recommendation }, boolean?)
	local candidates, fallback = fromEngine(context)
	if not candidates then
		return usable(heuristic(context)), nil
	end
	local list = fitRing(context, candidates)
	local short = context.count - #list
	if short > 0 then
		-- Too few that fit: the heuristic tops it up.
		local exclude = table.clone(context.exclude or {})
		for _, entry in list do
			exclude[entry.item.id] = true
		end
		for _, entry in usable(heuristic({ basis = context.basis, worn = context.worn, exclude = exclude, count = short })) do
			table.insert(list, entry)
		end
	end
	print(`[Recommender] engine ring ({#candidates} found{if fallback then ", fallback" else ""}):\n{Recommender.describe(list)}`)
	return list, fallback
end

function Recommender.describe(list: { Recommendation }): string
	local lines = {}
	for index, entry in list do
		local item = entry.item
		local marks = (if entry.ripple then " R" else "") .. (if entry.promoted then "↑" else "") .. (if entry.boosted then " ★" else "")
		local score = if entry.score then string.format(" %.4f", entry.score) else ""
		table.insert(lines, `{index}. [{entry.reason}]{marks}{score} {item.name} ({item.typeName}, by {item.creator}, {item.id})`)
	end
	return table.concat(lines, "\n")
end

return Recommender
