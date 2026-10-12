--!strict

--[[
	AvatarController

	Try-on requests from the HUD. Items arrive as { targetId, kind } (the
	catalogue id and "Asset" / "Bundle"); the server looks each one up itself
	(AvatarService.resolve) and only accepts types AvatarConfig knows how to
	wear, so a client can't name its own types or put arbitrary assets on.
	Requests closer together than AvatarConfig.tryOnCooldown are dropped.

	Actions:
		TryOn(item)        wear it (replacing its slot / stacking per config)
		TakeOff(item)      take it off
		WearMany(items, skin?)   wear several (an outfit, the basket), up to
		                   maxWearMany; `skin` also sets the skin colours
		SetSkin(skin)      the skin colours: { [part] = "#RRGGBB" } (a part left
		                   out is the player's own; {} = all their own)
		RefreshOwn()       re-read the player's own Roblox avatar (it may have
		                   changed since they joined), at most every
		                   REFRESH_SECONDS; re-dresses them, as their base did
		TakeOffAll()       wear nothing (the body stays)
		Undo()             step back one change
		Reset()            back to the player's own Roblox avatar
		WearRobloxOutfit(outfitId)   wear an outfit saved on Roblox: its
		                   items, head, face and skin tone (body parts and
		                   proportions stay the player's own)
		WearUserLook(userId)   wear another user's look the same way (with
		                   their skin tone): what a player in this server is
		                   wearing here, or anyone else's current Roblox avatar

	Each change re-dresses the character through AvatarService. Try-ons,
	take-offs and resets are tracked as analytics events with the item's id
	and type (signals for the phase-3 recommendation engine), on top of the
	automatic per-action tracking.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AbstractController = require(script.Parent.AbstractController)
local AvatarModel = require(script.Parent.Parent.models.user.AvatarModel)
local AvatarService = require(ServerScriptService.services.game.AvatarService)
local RobloxAvatarLookupService = require(ServerScriptService.services.game.RobloxAvatarLookupService)
local Network = require(ReplicatedStorage.Network)

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))

local AvatarController = {}
AvatarController.__index = AvatarController
setmetatable(AvatarController, AbstractController)

export type AvatarController = typeof(setmetatable({}, AvatarController)) & AbstractController.AbstractController

local lastRequest: { [Player]: number } = {}

-- Lazy, like AbstractController (avoids a load-order dependency).
local analytics: any = nil
local function track(player: Player, eventName: string, params: { [string]: any }?)
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

local function itemParams(item: AvatarModel.WornItem): { [string]: any }
	return { item_id = item.targetId, item_kind = item.kind, item_type = item.typeName }
end

local function wearable(typeName: string): boolean
	return AvatarConfig.slots[typeName] ~= nil or AvatarConfig.groups[typeName] ~= nil
end

-- { targetId, kind } from the client -> a looked-up, wearable item (or nil).
local function resolve(raw: any): AvatarModel.WornItem?
	if type(raw) ~= "table" then
		return nil
	end
	local targetId, kind = raw.targetId, raw.kind
	if type(targetId) ~= "number" or targetId ~= targetId or targetId <= 0 or targetId % 1 ~= 0 then
		return nil
	end
	if kind ~= "Asset" and kind ~= "Bundle" then
		return nil
	end
	local item = AvatarService.resolve(targetId, kind)
	if item and wearable(item.typeName) then
		return item
	end
	return nil
end

local function tryOn(player: Player, model: any, raw: any)
	local item = resolve(raw)
	if item then
		model:wear(item)
		AvatarService.apply(player)
		track(player, "try_on", itemParams(item))
	end
end

local function takeOff(player: Player, model: any, raw: any)
	if type(raw) == "table" and type(raw.targetId) == "number" and (raw.kind == "Asset" or raw.kind == "Bundle") then
		for _, worn in model.worn do
			if worn.targetId == raw.targetId and worn.kind == raw.kind then
				model:takeOff(worn)
				AvatarService.apply(player)
				track(player, "take_off", itemParams(worn))
				return
			end
		end
	end
end

-- Skin colours from the client (a per-part table, or one colour / "" for
-- the whole body); nil if there's nothing usable.
local function skinOf(raw: any): SkinColours.Colours?
	if raw == "" then
		return {}
	end
	if type(raw) ~= "table" and type(raw) ~= "string" then
		return nil
	end
	return SkinColours.normalise(raw)
end

local REFRESH_SECONDS = 15
local lastRefresh: { [Player]: number } = {}

local function refreshOwn(player: Player, _model: any, _raw: any)
	local now = os.clock()
	if now - (lastRefresh[player] or -math.huge) < REFRESH_SECONDS then
		return
	end
	lastRefresh[player] = now
	AvatarService.ownLook(player)
	AvatarService.apply(player)
end

local function setSkin(player: Player, model: any, raw: any)
	local skin = skinOf(raw)
	if skin then
		model:setSkin(skin)
		AvatarService.apply(player)
	end
end

local function wearMany(player: Player, model: any, raw: any, rawSkin: any)
	if type(raw) ~= "table" then
		return
	end
	local items = {}
	for index, entry in raw do
		if type(index) ~= "number" or index > AvatarConfig.maxWearMany then
			continue
		end
		local item = resolve(entry)
		if item then
			table.insert(items, item)
		end
	end
	local skin = skinOf(rawSkin)
	if #items > 0 or skin then
		model:wearMany(items, skin)
		AvatarService.apply(player)
		for _, item in items do
			track(player, "try_on", itemParams(item))
		end
	end
end

local function takeOffAll(player: Player, model: any, _raw: any)
	model:takeOffAll()
	AvatarService.apply(player)
end

local function undo(player: Player, model: any, _raw: any)
	if model:undo() then
		AvatarService.apply(player)
	end
end

local function reset(player: Player, model: any, _raw: any)
	model:setLook(AvatarService.ownLook(player), {})
	AvatarService.apply(player)
	track(player, "reset")
end

local function wearRobloxOutfit(player: Player, model: any, raw: any)
	if type(raw) ~= "number" or raw ~= raw or raw <= 0 or raw % 1 ~= 0 then
		return
	end
	local description, items = AvatarService.robloxOutfit(raw)
	if not description then
		return
	end
	model:setLook(items, AvatarService.skinOf(description))
	AvatarService.apply(player)
	track(player, "outfit_wear", { outfit_id = raw, item_count = #items, partial = false, source = "roblox" })
end

local function wearUserLook(player: Player, model: any, raw: any)
	if type(raw) ~= "number" or raw ~= raw or raw <= 0 or raw % 1 ~= 0 then
		return
	end
	local look = RobloxAvatarLookupService.look(raw)
	if not look or #look.items == 0 then
		return
	end
	model:setLook(table.clone(look.items), look.skin)
	AvatarService.apply(player)
	track(player, "outfit_wear", { item_count = #look.items, partial = false, source = if look.inServer then "server_player" else "roblox_user" })
end

local ACTIONS = {
	[Network.Actions.Avatar.TryOn] = tryOn,
	[Network.Actions.Avatar.TakeOff] = takeOff,
	[Network.Actions.Avatar.WearMany] = wearMany,
	[Network.Actions.Avatar.TakeOffAll] = takeOffAll,
	[Network.Actions.Avatar.Undo] = undo,
	[Network.Actions.Avatar.Reset] = reset,
	[Network.Actions.Avatar.WearRobloxOutfit] = wearRobloxOutfit,
	[Network.Actions.Avatar.WearUserLook] = wearUserLook,
	[Network.Actions.Avatar.SetSkin] = setSkin,
	[Network.Actions.Avatar.RefreshOwn] = refreshOwn,
}

function AvatarController:executeAction(player: Player, action: Network.AvatarAction, raw: any, extra: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < AvatarConfig.tryOnCooldown then
		return
	end
	lastRequest[player] = now
	local model = AvatarModel.get(tostring(player.UserId))
	if not model then
		return
	end
	self:dispatchAction(ACTIONS, action, player, player, model, raw, extra)
end

function AvatarController.new(): AvatarController
	local self = AbstractController.new("AvatarController") :: any
	setmetatable(self, AvatarController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.AvatarAction, raw: any, extra: any)
		self:executeAction(player, action, raw, extra)
	end)

	return self :: AvatarController
end

return AvatarController
