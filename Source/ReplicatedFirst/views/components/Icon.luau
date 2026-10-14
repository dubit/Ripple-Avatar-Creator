--!strict

--[[
	Icon

	A Material Symbols Rounded glyph (one image per icon, IDs in SkinAssets),
	tinted with ImageColor3. `size` is the design's CSS font-size for the icon,
	in design px — each PNG is drawn so the glyph fills its box exactly the way
	the font does.

	An icon with no ID renders a clearly-marked placeholder (outlined box + the
	icon's initials) so missing art is obvious.

	Props:
		name: string            Material Symbols name, e.g. "shopping_basket"
		size: number            design px
		color: Color3?          default white
		transparency: number?
		zIndex: number?
		layoutOrder, position, anchorPoint
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local SkinAssets = require(views:WaitForChild("SkinAssets"))
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))

local e = React.createElement

export type Props = {
	name: string,
	size: number,
	color: Color3?,
	transparency: any?,
	zIndex: number?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
}

local function initials(name: string): string
	local letters = ""
	for word in string.gmatch(name, "[^_]+") do
		letters ..= string.upper(string.sub(word, 1, 1))
		if #letters >= 2 then
			break
		end
	end
	return letters
end

local function Icon(props: Props)
	local skin = useSkin()
	local px = skin.px(props.size)
	local color = props.color or Tokens.color.white
	local image = SkinAssets.iconImage(props.name)

	if image then
		return e("ImageLabel", {
			Name = "Icon_" .. props.name,
			Size = UDim2.fromOffset(px, px),
			Position = props.position,
			AnchorPoint = props.anchorPoint,
			LayoutOrder = props.layoutOrder or 0,
			ZIndex = props.zIndex,
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = color,
			ImageTransparency = props.transparency or 0,
			ScaleType = Enum.ScaleType.Fit,
		})
	end

	-- Placeholder: deliberately not pretty.
	return e("Frame", {
		Name = "IconPlaceholder_" .. props.name,
		Size = UDim2.fromOffset(px, px),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder or 0,
		ZIndex = props.zIndex,
		BackgroundTransparency = 1,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
		Stroke = e("UIStroke", {
			Color = color,
			Thickness = skin.stroke(1.5),
			Transparency = 0.3,
		}),
		Label = e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = initials(props.name),
			TextColor3 = color,
			TextSize = math.max(6, math.floor(px * 0.42)),
			FontFace = Tokens.font(800),
			ZIndex = props.zIndex,
		}),
	})
end

return Icon
