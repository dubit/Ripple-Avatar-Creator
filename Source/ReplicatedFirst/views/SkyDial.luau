--!strict

--[[
	SkyDial

	The time-of-day slider means something else under some skies (config
	skyDials): Studio's is its warmth, warm white through neutral to cool
	white, and Void's its colour, once round the colour wheel. The range stays
	the time's (0..24), so it's one saved value; picking a sky whose slider
	means something else jumps it to that sky's default (WorldOptionsView).
	WorldRenderer paints the sky and the haze in the colour; the panel shows
	it on the slider and the sky chips.
]]

local SkyDial = {}

export type Kind = "time" | "warmth" | "hue"

local WARM = Color3.fromHex("#ffc48f")
local NEUTRAL = Color3.fromHex("#e9ebef")
local COOL = Color3.fromHex("#b0c8ff")
local HUE_SATURATION = 0.6
local HUE_VALUE = 1
local HUE_STOPS = 6

function SkyDial.kind(config: any, sky: string): Kind
	local dial = config.skyDials[sky]
	return if dial then dial.kind else "time"
end

-- Where the slider starts under this sky.
function SkyDial.default(config: any, sky: string): number
	local dial = config.skyDials[sky]
	return if dial then dial.default else config.defaults.time
end

-- The colour at `value` (timeMin..timeMax) for a warmth or hue slider.
function SkyDial.colour(kind: Kind, value: number, config: any): Color3
	local t = math.clamp((value - config.timeMin) / (config.timeMax - config.timeMin), 0, 1)
	if kind == "warmth" then
		return if t < 0.5 then WARM:Lerp(NEUTRAL, t * 2) else NEUTRAL:Lerp(COOL, t * 2 - 1)
	end
	return Color3.fromHSV(t % 1, HUE_SATURATION, HUE_VALUE)
end

-- The whole range, for the slider's track and the sky chip's strip.
function SkyDial.track(kind: Kind): ColorSequence
	if kind == "warmth" then
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, WARM),
			ColorSequenceKeypoint.new(0.5, NEUTRAL),
			ColorSequenceKeypoint.new(1, COOL),
		})
	end
	local points = {}
	for index = 0, HUE_STOPS do
		local t = index / HUE_STOPS
		table.insert(points, ColorSequenceKeypoint.new(t, Color3.fromHSV(t % 1, HUE_SATURATION, HUE_VALUE)))
	end
	return ColorSequence.new(points)
end

return SkyDial
