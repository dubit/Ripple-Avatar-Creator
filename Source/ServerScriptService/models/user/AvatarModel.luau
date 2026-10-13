--!strict

--[[
	AvatarModel (User scope — persisted per player)

	What the player is wearing: an ordered list of catalogue items
	(`worn`, oldest first), saved across sessions. On a player's first join
	it's empty and `seeded` is false; AvatarService then fills it from their
	own Roblox avatar.

	The slot rules live here (AvatarConfig): an item replaces whatever is in
	its slot (one hair, one shirt, one body…); grouped items stack up to the
	group's limit, the oldest dropping off (accessories, emotes).

	`skin` is the chosen skin colours, one "#RRGGBB" per body part
	(SkinColours; a part left out is the player's own colour). It's part of
	the look: outfits save it and Undo steps back over it. `ownSkin` is the
	player's own avatar's colours (all six parts), for the Skin tone picker.
	`scale` is the chosen body scale (BodyScale: height, width, head, body
	type, proportions; one left out is the player's own), saved and undone
	the same way; `ownScale` is the player's own.

	Layered clothing goes on in the order it sits in `worn` (first =
	closest to the body); `moveLayer` changes that order.

	Undo history is session-only (`_undo`, never saved or sent): every change
	pushes the previous look (items and skin), up to AvatarConfig.undoDepth.

	Logical state only. AvatarService turns `worn` into the real character
	(server Workspace), which Roblox replicates to everyone. Items arrive
	already resolved and validated by AvatarController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))
local BodyScale = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("BodyScale"))

local AvatarModel = {}
AvatarModel.__index = AvatarModel
setmetatable(AvatarModel, AbstractModel)

export type WornItem = {
	targetId: number,
	kind: "Asset" | "Bundle",
	typeName: string,
	name: string,
	owned: boolean?, -- known owned (it came from the player's own avatar)
}

export type AvatarModel = typeof(setmetatable({} :: {
	worn: { WornItem },
	seeded: boolean,
	own: { WornItem }, -- the player's own Roblox avatar's items (refreshed every join)
	canUndo: boolean,
	skin: SkinColours.Colours,
	ownSkin: SkinColours.Colours,
	scale: BodyScale.Scale,
	ownScale: BodyScale.Scale,
	_undo: { { worn: { WornItem }, skin: SkinColours.Colours, scale: BodyScale.Scale } },
}, AvatarModel)) & AbstractModel.AbstractModel

local function same(a: WornItem, b: WornItem): boolean
	return a.targetId == b.targetId and a.kind == b.kind
end

-- `list` with `item` put on, by the slot rules.
local function wearOne(list: { WornItem }, item: WornItem): { WornItem }
	local slot = AvatarConfig.slots[item.typeName]
	local group = AvatarConfig.groups[item.typeName]
	-- The slots this item empties: its own, plus any it also replaces.
	local replaced: { [string]: boolean } = {}
	if slot then
		replaced[slot] = true
		for _, other in (AvatarConfig.alsoReplaces or {})[slot] or {} do
			replaced[other] = true
		end
	end
	local result = {}
	for _, other in list do
		local otherSlot = AvatarConfig.slots[other.typeName]
		if not same(other, item) and not (otherSlot and replaced[otherSlot]) then
			table.insert(result, other)
		end
	end
	table.insert(result, item)
	if group then
		local limit = AvatarConfig.groupLimits[group] or math.huge
		local count = 0
		for _, other in result do
			if AvatarConfig.groups[other.typeName] == group then
				count += 1
			end
		end
		-- Over the limit: drop the oldest in the group.
		local index = 1
		while count > limit and index <= #result do
			if AvatarConfig.groups[result[index].typeName] == group then
				table.remove(result, index)
				count -= 1
			else
				index += 1
			end
		end
	end
	return result
end

function AvatarModel.new(ownerId: string): AvatarModel
	local self = AbstractModel.new("AvatarModel", ownerId, "User") :: any
	setmetatable(self, AvatarModel)
	self.worn = {}
	self.skin = {}
	self.ownSkin = {}
	self.scale = {}
	self.ownScale = {}
	self.seeded = false
	self.own = {}
	self.canUndo = false
	self._undo = {}
	return self :: AvatarModel
end

function AvatarModel.get(ownerId: string): AvatarModel?
	return AbstractModel.getOrWait("AvatarModel", ownerId, function()
		return AvatarModel.new(ownerId)
	end) :: AvatarModel?
end

function AvatarModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("AvatarModel", ownerId)
end

function AvatarModel:isWearing(item: WornItem): boolean
	for _, other in self.worn do
		if same(other, item) then
			return true
		end
	end
	return false
end

local function remember(self: any)
	table.insert(self._undo, {
		worn = self.worn,
		skin = SkinColours.normalise(self.skin),
		scale = BodyScale.normalise(self.scale),
	})
	while #self._undo > AvatarConfig.undoDepth do
		table.remove(self._undo, 1)
	end
	self.canUndo = true
end

-- Replace the whole list (undoable).
function AvatarModel:setWorn(list: { WornItem }): ()
	remember(self)
	self.worn = list
	self:syncState()
end

-- Change the skin colours (parts left out = the player's own), undoable.
function AvatarModel:setSkin(skin: SkinColours.Colours): ()
	if SkinColours.equal(skin, SkinColours.normalise(self.skin)) then
		return
	end
	remember(self)
	self.skin = skin
	self:syncState()
end

-- Change the body scale (one left out = the player's own), undoable.
function AvatarModel:setScale(scale: BodyScale.Scale): ()
	if BodyScale.equal(scale, BodyScale.normalise(self.scale)) then
		return
	end
	remember(self)
	self.scale = scale
	self:syncState()
end

-- Replace the whole look, items, skin colours and scale (undoable): wearing
-- an outfit or someone's look. `skin` / `scale` nil keeps the current one.
function AvatarModel:setLook(list: { WornItem }, skin: SkinColours.Colours?, scale: BodyScale.Scale?): ()
	remember(self)
	self.worn = list
	if skin ~= nil then
		self.skin = skin
	end
	if scale ~= nil then
		self.scale = scale
	end
	self:syncState()
end

-- Move a layered item one step in (-1, closer to the body) or out (+1),
-- past the next layered item. Returns whether it moved.
function AvatarModel:moveLayer(item: WornItem, direction: number, isLayered: (typeName: string) -> boolean): boolean
	local at = nil
	for index, other in self.worn do
		if same(other, item) then
			at = index
		end
	end
	if not at or not isLayered(self.worn[at].typeName) then
		return false
	end
	local swap = at + direction
	while self.worn[swap] and not isLayered(self.worn[swap].typeName) do
		swap += direction
	end
	if not self.worn[swap] then
		return false
	end
	local list = table.clone(self.worn)
	list[at], list[swap] = list[swap], list[at]
	self:setWorn(list)
	return true
end

function AvatarModel:wear(item: WornItem): ()
	self:setWorn(wearOne(self.worn, item))
end

-- Put several on (and, if given, change the skin colours and scale), as
-- one change.
function AvatarModel:wearMany(items: { WornItem }, skin: SkinColours.Colours?, scale: BodyScale.Scale?): ()
	local list = self.worn
	for _, item in items do
		list = wearOne(list, item)
	end
	self:setLook(list, skin, scale)
end

function AvatarModel:takeOff(item: WornItem): ()
	local list = {}
	for _, other in self.worn do
		if not same(other, item) then
			table.insert(list, other)
		end
	end
	self:setWorn(list)
end

-- Take several off as one change (e.g. a whole body's parts).
function AvatarModel:takeOffMany(items: { WornItem }): ()
	local list = {}
	for _, other in self.worn do
		local gone = false
		for _, item in items do
			if same(other, item) then
				gone = true
				break
			end
		end
		if not gone then
			table.insert(list, other)
		end
	end
	if #list ~= #self.worn then
		self:setWorn(list)
	end
end

function AvatarModel:takeOffAll(): ()
	self:setWorn({})
end

-- Back one change. Returns whether there was anything to undo.
function AvatarModel:undo(): boolean
	local previous = table.remove(self._undo)
	if not previous then
		return false
	end
	self.worn = previous.worn
	self.skin = previous.skin
	self.scale = previous.scale or {}
	self.canUndo = #self._undo > 0
	self:syncState()
	return true
end

-- The player's own Roblox avatar's items, for the Outfits "Your avatar" card
-- (what Reset puts back).
function AvatarModel:setOwn(list: { WornItem }, ownSkin: SkinColours.Colours, ownScale: BodyScale.Scale): ()
	self.own = list
	self.ownSkin = ownSkin
	self.ownScale = ownScale
	self.scale = BodyScale.normalise(self.scale)
	-- Older looks kept one colour for the whole body.
	self.skin = SkinColours.normalise(self.skin)
	self:syncState()
end

-- First join: the player's own avatar, without an undo step.
function AvatarModel:seed(list: { WornItem }): ()
	self.worn = list
	self.seeded = true
	self.canUndo = #self._undo > 0
	self:syncState()
end

return AvatarModel
