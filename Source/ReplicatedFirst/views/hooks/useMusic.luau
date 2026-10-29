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
	The volume is fixed (music.volume).

	The playlist plays shuffled: each next track is a random one not yet
	played since every track had its turn, and never the one just playing
	(a one-track playlist repeats it). It starts on a random one too.

	Returns:
		tracks, current (a track), playing
		toggle(key)       not in the playlist: add it and play it now. In it:
		                  take it out (playing it? on to the next); the last one
		                  can't go (an error sound, returns false)
		playPause()       start / stop
		next()            a shuffled next track
		previous()        back through the tracks played (still in the playlist);
		                  past 3 s in, or with none to go back to, restarts it
		seek(fraction)    0..1 of the track
		audio()           { player: AudioPlayer, analyzer: AudioAnalyzer }? for
		                  the panel's clock, progress and spectrum
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local RESTART_AFTER = 3 -- seconds in, Previous restarts the track instead

local WorldOptionsSections = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("WorldOptionsSections"))
local Sounds = require(script.Parent.Parent:WaitForChild("Sounds"))

export type Track = { key: string, name: string, mood: string, audio: number, cover: number }

export type Audio = { player: AudioPlayer, analyzer: AudioAnalyzer }

local function useMusic(world: any)
	local options = world.options
	local music = world.config.music
	local tracks: { Track } = music.tracks
	local playlist: { string } = options.playlist
	local playing: boolean = options.musicOn

	local chosen, setChosen = React.useState(function()
		return playlist[math.random(#playlist)]
	end)
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
	-- Tracks played since the shuffle last started over.
	local played = React.useRef({ [key] = true } :: { [string]: boolean })
	-- The tracks played before this one, most recent last (for Previous).
	local history = React.useRef({} :: { string })

	local function goTo(nextKey: string, back: boolean?)
		if not back and nextKey ~= latest.current.key then
			table.insert(history.current, latest.current.key)
		end
		played.current[nextKey] = true
		setChosen(nextKey)
		setStart(function(n: number)
			return n + 1
		end)
	end

	-- A random track in `list` that isn't `fromKey` and hasn't played since
	-- the shuffle started over (when every one has, it starts over).
	local function shuffled(list: { string }, fromKey: string): string
		local function fresh(): { string }
			local out = {}
			for _, candidate in list do
				if candidate ~= fromKey and not played.current[candidate] then
					table.insert(out, candidate)
				end
			end
			return out
		end
		local pool = fresh()
		if #pool == 0 then
			played.current = { [fromKey] = true }
			pool = fresh()
		end
		if #pool == 0 then
			return list[1] -- a one-track playlist: that one again
		end
		return pool[math.random(#pool)]
	end

	local function advance()
		local now = latest.current
		goTo(shuffled(now.playlist, now.key))
	end

	-- The audio graph, once.
	React.useEffect(function()
		local folder = Instance.new("Folder")
		folder.Name = "MusicPlayer"
		local player = Instance.new("AudioPlayer")
		player.Looping = false
		player.Volume = music.volume
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
		local ended = player.Ended:Connect(advance)
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
				goTo(shuffled(rest, trackKey))
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
		if not audio or audio.player.TimePosition <= RESTART_AFTER then
			local list = latest.current.playlist
			while #history.current > 0 do
				local last = table.remove(history.current) :: string
				if table.find(list, last) and last ~= latest.current.key then
					goTo(last, true)
					return
				end
			end
		end
		goTo(latest.current.key, true) -- from the top
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
		toggle = toggle,
		playPause = function()
			world.commit({ musicOn = not latest.current.playing })
		end,
		next = advance,
		previous = previous,
		seek = seek,
		audio = function(): Audio?
			return nodes.current
		end,
	}
end

return useMusic
