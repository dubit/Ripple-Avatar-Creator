--!strict

--[[
	RecommendationsController

	Two jobs for the recommendation ring (RecommendationRing, client-only).

	1. The engine. Asks Ripple's recommendation engine for a ring, over the
	   "Recommend" remote function (Bolt). It's called from here, not the
	   client: HttpService only works on the server, and the API key is a
	   Roblox secret the client never sees. Where the engine is comes from
	   ServerScriptService.Config.RecommendationEngineConfig (Studio-authored;
	   see ConfigTypes/RecommendationEngineConfigTypes).

	     "Recommend"({ basis, worn, exclude, count })
	         -> { ok = true, fallback, items, fromRoblox } or { ok = false, error }
	     The engine leaves out RecommendationConfig.skipTypes (excludeTypes;
	     they still count as basis and worn).
	     An empty basis (wearing nothing the engine can use) means: go on
	     the player's real Roblox avatar instead (fromRoblox = true), less
	     body parts and RecommendationConfig.unsentTypes.
	     basis / worn / exclude: lists of { kind = "Asset" | "Bundle", id }
	     items: { kind, id, assetTypeId?, groupId?, score?, reasons }
	     fallback: the engine padded the list with popular items (it had
	     too few recommendations for the basis)
	     Items the player owns are dropped here (OwnershipService).

	   ok = false ("disabled", "busy", "failed", "bad request"), with a
	   short detail for "failed": the ring shows it (there's no other
	   source of recommendations).

	     "RecommendRows"({ tab, rows = { { basis, worn, others? } } })
	         -> { ok = true, rows = { per row: { ok, items, fallback,
	              fromRoblox } or { ok = false, error, detail } } }
	     The catalogue's recommendation rows (Clothing › All): up to
	     MAX_ROWS lists in ONE engine request and one go of the budget, each
	     limited to the tab's types (excludeTypes / excludeKinds from
	     CatalogueConfig). others = true: the basis is what everyone else in
	     the server is wearing (AvatarModel).

	2. Analytics. The client reports what each ring offered and what the
	   player did with it, and this records it: the implicit feedback the
	   engine learns from (a set shown, one chosen). Nothing is stored; a bad
	   or over-budget report is dropped, never answered.

	3. Sharing. The client says what its ring holds and where
	   (ShareRing), and RingsModel shares that with everyone, so other
	   players see the ring's items round them (OthersRings). Checked here:
	   at most RING_PADS pads, real ids, spots near the player.

	Actions:
		Track({ event, ... })   one of the events below, with its params
		ShareRing({ pads })     the player's ring now: { { kind, id, x, y,
		                        z, back } }; no pads = the ring closed

	Events (names and every param checked here, so a client can't invent
	them). Item ids are CatalogueClient ids: an asset's id, or a bundle's id
	negated. A reason is the engine's first reason (bought_with,
	worn_with…).
		rec_open    { outfit_size }      the ring opened (tapping yourself)
		rec_ring    { trail_id, depth, basis_id, back_id, revisit, fallback?,
		              item_1..item_7, reason_1..reason_7 }
		                                 a ring was shown: its new items in
		                                 order and why each was chosen;
		                                 basis_id 0 = the whole outfit;
		                                 back_id 0 = no back pad; revisit =
		                                 shown again by going back; fallback
		                                 = the engine padded it. A ring the
		                                 engine failed is not reported
		rec_pick    { trail_id, depth, item_id, reason, slot }
		                                 an item was walked onto (also
		                                 logged as try_on)
		rec_back    { trail_id, depth, undone }   the back pad was used
		rec_others_pick { item_id, back }  an item in another player's ring
		                                 was tapped and put on (back: it
		                                 was their back pad's ghost)
		onboarding_hint { step }          the onboarding hint showed (first
		                                 time a session; step "ring": tap
		                                 yourself). Not a ring event, but
		                                 its funnel ends at rec_open
		rec_close   { trail_id, depth, rings, picks, reason }
		                                 the ring closed: reason tap /
		                                 walk_away / respawn

	"Track" is in AnalyticsConfig.excludedActions, so these aren't also
	logged as controller_action.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AbstractController = require(script.Parent.AbstractController)
local OwnershipModel = require(script.Parent.Parent.models.userSession.OwnershipModel)
local OnboardingModel = require(script.Parent.Parent.models.user.OnboardingModel)
local AvatarModel = require(script.Parent.Parent.models.user.AvatarModel)
local RingsModel = require(script.Parent.Parent.models.server.RingsModel)
local OwnershipService = require(script.Parent.Parent.services.game.OwnershipService)
local RobloxAvatarLookupService = require(script.Parent.Parent.services.game.RobloxAvatarLookupService)
local Bolt = require(ReplicatedStorage.Bolt)
local Network = require(ReplicatedStorage.Network)

local RecommendationsController = {}
RecommendationsController.__index = RecommendationsController
setmetatable(RecommendationsController, AbstractController)

export type RecommendationsController = typeof(setmetatable({}, RecommendationsController)) & AbstractController.AbstractController

local MAX_ITEMS = 7
local MAX_DEPTH = 500
local MAX_COUNT = 10000
-- A reason: whatever the engine says (bought_with, worn_with…), a short
-- snake_case word.
local function isReason(value: any): boolean
	return type(value) == "string" and #value <= 24 and string.match(value, "^[a-z][a-z_]*$") ~= nil
end
local CLOSE_REASONS = { tap = true, walk_away = true, respawn = true }

-- At most BUDGET reports per WINDOW seconds per player.
local BUDGET = 30
local WINDOW = 10

local recent: { [Player]: { number } } = {}

-- Engine requests: at most ENGINE_BUDGET per ENGINE_WINDOW seconds per player
-- (a ring is one request; walking a trail quickly makes a few).
local ENGINE_BUDGET = 12
local ENGINE_WINDOW = 10
local MAX_REFS = { basis = 60, worn = 60, exclude = 400 }
local MAX_COUNT_ASKED = 50

local engineRecent: { [Player]: { number } } = {}

-- Types never sent to the engine (the client's list) and body parts: what
-- a real Roblox avatar's items are filtered by when they stand in for an
-- empty outfit.
local notBasis: { [string]: boolean } = {
	Head = true, DynamicHead = true, Torso = true, LeftArm = true, RightArm = true,
	LeftLeg = true, RightLeg = true,
}
local RecommendationConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("RecommendationConfig"))
for _, name in RecommendationConfig.unsentTypes do
	notBasis[name] = true
end

-- Types the ring never shows (RecommendationConfig.skipTypes), as asset
-- type ids for the engine's excludeTypes, so it fills the list with ones
-- we can use. Names that aren't asset types are left to the client's filter.
local excludeTypes: { number } = {}
for _, name in RecommendationConfig.skipTypes do
	local ok, assetType = pcall(function()
		return (Enum.AssetType :: any)[name]
	end)
	if ok and assetType then
		table.insert(excludeTypes, assetType.Value)
	end
end

-- The player's real Roblox avatar, as engine refs.
local function robloxBasis(player: Player): { { kind: string, id: number } }
	local refs = {}
	for _, item in RobloxAvatarLookupService.robloxItems(player.UserId) do
		if not notBasis[item.typeName] and #refs < MAX_REFS.basis then
			table.insert(refs, { kind = item.kind, id = item.targetId })
		end
	end
	return refs
end

-- Lazy, like AbstractController (avoids a load-order dependency).
local analytics: any = nil
local function track(player: Player, eventName: string, params: { [string]: any })
	if analytics == nil then
		local ok, service = pcall(function()
			return require(script.Parent.Parent.services.framework.AnalyticsService)
		end)
		analytics = if ok then service else false
	end
	if analytics and analytics.isEnabled then
		analytics:trackEvent(player, eventName, params)
	end
end

local function isInt(value: any, low: number, high: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= low and value <= high
end

local function isId(value: any): boolean
	return isInt(value, -2 ^ 53, 2 ^ 53) and value ~= 0
end

local function isIdOrNone(value: any): boolean
	return value == 0 or isId(value)
end

local function trailOk(raw: any): boolean
	return isInt(raw.trail_id, 1, 2 ^ 31) and isInt(raw.depth, 1, MAX_DEPTH)
end

local HANDLERS: { [string]: (Player, any) -> () } = {
	rec_open = function(player, raw)
		if isInt(raw.outfit_size, 0, 200) then
			track(player, "rec_open", { outfit_size = raw.outfit_size })
		end
		-- They've found the ring: the onboarding hint stops (OnboardingHint).
		local onboarding = OnboardingModel.get(tostring(player.UserId))
		if onboarding then
			onboarding:complete("ring")
		end
	end,
	-- The onboarding hint showed (first time this session).
	onboarding_hint = function(player, raw)
		if raw.step == "ring" then
			track(player, "onboarding_hint", { step = raw.step })
		end
	end,
	rec_ring = function(player, raw)
		if not trailOk(raw) or not isIdOrNone(raw.basis_id) or not isIdOrNone(raw.back_id) or type(raw.revisit) ~= "boolean" then
			return
		end
		local params: { [string]: any } = {
			trail_id = raw.trail_id,
			depth = raw.depth,
			basis_id = raw.basis_id,
			back_id = raw.back_id,
			revisit = raw.revisit,
		}
		if raw.fallback ~= nil then
			if type(raw.fallback) ~= "boolean" then
				return
			end
			params.fallback = raw.fallback
		end
		for index = 1, MAX_ITEMS do
			local id, reason = raw["item_" .. index], raw["reason_" .. index]
			if id == nil and reason == nil then
				continue
			end
			if not isId(id) or not isReason(reason) then
				return
			end
			params["item_" .. index] = id
			params["reason_" .. index] = reason
		end
		track(player, "rec_ring", params)
	end,
	rec_pick = function(player, raw)
		if trailOk(raw) and isId(raw.item_id) and isReason(raw.reason) and isInt(raw.slot, 1, MAX_ITEMS) then
			track(player, "rec_pick", {
				trail_id = raw.trail_id,
				depth = raw.depth,
				item_id = raw.item_id,
				reason = raw.reason,
				slot = raw.slot,
			})
		end
	end,
	rec_others_pick = function(player, raw)
		if isId(raw.item_id) and type(raw.back) == "boolean" then
			track(player, "rec_others_pick", { item_id = raw.item_id, back = raw.back })
		end
	end,
	rec_back = function(player, raw)
		if trailOk(raw) and type(raw.undone) == "boolean" then
			track(player, "rec_back", { trail_id = raw.trail_id, depth = raw.depth, undone = raw.undone })
		end
	end,
	rec_close = function(player, raw)
		if trailOk(raw) and isInt(raw.rings, 1, MAX_COUNT) and isInt(raw.picks, 0, MAX_COUNT)
			and type(raw.reason) == "string" and CLOSE_REASONS[raw.reason] then
			track(player, "rec_close", {
				trail_id = raw.trail_id,
				depth = raw.depth,
				rings = raw.rings,
				picks = raw.picks,
				reason = raw.reason,
			})
		end
	end,
}

local function trackReport(player: Player, raw: any)
	if type(raw) ~= "table" or type(raw.event) ~= "string" then
		return
	end
	local handler = HANDLERS[raw.event]
	if handler then
		handler(player, raw)
	end
end

-- A shared ring: at most RING_PADS pads, each a real item on a spot within
-- RING_REACH studs of the player (the ring is left where it opened; the
-- player closes it by walking well away, so a little further than its radius).
local RING_PADS = 8
local RING_REACH = 40

local function shareRing(player: Player, raw: any)
	local userId = tostring(player.UserId)
	local rings = RingsModel.get()
	if type(raw) ~= "table" or type(raw.pads) ~= "table" or #raw.pads == 0 then
		rings:clear(userId)
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or #raw.pads > RING_PADS then
		return
	end
	local pads = {}
	for _, pad in raw.pads do
		if type(pad) ~= "table" or (pad.kind ~= "Asset" and pad.kind ~= "Bundle") or not isInt(pad.id, 1, 2 ^ 53) then
			return
		end
		local x, y, z = pad.x, pad.y, pad.z
		if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or x ~= x or y ~= y or z ~= z then
			return
		end
		local spot = Vector3.new(x, y, z)
		if (spot - root.Position).Magnitude > RING_REACH then
			return
		end
		table.insert(pads, { kind = pad.kind, id = pad.id, x = x, y = y, z = z, back = pad.back == true })
	end
	rings:set(userId, pads)
end

local ACTIONS = {
	[Network.Actions.Recommendations.Track] = trackReport,
	[Network.Actions.Recommendations.ShareRing] = shareRing,
}

-- True if the player still has `budget` in the last `window` seconds of
-- `log` (and spends one).
local function spend(log: { [Player]: { number } }, player: Player, budget: number, window: number): boolean
	local now = os.clock()
	local times = log[player] or {}
	log[player] = times
	while times[1] and now - times[1] > window do
		table.remove(times, 1)
	end
	if #times >= budget then
		return false
	end
	table.insert(times, now)
	return true
end

local function allowed(player: Player): boolean
	return spend(recent, player, BUDGET, WINDOW)
end

-- ===== The engine =====

-- The engine's config: Studio-authored, read once. Missing means disabled
-- (warned): the ring shows "Engine failed: disabled".
local engineConfig: any = nil
local function engine(): any
	if engineConfig == nil then
		local module = ServerScriptService:WaitForChild("Config"):WaitForChild("RecommendationEngineConfig", 10)
		if module then
			engineConfig = require(module :: ModuleScript)
		else
			warn("[RecommendationsController] No ServerScriptService.Config.RecommendationEngineConfig: the ring is disabled")
			engineConfig = { enabled = false }
		end
	end
	return engineConfig
end

-- A list of { kind, id } from the client, or nil if it's malformed.
local function refsOf(raw: any, max: number): { { kind: string, id: number } }?
	if raw == nil then
		return {}
	end
	if type(raw) ~= "table" or #raw > max then
		return nil
	end
	local list = {}
	for _, ref in raw do
		if type(ref) ~= "table" or (ref.kind ~= "Asset" and ref.kind ~= "Bundle") or not isInt(ref.id, 1, 2 ^ 53) then
			return nil
		end
		table.insert(list, { kind = ref.kind, id = ref.id })
	end
	return list
end

-- One item from the engine, checked and trimmed to what the client needs.
local function itemOf(raw: any): any?
	if type(raw) ~= "table" or (raw.kind ~= "Asset" and raw.kind ~= "Bundle") or not isInt(raw.id, 1, 2 ^ 53) then
		return nil
	end
	local reasons = {}
	if type(raw.reasons) == "table" then
		for _, reason in raw.reasons do
			if isReason(reason) and #reasons < 4 then
				table.insert(reasons, reason)
			end
		end
	end
	return {
		kind = raw.kind,
		id = raw.id,
		assetTypeId = if type(raw.assetTypeId) == "number" then raw.assetTypeId else nil,
		groupId = if type(raw.groupId) == "number" then raw.groupId else nil,
		score = if type(raw.score) == "number" then raw.score else nil,
		reasons = reasons,
	}
end

-- Sends `queries` to the engine in one request: its results in the same
-- order (each { items, fallback }, items checked by itemOf), or nil and a
-- short detail.
local function askEngine(config: any, queries: { any }): ({ { items: { any }, fallback: boolean } }?, string?)
	local ok, response = pcall(function()
		local auth = HttpService:GetSecret(config.secretName):AddPrefix("Bearer ")
		return HttpService:RequestAsync({
			Url = config.baseUrl .. "/v1/recommend",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", Authorization = auth },
			Body = HttpService:JSONEncode({ queries = queries }),
		})
	end)
	if not ok then
		warn("[RecommendationsController] engine request failed:", response)
		return nil, string.sub(tostring(response), 1, 120)
	end
	if not response.Success then
		warn("[RecommendationsController] engine answered", response.StatusCode, string.sub(response.Body or "", 1, 200))
		return nil, `HTTP {response.StatusCode} {string.sub(response.Body or "", 1, 100)}`
	end
	local decoded, body = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decoded or type(body) ~= "table" or type(body.results) ~= "table" then
		warn("[RecommendationsController] engine answer not understood:", string.sub(response.Body or "", 1, 200))
		return nil, "answer not understood"
	end
	local results = {}
	for index = 1, #queries do
		local result = body.results[index]
		if type(result) ~= "table" or type(result.items) ~= "table" then
			warn("[RecommendationsController] engine answer not understood:", string.sub(response.Body or "", 1, 200))
			return nil, "answer not understood"
		end
		local items = {}
		for _, rawItem in result.items do
			local item = itemOf(rawItem)
			if item then
				table.insert(items, item)
			end
		end
		results[index] = { items = items, fallback = result.fallback == true }
	end
	return results
end

-- Not things the player owns (user, 2026-11-24): drops them from each
-- list, and says how many went. The lookups run in parallel (all the
-- lists' items at once) and are remembered for the session
-- (OwnershipModel), so the client's items show as owned elsewhere too.
local function dropOwned(player: Player, lists: { { any } }): ({ { any } }, number)
	local ownership = OwnershipModel.get(tostring(player.UserId))
	if not ownership then
		return lists, 0
	end
	local refs, seen = {}, {}
	for _, items in lists do
		for _, item in items do
			local key = OwnershipService.keyOf(item.id, item.kind)
			if not seen[key] then
				seen[key] = true
				table.insert(refs, { targetId = item.id, kind = item.kind })
			end
		end
	end
	OwnershipService.check(player, ownership, refs)
	local dropped = 0
	local out = {}
	for index, items in lists do
		local kept = {}
		for _, item in items do
			if ownership:owns(OwnershipService.keyOf(item.id, item.kind)) then
				dropped += 1
			else
				table.insert(kept, item)
			end
		end
		out[index] = kept
	end
	return out, dropped
end

local function engineReady(): (any?, any?)
	local config = engine()
	if not config.enabled or type(config.baseUrl) ~= "string" or config.baseUrl == "" then
		return nil, { ok = false, error = "disabled" }
	end
	return config, nil
end

local function recommend(player: Player, raw: any): any
	local config, refusal = engineReady()
	if not config then
		return refusal
	end
	if type(raw) ~= "table" then
		return { ok = false, error = "bad request" }
	end
	local basis = refsOf(raw.basis, MAX_REFS.basis)
	local worn = refsOf(raw.worn, MAX_REFS.worn)
	local exclude = refsOf(raw.exclude, MAX_REFS.exclude)
	if not basis or not worn or not exclude then
		return { ok = false, error = "bad request" }
	end
	if not spend(engineRecent, player, ENGINE_BUDGET, ENGINE_WINDOW) then
		return { ok = false, error = "busy" }
	end
	-- Wearing nothing the engine can use: go on their real Roblox avatar.
	local fromRoblox = false
	if #basis == 0 then
		basis = robloxBasis(player)
		fromRoblox = true
		if #basis == 0 then
			return { ok = false, error = "empty", detail = "Nothing to go on: put something on" }
		end
	end
	local count = if isInt(raw.count, 1, MAX_COUNT_ASKED) then raw.count else config.count or 20

	local started = os.clock()
	local results, detail = askEngine(config, {
		{ basis = basis, worn = worn, exclude = exclude, excludeTypes = excludeTypes, count = count },
	})
	if not results then
		return { ok = false, error = "failed", detail = detail }
	end
	local result = results[1]
	local lists, dropped = dropOwned(player, { result.items })
	local items = lists[1]
	if config.debug then
		print(string.format(
			"[RecommendationsController] engine: %d items (%d owned dropped) for %s (basis %d%s, worn %d, exclude %d) in %.2fs%s",
			#items, dropped, player.Name, #basis, if fromRoblox then " from their Roblox avatar" else "", #worn, #exclude, os.clock() - started,
			if result.fallback then ", fallback" else ""
		))
	end
	return { ok = true, fallback = result.fallback, items = items, fromRoblox = fromRoblox }
end

-- ===== Catalogue rows =====

-- A catalogue tab's limits for the engine: every asset type outside it
-- (and the ring's skipTypes) as excludeTypes, and whether bundles can be in
-- it (a tab with no bundle chips leaves them out: excludeKinds). nil: not
-- a tab the rows can be on (no such tab, or a special one).
local CatalogueConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CatalogueConfig"))
local tabLimits: { [string]: { excludeTypes: { number }, excludeKinds: { string }? } } = {}
local function limitsOf(tab: any): { excludeTypes: { number }, excludeKinds: { string }? }?
	if type(tab) ~= "string" then
		return nil
	end
	if tabLimits[tab] then
		return tabLimits[tab]
	end
	for _, entry in CatalogueConfig.categories do
		if entry.name ~= tab or entry.special then
			continue
		end
		local inside: { [string]: boolean } = {}
		local bundles = false
		for _, chip in entry.chips do
			for _, name in chip.assetTypes or {} do
				inside[name] = true
			end
			if chip.bundleTypes and #chip.bundleTypes > 0 then
				bundles = true
			end
		end
		local outside = table.clone(excludeTypes)
		for _, assetType in Enum.AssetType:GetEnumItems() do
			if not inside[assetType.Name] and not table.find(outside, assetType.Value) then
				table.insert(outside, assetType.Value)
			end
		end
		local limits = { excludeTypes = outside, excludeKinds = if bundles then nil else { "Bundle" } }
		tabLimits[tab] = limits
		return limits
	end
	return nil
end

-- What everyone else in the server is wearing, as engine refs (the "players
-- here" row), less body parts and unsentTypes.
local function othersBasis(player: Player): { { kind: string, id: number } }
	local refs, seen = {}, {}
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local avatar = AvatarModel.get(tostring(other.UserId))
		for _, item in if avatar then avatar.worn else {} do
			local key = item.kind .. item.targetId
			if not notBasis[item.typeName] and not seen[key] and #refs < MAX_REFS.basis then
				seen[key] = true
				table.insert(refs, { kind = item.kind, id = item.targetId })
			end
		end
	end
	return refs
end

local MAX_ROWS = 5

-- "RecommendRows"({ tab, rows = { { basis, worn, others?, ring? } } })
--   -> { ok = true, rows = { { ok = true, items, fallback, fromRoblox }
--        | { ok = false, error, detail? } } } or { ok = false, error, detail? }
-- The catalogue's recommendation rows (CatalogueScreen): every row in one
-- engine request and one go of the budget, limited to the tab's types.
-- others = true: the basis is what everyone else here is wearing (sent
-- basis ignored). ring = true: not limited to the tab, but like "Recommend"
-- (the client's join-time prefetch of the ring's first ring, Recommender).
-- An empty basis otherwise means their Roblox avatar.
local function recommendRows(player: Player, raw: any): any
	local config, refusal = engineReady()
	if not config then
		return refusal
	end
	if type(raw) ~= "table" or type(raw.rows) ~= "table" or #raw.rows == 0 or #raw.rows > MAX_ROWS then
		return { ok = false, error = "bad request" }
	end
	local limits = limitsOf(raw.tab)
	if not limits then
		return { ok = false, error = "bad request" }
	end
	local asks = {}
	for index, row in raw.rows do
		if type(row) ~= "table" or (row.others ~= nil and type(row.others) ~= "boolean")
			or (row.ring ~= nil and type(row.ring) ~= "boolean") then
			return { ok = false, error = "bad request" }
		end
		local basis = refsOf(row.basis, MAX_REFS.basis)
		local worn = refsOf(row.worn, MAX_REFS.worn)
		if not basis or not worn then
			return { ok = false, error = "bad request" }
		end
		asks[index] = { basis = basis, worn = worn, others = row.others == true, ring = row.ring == true }
	end
	if not spend(engineRecent, player, ENGINE_BUDGET, ENGINE_WINDOW) then
		return { ok = false, error = "busy" }
	end

	local answers = {}
	local queries, queried = {}, {}
	for index, ask in asks do
		local fromRoblox = false
		if ask.others then
			ask.basis = othersBasis(player)
		elseif #ask.basis == 0 then
			ask.basis = robloxBasis(player)
			fromRoblox = true
		end
		if #ask.basis == 0 then
			answers[index] = { ok = false, error = "empty", detail = if ask.others then "Nobody else here is wearing anything to go on" else "Nothing to go on: put something on" }
			continue
		end
		answers[index] = { ok = true, fromRoblox = fromRoblox }
		table.insert(queries, {
			basis = ask.basis,
			worn = ask.worn,
			-- ring = true: the ring's first ring instead (every type but
			-- skipTypes), asked alongside when the player joins.
			excludeTypes = if ask.ring then excludeTypes else limits.excludeTypes,
			excludeKinds = if ask.ring then nil else limits.excludeKinds,
			count = MAX_COUNT_ASKED,
		})
		table.insert(queried, index)
	end
	if #queries == 0 then
		return { ok = true, rows = answers }
	end

	local started = os.clock()
	local results, detail = askEngine(config, queries)
	if not results then
		return { ok = false, error = "failed", detail = detail }
	end
	local lists = {}
	for slot in queried do
		lists[slot] = results[slot].items
	end
	local kept, dropped = dropOwned(player, lists)
	for slot, index in queried do
		answers[index].items = kept[slot]
		answers[index].fallback = results[slot].fallback
	end
	if config.debug then
		print(string.format(
			"[RecommendationsController] engine rows: %d queries (%s) for %s, %d owned dropped, in %.2fs",
			#queries, tostring(raw.tab), player.Name, dropped, os.clock() - started
		))
	end
	return { ok = true, rows = answers }
end

function RecommendationsController:executeAction(player: Player, action: Network.RecommendationsAction, raw: any)
	if not allowed(player) then
		return
	end
	self:dispatchAction(ACTIONS, action, player, player, raw)
end

function RecommendationsController.new(): RecommendationsController
	local self = AbstractController.new("RecommendationsController") :: any
	setmetatable(self, RecommendationsController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.RecommendationsAction, raw: any)
		self:executeAction(player, action, raw)
	end)

	Bolt.RemoteFunction("Recommend").OnServerInvoke = recommend
	Bolt.RemoteFunction("RecommendRows").OnServerInvoke = recommendRows

	-- A ring closes when its player respawns or leaves: so does the shared one.
	local function forgetRing(player: Player)
		RingsModel.get():clear(tostring(player.UserId))
	end
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			forgetRing(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		recent[player] = nil
		engineRecent[player] = nil
		forgetRing(player)
	end)

	return self :: RecommendationsController
end

return RecommendationsController
