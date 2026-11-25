--!strict

--[[
	OnboardingHint (client view, renders nothing in the React tree)

	Teaches new players to tap themselves (it opens the recommendation ring):
	their character flashes (a Roblox Highlight, mostly fill) and a call to
	action floats over their head. It shows once they've stood still for
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
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local views = script.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local useBoltState = require(views:WaitForChild("hooks"):WaitForChild("useBoltState"))

local STEP = "ring"
local IDLE_SECONDS = 5 -- standing still this long with nothing open
local MOVING = 0.5 -- studs/second of root-part speed that counts as moving
local FADE = 4 -- per second, in and out

-- The flash: the fill pulses from nothing to FILL_PEAK opacity and back,
-- once every FLASH_PERIOD seconds; the outline stays faint.
local FILL_COLOUR = Tokens.color.white
local FILL_PEAK = 0.55 -- opacity at the top of a flash (0..1)
local OUTLINE_COLOUR = Tokens.color.accent
local OUTLINE_PEAK = 0.35
local FLASH_PERIOD = 1.4

local player = Players.LocalPlayer

local function ctaText(): string
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return (if touch then "Tap" else "Click") .. " yourself for outfit ideas"
end

type Parts = { highlight: Highlight, card: BillboardGui, pill: Frame, label: TextLabel }

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
	card.Name = "OnboardingCta"
	card.AlwaysOnTop = false -- it sits above the head; nothing else is in the way
	card.LightInfluence = 0
	card.Size = UDim2.fromOffset(380, 58)
	card.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	card.Parent = player:WaitForChild("PlayerGui")

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Tokens.color.black
	pill.BackgroundTransparency = 1
	pill.Parent = card
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Tokens.font(800)
	label.TextSize = 26
	label.TextColor3 = Tokens.color.white
	label.TextTransparency = 1
	label.Text = ctaText()
	label.Parent = pill

	return { highlight = highlight, card = card, pill = pill, label = label }
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
				p.card.StudsOffsetWorldSpace = Vector3.new(0, if head then 2.6 else 4.2, 0)
			end
			if visible > 0 then
				clock += dt
			else
				clock = 0 -- each showing starts at the top of a flash
			end
			-- 1 at the start of each period, easing down to 0 and back.
			local flash = (math.cos(clock / FLASH_PERIOD * 2 * math.pi) + 1) / 2
			p.highlight.FillTransparency = 1 - FILL_PEAK * flash * visible
			p.highlight.OutlineTransparency = 1 - OUTLINE_PEAK * visible
			p.highlight.Enabled = visible > 0
			p.card.Enabled = visible > 0
			p.pill.BackgroundTransparency = 1 - 0.7 * visible
			p.label.TextTransparency = 1 - visible
			p.pill.Size = UDim2.fromScale(0.9 + 0.1 * visible, 0.9 + 0.1 * visible)
		end)

		return function()
			connection:Disconnect()
			clear()
		end
	end, { wanted })

	return nil
end

return OnboardingHint
