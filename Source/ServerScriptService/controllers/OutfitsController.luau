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
		WearSelected({ id, indices, skin? })   put those items (and with
		                           `skin`, its skin tone) on over the current look
		Follow({ userId })         follow someone here, or unfollow (a real
		                           Roblox user; private to the player)
		Share({ id })              give the outfit a 6-character share code: a
		                           frozen copy of it now (SharedContentService),
		                           which is also its Community entry (listed
		                           with the code; CommunityService). Asking
		                           again for one that has a code lists it if it
		                           isn't yet. Renaming or saving over it
		                           detaches the code
		                           (it keeps opening the old copy; sharing again
		                           makes a new one). Deleting it keeps the copy
		                           but drops the owner's name from it
		ShareCreation({ outfitId, name, check? })   share one of the player's
		                           outfits saved on Roblox (Creations): its
		                           contents come from Roblox (items, body, skin,
		                           scale), the name is text-filtered; the code
		                           is kept in `creationCodes` (not a Wardrobe
		                           outfit) while the copy still matches Roblox.
		                           When it doesn't (edited on Roblox), the old
		                           code is detached: with `check` (the dialog
		                           opening) that's all; otherwise a new code
		                           is made. Listed on Community like Share
		WearShared({ code })       wear a shared outfit exactly (replaces the
		                           look, with its skin colours and scale)

	"ResolveShareCode"(text) (Bolt remote function): a typed code -> { ok,
	code, kind = "outfit", outfit = { name, by, ownerId, items, skin, scale } }
	or { ok = false, error = "notfound" | "busy" }. A code's kind travels with
	it, so other kinds of shared things can join later.

	The outfit page's 3D preview asks over the "OutfitPreview" remote function
	(Bolt) with (kind, id): "saved" + a saved outfit's id, "own" (the player's
	own Roblox avatar), "roblox" + an outfit saved on Roblox, or "user" + a
	user id (another user's look: RobloxAvatarLookupService). The server
	builds the look
	(AvatarService.describeLook, the same code that dresses characters) and
	parents the HumanoidDescription into the player's PlayerGui (so only they
	get it), returning its name; the client builds a rig from it. Previews are
	cleaned up after PREVIEW_LIFETIME.

	Analytics: outfit_save, outfit_wear (with partial = true for a selection),
	outfit_delete, outfit_share; community_publish when a code is listed;
	community_wear when a Community outfit is worn by someone
	other than its creator (also counted for its ordering: CommunityService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local AbstractController = require(script.Parent.AbstractController)
local OutfitsModel = require(script.Parent.Parent.models.user.OutfitsModel)
local AvatarModel = require(script.Parent.Parent.models.user.AvatarModel)
local AvatarService = require(ServerScriptService.services.game.AvatarService)
local RobloxAvatarLookupService = require(ServerScriptService.services.game.RobloxAvatarLookupService)
local SharedContentService = require(ServerScriptService.services.game.SharedContentService)
local CommunityService = require(ServerScriptService.services.game.CommunityService)
local Network = require(ReplicatedStorage.Network)
local Bolt = require(ReplicatedStorage.Bolt)
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))
local BodyScale = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("BodyScale"))

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
local filtered = SharedContentService.filterName

local function save(player: Player, model: any, _raw: any)
	local avatar = AvatarModel.get(tostring(player.UserId))
	if not avatar or #avatar.worn == 0 then
		return
	end
	local outfit = model:add(defaultName(model), avatar.worn, avatar.skin, avatar.scale)
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
	local outfit = model:overwrite(id, avatar.worn, avatar.skin, avatar.scale)
	if outfit then
		track(player, "outfit_save", { outfit_id = outfit.id, item_count = #outfit.items, replaced = true })
	end
end

-- What everyone sees of a shared outfit: a frozen copy of it now.
local function shared(player: Player, outfit: any): { [string]: any }
	return SharedContentService.outfitRecord(player, outfit.name, outfit.items, outfit.skin, outfit.scale)
end

-- A code is its outfit on Community: sharing lists the copy (once; one
-- shared before Community, or hidden, is left as it is).
local function listShared(player: Player, model: any, code: string, source: string)
	if table.find(model.published or {}, code) then
		return
	end
	if CommunityService.publish(code, player.UserId) then
		model:addPublished(code)
		track(player, "community_publish", { code = code, source = source })
	end
end

local function share(player: Player, model: any, raw: any)
	local id = idOf(raw)
	local outfit = id and model:find(id)
	if not outfit then
		return
	end
	if outfit.code then
		if SharedContentService.normalise(outfit.code) then
			listShared(player, model, outfit.code, "saved") -- it has one already
			return
		end
		-- An old-format code ("OUT-…"): replace it with a short one.
		task.spawn(SharedContentService.remove, outfit.code)
	end
	local code = SharedContentService.claim(shared(player, outfit))
	if code and model:find(id) then
		model:setCode(id, code)
		track(player, "outfit_share", { outfit_id = id, item_count = #outfit.items })
		listShared(player, model, code, "saved")
	end
end

local function shareCreation(player: Player, model: any, raw: any)
	if type(raw) ~= "table" or type(raw.outfitId) ~= "number" or raw.outfitId <= 0 or raw.outfitId % 1 ~= 0 then
		return
	end
	local description, items = AvatarService.robloxOutfit(raw.outfitId)
	if not description then
		return
	end
	local name = if type(raw.name) == "string" and string.match(raw.name, "%S") then string.sub(raw.name, 1, 60) else "Outfit"
	local record = SharedContentService.outfitRecord(
		player,
		filtered(player, name) or "Outfit",
		items,
		AvatarService.skinOf(description),
		AvatarService.scaleOf(description)
	)
	local key = tostring(raw.outfitId)
	local existing = (model.creationCodes or {})[key]
	if existing and SharedContentService.normalise(existing) then
		if SharedContentService.sameOutfit(SharedContentService.lookup(existing), record.name, record.items, record.skin, record.scale) then
			if not raw.check then
				listShared(player, model, existing, "roblox")
			end
			return -- the copy still matches
		end
		model:setCreationCode(raw.outfitId, nil) -- edited on Roblox: detach the old copy
	end
	if raw.check then
		return
	end
	local code = SharedContentService.claim(record)
	if code then
		model:setCreationCode(raw.outfitId, code)
		track(player, "outfit_share", { item_count = #items, source = "roblox" })
		listShared(player, model, code, "roblox")
	end
end

local function wearShared(player: Player, _model: any, raw: any)
	local code = if type(raw) == "table" then SharedContentService.normalise(raw.code) else nil
	local avatar = AvatarModel.get(tostring(player.UserId))
	if not code or not avatar then
		return
	end
	local record = SharedContentService.lookup(code)
	if type(record) ~= "table" or record.kind ~= "outfit" or type(record.items) ~= "table" or record.hidden then
		return
	end
	avatar:setLook(table.clone(record.items), SkinColours.normalise(record.skin), BodyScale.normalise(record.scale))
	AvatarService.apply(player)
	local community = CommunityService.isListed(record)
	track(player, "outfit_wear", { item_count = #record.items, partial = false, source = if community then "community" else "share_code" })
	if community and record.ownerId ~= player.UserId then
		CommunityService.countWear(code)
		track(player, "community_wear", { code = code })
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
		if outfit.code then
			-- Its copy lives on (codes others have keep working), unsigned.
			task.spawn(SharedContentService.anonymise, outfit.code)
		end
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
	avatar:setLook(table.clone(outfit.items), SkinColours.normalise(outfit.skin), BodyScale.normalise(outfit.scale))
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
	-- The skin tone comes too if its row was ticked.
	local colours = SkinColours.normalise(outfit.skin)
	local skin = if raw.skin == true and not SkinColours.isEmpty(colours) then colours else nil
	local outfitScale = BodyScale.normalise(outfit.scale)
	local scale = if raw.scale == true and not BodyScale.isEmpty(outfitScale) then outfitScale else nil
	if #items == 0 and not skin and not scale then
		return
	end
	avatar:wearMany(items, skin, scale)
	AvatarService.apply(player)
	track(player, "outfit_wear", { outfit_id = outfit.id, item_count = #items, partial = true })
end

local function follow(player: Player, model: any, raw: any)
	local userId = if type(raw) == "table" then raw.userId else nil
	if type(userId) ~= "number" or userId ~= userId or userId <= 0 or userId % 1 ~= 0 or userId == player.UserId then
		return
	end
	-- Unfollowing needs no check; following must be a real user.
	if not table.find(model.following, userId) and not RobloxAvatarLookupService.user(userId) then
		return
	end
	local on = model:toggleFollow(userId)
	track(player, if on then "user_follow" else "user_unfollow", { followed_user_id = userId })
end

local ACTIONS = {
	[Network.Actions.Outfits.Save] = save,
	[Network.Actions.Outfits.Overwrite] = overwrite,
	[Network.Actions.Outfits.Rename] = rename,
	[Network.Actions.Outfits.Delete] = delete,
	[Network.Actions.Outfits.WearAll] = wearAll,
	[Network.Actions.Outfits.WearSelected] = wearSelected,
	[Network.Actions.Outfits.Follow] = follow,
	[Network.Actions.Outfits.Share] = share,
	[Network.Actions.Outfits.ShareCreation] = shareCreation,
	[Network.Actions.Outfits.WearShared] = wearShared,
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
	if kind ~= "own" and type(id) ~= "number" and not (kind == "shared" and type(id) == "string") then
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
			local ok, result = pcall(AvatarService.describeLook, player, outfit.items, outfit.skin, outfit.scale)
			description = if ok then result else nil
		end
	elseif kind == "own" then
		description = AvatarService.ownDescription(player)
	elseif kind == "roblox" then
		description = AvatarService.robloxOutfit(id)
	elseif kind == "user" then
		description = RobloxAvatarLookupService.description(id)
	elseif kind == "shared" then
		local record = SharedContentService.lookup(SharedContentService.normalise(id) or "")
		if type(record) == "table" and record.kind == "outfit" and type(record.items) == "table" and not record.hidden then
			local ok, result = pcall(AvatarService.describeLook, player, record.items, record.skin, record.scale)
			description = if ok then result else nil
		end
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
	Bolt.RemoteFunction("ResolveShareCode").OnServerInvoke = function(player: Player, text: any)
		local code = SharedContentService.normalise(text)
		if not code then
			return { ok = false, error = "notfound" }
		end
		if not SharedContentService.allowed(player) then
			return { ok = false, error = "busy" }
		end
		local record = SharedContentService.lookup(code)
		if type(record) ~= "table" or record.kind ~= "outfit" or type(record.items) ~= "table" or record.hidden then
			return { ok = false, error = "notfound" }
		end
		track(player, "share_resolve", { kind = "outfit" })
		local listed = CommunityService.isListed(record)
		return {
			ok = true,
			code = code,
			kind = "outfit",
			outfit = {
				name = record.name,
				by = if record.anonymous then nil else record.ownerName,
				ownerId = if record.anonymous then 0 else record.ownerId,
				items = record.items,
				skin = record.skin,
				scale = record.scale,
				mine = record.ownerId == player.UserId,
				-- On Community: its counts (nil when it isn't listed).
				community = if listed
					then { wears = tonumber(record.wears) or 0, favourites = tonumber(record.favourites) or 0 }
					else nil,
			},
		}
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequest[player] = nil
		previewTimes[player] = nil
	end)

	return self :: OutfitsController
end

return OutfitsController
