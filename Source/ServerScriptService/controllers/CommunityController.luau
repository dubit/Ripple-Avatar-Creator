--!strict

--[[
	CommunityController

	Community outfits (CommunityService): publishing, starring, reporting,
	browsing. An entry is a frozen shared copy, so publishing an outfit
	reuses its share code while it's unedited (or makes one). Requests
	closer together than COOLDOWN are dropped.

	Actions:
		Publish({ id })                 publish a saved outfit
		Publish({ outfitId, name })     publish an outfit saved on Roblox
		                                (Creations), copied as it is there now
		Publish({ code })               republish one of your own copies
		Unpublish({ code })             take your entry off Community (its
		                                code keeps working; off Mine too)
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

	Analytics: community_publish, community_unpublish, community_open,
	community_report (community_wear is OutfitsController's, on wearing a
	listed code).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AbstractController = require(script.Parent.AbstractController)
local OutfitsModel = require(script.Parent.Parent.models.user.OutfitsModel)
local AvatarService = require(ServerScriptService.services.game.AvatarService)
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

-- The code to publish for a request: an existing copy or a new one.
local function codeToPublish(player: Player, model: any, raw: any): (string?, string?)
	if type(raw) ~= "table" then
		return nil, nil
	end
	if type(raw.id) == "number" then
		local outfit = model:find(raw.id)
		if not outfit then
			return nil, nil
		end
		if outfit.code and SharedContentService.normalise(outfit.code) then
			return outfit.code, "saved"
		end
		local code = SharedContentService.claim(
			SharedContentService.outfitRecord(player, outfit.name, outfit.items, outfit.skin, outfit.scale)
		)
		if code and model:find(raw.id) then
			model:setCode(raw.id, code)
		end
		return code, "saved"
	end
	if type(raw.outfitId) == "number" and raw.outfitId > 0 and raw.outfitId % 1 == 0 then
		local description, items = AvatarService.robloxOutfit(raw.outfitId)
		if not description then
			return nil, nil
		end
		local name = if type(raw.name) == "string" and string.match(raw.name, "%S") then string.sub(raw.name, 1, 60) else "Outfit"
		local record = SharedContentService.outfitRecord(
			player,
			SharedContentService.filterName(player, name) or "Outfit",
			items,
			AvatarService.skinOf(description),
			AvatarService.scaleOf(description)
		)
		local existing = (model.creationCodes or {})[tostring(raw.outfitId)]
		if
			existing
			and SharedContentService.normalise(existing)
			and SharedContentService.sameOutfit(SharedContentService.lookup(existing), record.name, record.items, record.skin, record.scale)
		then
			return existing, "roblox"
		end
		local code = SharedContentService.claim(record)
		if code then
			model:setCreationCode(raw.outfitId, code)
		end
		return code, "roblox"
	end
	local code = codeOf(raw)
	if code then
		return code, "copy"
	end
	return nil, nil
end

local function publish(player: Player, model: any, raw: any)
	local code, source = codeToPublish(player, model, raw)
	if code and CommunityService.publish(code, player.UserId) then
		model:addPublished(code)
		track(player, "community_publish", { code = code, source = source })
	end
end

local function unpublish(player: Player, model: any, raw: any)
	local code = codeOf(raw)
	if not code then
		return
	end
	if CommunityService.unpublish(code, player.UserId) or table.find(model.published or {}, code) then
		model:removePublished(code)
		track(player, "community_unpublish", { code = code })
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
	[Network.Actions.Community.Publish] = publish,
	[Network.Actions.Community.Unpublish] = unpublish,
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
