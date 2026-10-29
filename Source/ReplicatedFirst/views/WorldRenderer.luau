--!strict

--[[
	WorldRenderer (renders nothing — applies World options to this client's world)

	Client-side changes to Lighting, terrain Clouds and the floor part aren't
	replicated, so each player's settings stay private by construction.

	  time        Lighting.ClockTime — Roblox moves the sun/moon and brings out
	              the stars itself. Under Studio and Void it's their colour
	              instead (SkyDial) and the clock stays at midday
	  brightness  Lighting.ExposureCompensation = log2(percent / 100), so the
	              sky dims/brightens with the scene. Roblox clamps exposure to
	              ±3 stops, so 0% bottoms out at 1/8 brightness (very dark, not
	              black) and 200% is +1 stop
	  shadows     Lighting.GlobalShadows
	  sky         Clear  = the place's own Sky + Atmosphere
	              Clouds = that plus terrain Clouds
	              Studio / Void = a dome of Neon walls round the camera in the
	              slider's colour (a Sky image can't be tinted and haze doesn't
	              reach overhead), with a horizon haze in that colour; sun, moon
	              and stars hidden. The flat skybox images (SkinAssets.skyTextures)
	              sit behind it
	              the rest = full skyboxes (SkinAssets.skyboxes), with their own
	              sun / moon / stars settings and no haze (it would fog them)
	              (a dense Atmosphere fogged the floor blue-grey)
	  light       every sky but Clear / Clouds tints the ambient light and the
	              sunlight with its colour (the skybox's `light`, or the dial's),
	              so the avatar looks like it's under that sky
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
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local SkinAssets = require(script.Parent:WaitForChild("SkinAssets"))
local SkyDial = require(script.Parent:WaitForChild("SkyDial"))

local FLOOR_TAG = "WorldFloor"
local STUDIO_CLOCK_TIME = 14
-- The dome: walls this far from the camera each way (2048 studs square, so
-- they meet at the corners), following it so you never reach them.
local DOME = "WorldOptionsDome"
local DOME_REACH = 1000
-- Neon brightens and saturates its colour (and blows out near white), so the
-- walls get a softer, darker one to land near the slider's.
local DOME_SATURATION = 0.67
local DOME_VALUE = 0.83
-- Sky light: how far the ambient light moves to the sky's colour (kept at
-- its own brightness), and how much of the colour tints the sunlight.
local AMBIENT_MIX = 0.6
local SUN_TINT = 0.25
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

local ADDED_SKY = "WorldOptionsSky"
local SKYBOX_FACES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }

type Snapshot = {
	starCount: number,
	bodies: boolean,
	sunSize: number,
	moonSize: number,
	orientation: Vector3,
	skybox: { [string]: string },
	ambient: Color3,
	outdoorAmbient: Color3,
	colorShiftTop: Color3,
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
		bodies = if sky then sky.CelestialBodiesShown else true,
		sunSize = if sky then sky.SunAngularSize else 21,
		moonSize = if sky then sky.MoonAngularSize else 11,
		orientation = if sky then sky.SkyboxOrientation else Vector3.zero,
		skybox = skybox,
		ambient = Lighting.Ambient,
		outdoorAmbient = Lighting.OutdoorAmbient,
		colorShiftTop = Lighting.ColorShift_Top,
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
	local box = SkinAssets.skyboxes[options.sky]

	-- A place without a Sky gets one (this client only) for the presets that
	-- replace the skybox, and loses it again for Clear / Clouds.
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky and open and sky.Name == ADDED_SKY then
		sky:Destroy()
		sky = nil
	elseif not sky and not open then
		local added = Instance.new("Sky")
		added.Name = ADDED_SKY
		added.Parent = Lighting
		sky = added
	end
	if sky then
		if box then
			for _, face in SKYBOX_FACES do
				(sky :: any)[face] = "rbxassetid://" .. (box :: any)[string.sub(face, 7)]
			end
			sky.CelestialBodiesShown = box.bodies
			sky.StarCount = original.starCount
			sky.SunAngularSize = box.sunSize or original.sunSize
			sky.MoonAngularSize = box.moonSize or original.moonSize
			sky.SkyboxOrientation = Vector3.new(0, box.turn or 0, 0)
		else
			sky.CelestialBodiesShown = if open then original.bodies else false
			sky.StarCount = if open then original.starCount else 0
			sky.SunAngularSize = original.sunSize
			sky.MoonAngularSize = original.moonSize
			sky.SkyboxOrientation = original.orientation
			local flatId = SkinAssets.skyTextures[options.sky]
			for _, face in SKYBOX_FACES do
				(sky :: any)[face] = if not open and flatId and flatId ~= 0
					then "rbxassetid://" .. flatId
					else original.skybox[face]
			end
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
		else -- no haze for the skyboxes; Studio / Void get theirs in applyTint
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

-- Six inward-facing Neon walls round the origin (moved to the camera).
local function makeDome(): Model
	local dome = Instance.new("Model")
	dome.Name = DOME
	for _, direction in { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis } do
		local wall = Instance.new("Part")
		wall.Anchored = true
		wall.CanCollide = false
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Material = Enum.Material.Neon
		wall.Size = Vector3.new(2048, 2048, 1)
		local up = if math.abs(direction.Y) > 0 then Vector3.zAxis else Vector3.yAxis
		wall.CFrame = CFrame.lookAt(direction * DOME_REACH, Vector3.zero, up)
		wall.Parent = dome
	end
	dome.WorldPivot = CFrame.new()
	return dome
end

-- `colour` at `base`'s brightness.
local function atBrightness(colour: Color3, base: Color3): Color3
	local function luminance(c: Color3): number
		return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	end
	local scale = luminance(base) / math.max(luminance(colour), 0.01)
	return Color3.new(math.min(colour.R * scale, 1), math.min(colour.G * scale, 1), math.min(colour.B * scale, 1))
end

-- The sky's colour on the light (nil: the place's own), and on the dome and
-- haze under Studio / Void.
local function applyTint(options: any, config: any, original: Snapshot, dome: Model?)
	local kind = SkyDial.kind(config, options.sky)
	local box = SkinAssets.skyboxes[options.sky]
	local tint = if kind ~= "time"
		then SkyDial.colour(kind, options.time, config)
		elseif box then Color3.fromHex(box.light)
		else nil

	if tint then
		Lighting.Ambient = original.ambient:Lerp(atBrightness(tint, original.ambient), AMBIENT_MIX)
		Lighting.OutdoorAmbient = original.outdoorAmbient:Lerp(atBrightness(tint, original.outdoorAmbient), AMBIENT_MIX)
		Lighting.ColorShift_Top = Color3.new():Lerp(tint, SUN_TINT)
	else
		Lighting.Ambient = original.ambient
		Lighting.OutdoorAmbient = original.outdoorAmbient
		Lighting.ColorShift_Top = original.colorShiftTop
	end

	if kind ~= "time" and tint then
		if dome then
			local hue, saturation, value = tint:ToHSV()
			local wallColour = Color3.fromHSV(hue, saturation * DOME_SATURATION, value * DOME_VALUE)
			for _, wall in dome:GetChildren() do
				(wall :: BasePart).Color = wallColour
			end
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			atmosphere.Density = 0.3
			atmosphere.Offset = 0.25
			atmosphere.Color = tint
			atmosphere.Decay = tint
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
	local dialKind = SkyDial.kind(props.config, options.sky)
	local dome = React.useRef(nil :: Model?)

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
			Lighting.ClockTime = if dialKind ~= "time" then STUDIO_CLOCK_TIME else options.time
		end
	end, { ready, options.time, dialKind } :: { any })

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

	-- The dome, while a Studio / Void sky is on.
	React.useEffect(function()
		if not ready or dialKind == "time" then
			return
		end
		local created = makeDome()
		created.Parent = workspace
		dome.current = created
		local follow = RunService.RenderStepped:Connect(function()
			local camera = workspace.CurrentCamera
			if camera then
				created:PivotTo(CFrame.new(camera.CFrame.Position))
			end
		end)
		return function()
			follow:Disconnect()
			created:Destroy()
			dome.current = nil
		end
	end, { ready, dialKind } :: { any })

	-- After the sky and the dome, which it colours.
	React.useEffect(function()
		if ready then
			applyTint(options, props.config, original.current :: Snapshot, dome.current)
		end
	end, { ready, options.sky, options.time } :: { any })

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
