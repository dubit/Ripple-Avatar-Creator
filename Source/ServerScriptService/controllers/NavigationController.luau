--!strict

--[[
	NavigationController

	Analytics for getting around the HUD: the client reports each change of
	the full panel (useNavigation, sent from Hud) and this records it. Nothing
	is stored; the only effect is analytics, so a bad or over-budget report is
	dropped, never answered.

	Actions:
		View({ root, screen, depth })   the panel now shows `screen` (a page
		                                kind, or "home" for the root itself)
		                                `depth` levels under `root`; root nil
		                                means the panel closed

	Events (both checked against fixed lists, so a client can't invent names):
		tab_open      { tab, from }               a different root opened (from
		                                          "world" or the previous root)
		screen_view   { root, screen, depth }     every change while open
		panel_close   { root, depth }             back to the world

	"View" is in AnalyticsConfig.excludedActions, so these aren't also logged
	as controller_action.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractController = require(script.Parent.AbstractController)
local Network = require(ReplicatedStorage.Network)

local NavigationController = {}
NavigationController.__index = NavigationController
setmetatable(NavigationController, AbstractController)

export type NavigationController = typeof(setmetatable({}, NavigationController)) & AbstractController.AbstractController

-- The panel's roots (useNavigation.Root) and the page kinds FullPanel shows.
local ROOTS = { Catalogue = true, Stores = true, Outfits = true, Basket = true, Wearing = true }
local SCREENS = { home = true, item = true, store = true, storeSection = true, outfit = true, skin = true }
local MAX_DEPTH = 12

-- At most BUDGET reports per WINDOW seconds per player.
local BUDGET = 40
local WINDOW = 10

local recent: { [Player]: { number } } = {}
local lastRoot: { [Player]: string } = {} -- "" while the panel is closed

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

local function view(player: Player, raw: any)
	if type(raw) ~= "table" then
		return
	end
	local root, screen, depth = raw.root, raw.screen, raw.depth
	if type(depth) ~= "number" or depth ~= depth or depth < 0 or depth > MAX_DEPTH or depth % 1 ~= 0 then
		return
	end
	local previous = lastRoot[player] or ""
	if root == nil then
		if previous ~= "" then
			track(player, "panel_close", { root = previous, depth = depth })
		end
		lastRoot[player] = ""
		return
	end
	if type(root) ~= "string" or not ROOTS[root] or type(screen) ~= "string" or not SCREENS[screen] then
		return
	end
	if root ~= previous then
		track(player, "tab_open", { tab = root, from = if previous == "" then "world" else previous })
	end
	lastRoot[player] = root
	track(player, "screen_view", { root = root, screen = screen, depth = depth })
end

local ACTIONS = {
	[Network.Actions.Navigation.View] = view,
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

function NavigationController:executeAction(player: Player, action: Network.NavigationAction, raw: any)
	if not allowed(player) then
		return
	end
	self:dispatchAction(ACTIONS, action, player, player, raw)
end

function NavigationController.new(): NavigationController
	local self = AbstractController.new("NavigationController") :: any
	setmetatable(self, NavigationController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.NavigationAction, raw: any)
		self:executeAction(player, action, raw)
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		recent[player] = nil
		lastRoot[player] = nil
	end)

	return self :: NavigationController
end

return NavigationController
