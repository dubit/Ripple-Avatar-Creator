--!strict

--[[
	useMusic

	The background music player (World options › Music). Mounted once in Hud,
	so music keeps playing with the panel shut. This client only: an
	AudioPlayer wired to the player's speakers (AudioDeviceOutput) and to an
	AudioAnalyzer for the panel's spectrum bars, under SoundService.

	What it plays comes from the saved World options (useWorldOptions):
	  playlist     track keys (WorldOptionsConfig.music.tracks), in grid order
	  musicOn      playing; false is stopped (it resumes where it stopped)
	  musicVolume  percent of music.maxVolume

	The playlist plays in grid order and wraps. A track ending goes to the
	next one (a one-track playlist repeats it).

	Returns:
		tracks, current (a track), playing, volume
		toggle(key)       not in the playlist: add it and play it now. In it:
		                  take it out (playing it? on to the next); the last one
		                  can't go (an error sound, returns false)
		playPause()       start / stop
		next(), previous()   previous restarts the track if it's past 3 s
		seek(fraction)    0..1 of the track
		changeVolume(v) / commitVolume(v)   live while dragging / saved
		audio()           { player: AudioPlayer, analyzer: AudioAnalyzer }? for
		                  the panel's clock, progress and spectrum
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local WorldOptionsSections = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("WorldOptionsSections"))
local Sounds = require(script.Parent.Parent:WaitForChild("Sounds"))

local RESTART_AFTER = 3 -- seconds in, Previous restarts the track instead

export type Track = { key: string, name: string, mood: string, audio: number, cover: number }

export type Audio = { player: AudioPlayer, analyzer: AudioAnalyzer }

local function useMusic(world: any)
	local options = world.options
	local music = world.config.music
	local tracks: { Track } = music.tracks
	local playlist: { string } = options.playlist
	local playing: boolean = options.musicOn

	local chosen, setChosen = React.useState(playlist[1])
	-- Bumped to (re)start the current track from the top, even the same one.
	local start, setStart = React.useState(0)
	local key = if table.find(playlist, chosen) then chosen else playlist[1]
	local current: Track = tracks[1]
	for _, track in tracks do
		if track.key == key then
			current = track
		end
	end

	local latest = React.useRef({ playlist = playlist, key = key, playing = playing })
	latest.current = { playlist = playlist, key = key, playing = playing }

	local nodes = React.useRef(nil :: Audio?)
	local resumeAt = React.useRef(0)

	local function goTo(nextKey: string)
		setChosen(nextKey)
		setStart(function(n: number)
			return n + 1
		end)
	end

	-- The key `step` places on from `fromKey` in `list` (by grid order, so a
	-- key that's just left the list still has a place), wrapping.
	local function stepFrom(list: { string }, fromKey: string, step: number): string
		local order: { string } = {}
		for _, track in tracks do
			if track.key == fromKey or table.find(list, track.key) then
				table.insert(order, track.key)
			end
		end
		local at = table.find(order, fromKey) or 1
		for i = 1, #order do
			local candidate = order[((at - 1 + step * i) % #order) + 1]
			if table.find(list, candidate) then
				return candidate
			end
		end
		return list[1]
	end

	local function advance(step: number)
		local now = latest.current
		goTo(stepFrom(now.playlist, now.key, step))
	end

	-- The audio graph, once.
	React.useEffect(function()
		local folder = Instance.new("Folder")
		folder.Name = "MusicPlayer"
		local player = Instance.new("AudioPlayer")
		player.Looping = false
		player.Parent = folder
		local output = Instance.new("AudioDeviceOutput")
		output.Parent = folder
		local analyzer = Instance.new("AudioAnalyzer")
		analyzer.SpectrumEnabled = true
		analyzer.Parent = folder
		for _, target in { output, analyzer } :: { Instance } do
			local wire = Instance.new("Wire")
			wire.SourceInstance = player
			wire.TargetInstance = target
			wire.Parent = folder
		end
		folder.Parent = SoundService
		nodes.current = { player = player, analyzer = analyzer }
		local ended = player.Ended:Connect(function()
			advance(1)
		end)
		return function()
			ended:Disconnect()
			folder:Destroy()
			nodes.current = nil
		end
	end, {})

	-- Load (or restart) the current track; play it when it's ready, if on.
	React.useEffect(function()
		local audio = nodes.current
		if not audio then
			return nil
		end
		local player = audio.player
		player:Stop()
		player.AssetId = "rbxassetid://" .. current.audio
		player.TimePosition = 0
		resumeAt.current = 0
		local function playWhenReady()
			if latest.current.playing and player.IsReady then
				player:Play()
			end
		end
		local ready = player:GetPropertyChangedSignal("IsReady"):Connect(playWhenReady)
		playWhenReady()
		return function()
			ready:Disconnect()
		end
	end, { current.key, start } :: { any })

	-- Start / stop (picking up where it stopped).
	React.useEffect(function()
		local audio = nodes.current
		if not audio then
			return
		end
		local player = audio.player
		if playing then
			if not player.IsPlaying and player.IsReady then
				player.TimePosition = resumeAt.current
				player:Play()
			end
		elseif player.IsPlaying then
			resumeAt.current = player.TimePosition
			player:Stop()
		end
	end, { playing })

	React.useEffect(function()
		local audio = nodes.current
		if audio then
			audio.player.Volume = math.clamp(options.musicVolume / 100, 0, 1) * music.maxVolume
		end
	end, { options.musicVolume })

	local function toggle(trackKey: string): boolean
		local list = latest.current.playlist
		if table.find(list, trackKey) then
			if #list <= 1 then
				Sounds.play("error")
				return false
			end
			local rest = table.clone(list)
			table.remove(rest, table.find(rest, trackKey) :: number)
			world.commit({ playlist = rest })
			if latest.current.key == trackKey then
				goTo(stepFrom(rest, trackKey, 1))
			end
			Sounds.play("back")
			return true
		end
		local added = table.clone(list)
		table.insert(added, trackKey)
		world.commit({
			playlist = WorldOptionsSections.playlist(added, tracks) or added,
			musicOn = true,
		})
		goTo(trackKey)
		Sounds.play("confirm")
		return true
	end

	local function previous()
		local audio = nodes.current
		if audio and audio.player.TimePosition > RESTART_AFTER then
			goTo(latest.current.key)
		else
			advance(-1)
		end
	end

	local function seek(fraction: number)
		local audio = nodes.current
		if audio and audio.player.TimeLength > 0 then
			local position = math.clamp(fraction, 0, 1) * audio.player.TimeLength
			audio.player.TimePosition = position
			resumeAt.current = position
		end
	end

	return {
		tracks = tracks,
		playlist = playlist,
		current = current,
		playing = playing,
		volume = options.musicVolume,
		toggle = toggle,
		playPause = function()
			world.commit({ musicOn = not latest.current.playing })
		end,
		next = function()
			advance(1)
		end,
		previous = previous,
		seek = seek,
		changeVolume = function(value: number)
			world.change({ musicVolume = value })
		end,
		commitVolume = function(value: number)
			world.commit({ musicVolume = value })
		end,
		audio = function(): Audio?
			return nodes.current
		end,
	}
end

return useMusic
