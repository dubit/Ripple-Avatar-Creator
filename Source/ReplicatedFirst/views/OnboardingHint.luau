--!strict

--[[
	OnboardingHint (client view, renders nothing in the React tree)

	Teaches new players to tap themselves (it opens the recommendation ring):
	their character pulses like a heartbeat (a Roblox Highlight, mostly
	fill) and a big hand cursor hovers over them, drawn on top. It shows once they've stood still for
	IDLE_SECONDS with nothing open, fades while they move or a menu or the
	ring is open, and stops for good the first time they open the ring
	(OnboardingModel step "ring", marked by the server on rec_open; reset
	with /onboardingmodel reset).

	The first time it shows in a session it reports onboarding_hint
	({ step = "ring" }), so the hint -> rec_open funnel can be measured.

	Props:
	  active   false while a menu or the ring is open (hide)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local views = script.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local SkinAssets = require(views:WaitForChild("SkinAssets"))
local useBoltState = require(views:WaitForChild("hooks"):WaitForChild("useBoltState"))

local STEP = "ring"
local IDLE_SECONDS = 5 -- standing still this long with nothing open
local MOVING = 0.5 -- studs/second of root-part speed that counts as moving
local FADE = 4 -- per second, in and out

-- The flash: the fill beats like a heart, in twos (lub-dub, rest), once
-- every BEAT_PERIOD seconds; the outline stays faint.
local FILL_COLOUR = Tokens.swatch.Yellow
local FILL_PEAK = 0.6 -- opacity at the top of the first beat (0..1)
local OUTLINE_COLOUR = Tokens.color.accent
local OUTLINE_PEAK = 0.35
local BEAT_PERIOD = 1.1 -- seconds from one lub to the next
local BEAT_GAP = 0.22 -- seconds from lub to dub
local BEAT_RISE = 0.06 -- seconds for a beat to peak
local DUB = 0.75 -- the second beat's strength, against the first

-- The pointer: a big hand cursor hovering over the player, finger up and
-- its tip on their chest, pressing (shrinking a little) on each beat, like
-- a click (SkinAssets.pointer, a white 3D hand). It's
-- screen UI placed over the chest each frame, not a BillboardGui: in the
-- world the highlight's fill draws over it (and it casts a shadow).
local POINTER_STUDS = 3.2 -- its height, as if it were in the world at the player
-- The image is a flipbook (tools/build_pointer.py): coloured light drifts
-- through the hand's shadows. Two layers cross-fade from frame to frame, so
-- it flows smoothly at a few frames a second.
local FRAME_SIZE = Vector2.new(197, 256) -- px
local FRAMES = 20
local COLUMNS = 5
local LOOP_SECONDS = 4 -- once through every frame
local POINTER_ASPECT = FRAME_SIZE.X / FRAME_SIZE.Y
local POINTER_PRESS = 0.12 -- how much it shrinks on a beat (0..1)
local TIP = Vector2.new(0.39, 0) -- the fingertip in the image (0..1, from top left)
local CHEST = 0.5 -- studs above the root part's centre for the fingertip

local player = Players.LocalPlayer

-- One heartbeat bump: 0 at x = 0, up to 1 at BEAT_RISE, then easing away.
local function bump(x: number): number
	if x <= 0 then
		return 0
	end
	local t = x / BEAT_RISE
	return t * math.exp(1 - t)
end

-- 0..1: lub, dub, rest.
local function heartbeat(clock: number): number
	local t = clock % BEAT_PERIOD
	return math.max(bump(t), DUB * bump(t - BEAT_GAP))
end

type Parts = { highlight: Highlight, card: ScreenGui, pointer: Frame, under: ImageLabel, over: ImageLabel }

local function build(character: Model): Parts
	local highlight = Instance.new("Highlight")
	highlight.Name = "OnboardingHint"
	highlight.Adornee = character
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = FILL_COLOUR
	highlight.OutlineColor = OUTLINE_COLOUR
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = character

	local card = Instance.new("ScreenGui")
	card.Name = "OnboardingPointer"
	card.IgnoreGuiInset = true -- viewport coordinates
	card.ResetOnSpawn = false
	card.DisplayOrder = -1 -- under the HUD
	card.Parent = player:WaitForChild("PlayerGui")

	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.BackgroundTransparency = 1
	pointer.AnchorPoint = TIP -- so the press shrinks it toward the fingertip
	pointer.Parent = card
	local function layer(name: string, z: number): ImageLabel
		local label = Instance.new("ImageLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Image = `rbxassetid://{SkinAssets.pointer}`
		label.ImageRectSize = FRAME_SIZE
		label.ImageTransparency = 1
		label.ZIndex = z
		label.Parent = pointer
		return label
	end

	return {
		highlight = highlight,
		card = card,
		pointer = pointer,
		under = layer("Frame", 1),
		over = layer("Next", 2),
	}
end

local function OnboardingHint(props: { active: boolean })
	local state = useBoltState(Network.State.Onboarding, { ownerId = "", done = {} } :: any)
	-- Not until the saved state has arrived (ownerId set), so a player who
	-- has done it never sees a flash of the hint.
	local wanted = state.ownerId ~= "" and not table.find(state.done, STEP)

	local active = React.useRef(props.active)
	active.current = props.active

	React.useEffect(function()
		if not wanted then
			return nil
		end
		local parts: Parts? = nil
		local shownFor: Model? = nil
		local idle = 0
		local visible = 0 -- 0..1, faded
		local clock = 0
		local reported = false

		local function clear()
			if parts then
				parts.highlight:Destroy()
				parts.card:Destroy()
				parts = nil
			end
			shownFor = nil
		end

		-- RenderStepped: the pointer follows the camera without a frame's lag.
		local connection = RunService.RenderStepped:Connect(function(dt: number)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not character or not root then
				clear()
				return
			end
			if shownFor ~= character then
				clear()
				parts = build(character)
				shownFor = character
				idle = 0
				visible = 0
			end

			local still = root.AssemblyLinearVelocity.Magnitude < MOVING
			if active.current and still then
				idle += dt
			else
				idle = 0
			end
			local target = if idle >= IDLE_SECONDS then 1 else 0
			-- Toward the target, stopping there (not overshooting back and forth).
			visible = if target == 1 then math.min(1, visible + FADE * dt) else math.max(0, visible - FADE * dt)
			if target == 1 and not reported then
				reported = true
				Network.Intent.Recommendations:FireServer(
					Network.Actions.Recommendations.Track,
					{ event = "onboarding_hint", step = STEP }
				)
			end

			local p = parts :: Parts
			if visible > 0 then
				clock += dt
			else
				clock = 0 -- each showing starts on a beat
			end
			local beat = heartbeat(clock)
			p.highlight.FillTransparency = 1 - FILL_PEAK * beat * visible
			p.highlight.OutlineTransparency = 1 - OUTLINE_PEAK * visible
			p.highlight.Enabled = visible > 0
			local camera = workspace.CurrentCamera
			local chest = (root.CFrame * CFrame.new(0, CHEST, 0)).Position
			local at, onScreen = camera:WorldToViewportPoint(chest)
			p.card.Enabled = visible > 0 and onScreen
			-- Pixels per stud at the player's distance.
			local perStud = camera.ViewportSize.Y / (2 * at.Z * math.tan(math.rad(camera.FieldOfView) / 2))
			local size = POINTER_STUDS * perStud * (1 - POINTER_PRESS * beat)
			p.pointer.Size = UDim2.fromOffset(size * POINTER_ASPECT, size)
			p.pointer.Position = UDim2.fromOffset(at.X, at.Y)
			-- The flipbook: this frame under, the next fading in over it.
			local place = (clock / LOOP_SECONDS % 1) * FRAMES
			local index = math.floor(place)
			local blend = place - index
			p.under.ImageRectOffset = FRAME_SIZE * Vector2.new(index % COLUMNS, index // COLUMNS)
			local next = (index + 1) % FRAMES
			p.over.ImageRectOffset = FRAME_SIZE * Vector2.new(next % COLUMNS, next // COLUMNS)
			p.under.ImageTransparency = 1 - visible
			p.over.ImageTransparency = 1 - visible * blend
		end)

		return function()
			connection:Disconnect()
			clear()
		end
	end, { wanted })

	return nil
end

return OnboardingHint
