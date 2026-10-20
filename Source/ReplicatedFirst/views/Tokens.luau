--!strict

--[[
	Tokens

	The Ripple Avatar Creator skin: every colour, gradient, radius, size, type
	style and spring preset the HUD uses, so no screen holds magic numbers.

	Values are lifted from the Claude Design mock
	(features/cac-adaptation/design/markup.html + logic.js). All sizes are
	DESIGN PIXELS on the 1180x820 iPad canvas; components convert them through
	useSkin().px so the sizing mode (relative vs canvas) is decided in one place.

	Inferred translations from CSS are commented where they aren't literal.
]]

local Tokens = {}

-- 1180x820 is the point size of iPad Air / iPad Pro 11", so on the target
-- iPad the design renders at exactly scale 1.0.
Tokens.design = {
	width = 1180,
	height = 820,
}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

Tokens.color = {
	white = Color3.new(1, 1, 1),
	black = Color3.new(0, 0, 0),
	accent = hex("#ff8a1a"),
	accentText = hex("#ffa64d"),
	accentIcon = hex("#ff9a3a"),
	accentSoft = hex("#ffb36b"),
	borderOrange = hex("#6a2a00"),
	iconDark = hex("#1a1a1a"),
	inputWell = hex("#0a0a0a"),
	toggleOff = hex("#222222"),
}

-- Text/line alphas from the design, expressed as Roblox TRANSPARENCY (1 - alpha).
Tokens.alpha = {
	textMuted = 1 - 0.55,
	textDim = 1 - 0.6,
	textSoft = 1 - 0.7,
	textQuiet = 1 - 0.75,
	textBright = 1 - 0.85,
}

-- Catalogue colour filter swatches (logic.js COL).
Tokens.swatch = {
	Red = hex("#e0403a"),
	Yellow = hex("#f2c94c"),
	Grey = hex("#8c8c8c"),
	Orange = hex("#ff7a00"),
	Black = hex("#2a2a2a"),
	White = hex("#d9d9d9"),
	Pink = hex("#ff5fa8"),
	Blue = hex("#3b82f6"),
	Green = hex("#3fbf6a"),
	Purple = hex("#8b5cf6"),
	Brown = hex("#8a5a3b"),
}

-- World options floor swatches (logic.js floors).
Tokens.floorSwatches = { hex("#ff7a00"), hex("#1c1c1e"), hex("#e9e6e1"), hex("#3fbf8a"), hex("#7a5cff") }

local function sequence(stops: { { number | string } }): ColorSequence
	local keypoints = {}
	for _, stop in stops do
		table.insert(keypoints, ColorSequenceKeypoint.new(stop[1] :: number, hex(stop[2] :: string)))
	end
	return ColorSequence.new(keypoints)
end

-- Vertical gradients (UIGradient Rotation = 90). Always apply to a frame whose
-- BackgroundColor3 is WHITE — UIGradient multiplies with the background
-- (html-to-react-luau pitfall 1).
Tokens.gradient = {
	rotation = 90,
	-- The glossy "split" pills: hard step at 48%/52%.
	black = sequence({ { 0, "#4a4a4a" }, { 0.48, "#1d1d1d" }, { 0.52, "#050505" }, { 1, "#161616" } }),
	orange = sequence({ { 0, "#ffc27a" }, { 0.48, "#ff8a1a" }, { 0.52, "#ec6500" }, { 1, "#ff9a3a" } }),
	whiteBadge = sequence({ { 0, "#ffffff" }, { 1, "#d6d6d6" } }),
	knob = sequence({ { 0, "#ffffff" }, { 1, "#cfcfcf" } }),
	-- Inferred: the design's radial-gradient(120% 90% at 50% -30%, ...) full-panel
	-- background, approximated linearly (divergence; a radial PNG would close it).
	fullPanel = sequence({ { 0, "#3a3a3a" }, { 0.55, "#151515" }, { 1, "#070707" } }),
}

-- Inset top highlight (CSS `inset 0 1px 0 rgba(255,255,255,a)`), approximated
-- by a 1px white stroke whose gradient fades out down the shape.
function Tokens.highlightTransparency(alpha: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - alpha),
		NumberSequenceKeypoint.new(0.35, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

Tokens.highlight = {
	blackPill = 0.5,
	orangePill = 0.6,
	tab = 0.45,
	panel = 0.3,
	bar = 0.35,
	card = 0.15,
}

Tokens.radius = {
	tabBar = 27,
	sidePanel = 22,
	contentPanel = 22,
	basketCard = 18,
	itemCard = 14,
	chip = 17,
	search = 20,
	toggle = 14,
	badge = 13,
	itemBadge = 12,
}

Tokens.size = {
	tabWidth = 172,
	tabHeight = 52,
	-- Round buttons: diameter and icon size.
	basket = { size = 84, icon = 42, glow = 18 },
	action = { size = 64, icon = 30, glow = 14 },
	close = { size = 52, icon = 28, glow = 12 },
	undo = { size = 44, icon = 24, glow = 12 },
	back = { size = 40, icon = 22, glow = 12 },
	small = { size = 36, icon = 20, glow = 0 },
	badgeHeight = 26,
	markerBadge = 24,
	chipHeight = 34,
	textTabHeight = 42,
	ctaHeight = 42,
	wearingBar = 44,
	sidePanelWidth = 340,
	edgeInset = 28,
	-- Placeholder the design reserves for Roblox's own top-bar buttons.
	systemBar = { x = 20, y = 14, width = 160, height = 36 },
}

Tokens.stroke = {
	border = 1,
	borderColor = Color3.new(0, 0, 0),
	-- Panel/card borders: white at the design's alpha, as transparency.
	panelTransparency = 1 - 0.18,
	contentTransparency = 1 - 0.12,
	cardTransparency = 1 - 0.12,
	tabRingTransparency = 1 - 0.12,
	-- Inferred: CSS drop shadows become the canonical black UIStroke halo.
	-- UIStroke can't feather, so keep it thin and faint or it reads as a
	-- hard ring (seen in the first gallery pass at 8px / 0.75).
	shadowThickness = 3,
	shadowTransparency = 0.82,
}

-- Nunito ships with Roblox; design weights 600/700/800/900 map to these faces.
local NUNITO = "rbxasset://fonts/families/Nunito.json"
local WEIGHTS: { [number]: Enum.FontWeight } = {
	[400] = Enum.FontWeight.Regular,
	[600] = Enum.FontWeight.SemiBold,
	[700] = Enum.FontWeight.Bold,
	[800] = Enum.FontWeight.ExtraBold,
	[900] = Enum.FontWeight.Heavy,
}

function Tokens.font(weight: number): Font
	return Font.new(NUNITO, WEIGHTS[weight] or Enum.FontWeight.Bold)
end

export type TypeStyle = { size: number, weight: number }

Tokens.type = {
	tabLabel = { size = 18, weight = 900 },
	panelTitle = { size = 18, weight = 900 },
	cardTitle = { size = 16, weight = 900 },
	textTab = { size = 15.5, weight = 900 },
	cta = { size = 15, weight = 900 },
	badge = { size = 15, weight = 900 },
	crumb = { size = 15, weight = 800 },
	sectionLabel = { size = 14, weight = 800 },
	bodyStrong = { size = 14, weight = 900 },
	chip = { size = 13.5, weight = 800 },
	small = { size = 13, weight = 800 },
	meta = { size = 13, weight = 700 },
	search = { size = 14.5, weight = 700 },
	hint = { size = 13, weight = 600 },
	minPx = 10,
}

-- Glass fills: top→bottom colour and alpha. `blur` uses the design's alphas
-- (which assume a 14px backdrop blur); `translucent` is denser to stay legible
-- without one.
export type GlassVariant = {
	top: Color3,
	bottom: Color3,
	alphaTop: number,
	alphaBottom: number,
	border: number,
	highlight: number,
}

Tokens.glass = {
	dark = {
		top = Color3.fromRGB(60, 60, 60),
		bottom = Color3.fromRGB(10, 10, 10),
		alphaTop = 0.72,
		alphaBottom = 0.86,
		border = 1 - 0.18,
		highlight = 0.3,
	} :: GlassVariant,
	bar = {
		top = Color3.fromRGB(70, 70, 70),
		bottom = Color3.fromRGB(8, 8, 8),
		alphaTop = 0.92,
		alphaBottom = 0.95,
		border = 1 - 0.2,
		highlight = 0.35,
	} :: GlassVariant,
	light = {
		top = Color3.new(1, 1, 1),
		bottom = Color3.new(1, 1, 1),
		alphaTop = 0.07,
		alphaBottom = 0.02,
		border = 1 - 0.12,
		highlight = 0.18,
	} :: GlassVariant,
	-- Added to alpha (clamped) in translucent mode. Tuned in the gallery.
	translucentBoost = 0.1,
	blurSize = 16,
}

Tokens.glow = {
	color = hex("#ff8a1a"),
	-- Inferred: CSS `0 0 Npx rgba(255,138,26,.9)` approximated by three
	-- concentric rounded rings behind the button (extra size, transparency).
	rings = {
		{ grow = 0.12, transparency = 0.55 },
		{ grow = 0.45, transparency = 0.8 },
		{ grow = 1, transparency = 0.92 },
	},
}

-- Inferred: CSS `filter: brightness(1.18)` approximated by a white overlay.
Tokens.hover = {
	overlayTransparency = 0.9,
}

Tokens.press = {
	scale = 0.94,
}

export type SpringPreset = { force: number, dampening: number, mass: number? }

-- Damping ratio = dampening / (2 * sqrt(force)); < 1 overshoots (bouncy),
-- >= 1 settles without overshoot.
Tokens.spring = {
	hover = { force = 300, dampening = 28 } :: SpringPreset,
	press = { force = 450, dampening = 30 } :: SpringPreset,
	state = { force = 240, dampening = 26 } :: SpringPreset,
	panel = { force = 180, dampening = 22 } :: SpringPreset,
	-- Full panel open (slight overshoot) / close (fast, no overshoot).
	panelIn = { force = 260, dampening = 26 } :: SpringPreset,
	panelOut = { force = 420, dampening = 44 } :: SpringPreset,
	-- Screen content arriving after a tab or crumb change.
	screen = { force = 340, dampening = 30 } :: SpringPreset,
	-- Side panels sliding in from the edge.
	slide = { force = 240, dampening = 26 } :: SpringPreset,
	-- Number roll on badges and counts.
	count = { force = 140, dampening = 20 } :: SpringPreset,
}

-- Motion distances (design px).
Tokens.motion = {
	panelDrop = 24, -- full panel content drops in from above
	screenSlide = 18, -- screen content slides in from the right
	sideSlide = 48, -- World options slides in from the right edge
}

-- UI sound volumes (0..1) per slot; `default` for any slot not listed.
Tokens.sound = {
	volume = {
		default = 0.5,
		press = 0.35,
		tab = 0.35,
		open = 0.45,
		close = 0.4,
		back = 0.4,
		confirm = 0.5,
		tryOn = 0.5,
		error = 0.45,
		-- The synthesised swipes measure louder than the pack's tones.
		switch = 0.3,
		worldIn = 0.35,
		worldOut = 0.35,
		purchase = 0.6,
	},
}

-- Robux, shown one way everywhere: the symbol, then the amount with
-- thousands separators ("₹12,499"). Change the symbol here only.
Tokens.robuxSymbol = "₹"

-- 12499 -> "12,499"
function Tokens.grouped(amount: number): string
	local digits = tostring(math.floor(amount + 0.5))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end
	return grouped
end

function Tokens.robux(amount: number): string
	return Tokens.robuxSymbol .. Tokens.grouped(amount)
end

return Tokens
