--!strict

--[[
	SkinToneScreen (a deeper page: the skin colours that come with an outfit
	or someone's look; opened from its Skin tone row)

	The figure in those colours (a part they don't set shows your own), and
	a row per body part: its swatch, Roblox's name for the colour and the
	hex. Wear these colours puts them on (parts they don't set go back to
	your own), undoable.

	Props: nav, look, colours ({ [part]: "#RRGGBB" }), from (whose: shown under
	the title)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local ShadowText = require(views:WaitForChild("components"):WaitForChild("ShadowText"))
local PillButton = require(views:WaitForChild("components"):WaitForChild("PillButton"))
local BodyFigure = require(views:WaitForChild("components"):WaitForChild("BodyFigure"))
local Parts = require(script.Parent:WaitForChild("Parts"))

local e = React.createElement

local LEFT = 300

local function SkinToneScreen(props: { nav: any, look: any, colours: any, from: string })
	local skin = useSkin()
	local colours = SkinColours.normalise(props.colours)
	local own = SkinColours.normalise(props.look.ownSkin)
	local wearing = SkinColours.normalise(props.look.skin)
	local shown: { [string]: string } = {}
	for _, part in SkinColours.PARTS do
		shown[part] = colours[part] or own[part]
	end

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(6)) }),
		Inset = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(3)),
			PaddingLeft = UDim.new(0, skin.px(3)),
			PaddingRight = UDim.new(0, skin.px(8)),
		}),
	}
	for index, part in SkinColours.PARTS do
		local hex = colours[part]
		rows[part] = e(Parts.ListRow, {
			title = SkinColours.label[part],
			subtitle = if hex then SkinColours.name(hex) .. " · " .. hex else "Not set: you'd keep your own",
			colour = Color3.fromHex(shown[part] or "#2a2a2a"),
			flat = true,
			layoutOrder = index,
			trailingWidth = 80,
			trailing = {
				Same = if hex and wearing[part] == hex
					then e(ShadowText, { text = "Wearing", style = Tokens.type.small, color = Tokens.color.accentText, shadow = false })
					else nil,
			},
		})
	end

	local left = skin.px(LEFT)
	return e("Frame", {
		Name = "SkinToneScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Left = e("Frame", {
			Size = UDim2.new(0, left, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(12)),
			}),
			Title = e(ShadowText, { text = "Skin tone", style = { size = 24, weight = 900 }, layoutOrder = 1 }),
			From = e(ShadowText, {
				text = props.from,
				style = Tokens.type.meta,
				transparency = Tokens.alpha.textSoft,
				shadow = false,
				layoutOrder = 2,
			}),
			Figure = e("Frame", {
				Size = UDim2.new(1, 0, 0, skin.px(250)),
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, {
				Body = e(BodyFigure, {
					colours = shown,
					scale = 1.05,
					anchorPoint = Vector2.new(0.5, 0),
					position = UDim2.fromScale(0.5, 0),
				}),
			}),
			Wear = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				icon = "checkroom",
				iconSize = 18,
				label = "Wear these colours",
				active = true,
				disabled = SkinColours.equal(colours, wearing),
				sound = false, -- the change plays its own sound
				layoutOrder = 4,
				onActivated = function()
					props.look.setSkin(colours)
				end,
			}),
		}),
		Rows = e("ScrollingFrame", {
			Position = UDim2.fromOffset(left + skin.px(20), 0),
			Size = UDim2.new(1, -(left + skin.px(20)), 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, #SkinColours.PARTS * (skin.px(64) + skin.px(6)) + skin.px(6)),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = skin.px(8),
			ScrollBarImageColor3 = Tokens.color.accent,
		}, rows),
	})
end

return SkinToneScreen
