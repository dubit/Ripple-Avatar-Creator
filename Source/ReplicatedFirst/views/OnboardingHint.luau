--!strict

--[[
	OnboardingHint (client view, renders nothing in the React tree)

	Teaches new players to tap themselves (it opens the recommendation ring):
	their character pulses like a heartbeat (a Roblox Highlight, mostly
	fill) and a big hand cursor over their head points down at them. It shows once they've stood still for
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

-- The pointer: a big hand cursor over the head, pointing down at the
-- player, poking down on each beat.
local POINTER_STUDS = 3.2 -- its size
local POINTER_POKE = 0.5 -- studs it dips on a beat
local ABOVE_HEAD = 2.4 -- its centre above the head's centre (the tip just clears the head)
local ABOVE_ROOT = 4.2 -- the same with no head yet

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

type Parts = { highlight: Highlight, card: BillboardGui, pointer: ImageLabel }

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

	local card = Instance.new("BillboardGui")
	card.Name = "OnboardingPointer"
	card.AlwaysOnTop = false -- it sits above the head; nothing else is in the way
	card.LightInfluence = 0
	card.Size = UDim2.fromScale(POINTER_STUDS, POINTER_STUDS)
	card.StudsOffsetWorldSpace = Vector3.new(0, ABOVE_HEAD, 0)
	card.Parent = player:WaitForChild("PlayerGui")

	local pointer = Instance.new("ImageLabel")
	pointer.Name = "Pointer"
	pointer.BackgroundTransparency = 1
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.fromScale(0.5, 0.5)
	pointer.Size = UDim2.fromScale(1, 1)
	pointer.Image = `rbxassetid://{SkinAssets.pointer}`
	pointer.ImageTransparency = 1
	pointer.Parent = card

	return { highlight = highlight, card = card, pointer = pointer }
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

		local connection = RunService.Heartbeat:Connect(function(dt: number)
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
			visible = if target > visible then math.min(1, visible + FADE * dt) else math.max(0, visible - FADE * dt)
			if target == 1 and not reported then
				reported = true
				Network.Intent.Recommendations:FireServer(
					Network.Actions.Recommendations.Track,
					{ event = "onboarding_hint", step = STEP }
				)
			end

			local p = parts :: Parts
			-- The avatar loader swaps the head as the look is applied: follow it.
			local head = character:FindFirstChild("Head") :: BasePart?
			local anchor = head or root
			if p.card.Adornee ~= anchor then
				p.card.Adornee = anchor
			end
			if visible > 0 then
				clock += dt
			else
				clock = 0 -- each showing starts on a beat
			end
			local beat = heartbeat(clock)
			p.highlight.FillTransparency = 1 - FILL_PEAK * beat * visible
			p.highlight.OutlineTransparency = 1 - OUTLINE_PEAK * visible
			p.highlight.Enabled = visible > 0
			p.card.Enabled = visible > 0
			p.card.StudsOffsetWorldSpace =
				Vector3.new(0, (if head then ABOVE_HEAD else ABOVE_ROOT) - POINTER_POKE * beat, 0)
			p.pointer.ImageTransparency = 1 - visible
		end)

		return function()
			connection:Disconnect()
			clear()
		end
	end, { wanted })

	return nil
end

return OnboardingHint
