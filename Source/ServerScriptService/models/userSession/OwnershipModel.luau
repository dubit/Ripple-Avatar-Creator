--!strict

--[[
	OwnershipModel (UserSession scope — per player, not saved)

	What we know the player owns, and how their latest purchase went.

	  owned     "Asset:123" / "Bundle:45" keys checked and found owned
	            (OwnershipService asks Roblox; purchases add to it)
	  purchase  the latest purchase: the client's request id, its state
	            ("waiting" while Roblox's prompt is up, then "done",
	            "cancelled" or "failed"), why nothing or not everything was
	            bought, and the keys bought

	Private (never sent): `_checked` remembers every key asked about, owned
	or not, so each is looked up once a session; `_pending` is the purchase
	in progress (its items and when it started).

	Session-only because ownership can change outside the game (bought on
	the website, traded away); each session checks afresh.
]]

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local OwnershipModel = {}
OwnershipModel.__index = OwnershipModel
setmetatable(OwnershipModel, AbstractModel)

export type PurchaseState = "idle" | "waiting" | "done" | "cancelled" | "failed"

export type Purchase = {
	id: number,
	state: PurchaseState,
	reason: string,
	bought: { string },
}

export type PendingItem = { targetId: number, kind: "Asset" | "Bundle", key: string }

export type OwnershipModel = typeof(setmetatable({} :: {
	owned: { string },
	purchase: Purchase,
	_checked: { [string]: boolean },
	_pending: { items: { PendingItem }, at: number, store: string? }?, -- store: bought through it (PurchaseController)
}, OwnershipModel)) & AbstractModel.AbstractModel

function OwnershipModel.new(ownerId: string): OwnershipModel
	local self = AbstractModel.new("OwnershipModel", ownerId, "UserSession") :: any
	setmetatable(self, OwnershipModel)
	self.owned = {}
	self.purchase = { id = 0, state = "idle", reason = "", bought = {} }
	self._checked = {}
	self._pending = nil
	return self :: OwnershipModel
end

-- Session models have nothing to load, so no waiting (getOrWait would wait
-- forever: only persisted models are marked loaded).
function OwnershipModel.get(ownerId: string): OwnershipModel?
	return AbstractModel.getOrCreate("OwnershipModel", ownerId, function()
		return OwnershipModel.new(ownerId)
	end) :: OwnershipModel?
end

function OwnershipModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("OwnershipModel", ownerId)
end

function OwnershipModel:owns(key: string): boolean
	return self._checked[key] == true
end

-- Has this key been looked up (owned or not)?
function OwnershipModel:knows(key: string): boolean
	return self._checked[key] ~= nil
end

-- Record lookups: { [key] = owned }. Broadcasts if anything new is owned.
function OwnershipModel:record(results: { [string]: boolean }): ()
	local changed = false
	for key, owned in results do
		local was = self._checked[key]
		self._checked[key] = owned
		if owned and was ~= true then
			table.insert(self.owned, key)
			changed = true
		elseif not owned and was == true then
			local index = table.find(self.owned, key)
			if index then
				table.remove(self.owned, index)
				changed = true
			end
		end
	end
	if changed then
		self:syncState()
	end
end

function OwnershipModel:startPurchase(id: number, items: { PendingItem }): ()
	self._pending = { items = items, at = os.clock() }
	self.purchase = { id = id, state = "waiting", reason = "", bought = {} }
	self:syncState()
end

-- End the purchase in progress (or answer a request that never got one).
function OwnershipModel:finishPurchase(id: number, state: PurchaseState, reason: string, bought: { string }): ()
	self._pending = nil
	self.purchase = { id = id, state = state, reason = reason, bought = bought }
	self:syncState()
end

return OwnershipModel
