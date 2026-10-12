--!strict

--[[
	OutfitsController

	Saving, renaming, deleting and wearing the player's outfits. Requests
	carry outfit ids and item positions only, never item lists: what an
	outfit holds always comes from the server (Save snapshots the worn list),
	so a client can't slip its own items in. Requests closer together than
	AvatarConfig.outfits.cooldown are dropped.

	Actions:
		Save()                     save what's being worn as "Outfit N"
		Overwrite({ id })          replace that outfit's items with what's worn
		Rename({ id, name })       rename (trimmed, length-capped and passed
		                           through Roblox text filtering for text others
		                           may see, since outfits can be shared later)
		Delete({ id })
		WearAll({ id })            wear exactly the outfit (replaces the look;
		                           undoable)
		WearSelected({ id, indices })   put those items on over the current look

	The outfit page's 3D preview asks over the "OutfitPreview" remote function
	(Bolt) with (kind, id): "saved" + a saved outfit's id, "own" (the player's
	own Roblox avatar) or "roblox" + an outfit saved on Roblox. The server
	builds the look
	(AvatarService.describeLook, the same code that dresses characters) and
	parents the HumanoidDescription into the player's PlayerGui (so only they
	get it), returning its name; the client builds a rig from it. Previews are
	cleaned up after PREVIEW_LIFETIME.

	Analytics: outfit_save, outfit_wear (with partial = true for a selection),
	outfit_delete.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local AbstractController = require(script.Parent.AbstractController)
local OutfitsModel = require(script.Parent.Parent.models.user.OutfitsModel)
local AvatarModel = require(script.Parent.Parent.models.user.AvatarModel)
local AvatarService = require(ServerScriptService.services.game.AvatarService)
local Network = require(ReplicatedStorage.Network)
local Bolt = require(ReplicatedStorage.Bolt)

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))

local OutfitsController = {}
OutfitsController.__index = OutfitsController
setmetatable(OutfitsController, AbstractController)

export type OutfitsController = typeof(setmetatable({}, OutfitsController)) & AbstractController.AbstractController

local PREVIEW_FOLDER = "OutfitPreviews"
local PREVIEW_LIFETIME = 30 -- seconds a preview description stays in PlayerGui
local PREVIEW_BUDGET = { requests = 10, seconds = 10 }

local lastRequest: { [Player]: number } = {}
local previewTimes: { [Player]: { number } } = {}

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

local function idOf(raw: any): number?
	local id = if type(raw) == "table" then raw.id else nil
	if type(id) == "number" and id == id and id > 0 and id % 1 == 0 then
		return id
	end
	return nil
end

-- "Outfit N" with the first N not already taken.
local function defaultName(model: any): string
	local taken = {}
	for _, outfit in model.outfits do
		taken[outfit.name] = true
	end
	local n = #model.outfits + 1
	while taken["Outfit " .. n] do
		n += 1
	end
	return "Outfit " .. n
end

-- Roblox text filtering for a name others may see; nil if it can't be done.
local function filtered(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" then
		return nil
	end
	return result
end

local function save(player: Player, model: any, _raw: any)
	local avatar = AvatarModel.get(tostring(player.UserId))
	if not avatar or #avatar.worn == 0 then
		return
	end
	local outfit = model:add(defaultName(model), avatar.worn)
	if outfit then
		track(player, "outfit_save", { outfit_id = outfit.id, item_count = #outfit.items })
	end
end

local function overwrite(player: Player, model: any, raw: any)
	local id = idOf(raw)
	local avatar = AvatarModel.get(tostring(player.UserId))
	if not id or not avatar or #avatar.worn == 0 then
		return
	end
	local outfit = model:overwrite(id, avatar.worn)
	if outfit then
		track(player, "outfit_save", { outfit_id = outfit.id, item_count = #outfit.items, replaced = true })
	end
end

local function rename(player: Player, model: any, raw: any)
	local id = idOf(raw)
	local name = if type(raw) == "table" then raw.name else nil
	if not id or type(name) ~= "string" or not model:find(id) then
		return
	end
	-- Trim, squash runs of whitespace, cap the length (by characters).
	name = string.gsub(string.gsub(name, "%s+", " "), "^%s*(.-)%s*$", "%1")
	local length = utf8.len(name)
	if not length then
		return -- not valid UTF-8
	end
	if length > AvatarConfig.outfits.nameLength then
		name = string.sub(name, 1, (utf8.offset(name, AvatarConfig.outfits.nameLength + 1) or (#name + 1)) - 1)
	end
	if name == "" then
		return
	end
	local clean = filtered(player, name)
	if clean then
		model:rename(id, clean)
	end
end

local function delete(player: Player, model: any, raw: any)
	local id = idOf(raw)
	local outfit = id and model:delete(id)
	if outfit then
		track(player, "outfit_delete", { outfit_id = outfit.id, item_count = #outfit.items })
	end
end

local function wearAll(player: Player, model: any, raw: any)
	local id = idOf(raw)
	local outfit = id and model:find(id)
	local avatar = AvatarModel.get(tostring(player.UserId))
	if not outfit or not avatar then
		return
	end
	avatar:setWorn(table.clone(outfit.items))
	AvatarService.apply(player)
	track(player, "outfit_wear", { outfit_id = outfit.id, item_count = #outfit.items, partial = false })
end

local function wearSelected(player: Player, model: any, raw: any)
	local id = idOf(raw)
	local outfit = id and model:find(id)
	local avatar = AvatarModel.get(tostring(player.UserId))
	if not outfit or not avatar or type(raw.indices) ~= "table" then
		return
	end
	local items = {}
	local seen = {}
	for _, index in raw.indices do
		if type(index) == "number" and outfit.items[index] and not seen[index] then
			seen[index] = true
			table.insert(items, outfit.items[index])
		end
	end
	if #items == 0 then
		return
	end
	avatar:wearMany(items)
	AvatarService.apply(player)
	track(player, "outfit_wear", { outfit_id = outfit.id, item_count = #items, partial = true })
end

local ACTIONS = {
	[Network.Actions.Outfits.Save] = save,
	[Network.Actions.Outfits.Overwrite] = overwrite,
	[Network.Actions.Outfits.Rename] = rename,
	[Network.Actions.Outfits.Delete] = delete,
	[Network.Actions.Outfits.WearAll] = wearAll,
	[Network.Actions.Outfits.WearSelected] = wearSelected,
}

function OutfitsController:executeAction(player: Player, action: Network.OutfitsAction, raw: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < AvatarConfig.outfits.cooldown then
		return
	end
	lastRequest[player] = now
	local model = OutfitsModel.get(tostring(player.UserId))
	if not model then
		return
	end
	self:dispatchAction(ACTIONS, action, player, player, model, raw)
end

-- The outfit page's preview: build the look and hand it to this player only.
local function preview(player: Player, kind: any, id: any): string?
	if kind ~= "own" and type(id) ~= "number" then
		return nil
	end
	local now = os.clock()
	local times = previewTimes[player] or {}
	previewTimes[player] = times
	while times[1] and now - times[1] > PREVIEW_BUDGET.seconds do
		table.remove(times, 1)
	end
	if #times >= PREVIEW_BUDGET.requests then
		return nil
	end
	table.insert(times, now)

	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return nil
	end
	local description: HumanoidDescription? = nil
	if kind == "saved" then
		local model = OutfitsModel.get(tostring(player.UserId))
		local outfit = model and model:find(id)
		if outfit then
			local ok, result = pcall(AvatarService.describeLook, player, outfit.items)
			description = if ok then result else nil
		end
	elseif kind == "own" then
		description = AvatarService.ownDescription(player)
	elseif kind == "roblox" then
		description = AvatarService.robloxOutfit(id)
	end
	if not description then
		return nil
	end
	local folder = gui:FindFirstChild(PREVIEW_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PREVIEW_FOLDER
		folder.Parent = gui
	end
	description.Name = HttpService:GenerateGUID(false)
	description.Parent = folder
	Debris:AddItem(description, PREVIEW_LIFETIME)
	return description.Name
end

function OutfitsController.new(): OutfitsController
	local self = AbstractController.new("OutfitsController") :: any
	setmetatable(self, OutfitsController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.OutfitsAction, raw: any)
		self:executeAction(player, action, raw)
	end)

	Bolt.RemoteFunction("OutfitPreview").OnServerInvoke = preview

	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequest[player] = nil
		previewTimes[player] = nil
	end)

	return self :: OutfitsController
end

return OutfitsController
