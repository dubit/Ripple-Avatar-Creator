--!strict

--[[
	AvatarService (event-driven)

	Puts what a player is wearing (AvatarModel.worn) onto their real
	character, on the server, so Roblox replicates it to everyone.

	  · The player's own Roblox avatar is the base: their body, head, skin,
	    proportions and animations. Its wearable items (accessories, clothing,
	    emotes, makeup) are what `worn` is seeded with on first join, and what
	    Reset brings back.
	  · `worn` is applied on top with Humanoid:ApplyDescription — after every
	    change and every respawn (a new character starts as the plain avatar).
	    Bundles (bodies, heads, animation packs, shoes) contribute what their
	    outfit holds for that part of the avatar.
	  · Gear is held but inert: the tool is loaded, its scripts stripped, and
	    put in the character's hand, so nobody can use weapons or potions on
	    other players.
	  · Backgrounds are kept in `worn` (for the avatar preview) but don't
	    touch the character.

	Applies are coalesced per player: changes that land while one is running
	collapse into a single follow-up apply.

	Emote animations: the client can't open an emote asset to find the
	animation inside it, so it asks over the "AvatarEmoteAnimations" remote
	function (Bolt) with up to MAX_EMOTE_LOOKUP emote ids, and gets back a
	list of { id = emoteId, animation = "rbxassetid://…" } (cached). Used by the panel's avatar
	preview to play emotes. Read-only; no state changes.

	API (used by AvatarController):
		resolve(targetId, kind) -> WornItem?   look an item up (cached); nil if
		                                      it can't be found
		ownLook(player) -> { WornItem }        the player's own avatar's items
		apply(player)                          re-dress the character from `worn`

	Also used by OutfitsController (the outfit page's 3D preview) and
	AvatarController (wearing an outfit saved on Roblox):
		describeLook(player, worn) -> HumanoidDescription   `worn` on the
		                                      player's own base (gear left out)
		ownDescription(player) -> HumanoidDescription?      the player's own
		                                      Roblox avatar as it is
		robloxOutfit(outfitId) -> (HumanoidDescription?, { WornItem })   an
		                                      outfit saved on Roblox and its
		                                      wearable items (not its body:
		                                      the look keeps the player's own)
]]

local AssetService = game:GetService("AssetService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Bolt = require(ReplicatedStorage.Bolt)

local AvatarModel = require(ServerScriptService.models.user.AvatarModel)

type WornItem = AvatarModel.WornItem

local AvatarService = {}

-- Rigid accessories: catalogue type -> AccessoryType.
local RIGID: { [string]: Enum.AccessoryType } = {
	Hat = Enum.AccessoryType.Hat,
	HairAccessory = Enum.AccessoryType.Hair,
	FaceAccessory = Enum.AccessoryType.Face,
	NeckAccessory = Enum.AccessoryType.Neck,
	ShoulderAccessory = Enum.AccessoryType.Shoulder,
	FrontAccessory = Enum.AccessoryType.Front,
	BackAccessory = Enum.AccessoryType.Back,
	WaistAccessory = Enum.AccessoryType.Waist,
}

-- Layered: catalogue type -> AccessoryType.
local LAYERED: { [string]: Enum.AccessoryType } = {
	TShirtAccessory = Enum.AccessoryType.TShirt,
	ShirtAccessory = Enum.AccessoryType.Shirt,
	SweaterAccessory = Enum.AccessoryType.Sweater,
	JacketAccessory = Enum.AccessoryType.Jacket,
	PantsAccessory = Enum.AccessoryType.Pants,
	ShortsAccessory = Enum.AccessoryType.Shorts,
	DressSkirtAccessory = Enum.AccessoryType.DressSkirt,
	LeftShoeAccessory = Enum.AccessoryType.LeftShoe,
	RightShoeAccessory = Enum.AccessoryType.RightShoe,
	EyebrowAccessory = Enum.AccessoryType.Eyebrow,
	EyelashAccessory = Enum.AccessoryType.Eyelash,
}

-- Classic clothing: catalogue type -> HumanoidDescription property.
local CLASSIC: { [string]: string } = {
	Shirt = "Shirt",
	Pants = "Pants",
	TShirt = "GraphicTShirt",
}

local MAKEUP: { [string]: Enum.MakeupType } = {
	FaceMakeup = Enum.MakeupType.Face,
	LipMakeup = Enum.MakeupType.Lip,
	EyeMakeup = Enum.MakeupType.Eye,
}

local BODY_PARTS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local BODY_COLOURS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }
local BODY_SCALES = { "HeightScale", "WidthScale", "DepthScale", "HeadScale", "BodyTypeScale", "ProportionScale" }
-- What a head is: the head mesh, its face and the mood (expression) animation.
local HEAD_PARTS = { "Head", "Face", "MoodAnimation" }
local ANIMATIONS =
	{ "IdleAnimation", "WalkAnimation", "RunAnimation", "JumpAnimation", "FallAnimation", "ClimbAnimation", "SwimAnimation" }

local GEAR_ATTRIBUTE = "RippleGear"
local MAX_EMOTE_LOOKUP = 16 -- emote ids per request
-- Per player: at most this many lookups per window (a budget, not a strict
-- cooldown, since a preview rebuild can ask twice in quick succession).
local EMOTE_LOOKUP_BUDGET = 20
local EMOTE_LOOKUP_WINDOW = 10 -- seconds

-- Reverse of RIGID + LAYERED, for reading a player's own avatar.
local TYPE_OF_ACCESSORY: { [Enum.AccessoryType]: string } = {}
for typeName, accessoryType in RIGID do
	TYPE_OF_ACCESSORY[accessoryType] = typeName
end
for typeName, accessoryType in LAYERED do
	TYPE_OF_ACCESSORY[accessoryType] = typeName
end

local resolved: { [string]: WornItem | false } = {}
local bundleOutfits: { [number]: HumanoidDescription | false } = {}
local gearTemplates: { [number]: Tool | false } = {}
local bases: { [Player]: HumanoidDescription } = {}
local applying: { [Player]: { busy: boolean, again: boolean } } = {}
local emoteAnimations: { [number]: string | false } = {}
local emoteLookups: { [Player]: { number } } = {} -- request times

-- The animation inside an emote asset (cached; false if it has none).
local function emoteAnimation(emoteId: number): string?
	local cached = emoteAnimations[emoteId]
	if cached ~= nil then
		return cached or nil
	end
	local ok, model = pcall(function()
		return InsertService:LoadAsset(emoteId)
	end)
	local animation = if ok then model:FindFirstChildWhichIsA("Animation", true) else nil
	local id = if animation then animation.AnimationId else nil
	if ok then
		model:Destroy()
	else
		warn(`[AvatarService] Couldn't load emote {emoteId}: {model}`)
	end
	emoteAnimations[emoteId] = id or false
	return id
end

local function typeNameOf(value: any): string
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	return tostring(value)
end

function AvatarService.resolve(targetId: number, kind: "Asset" | "Bundle"): WornItem?
	local key = kind .. targetId
	local cached = resolved[key]
	if cached ~= nil then
		return cached or nil
	end
	local itemType = if kind == "Bundle" then Enum.AvatarItemType.Bundle else Enum.AvatarItemType.Asset
	local ok, details = pcall(function()
		return AvatarEditorService:GetItemDetails(targetId, itemType)
	end)
	if not ok then
		-- Don't cache failures: they may be a passing throttle.
		warn(`[AvatarService] Couldn't look up {kind} {targetId}: {details}`)
		return nil
	end
	local info = details :: any
	local item: WornItem = {
		targetId = targetId,
		kind = kind,
		typeName = typeNameOf(if kind == "Bundle" then info.BundleType else info.AssetType),
		name = info.Name or "",
	}
	resolved[key] = item
	return item
end

local function bundleOutfit(bundleId: number): HumanoidDescription?
	local cached = bundleOutfits[bundleId]
	if cached ~= nil then
		return cached or nil
	end
	local ok, description = pcall(function()
		local info = AssetService:GetBundleDetailsAsync(bundleId)
		for _, entry in info.Items do
			if entry.Type == "UserOutfit" then
				return Players:GetHumanoidDescriptionFromOutfitId(entry.Id)
			end
		end
		return nil
	end)
	local outfit = if ok then description else nil
	if not ok then
		warn(`[AvatarService] Couldn't load bundle {bundleId}: {description}`)
	end
	bundleOutfits[bundleId] = outfit or false
	return outfit
end

local function gearTemplate(assetId: number): Tool?
	local cached = gearTemplates[assetId]
	if cached ~= nil then
		return cached or nil
	end
	local ok, model = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	local tool = if ok then model:FindFirstChildWhichIsA("Tool", true) else nil
	if tool then
		-- Inert: no scripts, so it can be held and seen but not used.
		for _, descendant in tool:GetDescendants() do
			if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
				descendant:Destroy()
			end
		end
		tool:SetAttribute(GEAR_ATTRIBUTE, assetId)
		tool.Parent = nil
	else
		warn(`[AvatarService] Couldn't load gear {assetId}: {if ok then "no tool" else model}`)
	end
	if ok then
		model:Destroy()
	end
	gearTemplates[assetId] = tool or false
	return tool
end

-- The player's own avatar, as a list of wearable items (owned: they're on
-- the player's Roblox avatar).
local function itemsOf(description: HumanoidDescription): { WornItem }
	local items: { WornItem } = {}
	for _, accessory in description:GetAccessories(true) do
		local typeName = TYPE_OF_ACCESSORY[accessory.AccessoryType]
		if typeName then
			table.insert(items, { targetId = accessory.AssetId, kind = "Asset", typeName = typeName, name = "" })
		end
	end
	for typeName, property in CLASSIC do
		local id = (description :: any)[property]
		if id and id ~= 0 then
			table.insert(items, { targetId = id, kind = "Asset", typeName = typeName, name = "" })
		end
	end
	local emotes = description:GetEmotes()
	for _, name in description:GetEquippedEmotes() do
		local ids = emotes[(name :: any).Name or name]
		if ids and ids[1] then
			table.insert(items, { targetId = ids[1], kind = "Asset", typeName = "EmoteAnimation", name = tostring((name :: any).Name or name) })
		end
	end
	for _, child in description:GetChildren() do
		if child:IsA("MakeupDescription") then
			for typeName, makeupType in MAKEUP do
				if child.MakeupType == makeupType then
					table.insert(items, { targetId = child.AssetId, kind = "Asset", typeName = typeName, name = "" })
				end
			end
		end
	end
	for _, item in items do
		item.owned = true
	end
	-- Names, in one batch.
	local ids = {}
	for _, item in items do
		if item.name == "" then
			table.insert(ids, item.targetId)
		end
	end
	if #ids > 0 then
		local ok, details = pcall(function()
			return AvatarEditorService:GetBatchItemDetails(ids, Enum.AvatarItemType.Asset)
		end)
		if ok then
			local names = {}
			for _, entry in details do
				names[entry.Id] = entry.Name
			end
			for _, item in items do
				if item.name == "" then
					item.name = names[item.targetId] or ""
				end
			end
		end
	end
	return items
end

-- The player's own avatar with its wearable items taken off: the base that
-- `worn` goes on top of.
local function baseOf(description: HumanoidDescription): HumanoidDescription
	local base = description:Clone()
	base:SetAccessories({}, true)
	for _, property in CLASSIC do
		(base :: any)[property] = 0
	end
	base:SetEmotes({})
	base:SetEquippedEmotes({})
	for _, child in base:GetChildren() do
		if child:IsA("MakeupDescription") then
			child:Destroy()
		end
	end
	return base
end

local function fetchOwn(player: Player): HumanoidDescription?
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not ok then
		warn(`[AvatarService] Couldn't load {player.Name}'s avatar: {description}`)
		return nil
	end
	return description
end

function AvatarService.ownDescription(player: Player): HumanoidDescription?
	return fetchOwn(player)
end

function AvatarService.robloxOutfit(outfitId: number): (HumanoidDescription?, { WornItem })
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromOutfitId(outfitId)
	end)
	if not ok or not description then
		return nil, {}
	end
	return description, itemsOf(description)
end

function AvatarService.ownLook(player: Player): { WornItem }
	local own = fetchOwn(player)
	if not own then
		return {}
	end
	bases[player] = baseOf(own)
	return itemsOf(own)
end

-- `worn` on top of the base.
local function describe(player: Player, worn: { WornItem }): (HumanoidDescription, number?)
	local description = (bases[player] or Instance.new("HumanoidDescription")):Clone()
	local accessories = {}
	local layerOrder = 1
	local emotes, equipped = {}, {}
	local gear: number? = nil
	local seen: { [number]: boolean } = {} -- one asset can't be used twice

	local function addAccessory(assetId: number, accessoryType: Enum.AccessoryType, layered: boolean)
		if seen[assetId] then
			return
		end
		seen[assetId] = true
		if layered then
			table.insert(accessories, { AssetId = assetId, AccessoryType = accessoryType, IsLayered = true, Order = layerOrder })
			layerOrder += 1
		else
			table.insert(accessories, { AssetId = assetId, AccessoryType = accessoryType })
		end
	end

	for _, item in worn do
		local t = item.typeName
		if item.kind == "Bundle" then
			local outfit = bundleOutfit(item.targetId)
			if outfit then
				if t == "BodyParts" then
					-- A full body is everything its outfit defines: parts, head
					-- (with face and mood), skin, proportions, and any accessories
					-- that come with it (e.g. a knight's helmet).
					for _, property in BODY_PARTS do
						local id = (outfit :: any)[property]
						if id and id ~= 0 then
							(description :: any)[property] = id
						end
					end
					-- (A body without a head of its own keeps the player's.)
					if outfit.Head ~= 0 then
						for _, property in HEAD_PARTS do
							(description :: any)[property] = (outfit :: any)[property]
						end
					end
					for _, property in BODY_COLOURS do
						(description :: any)[property] = (outfit :: any)[property]
					end
					for _, property in BODY_SCALES do
						(description :: any)[property] = (outfit :: any)[property]
					end
					for _, accessory in outfit:GetAccessories(true) do
						addAccessory(accessory.AssetId, accessory.AccessoryType, accessory.IsLayered == true)
					end
				elseif t == "DynamicHead" or t == "DynamicHeadAvatar" then
					if outfit.Head ~= 0 then
						for _, property in HEAD_PARTS do
							(description :: any)[property] = (outfit :: any)[property]
						end
					end
				elseif t == "Animations" then
					for _, property in ANIMATIONS do
						local id = (outfit :: any)[property]
						if id and id ~= 0 then
							(description :: any)[property] = id
						end
					end
				elseif t == "Shoes" then
					for _, accessory in outfit:GetAccessories(true) do
						local at = accessory.AccessoryType
						if at == Enum.AccessoryType.LeftShoe or at == Enum.AccessoryType.RightShoe then
							addAccessory(accessory.AssetId, at, true)
						end
					end
				end
			end
		elseif RIGID[t] then
			addAccessory(item.targetId, RIGID[t], false)
		elseif LAYERED[t] then
			addAccessory(item.targetId, LAYERED[t], true)
		elseif CLASSIC[t] then
			(description :: any)[CLASSIC[t]] = item.targetId
		elseif MAKEUP[t] then
			local makeup = Instance.new("MakeupDescription")
			makeup.AssetId = item.targetId
			makeup.MakeupType = MAKEUP[t]
			makeup.Parent = description
		elseif t == "EmoteAnimation" then
			local name = if item.name ~= "" then item.name else tostring(item.targetId)
			emotes[name] = { item.targetId }
			table.insert(equipped, name)
		elseif t == "Gear" then
			gear = item.targetId
		end
	end

	description:SetAccessories(accessories, true)
	description:SetEmotes(emotes)
	description:SetEquippedEmotes(equipped)
	return description, gear
end

function AvatarService.describeLook(player: Player, worn: { WornItem }): HumanoidDescription
	local description = describe(player, worn)
	return description
end

local function holdGear(character: Model, gearId: number?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local player = Players:GetPlayerFromCharacter(character)
	local backpack = player and player:FindFirstChildOfClass("Backpack")
	local held: Tool? = nil
	for _, container in { character, backpack } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(GEAR_ATTRIBUTE) ~= nil then
					if child:GetAttribute(GEAR_ATTRIBUTE) == gearId and not held then
						held = child
					else
						child:Destroy()
					end
				end
			end
		end
	end
	if gearId and not held and humanoid then
		local template = gearTemplate(gearId)
		if template then
			local tool = template:Clone()
			tool.Parent = backpack or character
			humanoid:EquipTool(tool)
		end
	end
end

local function applyNow(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local model = AvatarModel.get(tostring(player.UserId))
	if not (character and humanoid and model) then
		return
	end
	local description, gear = describe(player, model.worn)
	local ok, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not ok then
		warn(`[AvatarService] Couldn't dress {player.Name}: {err}`)
	end
	holdGear(character :: Model, gear)
end

-- Re-dress the player's character from `worn` (coalesced).
function AvatarService.apply(player: Player)
	local state = applying[player]
	if not state then
		state = { busy = false, again = false }
		applying[player] = state
	end
	if state.busy then
		state.again = true
		return
	end
	state.busy = true
	task.spawn(function()
		repeat
			state.again = false
			applyNow(player)
		until not state.again or not player.Parent
		state.busy = false
	end)
end

local function onPlayer(player: Player)
	local model = AvatarModel.get(tostring(player.UserId))
	if not model then
		return
	end
	local own = fetchOwn(player)
	if own then
		bases[player] = baseOf(own)
		local ownItems = itemsOf(own)
		model:setOwn(table.clone(ownItems))
		if not model.seeded then
			model:seed(ownItems)
		else
			-- Anything worn that's on the player's own avatar is owned (also
			-- fixes looks saved before items carried the flag).
			local ownIds = {}
			for _, item in ownItems do
				ownIds[item.kind .. item.targetId] = true
			end
			local changed = false
			for _, item in model.worn do
				if not item.owned and ownIds[item.kind .. item.targetId] then
					item.owned = true
					changed = true
				end
			end
			if changed then
				model:syncState()
			end
		end
	end
	-- Undo history doesn't survive a rejoin.
	if model.canUndo then
		model.canUndo = false
		model:syncState(true)
	end
	player.CharacterAdded:Connect(function()
		AvatarService.apply(player)
	end)
	if player.Character then
		AvatarService.apply(player)
	end
end

function AvatarService.init()
	local lookup = Bolt.RemoteFunction("AvatarEmoteAnimations")
	lookup.OnServerInvoke = function(player: Player, ids: any)
		local result: { { id: number, animation: string } } = {}
		if type(ids) ~= "table" then
			return result
		end
		local now = os.clock()
		local recent = {}
		for _, at in emoteLookups[player] or {} do
			if now - at < EMOTE_LOOKUP_WINDOW then
				table.insert(recent, at)
			end
		end
		if #recent >= EMOTE_LOOKUP_BUDGET then
			return result
		end
		table.insert(recent, now)
		emoteLookups[player] = recent
		for index, id in ids do
			if type(index) == "number" and index <= MAX_EMOTE_LOOKUP and type(id) == "number" and id > 0 and id % 1 == 0 then
				local animation = emoteAnimation(id)
				if animation then
					table.insert(result, { id = id, animation = animation })
				end
			end
		end
		return result
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayer, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		bases[player] = nil
		applying[player] = nil
		emoteLookups[player] = nil
	end)
end

return AvatarService
