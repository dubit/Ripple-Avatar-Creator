--!strict

--[[
	WorldOptionsModel (User scope — persisted per player)

	The player's saved World options: time of day, sky preset, floor colour,
	pattern (+ its colour and strength), brightness and shadows, and the music
	player's playlist, on / off and volume. Logical state only — each client renders
	its own world from it (nothing here touches the Workspace), so one player's
	settings never reach another's screen.

	Values arrive already validated by WorldOptionsController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local WorldOptionsConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("WorldOptionsConfig"))
local WorldOptionsSections = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("WorldOptionsSections"))

local WorldOptionsModel = {}
WorldOptionsModel.__index = WorldOptionsModel
setmetatable(WorldOptionsModel, AbstractModel)

export type Changes = {
	time: number?,
	sky: string?,
	floor: string?,
	floorLightness: number?,
	pattern: string?,
	patternColor: string?,
	patternLightness: number?,
	patternStrength: number?,
	brightness: number?,
	shadows: boolean?,
	playlist: { string }?,
	musicOn: boolean?,
}

export type WorldOptionsModel = typeof(setmetatable({} :: {
	time: number,
	sky: string,
	floor: string,
	floorLightness: number,
	pattern: string,
	patternColor: string,
	patternLightness: number,
	patternStrength: number,
	brightness: number,
	shadows: boolean,
	playlist: { string },
	musicOn: boolean,
}, WorldOptionsModel)) & AbstractModel.AbstractModel

-- The config defaults, for every setting or (`keys`) just one section's.
local function applyDefaults(self: any, keys: { string }?)
	local defaults = WorldOptionsConfig.defaults :: any
	for key, value in defaults do
		if keys == nil or table.find(keys, key) then
			self[key] = if type(value) == "table" then table.clone(value) else value
		end
	end
end

function WorldOptionsModel.new(ownerId: string): WorldOptionsModel
	local self = AbstractModel.new("WorldOptionsModel", ownerId, "User") :: any
	setmetatable(self, WorldOptionsModel)
	applyDefaults(self)
	return self :: WorldOptionsModel
end

function WorldOptionsModel.get(ownerId: string): WorldOptionsModel?
	return AbstractModel.getOrWait("WorldOptionsModel", ownerId, function()
		return WorldOptionsModel.new(ownerId)
	end) :: WorldOptionsModel?
end

function WorldOptionsModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("WorldOptionsModel", ownerId)
end

-- Apply a partial set of (validated) changes.
function WorldOptionsModel:apply(changes: Changes): ()
	for key, value in changes :: { [string]: any } do
		(self :: any)[key] = value
	end
	self:syncState()
end

-- Back to the defaults: one section's settings (WorldOptionsSections), or all.
function WorldOptionsModel:reset(section: string?): ()
	applyDefaults(self, if section then WorldOptionsSections.KEYS[section] else nil)
	self:syncState()
end

return WorldOptionsModel
