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
	         -> { ok = true, fallback, items } or { ok = false, error }
	     basis / worn / exclude: lists of { kind = "Asset" | "Bundle", id }
	     items: { kind, id, assetTypeId?, groupId?, score?, reasons }
	     fallback: the engine padded the list with popular items (it had
	     too few recommendations for the basis)
	     Items the player owns are dropped here (OwnershipService).

	   ok = false ("disabled", "busy", "failed", "bad request") means the
	   client uses its own heuristic (Recommender) instead.

	2. Analytics. The client reports what each ring offered and what the
	   player did with it, and this records it: the implicit feedback the
	   engine learns from (a set shown, one chosen). Nothing is stored; a bad
	   or over-budget report is dropped, never answered.

	Actions:
		Track({ event, ... })   one of the events below, with its params

	Events (names and every param checked here, so a client can't invent
	them). Item ids are CatalogueClient ids: an asset's id, or a bundle's id
	negated. A reason is the engine's first reason (bought_with,
	worn_with…) or the heuristic's slot (creator, complete, style,
	wildcard, fill).
		rec_open    { outfit_size }      the ring opened (tapping yourself)
		rec_ring    { trail_id, depth, basis_id, back_id, revisit, fallback?,
		              item_1..item_7, reason_1..reason_7 }
		                                 a ring was shown: its new items in
		                                 order and why each was chosen;
		                                 basis_id 0 = the whole outfit;
		                                 back_id 0 = no back pad; revisit =
		                                 shown again by going back; fallback
		                                 = the engine padded it (absent when
		                                 the heuristic made the ring)
		rec_pick    { trail_id, depth, item_id, reason, slot }
		                                 an item was walked onto (also
		                                 logged as try_on)
		rec_back    { trail_id, depth, undone }   the back pad was used
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
local OwnershipService = require(script.Parent.Parent.services.game.OwnershipService)
local Bolt = require(ReplicatedStorage.Bolt)
local Network = require(ReplicatedStorage.Network)

local RecommendationsController = {}
RecommendationsController.__index = RecommendationsController
setmetatable(RecommendationsController, AbstractController)

export type RecommendationsController = typeof(setmetatable({}, RecommendationsController)) & AbstractController.AbstractController

local MAX_ITEMS = 7
local MAX_DEPTH = 500
local MAX_COUNT = 10000
-- A reason: the heuristic's slot names, or whatever the engine says
-- (bought_with, worn_with…): a short snake_case word either way.
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
local MAX_COUNT_ASKED = 30

local engineRecent: { [Player]: { number } } = {}

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

local ACTIONS = {
	[Network.Actions.Recommendations.Track] = trackReport,
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
-- (warned), so a place without it still plays on the heuristic.
local engineConfig: any = nil
local function engine(): any
	if engineConfig == nil then
		local module = ServerScriptService:WaitForChild("Config"):WaitForChild("RecommendationEngineConfig", 10)
		if module then
			engineConfig = require(module :: ModuleScript)
		else
			warn("[RecommendationsController] No ServerScriptService.Config.RecommendationEngineConfig: the ring uses its heuristic")
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

local function recommend(player: Player, raw: any): any
	local config = engine()
	if not config.enabled or type(config.baseUrl) ~= "string" or config.baseUrl == "" then
		return { ok = false, error = "disabled" }
	end
	if type(raw) ~= "table" then
		return { ok = false, error = "bad request" }
	end
	local basis = refsOf(raw.basis, MAX_REFS.basis)
	local worn = refsOf(raw.worn, MAX_REFS.worn)
	local exclude = refsOf(raw.exclude, MAX_REFS.exclude)
	if not basis or #basis == 0 or not worn or not exclude then
		return { ok = false, error = "bad request" }
	end
	if not spend(engineRecent, player, ENGINE_BUDGET, ENGINE_WINDOW) then
		return { ok = false, error = "busy" }
	end
	local count = if isInt(raw.count, 1, MAX_COUNT_ASKED) then raw.count else config.count or 20

	local started = os.clock()
	local ok, response = pcall(function()
		local auth = HttpService:GetSecret(config.secretName):AddPrefix("Bearer ")
		return HttpService:RequestAsync({
			Url = config.baseUrl .. "/v1/recommend",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", Authorization = auth },
			Body = HttpService:JSONEncode({
				queries = { { basis = basis, worn = worn, exclude = exclude, count = count } },
			}),
		})
	end)
	if not ok then
		warn("[RecommendationsController] engine request failed:", response)
		return { ok = false, error = "failed" }
	end
	if not response.Success then
		warn("[RecommendationsController] engine answered", response.StatusCode, string.sub(response.Body or "", 1, 200))
		return { ok = false, error = "failed" }
	end
	local decoded, body = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	local result = decoded and type(body) == "table" and type(body.results) == "table" and body.results[1]
	if type(result) ~= "table" or type(result.items) ~= "table" then
		warn("[RecommendationsController] engine answer not understood:", string.sub(response.Body or "", 1, 200))
		return { ok = false, error = "failed" }
	end
	local items = {}
	for _, rawItem in result.items do
		local item = itemOf(rawItem)
		if item then
			table.insert(items, item)
		end
	end
	-- Not things the player owns (user, 2026-11-24). The lookups run in
	-- parallel and are remembered for the session (OwnershipModel), so the
	-- client's items show as owned elsewhere too.
	local ownership = OwnershipModel.get(tostring(player.UserId))
	local dropped = 0
	if ownership then
		local refs = {}
		for _, item in items do
			table.insert(refs, { targetId = item.id, kind = item.kind })
		end
		OwnershipService.check(player, ownership, refs)
		local kept = {}
		for _, item in items do
			if ownership:owns(OwnershipService.keyOf(item.id, item.kind)) then
				dropped += 1
			else
				table.insert(kept, item)
			end
		end
		items = kept
	end
	if config.debug then
		print(string.format(
			"[RecommendationsController] engine: %d items (%d owned dropped) for %s (basis %d, worn %d, exclude %d) in %.2fs%s",
			#items, dropped, player.Name, #basis, #worn, #exclude, os.clock() - started,
			if result.fallback then ", fallback" else ""
		))
	end
	return { ok = true, fallback = result.fallback == true, items = items }
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

	Players.PlayerRemoving:Connect(function(player: Player)
		recent[player] = nil
		engineRecent[player] = nil
	end)

	return self :: RecommendationsController
end

return RecommendationsController
