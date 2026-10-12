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

	Undo history is session-only (`_undo`, never saved or sent): every change
	pushes the previous list, up to AvatarConfig.undoDepth.

	Logical state only. AvatarService turns `worn` into the real character
	(server Workspace), which Roblox replicates to everyone. Items arrive
	already resolved and validated by AvatarController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))

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
	_undo: { { WornItem } },
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

-- Replace the whole list (undoable).
function AvatarModel:setWorn(list: { WornItem }): ()
	table.insert(self._undo, self.worn)
	while #self._undo > AvatarConfig.undoDepth do
		table.remove(self._undo, 1)
	end
	self.worn = list
	self.canUndo = true
	self:syncState()
end

function AvatarModel:wear(item: WornItem): ()
	self:setWorn(wearOne(self.worn, item))
end

function AvatarModel:wearMany(items: { WornItem }): ()
	local list = self.worn
	for _, item in items do
		list = wearOne(list, item)
	end
	self:setWorn(list)
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

function AvatarModel:takeOffAll(): ()
	self:setWorn({})
end

-- Back one change. Returns whether there was anything to undo.
function AvatarModel:undo(): boolean
	local previous = table.remove(self._undo)
	if not previous then
		return false
	end
	self.worn = previous
	self.canUndo = #self._undo > 0
	self:syncState()
	return true
end

-- The player's own Roblox avatar's items, for the Outfits "Your avatar" card
-- (what Reset puts back).
function AvatarModel:setOwn(list: { WornItem }): ()
	self.own = list
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
