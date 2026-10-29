--!strict
-- REFERENCE COPY. The live module is Studio-authored at
-- ReplicatedStorage.Config.WorldOptionsConfig (configs aren't Rojo-synced in
-- this template — see docs/CONFIG_GUIDE.md). Keep the two in step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigTypes = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ConfigTypes")
local WorldOptionsConfigTypes = require(ConfigTypes:WaitForChild("WorldOptionsConfigTypes"))

type WorldOptionsConfig = WorldOptionsConfigTypes.WorldOptionsConfig

local config: WorldOptionsConfig = {
	timeMin = 0,
	timeMax = 24,
	timeStep = 0.25,
	brightnessMin = 0,
	brightnessMax = 200,
	brightnessStep = 5,
	skies = { "Clear", "Clouds", "Studio", "Void" },
	patterns = { "Grid", "Studs", "Checker", "Clouds", "Grass", "Water" },
	-- Both palettes share one order: orange, yellow, green, teal, purple, white.
	-- No black: each colour has a lightness multiplier that takes it down to
	-- black. Orange is the place's own Baseplate colour (the default floor).
	-- Saved as the hex itself, so reordering never swaps choices.
	floorColors = { "#cc5f00", "#f2c94c", "#3fbf8a", "#26a6b5", "#7a5cff", "#e9e6e1" },
	-- Pattern drawn over the floor: colour + lightness, texture + strength.
	-- Defaults match the modern baseplate: black grid (white at 0% lightness)
	-- at 0.8 transparency (20% strength).
	patternColors = { "#cc5f00", "#f2c94c", "#3fbf8a", "#26a6b5", "#7a5cff", "#ffffff" },
	lightnessMin = 0,
	lightnessMax = 100,
	lightnessStep = 5,
	patternStrengthMin = 0,
	patternStrengthMax = 100,
	patternStrengthStep = 5,
	-- The whole floor (part and pattern); at 0% it's invisible but still solid.
	floorOpacityMin = 0,
	floorOpacityMax = 100,
	floorOpacityStep = 5,
	defaults = {
		time = 14.5, -- the place's Lighting.ClockTime
		sky = "Clear",
		floor = "#cc5f00",
		floorLightness = 100,
		floorOpacity = 100,
		pattern = "Grid",
		patternColor = "#ffffff",
		patternLightness = 0,
		patternStrength = 20,
		brightness = 100,
		shadows = true,
		playlist = { "vinyl_cradle" },
		musicOn = true,
	},
	-- The music player (World options > Music): the 4x4 grid in this order;
	-- the first is the default playlist. `audio` / `cover` are asset ids.
	music = {
		volume = 0.6, -- AudioPlayer.Volume (no control): under the UI sounds
		tracks = {
			{ key = "vinyl_cradle", name = "Vinyl Cradle", mood = "Dusty boom-bap jazz", audio = 84810861102488, cover = 128779126002416 },
			{ key = "arcade_night", name = "Arcade Night", mood = "Neon chillwave", audio = 132723516994389, cover = 112332370885260 },
			{ key = "dont_blink_twice", name = "Don't Blink Twice", mood = "Midnight jazz lounge", audio = 109290101467093, cover = 101805811197266 },
			{ key = "rainy_evenings", name = "Rainy Evenings", mood = "Rain-streaked downtempo", audio = 120591093645567, cover = 135331647834111 },
			{ key = "pixelated_groove", name = "Pixelated Groove", mood = "Playful chiptune lo-fi", audio = 70515812111783, cover = 89372596188924 },
			{ key = "i_know_i_do", name = "I Know I Do", mood = "Sleek nu-jazz", audio = 81877368564387, cover = 89805249991731 },
			{ key = "airborne_idling", name = "Airborne Idling", mood = "Airy ambient drift", audio = 137599402859587, cover = 96555937078560 },
			{ key = "cartoonish_melodica", name = "Cartoonish Melodica", mood = "Off-kilter trip-hop", audio = 105268907997634, cover = 90586414956401 },
			{ key = "gradual_hope", name = "Gradual Hope", mood = "Slow-rising post-rock", audio = 125764986605533, cover = 89182000339830 },
			{ key = "buttons_wrong", name = "Buttons Wrong, But It'll Do", mood = "Scrappy slacker indie", audio = 74300952241061, cover = 136462338318708 },
			{ key = "fuzz_pedal_jangle", name = "Fuzz-Pedal Jangle", mood = "Sunlit fuzz-pop", audio = 79937625277834, cover = 78262495152234 },
			{ key = "jaunty_march", name = "Jaunty March", mood = "Whimsical folk march", audio = 134535938606627, cover = 130838448989063 },
			{ key = "fractured_warmth", name = "Fractured Warmth", mood = "Glitchy indie folk", audio = 88950803904745, cover = 89191688581625 },
			{ key = "ready_in_five", name = "Ready in Five", mood = "Late-90s girl-group pop", audio = 98946168717679, cover = 102654941344012 },
			{ key = "looking_fresh", name = "Looking Fresh", mood = "Y2K arcade breakbeat", audio = 130253538064862, cover = 76644051031280 },
			{ key = "soft_rain_on_leaves", name = "Soft Rain on Leaves", mood = "Rain and distant thunder", audio = 138117962370258, cover = 139840591712987 },
		},
	},
	flight = {
		enabled = true,
		speed = 40,
		climbSpeed = 24,
		doubleJumpWindow = 0.5,
	},
	sprint = {
		enabled = true,
		walkSpeed = 16, -- Roblox's default
		runSpeed = 28,
		flightMultiplier = 1.75,
	},
}

return config
