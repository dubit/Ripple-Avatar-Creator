--!strict

--[[
	SkinTonePanel (Catalogue › Body › Skin tone)

	A palette of skin tones (AvatarConfig.skinTones) after "Your own" (the
	tone of the player's own Roblox avatar, i.e. no override). The tone being
	worn has the orange ring. Picking one puts it on at once (undoable, like
	any change; outfits save it).

	Props:
		look: the HUD look (skin, setSkin)
		size, position
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local useInteraction = require(views:WaitForChild("hooks"):WaitForChild("useInteraction"))
local Icon = require(views:WaitForChild("components"):WaitForChild("Icon"))

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))

local e = React.createElement

local SWATCH = 76 -- design px

local function Swatch(props: {
	name: string,
	colour: Color3?, -- nil = "your own"
	selected: boolean,
	onPick: () -> (),
	layoutOrder: number,
})
	local skin = useSkin()
	local interaction = useInteraction()
	local size = skin.px(SWATCH)
	return e("TextButton", {
		Name = "Swatch",
		Size = UDim2.fromOffset(size, size + skin.px(22)),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(props.onPick),
		[React.Event.Activated] = Press.activated(props.onPick),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Chip = e("Frame", {
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = props.colour or Color3.fromHex("#2a2a2a"),
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Ring = e("UIStroke", {
				Color = if props.selected or interaction.hovered then Tokens.color.accentText else Tokens.color.white,
				Transparency = if props.selected then 0 elseif interaction.hovered then 0.3 else 0.85,
				Thickness = skin.stroke(if props.selected then 3 else 1.5),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			Own = if props.colour == nil
				then e(Icon, {
					name = "restart_alt",
					size = 30,
					transparency = 0.2,
					anchorPoint = Vector2.new(0.5, 0.5),
					position = UDim2.fromScale(0.5, 0.5),
				})
				else nil,
		}),
		Label = e("TextLabel", {
			Position = UDim2.fromOffset(0, size + skin.px(4)),
			Size = UDim2.new(1, 0, 0, skin.px(16)),
			BackgroundTransparency = 1,
			Text = props.name,
			TextColor3 = Tokens.color.white,
			TextTransparency = if props.selected then 0 else Tokens.alpha.textSoft,
			TextSize = skin.textPx(11.5),
			FontFace = Tokens.font(800),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function SkinTonePanel(props: { look: any, size: UDim2, position: UDim2 })
	local skin = useSkin()
	local current = string.upper(props.look.skin or "")
	local swatches: { [string]: any } = {
		Layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(skin.px(SWATCH), skin.px(SWATCH + 22)),
			CellPadding = UDim2.fromOffset(skin.px(18), skin.px(14)),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(6)),
			PaddingLeft = UDim.new(0, skin.px(6)),
		}),
		Own = e(Swatch, {
			name = "Your own",
			colour = nil,
			selected = current == "",
			layoutOrder = 0,
			onPick = function()
				props.look.setSkin("")
			end,
		}),
	}
	for index, tone in AvatarConfig.skinTones do
		local hex = string.upper(tone.hex)
		swatches["Tone" .. index] = e(Swatch, {
			name = tone.name,
			colour = Color3.fromHex(hex),
			selected = current == hex,
			layoutOrder = index,
			onPick = function()
				props.look.setSkin(hex)
			end,
		})
	end
	return e("ScrollingFrame", {
		Name = "SkinTonePanel",
		Position = props.position,
		Size = props.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = skin.px(8),
		ScrollBarImageColor3 = Tokens.color.accent,
	}, swatches)
end

return SkinTonePanel
