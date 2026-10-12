--!strict

--[[
	BodyFigure

	A blocky figure of the six body parts (head, torso, arms, legs), each
	filled with its colour. Used by the Skin tone picker (tap parts to
	select them; selected parts get the orange ring) and the skin tone detail
	page (read-only).

	The figure's left arm is on the viewer's right, as if facing you.

	Props:
		colours: { [part]: "#RRGGBB" }   what each part shows (SkinColours parts)
		selected: { [part]: boolean }?   ringed parts
		onPart: ((part) -> ())?          makes parts tappable
		scale: number?                   1 = 180 design px tall
		layoutOrder, position, anchorPoint
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))

local e = React.createElement

-- Design px at scale 1: x, y, width, height.
local LAYOUT = {
	Head = { 62, 0, 44, 44 },
	Torso = { 40, 48, 88, 88 },
	RightArm = { 0, 48, 36, 88 }, -- the figure's right: the viewer's left
	LeftArm = { 132, 48, 36, 88 },
	RightLeg = { 40, 140, 42, 88 },
	LeftLeg = { 86, 140, 42, 88 },
}
local WIDTH, HEIGHT = 168, 228

local function BodyFigure(props: {
	colours: { [string]: string },
	selected: { [string]: boolean }?,
	onPart: ((part: string) -> ())?,
	scale: number?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
})
	local skin = useSkin()
	local scale = props.scale or 1
	local function px(n: number): number
		return skin.px(n * scale)
	end
	local parts: { [string]: any } = {}
	for part, box in LAYOUT do
		local hex = props.colours[part]
		local on = props.selected ~= nil and props.selected[part] == true
		local onPart = props.onPart
		local function press()
			if onPart then
				onPart(part)
			end
		end
		parts[part] = e(if onPart then "TextButton" else "Frame", {
			Position = UDim2.fromOffset(px(box[1]), px(box[2])),
			Size = UDim2.fromOffset(px(box[3]), px(box[4])),
			BackgroundColor3 = if hex then Color3.fromHex(hex) else Color3.fromHex("#2a2a2a"),
			BorderSizePixel = 0,
			Text = if onPart then "" else nil,
			AutoButtonColor = if onPart then false else nil,
			[React.Event.InputBegan] = if onPart then Press.began(press) else nil,
			[React.Event.Activated] = if onPart then Press.activated(press) else nil,
		} :: any, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, px(if part == "Head" then 12 else 8)) }),
			Ring = e("UIStroke", {
				Color = if on then Tokens.color.accentText else Tokens.color.black,
				Transparency = if on then 0 else 0.5,
				Thickness = skin.stroke(if on then 3 else 1),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end
	return e("Frame", {
		Name = "BodyFigure",
		Size = UDim2.fromOffset(px(WIDTH), px(HEIGHT)),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
	}, parts)
end

return BodyFigure
