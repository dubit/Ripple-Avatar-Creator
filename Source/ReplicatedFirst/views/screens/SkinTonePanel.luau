--!strict

--[[
	SkinTonePanel (Catalogue › Body › Skin tone)

	Colour your body part by part. On the left, a figure of the six parts in
	the colours you're wearing (your own where you haven't chosen one): tap
	parts to select them (all are selected to start), or use All parts.
	On the right, the palette (AvatarConfig.skinTones: Roblox's avatar
	editor colours) between "Your own" and Custom: picking one colours the
	selected parts at once ("Your own" puts back your Roblox avatar's colour,
	re-read when the panel opens). A swatch has the orange ring when every
	selected part wears it. Custom opens a colour editor (hue, saturation,
	brightness, or a hex code) with Apply. Changes are undoable; outfits save
	them.

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
local Slider = require(views:WaitForChild("components"):WaitForChild("Slider"))
local useBackInput = require(views:WaitForChild("hooks"):WaitForChild("useBackInput"))

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))

local e = React.createElement

local SWATCH = 64 -- design px
local LEFT = 230 -- design px: the figure's column

local function Swatch(props: {
	colour: Color3?, -- nil = "your own" (or Custom, with `icon`)
	icon: string?, -- drawn on a colourless swatch
	selected: boolean,
	onPick: () -> (),
	layoutOrder: number,
})
	local skin = useSkin()
	local interaction = useInteraction()
	local size = skin.px(SWATCH)
	return e("TextButton", {
		Name = "Swatch",
		Size = UDim2.fromOffset(size, size),
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
					name = props.icon or "restart_alt",
					size = 26,
					transparency = 0.2,
					anchorPoint = Vector2.new(0.5, 0.5),
					position = UDim2.fromScale(0.5, 0.5),
				})
				else nil,
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

local function hexOf(h: number, sat: number, v: number): string
	return "#" .. string.upper(Color3.fromHSV(h / 360, sat / 100, v / 100):ToHex())
end

-- Any colour: hue, saturation and brightness sliders, or a hex code; a big
-- preview; Apply colours the selected parts; Cancel (or Back) returns to the
-- palette without changing anything. Each slider's track shows what moving along it
-- does to the colour (no orange fill: it's a quality, not an amount), and
-- its knob shows the current colour.
local function CustomColour(props: {
	start: string,
	parts: number,
	onApply: (hex: string) -> (),
	onClose: () -> (),
	position: UDim2,
	size: UDim2,
})
	local skin = useSkin()
	local hsv, setHsv = React.useState(function()
		local h, sat, v = Color3.fromHex(props.start):ToHSV()
		return { h = math.floor(h * 360 + 0.5), s = math.floor(sat * 100 + 0.5), v = math.floor(v * 100 + 0.5) }
	end)
	local hex = hexOf(hsv.h, hsv.s, hsv.v)
	local current = Color3.fromHex(hex)
	useBackInput(function()
		props.onClose()
		return true
	end)
	-- What each track shows.
	local hueStops = {}
	for i = 0, 6 do
		table.insert(hueStops, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i % 6) / 6, 1, 1)))
	end
	local tracks = {
		h = ColorSequence.new(hueStops),
		s = ColorSequence.new(Color3.fromHSV(hsv.h / 360, 0, hsv.v / 100), Color3.fromHSV(hsv.h / 360, 1, hsv.v / 100)),
		v = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(hsv.h / 360, hsv.s / 100, 1)),
	}
	local function slider(label: string, key: string, max: number, order: number)
		return e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(52)),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, {
			Label = e(ShadowText, {
				text = label .. "  " .. hsv[key],
				style = Tokens.type.meta,
				transparency = Tokens.alpha.textSoft,
				shadow = false,
			}),
			Track = e("Frame", {
				Position = UDim2.fromOffset(0, skin.px(22)),
				Size = UDim2.new(1, 0, 0, skin.px(30)),
				BackgroundTransparency = 1,
			}, {
				Slider = e(Slider, {
					value = hsv[key],
					min = 0,
					max = max,
					step = 1,
					trackColours = tracks[key],
					knobColour = current,
					onChange = function(value: number)
						setHsv(function(current)
							local next = table.clone(current)
							next[key] = value
							return next
						end)
					end,
					onCommit = function() end,
				}),
			}),
		})
	end
	local preview = skin.px(120)
	local top = skin.px(14) -- clear of the chips above
	return e("Frame", {
		Name = "CustomColour",
		Position = props.position,
		Size = props.size,
		BackgroundTransparency = 1,
	}, {
		Preview = e("Frame", {
			Position = UDim2.fromOffset(0, top),
			Size = UDim2.fromOffset(preview, preview),
			BackgroundColor3 = Color3.fromHex(hex),
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Ring = e("UIStroke", { Color = Tokens.color.white, Transparency = 0.7, Thickness = skin.stroke(1.5) }),
		}),
		Controls = e("Frame", {
			Position = UDim2.fromOffset(preview + skin.px(24), top),
			Size = UDim2.new(1, -(preview + skin.px(24)), 1, -top),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(10)) }),
			-- A little room between the colour code and the buttons.
			Gap = e("Frame", { Size = UDim2.new(1, 0, 0, skin.px(8)), BackgroundTransparency = 1, LayoutOrder = 5 }),
			Hue = slider("Hue", "h", 360, 1),
			Saturation = slider("Saturation", "s", 100, 2),
			Brightness = slider("Brightness", "v", 100, 3),
			Hex = e("Frame", {
				Size = UDim2.new(1, 0, 0, skin.px(40)),
				BackgroundTransparency = 1,
				LayoutOrder = 4,
			}, {
				Well = e("Frame", {
					Size = UDim2.new(0, skin.px(150), 1, 0),
					BackgroundColor3 = Tokens.color.inputWell,
					BorderSizePixel = 0,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
					Box = e("TextBox", {
						Position = UDim2.fromOffset(skin.px(14), 0),
						Size = UDim2.new(1, -skin.px(28), 1, 0),
						BackgroundTransparency = 1,
						ClearTextOnFocus = false,
						Text = hex,
						TextColor3 = Tokens.color.white,
						TextSize = skin.textPx(Tokens.type.search.size),
						FontFace = Tokens.font(800),
						TextXAlignment = Enum.TextXAlignment.Left,
						[React.Event.FocusLost] = function(box: TextBox)
							local text = string.match(box.Text, "^%s*#?(%x%x%x%x%x%x)%s*$")
							if text then
								local h, sat, v = Color3.fromHex("#" .. text):ToHSV()
								setHsv({ h = math.floor(h * 360 + 0.5), s = math.floor(sat * 100 + 0.5), v = math.floor(v * 100 + 0.5) })
							else
								box.Text = hex
							end
						end,
					}),
				}),
				Name = e("Frame", {
					Position = UDim2.fromOffset(skin.px(164), skin.px(11)),
					Size = UDim2.new(1, -skin.px(164), 0, skin.px(18)),
					BackgroundTransparency = 1,
				}, {
					Text = e(ShadowText, {
						text = "Near " .. SkinColours.name(hex),
						style = Tokens.type.meta,
						transparency = Tokens.alpha.textSoft,
						shadow = false,
					}),
				}),
			}),
			Buttons = e("Frame", {
				Size = UDim2.new(1, 0, 0, skin.px(Tokens.size.ctaHeight)),
				BackgroundTransparency = 1,
				LayoutOrder = 6,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(8)),
				}),
				Apply = e(PillButton, {
					variant = "pill",
					size = Tokens.size.ctaHeight,
					width = 220,
					icon = "check",
					iconSize = 18,
					label = if props.parts == 0 then "Pick parts first" else "Apply to " .. props.parts .. " part" .. (if props.parts == 1 then "" else "s"),
					active = props.parts > 0,
					disabled = props.parts == 0,
					sound = false, -- the change plays its own sound
					layoutOrder = 1,
					onActivated = function()
						props.onApply(hex)
					end,
				}),
				Cancel = e(PillButton, {
					variant = "pill",
					size = Tokens.size.ctaHeight,
					width = 150,
					label = "Cancel",
					sound = "back",
					layoutOrder = 2,
					onActivated = props.onClose,
				}),
			}),
		}),
	})
end

local function SkinTonePanel(props: { look: any, size: UDim2, position: UDim2 })
	local skin = useSkin()
	local chosen = SkinColours.normalise(props.look.skin)
	local own = SkinColours.normalise(props.look.ownSkin)
	local selected, setSelected = React.useState(allParts)
	local custom, setCustom = React.useState(false)
	-- Your own colours: re-read your Roblox avatar, which may have changed
	-- since you joined.
	React.useEffect(function()
		props.look.refreshOwn()
		return nil
	end, {})

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
			CellSize = UDim2.fromOffset(skin.px(SWATCH), skin.px(SWATCH)),
			CellPadding = UDim2.fromOffset(skin.px(14), skin.px(14)),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(6)),
			PaddingLeft = UDim.new(0, skin.px(6)),
		}),
		Own = e(Swatch, {
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
			colour = Color3.fromHex(hex),
			selected = allWear(hex),
			layoutOrder = index,
			onPick = function()
				apply(hex)
			end,
		})
	end

	-- Custom: selected unless every selected part wears a palette colour.
	local inPalette: { [string]: boolean } = {}
	for _, tone in AvatarConfig.skinTones do
		inPalette[string.upper(tone.hex)] = true
	end
	local customWorn = count > 0
	for _, part in SkinColours.PARTS do
		if selected[part] and (chosen[part] == nil or inPalette[chosen[part]]) then
			customWorn = false
		end
	end
	swatches.Custom = e(Swatch, {
		colour = nil,
		icon = "edit",
		selected = customWorn,
		layoutOrder = #AvatarConfig.skinTones + 1,
		onPick = function()
			setCustom(true)
		end,
	})

	local left = skin.px(LEFT)
	local everything = count == #SkinColours.PARTS
	-- The custom editor starts from the first selected part's colour.
	local startHex = "#AF9483"
	for _, part in SkinColours.PARTS do
		if selected[part] and shown[part] then
			startHex = shown[part]
			break
		end
	end
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
		Custom = if custom
			then e(CustomColour, {
				start = startHex,
				parts = count,
				position = UDim2.fromOffset(left + skin.px(20), 0),
				size = UDim2.new(1, -(left + skin.px(20)), 1, 0),
				onApply = function(hex: string)
					apply(hex)
				end,
				onClose = function()
					setCustom(false)
				end,
			})
			else nil,
		Palette = if custom then nil else e("ScrollingFrame", {
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
