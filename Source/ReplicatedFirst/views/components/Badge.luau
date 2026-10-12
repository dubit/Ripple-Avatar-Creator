--!strict

--[[
	Badge

	The design's small status badges.

	  kind "count"   pill with optional icon + text — the Basket's Robux total
	                 (orange, text "₹225")
	  kind "marker"  24px circle with an icon — "Wearing" (orange, "checkroom")
	                 and "In basket" (white, "shopping_basket")

	tone "orange" uses the glossy orange gradient with the dark-orange border;
	tone "white" uses the white badge gradient with a dark icon.

	A count without an icon is padded evenly and never narrower than it is
	tall, so a single digit sits centred in a circle.

	Props:
		kind: "count" | "marker"
		tone: "orange" | "white"
		icon: string?
		text: string?
		layoutOrder, position, anchorPoint, zIndex
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local useTextWidth = require(views:WaitForChild("hooks"):WaitForChild("useTextWidth"))
local Icon = require(script.Parent:WaitForChild("Icon"))

local e = React.createElement

export type Props = {
	kind: "count" | "marker",
	tone: "orange" | "white",
	icon: string?,
	text: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	zIndex: number?,
}

local function Badge(props: Props)
	local skin = useSkin()
	local z = props.zIndex or 1
	local isOrange = props.tone == "orange"
	local contentColor = if isOrange then Tokens.color.white else Tokens.color.iconDark
	local isMarker = props.kind == "marker"
	local height = skin.px(if isMarker then Tokens.size.markerBadge else Tokens.size.badgeHeight)
	local textSize = skin.textPx(Tokens.type.badge.size)
	local font = Tokens.font(Tokens.type.badge.weight)
	-- Explicit width, not AutomaticSize (mis-sizes under the canvas UIScale).
	local textWidth = useTextWidth(props.text or "", font, textSize)
	local iconSize = skin.px(if isMarker then 15 else 17)
	local gap = skin.px(2)
	-- With an icon the design pads 5 left / 9 right; text alone pads evenly.
	local padLeft = skin.px(if props.icon then 5 else 7)
	local padRight = skin.px(if props.icon then 9 else 7)
	local countWidth = math.max(height, padLeft + (if props.icon then iconSize + gap else 0) + textWidth + padRight)

	local children: { [string]: any } = {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Gradient = e("UIGradient", {
			Color = if isOrange then Tokens.gradient.orange else Tokens.gradient.whiteBadge,
			Rotation = Tokens.gradient.rotation,
		}),
		Border = e("UIStroke", {
			Color = if isOrange then Tokens.color.borderOrange else Tokens.color.black,
			Thickness = skin.stroke(1),
			Transparency = if isOrange then 0 else 0.6,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(2)),
		}),
	}

	if props.icon then
		children.Icon = e(Icon, {
			name = props.icon,
			size = if isMarker then 15 else 17,
			color = contentColor,
			layoutOrder = 1,
			zIndex = z + 1,
		})
	end

	if props.text and not isMarker then
		children.Label = e("TextLabel", {
			Size = UDim2.fromOffset(textWidth, height),
			BackgroundTransparency = 1,
			Text = props.text,
			TextColor3 = contentColor,
			TextSize = textSize,
			FontFace = font,
			LayoutOrder = 2,
			ZIndex = z + 1,
		})
		children.Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, padLeft),
			PaddingRight = UDim.new(0, padRight),
		})
	end

	return e("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(if isMarker then height else countWidth, height),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder or 0,
		BackgroundColor3 = Tokens.color.white,
		BorderSizePixel = 0,
		ZIndex = z,
	}, children)
end

return Badge
