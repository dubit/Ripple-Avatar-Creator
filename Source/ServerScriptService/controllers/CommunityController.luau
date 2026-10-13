--!strict

--[[
	CommunityController

	Community outfits (CommunityService): removing, starring, reporting,
	browsing. An entry is a frozen shared copy: sharing an outfit (its
	code, OutfitsController Share / ShareCreation) is what lists it, so a
	code and a Community entry are the same thing. Requests closer
	together than COOLDOWN are dropped.

	Actions:
		Remove({ code })                take your own copy down: off
		                                Community, and the code stops working
		                                (your outfit loses it; share again
		                                for a new one)
		Favourite({ code })             star / unstar a Community outfit
		                                (not your own)
		Report({ code })                report it (once per player; enough
		                                reports hide it)
		Open({ code })                  the player opened its page (Recent,
		                                analytics)
		Moderate(code, op)              admins only (CommunityService.isAdmin),
		                                op "hide" | "restore" | "takedown"; as
		                                a slash command: /communitycontroller Moderate
		                                7KQ2XM hide

	"BrowseCommunity"(sort, page) (Bolt remote function) -> { ok, cards, more }
	or { ok = false, error = "busy" }: sort "popular" | "trending" | "newest"
	(everyone's) or "favourited" | "recent" | "mine" (the player's own
	lists); page from 1. Cards: CommunityService.Card.

	Analytics: community_remove, community_open, community_report
	(community_publish and community_wear are OutfitsController's: on
	sharing, and on wearing a listed code).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AbstractController = require(script.Parent.AbstractController)
local OutfitsModel = require(script.Parent.Parent.models.user.OutfitsModel)
local SharedContentService = require(ServerScriptService.services.game.SharedContentService)
local CommunityService = require(ServerScriptService.services.game.CommunityService)
local Network = require(ReplicatedStorage.Network)
local Bolt = require(ReplicatedStorage.Bolt)

local CommunityController = {}
CommunityController.__index = CommunityController
setmetatable(CommunityController, AbstractController)

export type CommunityController = typeof(setmetatable({}, CommunityController)) & AbstractController.AbstractController

local COOLDOWN = 0.25
local PAGE_SIZE = 24 -- for the player's own lists (CommunityService pages its own)
local BROWSE_BUDGET = { requests = 20, seconds = 30 }
local REPORT_BUDGET = { requests = 5, seconds = 300 }
local PERSONAL = { favourited = "communityFavourites", recent = "communityRecent", mine = "published" }

local lastRequest: { [Player]: number } = {}
local budgets: { [string]: { [Player]: { number } } } = { browse = {}, report = {} }

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

local function allowed(kind: string, player: Player, budget: { requests: number, seconds: number }): boolean
	local now = os.clock()
	local times = budgets[kind][player] or {}
	budgets[kind][player] = times
	while times[1] and now - times[1] > budget.seconds do
		table.remove(times, 1)
	end
	if #times >= budget.requests then
		return false
	end
	table.insert(times, now)
	return true
end

local function codeOf(raw: any): string?
	local text = if type(raw) == "table" then raw.code else raw
	return SharedContentService.normalise(if type(text) == "number" then tostring(text) else text)
end

-- Take your own copy down: off Community and its code stops working.
-- Your outfit loses the code, so sharing it again makes a new one.
local function remove(player: Player, model: any, raw: any)
	local code = codeOf(raw)
	if not code then
		return
	end
	local record = SharedContentService.lookup(code)
	if type(record) == "table" and record.ownerId ~= player.UserId then
		return
	end
	if record then
		CommunityService.takedown(code)
		track(player, "community_remove", { code = code })
	end
	model:removePublished(code)
	for _, outfit in model.outfits or {} do
		if outfit.code == code then
			model:setCode(outfit.id, nil)
		end
	end
	for outfitId, creationCode in model.creationCodes or {} do
		if creationCode == code then
			model:setCreationCode(tonumber(outfitId), nil)
		end
	end
end

local function favourite(player: Player, model: any, raw: any)
	local code = codeOf(raw)
	if not code then
		return
	end
	local starred = table.find(model.communityFavourites or {}, code) ~= nil
	if not starred then
		-- Only Community outfits, and not your own (unstarring always works).
		local record = SharedContentService.lookup(code)
		if not CommunityService.isListed(record) or record.ownerId == player.UserId then
			return
		end
	end
	local now = model:toggleCommunityFavourite(code)
	CommunityService.countFavourite(code, if now then 1 else -1)
end

local function report(player: Player, _model: any, raw: any)
	local code = codeOf(raw)
	if not code or not allowed("report", player, REPORT_BUDGET) then
		return
	end
	if CommunityService.report(player, code) then
		track(player, "community_report", { code = code })
	end
end

local function open(player: Player, model: any, raw: any)
	local code = codeOf(raw)
	if code and CommunityService.isListed(SharedContentService.lookup(code)) then
		model:noteRecent(code)
		track(player, "community_open", { code = code })
	end
end

local function moderate(player: Player, _model: any, raw: any, op: any)
	if not CommunityService.isAdmin(player) then
		return
	end
	local code = codeOf(raw)
	local action = if type(raw) == "table" then raw.op else op
	if not code then
		return
	end
	if action == "hide" then
		CommunityService.hide(code, "admin " .. player.UserId)
	elseif action == "restore" then
		CommunityService.restore(code)
	elseif action == "takedown" then
		CommunityService.takedown(code)
	end
end

local ACTIONS = {
	[Network.Actions.Community.Remove] = remove,
	[Network.Actions.Community.Favourite] = favourite,
	[Network.Actions.Community.Report] = report,
	[Network.Actions.Community.Open] = open,
	[Network.Actions.Community.Moderate] = moderate,
}

function CommunityController:executeAction(player: Player, action: Network.CommunityAction, raw: any, extra: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < COOLDOWN then
		return
	end
	lastRequest[player] = now
	local model = OutfitsModel.get(tostring(player.UserId))
	if not model then
		return
	end
	self:dispatchAction(ACTIONS, action, player, player, model, raw, extra)
end

local function browse(player: Player, sort: any, page: any): any
	if type(sort) ~= "string" or type(page) ~= "number" or page < 1 or page % 1 ~= 0 then
		return { ok = false, error = "bad" }
	end
	if not allowed("browse", player, BROWSE_BUDGET) then
		return { ok = false, error = "busy" }
	end
	local codes: { string }
	local more: boolean
	local field = PERSONAL[sort]
	if field then
		local model = OutfitsModel.get(tostring(player.UserId))
		local list = if model then (model :: any)[field] or {} else {}
		local first = (page - 1) * PAGE_SIZE + 1
		codes = table.move(list, first, math.min(#list, first + PAGE_SIZE - 1), 1, {})
		more = #list > first + PAGE_SIZE - 1
	else
		codes, more = CommunityService.page(sort, page)
	end
	return { ok = true, cards = CommunityService.cards(codes, player), more = more }
end

function CommunityController.new(): CommunityController
	local self = AbstractController.new("CommunityController") :: any
	setmetatable(self, CommunityController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.CommunityAction, raw: any)
		self:executeAction(player, action, raw)
	end)

	Bolt.RemoteFunction("BrowseCommunity").OnServerInvoke = browse

	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequest[player] = nil
		budgets.browse[player] = nil
		budgets.report[player] = nil
	end)

	return self :: CommunityController
end

return CommunityController
