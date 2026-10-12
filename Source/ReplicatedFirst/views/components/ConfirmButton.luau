--!strict

--[[
	ConfirmButton

	A full-width pill for something hard to take back (Remove all, Take
	everything off, Delete outfit). The first press arms it: it turns orange
	and reads "Tap again to confirm" (or `armedLabel`) for CONFIRM_SECONDS,
	wiggling side to side every so often to draw the eye. A second press
	within that does it. No dialog.

	Props:
		label: string
		icon: string
		armedLabel: string?
		disabled: boolean?
		onConfirm: () -> ()
		layoutOrder
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local PillButton = require(script.Parent:WaitForChild("PillButton"))

local e = React.createElement

local CONFIRM_SECONDS = 3
local WIGGLE_AT = { 0.35, 1.15, 1.95 } -- seconds after arming
local WIGGLE_SECONDS = 0.35
local WIGGLE_PX = 5 -- design px, either side
local WIGGLE_SWINGS = 3 -- full left-right swings per wiggle

-- Sideways offset (0..1 of WIGGLE_PX) `elapsed` seconds after arming.
local function wiggle(elapsed: number): number
	for _, start in WIGGLE_AT do
		local t = elapsed - start
		if t >= 0 and t < WIGGLE_SECONDS then
			local fade = 1 - t / WIGGLE_SECONDS
			return math.sin(t / WIGGLE_SECONDS * WIGGLE_SWINGS * 2 * math.pi) * fade
		end
	end
	return 0
end

local function ConfirmButton(props: {
	label: string,
	icon: string,
	armedLabel: string?,
	layoutOrder: number?,
	disabled: boolean?,
	onConfirm: () -> (),
})
	local skin = useSkin()
	local armed, setArmed = React.useState(false)
	local shake, setShake = React.useBinding(0)
	React.useEffect(function()
		if not armed then
			setShake(0)
			return nil
		end
		local started = os.clock()
		local connection = RunService.RenderStepped:Connect(function()
			setShake(wiggle(os.clock() - started))
		end)
		local thread = task.delay(CONFIRM_SECONDS, function()
			setArmed(false)
		end)
		return function()
			connection:Disconnect()
			task.cancel(thread)
		end
	end, { armed })
	-- The wrapper holds the layout slot; the button moves inside it (a
	-- UIListLayout would ignore the button's own Position).
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(Tokens.size.ctaHeight)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Button = e(PillButton, {
			variant = "pill",
			size = Tokens.size.ctaHeight,
			label = if armed then props.armedLabel or "Tap again to confirm" else props.label,
			icon = props.icon,
			iconSize = 18,
			active = armed,
			sound = if armed then false else nil, -- the action plays its own sound
			disabled = props.disabled,
			position = shake:map(function(amount: number)
				return UDim2.fromOffset(amount * skin.px(WIGGLE_PX), 0)
			end) :: any,
			onActivated = function()
				if armed then
					setArmed(false)
					props.onConfirm()
				else
					setArmed(true)
				end
			end,
		}),
	})
end

return ConfirmButton
