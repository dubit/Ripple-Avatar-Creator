--!strict

--[[
	SkinTonePanel (Catalogue › Body › Skin tone)

	Colour your body part by part. On the left, a figure of the six parts in
	the colours you're wearing (your own where you haven't chosen one): tap
	parts to select them (all are selected to start), or use All parts.
	On the right, the palette (AvatarConfig.skinTones) after "Your own":
	picking one colours the selected parts at once ("Your own" puts their
	own colour back). A swatch has the orange ring when every selected part
	wears it. Changes are undoable; outfits save them.

	Props:
		look: the HUD look (skin, ownSkin, setSkin)
		size, position
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local useInteraction = require(views:WaitForChild("hooks"):WaitForChild("useInteraction"))
local Icon = require(views:WaitForChild("components"):WaitForChild("Icon"))
local ShadowText = require(views:WaitForChild("components"):WaitForChild("ShadowText"))
local PillButton = require(views:WaitForChild("components"):WaitForChild("PillButton"))
local BodyFigure = require(views:WaitForChild("components"):WaitForChild("BodyFigure"))

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))

local e = React.createElement

local SWATCH = 64 -- design px
local LEFT = 230 -- design px: the figure's column

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
					size = 26,
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
			TextSize = skin.textPx(11),
			FontFace = Tokens.font(800),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function allParts(): { [string]: boolean }
	local set = {}
	for _, part in SkinColours.PARTS do
		set[part] = true
	end
	return set
end

local function SkinTonePanel(props: { look: any, size: UDim2, position: UDim2 })
	local skin = useSkin()
	local chosen = SkinColours.normalise(props.look.skin)
	local own = SkinColours.normalise(props.look.ownSkin)
	local selected, setSelected = React.useState(allParts)

	-- What each part shows: the chosen colour, else your own.
	local shown: { [string]: string } = {}
	for _, part in SkinColours.PARTS do
		shown[part] = chosen[part] or own[part]
	end
	local count = 0
	for _, part in SkinColours.PARTS do
		if selected[part] then
			count += 1
		end
	end

	-- Every selected part has this choice ("" = your own).
	local function allWear(hex: string): boolean
		if count == 0 then
			return false
		end
		for _, part in SkinColours.PARTS do
			if selected[part] and (chosen[part] or "") ~= hex then
				return false
			end
		end
		return true
	end
	local function apply(hex: string)
		local next: SkinColours.Colours = table.clone(chosen)
		for _, part in SkinColours.PARTS do
			if selected[part] then
				next[part] = if hex == "" then nil else hex
			end
		end
		props.look.setSkin(next)
	end

	local swatches: { [string]: any } = {
		Layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(skin.px(SWATCH), skin.px(SWATCH + 22)),
			CellPadding = UDim2.fromOffset(skin.px(16), skin.px(12)),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(6)),
			PaddingLeft = UDim.new(0, skin.px(6)),
		}),
		Own = e(Swatch, {
			name = "Your own",
			colour = nil,
			selected = allWear(""),
			layoutOrder = 0,
			onPick = function()
				apply("")
			end,
		}),
	}
	for index, tone in AvatarConfig.skinTones do
		local hex = string.upper(tone.hex)
		swatches["Tone" .. index] = e(Swatch, {
			name = tone.name,
			colour = Color3.fromHex(hex),
			selected = allWear(hex),
			layoutOrder = index,
			onPick = function()
				apply(hex)
			end,
		})
	end

	local left = skin.px(LEFT)
	local everything = count == #SkinColours.PARTS
	return e("Frame", {
		Name = "SkinTonePanel",
		Position = props.position,
		Size = props.size,
		BackgroundTransparency = 1,
	}, {
		Figure = e("Frame", {
			Size = UDim2.new(0, left, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, skin.px(12)),
			}),
			Padding = e("UIPadding", { PaddingTop = UDim.new(0, skin.px(6)) }),
			Hint = e(ShadowText, {
				text = if count == 0 then "Tap parts to colour them"
					elseif everything then "Colouring every part"
					else "Colouring " .. count .. " part" .. (if count == 1 then "" else "s"),
				style = Tokens.type.meta,
				transparency = Tokens.alpha.textSoft,
				shadow = false,
				layoutOrder = 1,
			}),
			Body = e(BodyFigure, {
				colours = shown,
				selected = selected,
				layoutOrder = 2,
				onPart = function(part: string)
					setSelected(function(current: { [string]: boolean })
						local next = table.clone(current)
						next[part] = if next[part] then nil else true
						return next
					end)
				end,
			}),
			All = e(PillButton, {
				variant = "pill",
				size = 36,
				width = 160,
				label = if everything then "Select none" else "All parts",
				textStyle = Tokens.type.small,
				layoutOrder = 3,
				onActivated = function()
					setSelected(if everything then {} else allParts())
				end,
			}),
		}),
		Palette = e("ScrollingFrame", {
			Position = UDim2.fromOffset(left + skin.px(20), 0),
			Size = UDim2.new(1, -(left + skin.px(20)), 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = skin.px(8),
			ScrollBarImageColor3 = Tokens.color.accent,
		}, swatches),
	})
end

return SkinTonePanel
