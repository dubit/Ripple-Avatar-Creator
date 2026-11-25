--!strict

--[[
	RingsModel (Server scope: shared by everyone, never saved)

	Every player's recommendation ring as it stands, so other players can
	see it (OthersRings draws it: the floating items only, nothing to stand
	on). Keyed by the owner's UserId (a string):
	  rings[userId] = { pads = { { kind, id, x, y, z, back } } }
	    kind / id   the item ("Asset" | "Bundle", its Roblox id)
	    x, y, z     the pad's spot on the ground
	    back        the back pad (drawn as a ghost)
	A player with no ring open has no entry.

	Written by RecommendationsController (ShareRing, which checks it), and
	cleared when the player leaves or respawns.
]]

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local RingsModel = {}
RingsModel.__index = RingsModel
setmetatable(RingsModel, AbstractModel)

export type RingPad = { kind: string, id: number, x: number, y: number, z: number, back: boolean }

export type RingsModel = typeof(setmetatable({} :: {
	rings: { [string]: { pads: { RingPad } } },
}, RingsModel)) & AbstractModel.AbstractModel

function RingsModel.new(ownerId: string): RingsModel
	local self = AbstractModel.new("RingsModel", ownerId, "Server") :: any
	setmetatable(self, RingsModel)
	self.rings = {}
	return self :: RingsModel
end

function RingsModel.get(ownerId: string?): RingsModel
	return AbstractModel.getOrCreate("RingsModel", ownerId or "SERVER", function()
		return RingsModel.new(ownerId or "SERVER")
	end) :: RingsModel
end

function RingsModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("RingsModel", ownerId)
end

-- The player's ring is now these pads (already checked).
function RingsModel:set(userId: string, pads: { RingPad }): ()
	self.rings[userId] = { pads = pads }
	self:syncState()
end

-- The player has no ring open.
function RingsModel:clear(userId: string): ()
	if self.rings[userId] then
		self.rings[userId] = nil
		self:syncState()
	end
end

return RingsModel
