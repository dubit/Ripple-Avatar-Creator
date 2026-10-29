--!strict

--[[
	useWorldOptions

	The player's World options as the world should render them right now:
	their saved preferences (Network.State.WorldOptions, persisted by
	WorldOptionsModel) overlaid with any in-progress draft.

	  change(changes)  apply live (e.g. while dragging a slider) — client only
	  commit(changes)  apply and save (WorldOptions intent: Set)
	  reset(section?)  back to the config defaults (one section's settings,
	                   WorldOptionsSections, or all), applied instantly and saved
	                   (WorldOptions intent: Reset)

	A drafted value stays until the saved state catches up with it, so there's
	no flicker back to the old value between commit and the server's echo.

	Returns: { options, config, change, commit, reset }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local Network = require(ReplicatedStorage:WaitForChild("Network"))
local WorldOptionsConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("WorldOptionsConfig"))
local WorldOptionsSections = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("WorldOptionsSections"))
local useBoltState = require(script.Parent:WaitForChild("useBoltState"))

local DEFAULT = table.clone(WorldOptionsConfig.defaults) :: any
DEFAULT.ownerId = ""

-- A drafted value the saved state now holds (playlists compare by contents).
local function agrees(saved: any, value: any): boolean
	if type(value) == "table" then
		return WorldOptionsSections.samePlaylist(saved, value)
	end
	return saved == value
end

local function useWorldOptions()
	local saved = useBoltState(Network.State.WorldOptions, DEFAULT)
	local draft, setDraft = React.useState({} :: { [string]: any })

	-- Drop drafted keys the saved state now agrees with.
	React.useEffect(function()
		setDraft(function(current: { [string]: any })
			local pending = {}
			local changed = false
			for key, value in current do
				if agrees(saved[key], value) then
					changed = true
				else
					pending[key] = value
				end
			end
			return if changed then pending else current
		end)
	end, { saved })

	local options = table.clone(saved)
	for key, value in draft do
		options[key] = value
	end
	-- Saved values from before a preset was removed (e.g. the old "Plain"
	-- pattern) fall back to the default.
	if not table.find(WorldOptionsConfig.patterns, options.pattern) then
		options.pattern = WorldOptionsConfig.defaults.pattern
	end
	if not table.find(WorldOptionsConfig.skies, options.sky) then
		options.sky = WorldOptionsConfig.defaults.sky
	end
	-- Colours are saved as hex; older saves held list positions.
	if not table.find(WorldOptionsConfig.floorColors, options.floor) then
		options.floor = WorldOptionsConfig.defaults.floor
	end
	if not table.find(WorldOptionsConfig.patternColors, options.patternColor) then
		options.patternColor = WorldOptionsConfig.defaults.patternColor
	end
	-- Saves from before the music player have none of its settings.
	options.playlist = WorldOptionsSections.playlist(options.playlist, WorldOptionsConfig.music.tracks)
		or table.clone(WorldOptionsConfig.defaults.playlist)
	if type(options.musicOn) ~= "boolean" then
		options.musicOn = WorldOptionsConfig.defaults.musicOn
	end
	if type(options.musicVolume) ~= "number" then
		options.musicVolume = WorldOptionsConfig.defaults.musicVolume
	end

	local change = React.useCallback(function(changes: { [string]: any })
		setDraft(function(current: { [string]: any })
			local nextDraft = table.clone(current)
			for key, value in changes do
				nextDraft[key] = value
			end
			return nextDraft
		end)
	end, {})

	local commit = React.useCallback(function(changes: { [string]: any })
		change(changes)
		Network.Intent.WorldOptions:FireServer(Network.Actions.WorldOptions.Set, changes)
	end, { change })

	local reset = React.useCallback(function(section: string?)
		local keys = if section then WorldOptionsSections.KEYS[section] else nil
		local defaults: { [string]: any } = {}
		for key, value in WorldOptionsConfig.defaults :: any do
			if keys == nil or table.find(keys, key) then
				defaults[key] = value
			end
		end
		change(defaults)
		Network.Intent.WorldOptions:FireServer(Network.Actions.WorldOptions.Reset, section)
	end, { change })

	return {
		options = options,
		config = WorldOptionsConfig,
		change = change,
		commit = commit,
		reset = reset,
	}
end

return useWorldOptions
