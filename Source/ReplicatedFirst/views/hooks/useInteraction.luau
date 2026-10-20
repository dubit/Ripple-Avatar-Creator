--!strict

--[[
	useInteraction

	Hover + press state for a GuiButton, shared by every skin control.
	MouseButton1Down/Up also fire for touch, so press feedback works on
	tablets/phones. Leaving the button cancels the press, and so does a
	release anywhere (the button may not get its own Up). On touch-only
	devices hover is ignored — taps fire MouseEnter without a reliable
	MouseLeave, which would leave buttons stuck glowing.

	Usage:
		local interaction = useInteraction(props.disabled)
		e("TextButton", {
			[React.Event.MouseEnter] = interaction.onEnter,
			[React.Event.MouseLeave] = interaction.onLeave,
			[React.Event.MouseButton1Down] = interaction.onDown,
			[React.Event.MouseButton1Up] = interaction.onUp,
		})
		-- interaction.hovered, interaction.pressed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

export type Interaction = {
	hovered: boolean,
	pressed: boolean,
	onEnter: () -> (),
	onLeave: () -> (),
	onDown: () -> (),
	onUp: () -> (),
}

local function useInteraction(disabled: boolean?): Interaction
	local hovered, setHovered = React.useState(false)
	local pressed, setPressed = React.useState(false)

	local onEnter = React.useCallback(function()
		setHovered(true)
	end, {})
	local onLeave = React.useCallback(function()
		setHovered(false)
		setPressed(false)
	end, {})
	local onDown = React.useCallback(function()
		setPressed(true)
	end, {})
	local onUp = React.useCallback(function()
		setPressed(false)
	end, {})
	-- A release anywhere ends the press: something that opens over the
	-- button (a card's menu) takes the release, and touch has no leave.
	React.useEffect(function()
		if not pressed then
			return nil
		end
		local connection = UserInputService.InputEnded:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				setPressed(false)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { pressed })

	return {
		hovered = hovered and not disabled and not (UserInputService.TouchEnabled and not UserInputService.MouseEnabled),
		pressed = pressed and not disabled,
		onEnter = onEnter,
		onLeave = onLeave,
		onDown = onDown,
		onUp = onUp,
	}
end

return useInteraction
