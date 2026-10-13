--!strict

--[[
	StoresModel (User scope — persisted per player)

	The player's side of stores (StoresService holds the stores
	themselves, by code):
	  · `mine`: codes of the stores they own, newest first (published or
	    not; capped by StoresConfig.maxStores in StoresController)
	  · `favourites`: stores they've starred, newest first
	  · `visited`: the day (days since 1970) they last visited each store,
	    so a visit counts once a day; the oldest are dropped past MAX_VISITED

	Codes arrive validated by StoresController.
]]

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local StoresModel = {}
StoresModel.__index = StoresModel
setmetatable(StoresModel, AbstractModel)

local MAX_FAVOURITES = 200
local MAX_VISITED = 200
local DAY = 24 * 60 * 60

export type StoresModel = typeof(setmetatable({} :: {
	mine: { string },
	favourites: { string },
	visited: { [string]: number },
}, StoresModel)) & AbstractModel.AbstractModel

function StoresModel.new(ownerId: string): StoresModel
	local self = AbstractModel.new("StoresModel", ownerId, "User") :: any
	setmetatable(self, StoresModel)
	self.mine = {}
	self.favourites = {}
	self.visited = {}
	return self :: StoresModel
end

function StoresModel.get(ownerId: string): StoresModel?
	return AbstractModel.getOrWait("StoresModel", ownerId, function()
		return StoresModel.new(ownerId)
	end) :: StoresModel?
end

function StoresModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("StoresModel", ownerId)
end

function StoresModel:owns(code: string): boolean
	return table.find(self.mine, code) ~= nil
end

function StoresModel:addMine(code: string): ()
	table.insert(self.mine, 1, code)
	self:syncState()
end

function StoresModel:removeMine(code: string): ()
	local index = table.find(self.mine, code)
	if index then
		table.remove(self.mine, index)
	end
	-- Gone for everyone: off the player's other lists too.
	index = table.find(self.favourites, code)
	if index then
		table.remove(self.favourites, index)
	end
	self.visited[code] = nil
	self:syncState()
end

-- Star a store, or unstar it. Returns whether it's starred now.
function StoresModel:toggleFavourite(code: string): boolean
	local index = table.find(self.favourites, code)
	if index then
		table.remove(self.favourites, index)
	else
		table.insert(self.favourites, 1, code)
		while #self.favourites > MAX_FAVOURITES do
			table.remove(self.favourites)
		end
	end
	self:syncState()
	return index == nil
end

-- Note a visit. Returns true if it's the first today (so it counts).
function StoresModel:noteVisit(code: string): boolean
	local today = math.floor(os.time() / DAY)
	if self.visited[code] == today then
		return false
	end
	self.visited[code] = today
	local count = 0
	local oldest: string? = nil
	for key, day in self.visited do
		count += 1
		if not oldest or day < self.visited[oldest] then
			oldest = key
		end
	end
	if count > MAX_VISITED and oldest then
		self.visited[oldest] = nil
	end
	self:syncState()
	return true
end

return StoresModel
