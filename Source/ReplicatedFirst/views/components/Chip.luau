--!strict

--[[
	Chip

	The design's outlined filter chips (Catalogue sub-categories, price
	presets). Active: faint orange fill, orange border, soft-orange text.
	Inactive: transparent with a faint white border. Hover lifts the border to
	orange. No press scale: a UIScale on a list item changes its AbsoluteSize
	and would nudge its neighbours (the design only presses round HUD buttons).

	Props:
		label: string
		active: boolean
		onActivated: () -> ()
		icon: string?
		layoutOrder: number?
		disabled: boolean?   dimmed and inert (e.g. a row the store already has)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useSpring = require(hooks:WaitForChild("useSpring"))
local useInteraction = require(hooks:WaitForChild("useInteraction"))
local useTextWidth = require(hooks:WaitForChild("useTextWidth"))
local Sounds = require(views:WaitForChild("Sounds"))
local Press = require(views:WaitForChild("Press"))
local Icon = require(script.Parent:WaitForChild("Icon"))

local e = React.createElement

export type Props = {
	label: string,
	active: boolean,
	onActivated: () -> (),
	icon: string?,
	layoutOrder: number?,
	disabled: boolean?,
}

local BORDER_IDLE = Color3.new(1, 1, 1)
local BORDER_ACCENT = Tokens.color.accent
local BORDER_HOVER = Tokens.color.accentText
local TEXT_IDLE = Color3.new(1, 1, 1)

local function Chip(props: Props)
	local skin = useSkin()
	local interaction = useInteraction(props.disabled)
	local hovered = interaction.hovered and not props.disabled

	local borderColor = if props.active then BORDER_ACCENT elseif hovered then BORDER_HOVER else BORDER_IDLE
	local borderTransparency = if props.active then 1 - 0.65
		elseif props.disabled then 1 - 0.06
		elseif hovered then 1 - 0.7
		else 1 - 0.14

	local spring = useSpring({
		fill = if props.active then 1 - 0.16 else 1,
		borderColor = borderColor,
		borderTransparency = borderTransparency,
		textColor = if props.active then Tokens.color.accentSoft else TEXT_IDLE,
		textTransparency = if props.active then 0 elseif props.disabled then 1 - 0.3 else 1 - 0.75,
	}, Tokens.spring.state)

	local style = Tokens.type.chip
	local textSize = skin.textPx(style.size)
	local font = Tokens.font(style.weight)
	local height = skin.px(Tokens.size.chipHeight)
	-- Explicit width, not AutomaticSize (mis-sizes under the canvas UIScale).
	local textWidth = useTextWidth(props.label, font, textSize)
	local padding = skin.px(16)
	local gap = skin.px(6)
	local iconSize = skin.px(18)
	local width = padding * 2 + textWidth + (if props.icon then iconSize + gap else 0)

	local function onPress()
		if props.disabled then
			return
		end
		Sounds.play("tab")
		props.onActivated()
	end

	return e("TextButton", {
		Name = "Chip",
		Size = UDim2.fromOffset(width, height),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundColor3 = Tokens.color.accent,
		BackgroundTransparency = spring.fill,
		AutoButtonColor = false,
		Text = "",
		[React.Event.InputBegan] = Press.began(onPress),
		[React.Event.Activated] = Press.activated(onPress),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Border = e("UIStroke", {
			Color = spring.borderColor,
			Transparency = spring.borderTransparency,
			Thickness = skin.stroke(1),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, padding),
			PaddingRight = UDim.new(0, padding),
		}),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap),
		}),
		Icon = if props.icon
			then e(Icon, {
				name = props.icon,
				size = 18,
				color = Tokens.color.accentSoft,
				layoutOrder = 1,
			})
			else nil,
		Label = e("TextLabel", {
			Size = UDim2.fromOffset(textWidth, height),
			BackgroundTransparency = 1,
			Text = props.label,
			TextColor3 = spring.textColor,
			TextTransparency = spring.textTransparency,
			TextSize = textSize,
			FontFace = font,
			LayoutOrder = 2,
		}),
	})
end

return Chip
