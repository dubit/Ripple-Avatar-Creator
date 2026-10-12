--!strict

--[[
	OutfitsModel (User scope — persisted per player)

	The player's saved outfits, oldest first: each an id, a name (already
	text-filtered by OutfitsController) and the items that were worn, as the
	same short records as the worn list. `nextId` hands out ids, so an
	outfit keeps its id when others are deleted.

	One record for all of a player's outfits: at AvatarConfig.outfits limits
	(50 outfits × 40 items, ~80 bytes an item) it stays a few hundred KB at
	worst, far under the DataStore's per-key cap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))

local OutfitsModel = {}
OutfitsModel.__index = OutfitsModel
setmetatable(OutfitsModel, AbstractModel)

export type OutfitItem = {
	targetId: number,
	kind: "Asset" | "Bundle",
	typeName: string,
	name: string,
}

export type Outfit = {
	id: number,
	name: string,
	items: { OutfitItem },
}

export type OutfitsModel = typeof(setmetatable({} :: {
	outfits: { Outfit },
	nextId: number,
}, OutfitsModel)) & AbstractModel.AbstractModel

function OutfitsModel.new(ownerId: string): OutfitsModel
	local self = AbstractModel.new("OutfitsModel", ownerId, "User") :: any
	setmetatable(self, OutfitsModel)
	self.outfits = {}
	self.nextId = 1
	return self :: OutfitsModel
end

function OutfitsModel.get(ownerId: string): OutfitsModel?
	return AbstractModel.getOrWait("OutfitsModel", ownerId, function()
		return OutfitsModel.new(ownerId)
	end) :: OutfitsModel?
end

function OutfitsModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("OutfitsModel", ownerId)
end

function OutfitsModel:find(id: number): (Outfit?, number?)
	for index, outfit in self.outfits do
		if outfit.id == id then
			return outfit, index
		end
	end
	return nil, nil
end

function OutfitsModel:isFull(): boolean
	return #self.outfits >= AvatarConfig.outfits.maxOutfits
end

-- The items to keep: plain records, capped at maxItems.
local function keep(items: { OutfitItem }): { OutfitItem }
	local kept = {}
	for index, item in items do
		if index > AvatarConfig.outfits.maxItems then
			break
		end
		table.insert(kept, { targetId = item.targetId, kind = item.kind, typeName = item.typeName, name = item.name })
	end
	return kept
end

-- Save a new outfit from these items. Returns it (nil when full).
function OutfitsModel:add(name: string, items: { OutfitItem }): Outfit?
	if self:isFull() then
		return nil
	end
	local outfit = { id = self.nextId, name = name, items = keep(items) }
	self.nextId += 1
	table.insert(self.outfits, outfit)
	self:syncState()
	return outfit
end

-- Replace an outfit's items (keeping its id and name).
function OutfitsModel:overwrite(id: number, items: { OutfitItem }): Outfit?
	local outfit = self:find(id)
	if not outfit then
		return nil
	end
	outfit.items = keep(items)
	self:syncState()
	return outfit
end

function OutfitsModel:rename(id: number, name: string): boolean
	local outfit = self:find(id)
	if not outfit or outfit.name == name then
		return false
	end
	outfit.name = name
	self:syncState()
	return true
end

function OutfitsModel:delete(id: number): Outfit?
	local outfit, index = self:find(id)
	if not outfit or not index then
		return nil
	end
	table.remove(self.outfits, index)
	self:syncState()
	return outfit
end

return OutfitsModel
