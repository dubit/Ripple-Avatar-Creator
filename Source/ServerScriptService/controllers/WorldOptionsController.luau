--!strict

--[[
	WorldOptionsController

	Saves a player's World options. The client sends a partial table of
	changes when a slider is released or a choice is tapped (not per drag
	tick). Every field is checked against WorldOptionsConfig; unknown keys and
	bad values are dropped, numbers are clamped and snapped to their step.

	The music player's settings ride along: `playlist` (track keys, known
	ones only, in library order, never empty) and `musicOn`.

	Actions:
		Set(changes)     apply validated changes
		Reset(section?)  back to the config defaults: one section's settings
		                 ("sky" | "floor" | "music", WorldOptionsSections), or all
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractController = require(script.Parent.AbstractController)
local WorldOptionsModel = require(script.Parent.Parent.models.user.WorldOptionsModel)
local Network = require(ReplicatedStorage.Network)

local WorldOptionsConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("WorldOptionsConfig"))
local WorldOptionsSections = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("WorldOptionsSections"))

local WorldOptionsController = {}
WorldOptionsController.__index = WorldOptionsController
setmetatable(WorldOptionsController, AbstractController)

export type WorldOptionsController = typeof(setmetatable({}, WorldOptionsController)) & AbstractController.AbstractController

local function snap(value: any, min: number, max: number, step: number): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	local clamped = math.clamp(value, min, max)
	return math.clamp(math.floor((clamped - min) / step + 0.5) * step + min, min, max)
end

-- Returns only the valid fields of `raw`, normalised.
local function validate(raw: any): WorldOptionsModel.Changes
	local changes: WorldOptionsModel.Changes = {}
	if type(raw) ~= "table" then
		return changes
	end
	local config = WorldOptionsConfig
	changes.time = snap(raw.time, config.timeMin, config.timeMax, config.timeStep)
	changes.brightness = snap(raw.brightness, config.brightnessMin, config.brightnessMax, config.brightnessStep)
	changes.floorLightness = snap(raw.floorLightness, config.lightnessMin, config.lightnessMax, config.lightnessStep)
	changes.floorOpacity = snap(raw.floorOpacity, config.floorOpacityMin, config.floorOpacityMax, config.floorOpacityStep)
	changes.patternLightness = snap(raw.patternLightness, config.lightnessMin, config.lightnessMax, config.lightnessStep)
	changes.patternStrength =
		snap(raw.patternStrength, config.patternStrengthMin, config.patternStrengthMax, config.patternStrengthStep)
	if type(raw.sky) == "string" and table.find(config.skies, raw.sky) then
		changes.sky = raw.sky
	end
	if type(raw.pattern) == "string" and table.find(config.patterns, raw.pattern) then
		changes.pattern = raw.pattern
	end
	if type(raw.floor) == "string" and table.find(config.floorColors, raw.floor) then
		changes.floor = raw.floor
	end
	if type(raw.patternColor) == "string" and table.find(config.patternColors, raw.patternColor) then
		changes.patternColor = raw.patternColor
	end
	if type(raw.shadows) == "boolean" then
		changes.shadows = raw.shadows
	end
	local music = config.music
	changes.playlist = WorldOptionsSections.playlist(raw.playlist, music.tracks)
	if type(raw.musicOn) == "boolean" then
		changes.musicOn = raw.musicOn
	end
	return changes
end

local function set(model: any, raw: any)
	local changes = validate(raw)
	if next(changes :: any) ~= nil then
		model:apply(changes)
	end
end

local function reset(model: any, raw: any)
	model:reset(if type(raw) == "string" and WorldOptionsSections.KEYS[raw] then raw else nil)
end

local ACTIONS = {
	[Network.Actions.WorldOptions.Set] = set,
	[Network.Actions.WorldOptions.Reset] = reset,
}

function WorldOptionsController:executeAction(player: Player, action: Network.WorldOptionsAction, raw: any)
	local model = WorldOptionsModel.get(tostring(player.UserId))
	if not model then
		return
	end
	self:dispatchAction(ACTIONS, action, player, model, raw)
end

function WorldOptionsController.new(): WorldOptionsController
	local self = AbstractController.new("WorldOptionsController") :: any
	setmetatable(self, WorldOptionsController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.WorldOptionsAction, raw: any)
		self:executeAction(player, action, raw)
	end)

	return self :: WorldOptionsController
end

return WorldOptionsController
