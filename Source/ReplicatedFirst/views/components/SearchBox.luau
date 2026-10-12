--!strict

--[[
	SearchBox

	The design's search well: a sunken pill with a search icon, a text box
	and, once there's text, a clear (×) button. The placeholder hides while
	the box has focus, so focus reads as an empty box ready for input.

	Props:
		text: string
		placeholder: string
		onChange: (text: string) -> ()
		size: UDim2
		position, anchorPoint
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local Icon = require(script.Parent:WaitForChild("Icon"))
local PillButton = require(script.Parent:WaitForChild("PillButton"))

local e = React.createElement

local function SearchBox(props: {
	text: string,
	placeholder: string,
	onChange: (text: string) -> (),
	size: UDim2,
	position: UDim2?,
	anchorPoint: Vector2?,
})
	local skin = useSkin()
	local focused, setFocused = React.useState(false)
	return e("Frame", {
		Name = "Search",
		AnchorPoint = props.anchorPoint,
		Position = props.position,
		Size = props.size,
		BackgroundColor3 = Tokens.color.inputWell,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Stroke = e("UIStroke", { Color = Tokens.color.black, Thickness = skin.stroke(1) }),
		Icon = e(Icon, {
			name = "search",
			size = 20,
			transparency = 0.45,
			anchorPoint = Vector2.new(0, 0.5),
			position = UDim2.new(0, skin.px(14), 0.5, 0),
		}),
		Box = e("TextBox", {
			Position = UDim2.fromOffset(skin.px(40), 0),
			-- Leaves room on the right for the clear button.
			Size = UDim2.new(1, -skin.px(76), 1, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			Text = props.text,
			PlaceholderText = if focused then "" else props.placeholder,
			PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
			TextColor3 = Tokens.color.white,
			TextSize = skin.textPx(Tokens.type.search.size),
			FontFace = Tokens.font(Tokens.type.search.weight),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			[React.Change.Text] = function(box: TextBox)
				props.onChange(box.Text)
			end,
			[React.Event.Focused] = function()
				setFocused(true)
			end,
			[React.Event.FocusLost] = function()
				setFocused(false)
			end,
		}),
		-- Only there when there's something to clear.
		Clear = if props.text ~= ""
			then e(PillButton, {
				variant = "round",
				size = Tokens.size.small.size - 8,
				icon = "close",
				iconSize = Tokens.size.small.icon - 4,
				glowRadius = 0,
				sound = "back",
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.new(1, -skin.px(6), 0.5, 0),
				onActivated = function()
					props.onChange("")
				end,
			})
			else nil,
	})
end

return SearchBox
