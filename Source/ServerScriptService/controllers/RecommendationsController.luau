--!strict

--[[
	RecommendationsController

	Analytics for the recommendation ring (RecommendationRing, client-only):
	the client reports what each ring offered and what the player did with
	it, and this records it. That's the implicit feedback the external
	recommendation engine will learn from (a set shown, one chosen). Nothing
	is stored; a bad or over-budget report is dropped, never answered.

	Actions:
		Track({ event, ... })   one of the events below, with its params

	Events (names and every param checked here, so a client can't invent
	them). Item ids are CatalogueClient ids: an asset's id, or a bundle's id
	negated.
		rec_open    { outfit_size }                 the ring opened (tapping
		                                            yourself)
		rec_ring    { trail_id, depth, basis_id, back_id, revisit,
		              item_1..item_7, reason_1..reason_7 }
		                                            a ring was shown: its new
		                                            items in order and why each
		                                            was chosen (creator,
		                                            complete, style, wildcard,
		                                            fill); basis_id 0 = the
		                                            whole outfit; back_id 0 =
		                                            no back pad; revisit =
		                                            shown again by going back
		rec_pick    { trail_id, depth, item_id, reason, slot }
		                                            an item was walked onto
		                                            (also logged as try_on)
		rec_back    { trail_id, depth, undone }      the back pad was used
		rec_close   { trail_id, depth, rings, picks, reason }
		                                            the ring closed: reason
		                                            tap / walk_away / respawn

	"Track" is in AnalyticsConfig.excludedActions, so these aren't also
	logged as controller_action.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractController = require(script.Parent.AbstractController)
local Network = require(ReplicatedStorage.Network)

local RecommendationsController = {}
RecommendationsController.__index = RecommendationsController
setmetatable(RecommendationsController, AbstractController)

export type RecommendationsController = typeof(setmetatable({}, RecommendationsController)) & AbstractController.AbstractController

local MAX_ITEMS = 7
local MAX_DEPTH = 500
local MAX_COUNT = 10000
local REASONS = { creator = true, complete = true, style = true, wildcard = true, fill = true }
local CLOSE_REASONS = { tap = true, walk_away = true, respawn = true }

-- At most BUDGET reports per WINDOW seconds per player.
local BUDGET = 30
local WINDOW = 10

local recent: { [Player]: { number } } = {}

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
		for index = 1, MAX_ITEMS do
			local id, reason = raw["item_" .. index], raw["reason_" .. index]
			if id == nil and reason == nil then
				continue
			end
			if not isId(id) or type(reason) ~= "string" or not REASONS[reason] then
				return
			end
			params["item_" .. index] = id
			params["reason_" .. index] = reason
		end
		track(player, "rec_ring", params)
	end,
	rec_pick = function(player, raw)
		if trailOk(raw) and isId(raw.item_id) and type(raw.reason) == "string" and REASONS[raw.reason] and isInt(raw.slot, 1, MAX_ITEMS) then
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

-- True if the player still has budget for a report right now.
local function allowed(player: Player): boolean
	local now = os.clock()
	local times = recent[player] or {}
	recent[player] = times
	while times[1] and now - times[1] > WINDOW do
		table.remove(times, 1)
	end
	if #times >= BUDGET then
		return false
	end
	table.insert(times, now)
	return true
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

	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		recent[player] = nil
	end)

	return self :: RecommendationsController
end

return RecommendationsController
