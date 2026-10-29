--!strict

--[[
	WorldRenderer (renders nothing — applies World options to this client's world)

	Client-side changes to Lighting, terrain Clouds and the floor part aren't
	replicated, so each player's settings stay private by construction.

	  time        Lighting.ClockTime — Roblox moves the sun/moon and brings out
	              the stars itself (pinned at midday under the Studio sky)
	  brightness  Lighting.ExposureCompensation = log2(percent / 100), so the
	              sky dims/brightens with the scene. Roblox clamps exposure to
	              ±3 stops, so 0% bottoms out at 1/8 brightness (very dark, not
	              black) and 200% is +1 stop
	  shadows     Lighting.GlobalShadows
	  sky         Clear  = the place's own Sky + Atmosphere
	              Clouds = that plus terrain Clouds
	              Studio / Void = flat light-grey / black skybox images on all
	              six Sky faces (SkinAssets.skyTextures), sun, moon and stars
	              hidden; Studio keeps a light grey horizon haze, Void none
	              (a dense Atmosphere fogged the floor blue-grey)
	  floor       colour of every part tagged "WorldFloor", times floorLightness %
	              (the pattern colour likewise times patternLightness %)
	  pattern     the Texture on its upward face, whichever way the part is
	              turned (one is added if it has none; SkinAssets.floorTextures:
	              Grid, Studs, Checker, Clouds, Grass, Water) at PATTERN_STUDS studs per tile, drawn in
	              patternColor at patternStrength % opacity (the textures are
	              white/greyscale, so the colour is what's chosen)
	  floorOpacity  the floor as a whole, part and pattern; at 0 it's invisible
	              (and casts no shadow) but still solid

	The place's original Sky/Atmosphere values are captured once the game has
	loaded (the HUD mounts from ReplicatedFirst, before Lighting may exist on
	the client) and each floor texture's when first seen; they're used for the
	Clear sky and the Grid pattern. Floor parts that stream in later get the
	current options too.

	Props:
		options: Network.WorldOptionsState
		config: WorldOptionsConfig
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local SkinAssets = require(script.Parent:WaitForChild("SkinAssets"))

local FLOOR_TAG = "WorldFloor"
local STUDIO_CLOCK_TIME = 14
local STUDIO_COLOUR = Color3.fromHex("#c9ccd2")
-- Studs per texture tile. Grid uses the floor texture's own tiling (the
-- place's baseplate: 8). Studs: the image holds 2×2 studs. Checker: 4-stud
-- squares, matching the grid tile. Clouds: large soft patches. Grass: blades
-- about avatar-shin height. Water: ripples a few avatars across.
local PATTERN_STUDS: { [string]: number } = {
	Studs = 2,
	Checker = 8,
	Clouds = 64,
	Grass = 12,
	Water = 32,
}

local SKYBOX_FACES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }

type Snapshot = {
	starCount: number,
	skybox: { [string]: string },
	atmosphere: { density: number, offset: number, color: Color3, decay: Color3, haze: number, glare: number }?,
	textures: { [Texture]: { texture: string, studsU: number, studsV: number, transparency: number, color: Color3 } },
}

-- The part's face that points up in the world: Top only if the part isn't
-- turned (the place's Baseplate is stood on its side, 16 x 2048 x 2048, so
-- its floor is its Right face).
local function upFace(part: BasePart): Enum.NormalId
	local best, bestDot = Enum.NormalId.Top, -math.huge
	for _, face in Enum.NormalId:GetEnumItems() do
		local dot = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face)).Y
		if dot > bestDot then
			best, bestDot = face, dot
		end
	end
	return best
end

-- The Texture on the floor's upward face. A floor without one gets one (this
-- client only), starting as Roblox's grid, so every pattern can show on it.
local function topTexture(part: BasePart): Texture
	local face = upFace(part)
	for _, child in part:GetChildren() do
		if child:IsA("Texture") and child.Face == face then
			return child
		end
	end
	local texture = Instance.new("Texture")
	texture.Name = "WorldPattern"
	texture.Face = face
	texture.Texture = "rbxassetid://" .. SkinAssets.floorTextures.Grid
	texture.StudsPerTileU = 8
	texture.StudsPerTileV = 8
	texture.Transparency = 0.8
	texture.Color3 = Color3.new(0, 0, 0)
	texture.Parent = part
	return texture
end

-- The texture's original look, recorded the first time we touch it.
local function baseFor(texture: Texture, original: Snapshot)
	local base = original.textures[texture]
	if base == nil then
		base = {
			texture = texture.Texture,
			studsU = texture.StudsPerTileU,
			studsV = texture.StudsPerTileV,
			transparency = texture.Transparency,
			color = texture.Color3,
		}
		original.textures[texture] = base
	end
	return base
end

local function snapshot(): Snapshot
	local sky = Lighting:FindFirstChildOfClass("Sky")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local textures = {}
	local skybox = {}
	if sky then
		for _, face in SKYBOX_FACES do
			skybox[face] = (sky :: any)[face]
		end
	end
	return {
		starCount = if sky then sky.StarCount else 3000,
		skybox = skybox,
		atmosphere = if atmosphere
			then {
				density = atmosphere.Density,
				offset = atmosphere.Offset,
				color = atmosphere.Color,
				decay = atmosphere.Decay,
				haze = atmosphere.Haze,
				glare = atmosphere.Glare,
			}
			else nil,
		textures = textures,
	}
end

local function applySky(options: any, original: Snapshot)
	local open = options.sky == "Clear" or options.sky == "Clouds"

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.CelestialBodiesShown = open
		sky.StarCount = if open then original.starCount else 0
		local flatId = SkinAssets.skyTextures[options.sky]
		for _, face in SKYBOX_FACES do
			(sky :: any)[face] = if not open and flatId and flatId ~= 0
				then "rbxassetid://" .. flatId
				else original.skybox[face]
		end
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local saved = original.atmosphere
	if atmosphere and saved then
		if open then
			atmosphere.Density = saved.density
			atmosphere.Offset = saved.offset
			atmosphere.Color = saved.color
			atmosphere.Decay = saved.decay
			atmosphere.Haze = saved.haze
			atmosphere.Glare = saved.glare
		elseif options.sky == "Studio" then
			atmosphere.Density = 0.3
			atmosphere.Offset = 0.25
			atmosphere.Color = STUDIO_COLOUR
			atmosphere.Decay = STUDIO_COLOUR
			atmosphere.Haze = 0
			atmosphere.Glare = 0
		else -- Void: no haze at all
			atmosphere.Density = 0
			atmosphere.Haze = 0
			atmosphere.Glare = 0
		end
	end

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		-- Optional: only exists while the Clouds sky is on.
		local clouds = terrain:FindFirstChild("WorldOptionsClouds")
		if options.sky == "Clouds" and not clouds then
			local created = Instance.new("Clouds")
			created.Name = "WorldOptionsClouds"
			created.Cover = 0.55
			created.Density = 0.75
			created.Parent = terrain
		elseif options.sky ~= "Clouds" and clouds then
			clouds:Destroy()
		end
	end
end

local function applyFloor(options: any, config: any, original: Snapshot)
	local picked = Color3.fromHex(options.floor)
	local lightness = math.clamp(options.floorLightness / 100, 0, 1)
	local colour = Color3.new(picked.R * lightness, picked.G * lightness, picked.B * lightness)
	local patternPicked = Color3.fromHex(options.patternColor)
	local patternLightness = math.clamp(options.patternLightness / 100, 0, 1)
	local patternColour = Color3.new(
		patternPicked.R * patternLightness,
		patternPicked.G * patternLightness,
		patternPicked.B * patternLightness
	)
	local opacity = math.clamp(options.floorOpacity / 100, 0, 1)
	local patternTransparency = 1 - math.clamp(options.patternStrength / 100, 0, 1) * opacity
	for _, part in CollectionService:GetTagged(FLOOR_TAG) do
		if part:IsA("BasePart") then
			part.Color = colour
			-- Still solid at 0 (you walk on nothing); no shadow from a floor
			-- you can't see.
			part.Transparency = 1 - opacity
			part.CastShadow = opacity > 0
			local texture = topTexture(part)
			local base = baseFor(texture, original)
			do
				local id = SkinAssets.floorTextures[options.pattern]
				local studs = PATTERN_STUDS[options.pattern]
				texture.Texture = if id and id ~= 0 then "rbxassetid://" .. id else base.texture
				texture.StudsPerTileU = studs or base.studsU
				texture.StudsPerTileV = studs or base.studsV
				texture.Transparency = patternTransparency
				texture.Color3 = patternColour
			end
		end
	end
end

local function WorldRenderer(props: { options: any, config: any })
	local ready, setReady = React.useState(game:IsLoaded())
	local original = React.useRef(nil :: Snapshot?)
	local latest = React.useRef(props)
	latest.current = props
	local options = props.options

	React.useEffect(function()
		if not ready then
			local connection = game.Loaded:Connect(function()
				setReady(true)
			end)
			return function()
				connection:Disconnect()
			end
		end
		original.current = snapshot()
		-- Floor parts streaming in later get the current options.
		local added = CollectionService:GetInstanceAddedSignal(FLOOR_TAG):Connect(function()
			applyFloor(latest.current.options, latest.current.config, original.current :: Snapshot)
		end)
		return function()
			added:Disconnect()
		end
	end, { ready })

	React.useEffect(function()
		if ready then
			Lighting.ClockTime = if options.sky == "Studio" then STUDIO_CLOCK_TIME else options.time
		end
	end, { ready, options.time, options.sky } :: { any })

	React.useEffect(function()
		if ready then
			Lighting.ExposureCompensation = math.log(math.max(options.brightness, 1) / 100, 2)
		end
	end, { ready, options.brightness } :: { any })

	React.useEffect(function()
		if ready then
			Lighting.GlobalShadows = options.shadows
		end
	end, { ready, options.shadows } :: { any })

	React.useEffect(function()
		if ready then
			applySky(options, original.current :: Snapshot)
		end
	end, { ready, options.sky } :: { any })

	React.useEffect(function()
		if ready then
			applyFloor(options, props.config, original.current :: Snapshot)
		end
	end, {
		ready,
		options.floor,
		options.floorLightness,
		options.pattern,
		options.patternColor,
		options.patternLightness,
		options.patternStrength,
		options.floorOpacity,
	} :: { any })

	return nil
end

return WorldRenderer
