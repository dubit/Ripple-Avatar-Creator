--!strict

--[[
	WorldOptionsView (design: World options side panel)

	Three sections under tabs (WorldOptionsSections): Sky (time of day, sky
	preset, lighting and shadows, the flight hint), Floor (floor colour,
	pattern colour, pattern and its strength) and Music (the music player,
	MusicPanel). The open one is kept for the session, and Reset resets only
	it. Controls apply instantly (`onChange` — the world renders
	from the draft) and save once per gesture (`onCommit` — on slider release
	or tap), so dragging never floods the server.

	Translucent glass, not blurred: the player needs to see the world change
	behind it.

	Props:
		options: Network.WorldOptionsState   current (saved + draft) values
		config: WorldOptionsConfig
		onChange: (changes: { [string]: any }) -> ()
		onCommit: (changes: { [string]: any }) -> ()
		onReset: (section: string) -> ()   the open section back to its defaults
		music: useMusic result?   the music player (Music section)
		onClose: () -> ()
		t: binding?   slide progress (0 off the right edge → 1 in place)
		inset: number?   design px from the right edge (default edgeInset)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local Sounds = require(views:WaitForChild("Sounds"))
local Press = require(views:WaitForChild("Press"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local PillButton = require(components:WaitForChild("PillButton"))
local GlassPanel = require(components:WaitForChild("GlassPanel"))
local Icon = require(components:WaitForChild("Icon"))
local ShadowText = require(components:WaitForChild("ShadowText"))
local Slider = require(components:WaitForChild("Slider"))
local Toggle = require(components:WaitForChild("Toggle"))
local SkinAssets = require(views:WaitForChild("SkinAssets"))
local PillTabs = require(components:WaitForChild("PillTabs"))
local MusicPanel = require(views:WaitForChild("MusicPanel"))
local useSessionState = require(hooks:WaitForChild("useSessionState"))

local e = React.createElement

export type Props = {
	options: any,
	config: any,
	onChange: (changes: { [string]: any }) -> (),
	onCommit: (changes: { [string]: any }) -> (),
	onReset: (section: string) -> (),
	onClose: () -> (),
	t: any?,
	inset: number?,
	music: any?,
}

local TABS = {
	{ id = "sky", label = "Sky", icon = "wb_sunny" },
	{ id = "floor", label = "Floor", icon = "grid_on" },
	{ id = "music", label = "Music", icon = "music_note" },
}
local TABS_HEIGHT = 40

-- Colour swatches (design px): six across the scrolling body's width.
local SWATCH = 36
local SWATCH_GAP = 6

-- Pattern preview tiles (design px): three across the ~295px scrolling body,
-- wrapping onto more rows.
local PATTERN_TILE = { width = 92, height = 48, caption = 17, gap = 8 }
-- Preview texture tile size per pattern, so each shows a recognisable patch.
local PATTERN_PREVIEW_TILE: { [string]: number } = {
	Grid = 48,
	Studs = 24,
	Checker = 32,
	Clouds = 96,
	Grass = 48,
	Water = 64,
}

local function label(text: string, style: Tokens.TypeStyle, order: number, color: Color3?, transparency: number?)
	return e(ShadowText, {
		text = text,
		style = style,
		color = color,
		transparency = transparency,
		shadow = false,
		layoutOrder = order,
	})
end

local function row(skin, order: number, height: number, gap: number, children: { [string]: any })
	children.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, skin.px(gap)),
	})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(height)),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, children)
end

-- The pattern tiles, three to a row.
local function patternGrid(skin, order: number, count: number, children: { [string]: any })
	local cellHeight = PATTERN_TILE.height + PATTERN_TILE.caption
	local rows = math.ceil(count / 3)
	children.Layout = e("UIGridLayout", {
		CellSize = UDim2.fromOffset(skin.px(PATTERN_TILE.width), skin.px(cellHeight)),
		CellPadding = UDim2.fromOffset(skin.px(PATTERN_TILE.gap), skin.px(PATTERN_TILE.gap)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(rows * cellHeight + (rows - 1) * PATTERN_TILE.gap)),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, children)
end

-- "Label ............ value" header line above a slider.
local function valueHeader(skin, text: string, value: string, order: number)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(20)),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		Label = label(text, Tokens.type.sectionLabel, 1),
		Value = e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = value,
			TextColor3 = Tokens.color.accentText,
			TextSize = skin.textPx(Tokens.type.sectionLabel.size),
			FontFace = Tokens.font(800),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
	})
end

local function formatTime(t: number): string
	local hours = math.floor(t) % 24
	local minutes = math.floor((t % 1) * 60 + 0.5)
	return string.format("%02d:%02d", hours, minutes)
end

local function WorldOptionsView(props: Props)
	local skin = useSkin()
	local options = props.options
	local config = props.config
	local section, setSection = useSessionState("world.section", "sky")

	-- Height of the scrolling content in local units (for the canvas size).
	local layoutRef = React.useRef(nil :: UIListLayout?)
	local contentHeight, setContentHeight = React.useState(0)
	React.useEffect(function()
		local layout = layoutRef.current
		if not layout then
			return
		end
		local function update()
			setContentHeight(skin.fromScreen(layout.AbsoluteContentSize.Y))
		end
		update()
		local connection = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
		return function()
			connection:Disconnect()
		end
	end, { skin.scale, section } :: { any })

	-- Taps change and save in one go.
	local function choose(changes: { [string]: any })
		Sounds.play("tab")
		props.onChange(changes)
		props.onCommit(changes)
	end

	local skyButtons: { [string]: any } = {}
	for index, name in config.skies do
		skyButtons[name] = e(PillButton, {
			variant = "pill",
			size = 36,
			width = 68,
			label = name,
			textStyle = Tokens.type.small,
			active = options.sky == name,
			sound = false,
			layoutOrder = index,
			onActivated = function()
				choose({ sky = name })
			end,
		})
	end

	-- A row of round colour swatches saving the chosen hex under `key`; picking
	-- a colour also takes its lightness (`lightnessKey`) back up to full.
	local function swatches(colors: { string }, key: string, lightnessKey: string): { [string]: any }
		local row: { [string]: any } = {}
		for index, hex in colors do
			local selected = options[key] == hex
			local function pick()
				choose({ [key] = hex, [lightnessKey] = config.lightnessMax })
			end
			row["Swatch" .. index] = e("TextButton", {
				Size = UDim2.fromOffset(skin.px(SWATCH), skin.px(SWATCH)),
				BackgroundColor3 = Color3.fromHex(hex),
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
				[React.Event.InputBegan] = Press.began(pick),
				[React.Event.Activated] = Press.activated(pick),
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				-- Inferred: CSS double ring `0 0 0 2px #111, 0 0 0 4px #ffa64d` → one accent stroke.
				-- Border mode: on a button a UIStroke otherwise outlines the (empty) text.
				Ring = e("UIStroke", {
					Color = if selected then Tokens.color.accentText else Tokens.color.black,
					Thickness = skin.stroke(if selected then 3 else 1),
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			})
		end
		return row
	end

	-- Pattern picker: a live preview tile per pattern — the texture tiled over
	-- the current floor colour, in the pattern colour at the pattern strength.
	local picked = Color3.fromHex(options.floor)
	local lightness = math.clamp(options.floorLightness / 100, 0, 1)
	local floorColour = Color3.new(picked.R * lightness, picked.G * lightness, picked.B * lightness)
	local patternPicked = Color3.fromHex(options.patternColor)
	local patternLightness = math.clamp(options.patternLightness / 100, 0, 1)
	local patternColour = Color3.new(
		patternPicked.R * patternLightness,
		patternPicked.G * patternLightness,
		patternPicked.B * patternLightness
	)
	local patternTiles: { [string]: any } = {}
	for index, name in config.patterns do
		local selected = options.pattern == name
		local id = SkinAssets.floorTextures[name]
		local function pick()
			choose({ pattern = name })
		end
		patternTiles[name] = e("Frame", {
			Size = UDim2.fromOffset(skin.px(PATTERN_TILE.width), skin.px(PATTERN_TILE.height + PATTERN_TILE.caption)),
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, {
			Tile = e("ImageButton", {
				Size = UDim2.fromOffset(skin.px(PATTERN_TILE.width), skin.px(PATTERN_TILE.height)),
				BackgroundColor3 = floorColour,
				AutoButtonColor = false,
				Image = if id and id ~= 0 then "rbxassetid://" .. id else "",
				ImageColor3 = patternColour,
				ImageTransparency = 1 - math.clamp(options.patternStrength / 100, 0, 1),
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(skin.px(PATTERN_PREVIEW_TILE[name] or 32), skin.px(PATTERN_PREVIEW_TILE[name] or 32)),
				[React.Event.InputBegan] = Press.began(pick),
				[React.Event.Activated] = Press.activated(pick),
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(12)) }),
				-- Border mode: on a button a UIStroke otherwise outlines the (empty) text.
				Ring = e("UIStroke", {
					Color = if selected then Tokens.color.accentText else Tokens.color.black,
					Thickness = skin.stroke(if selected then 3 else 1),
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			}),
			Caption = e("TextLabel", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, skin.px(PATTERN_TILE.caption)),
				BackgroundTransparency = 1,
				Text = name,
				TextColor3 = if selected then Tokens.color.accentText else Tokens.color.white,
				TextTransparency = if selected then 0 else Tokens.alpha.textDim,
				TextSize = skin.textPx(Tokens.type.meta.size),
				FontFace = Tokens.font(800),
				TextYAlignment = Enum.TextYAlignment.Bottom,
			}),
		})
	end

	-- A saved slider: applies live while dragging, saves on release.
	local function slider(key: string, min: number, max: number, step: number, order: number)
		return e(Slider, {
			value = options[key],
			min = min,
			max = max,
			step = step,
			layoutOrder = order,
			onChange = function(value: number)
				props.onChange({ [key] = value })
			end,
			onCommit = function(value: number)
				props.onCommit({ [key] = value })
			end,
		})
	end

	local function percent(value: number): string
		return math.floor(value + 0.5) .. "%"
	end

	local header = skin.px(36)
	local headerGap = skin.px(10)
	local tabsTop = header + headerGap
	local bodyTop = tabsTop + skin.px(TABS_HEIGHT) + skin.px(12)

	return e(GlassPanel, {
		variant = "dark",
		cornerRadius = Tokens.radius.sidePanel,
		shadow = true,
		anchorPoint = Vector2.new(1, 0),
		position = (props.t or React.createBinding(1)):map(function(t: number)
			local inset = props.inset or Tokens.size.edgeInset
			local off = (1 - t) * skin.px(Tokens.size.sidePanelWidth + inset)
			return UDim2.new(1, -skin.px(inset) + off, 0, skin.px(88))
		end),
		size = UDim2.new(0, skin.px(Tokens.size.sidePanelWidth), 1, -skin.px(88 + 112)),
		zIndex = 5,
	}, {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(14)),
			PaddingBottom = UDim.new(0, skin.px(14)),
			PaddingLeft = UDim.new(0, skin.px(18)),
			PaddingRight = UDim.new(0, skin.px(10)),
		}),
		-- Fixed title row; everything else scrolls beneath it.
		Header = e("Frame", {
			Size = UDim2.new(1, -skin.px(4), 0, header),
			BackgroundTransparency = 1,
		}, {
			Title = row(skin, 1, 36, 8, {
				Icon = e(Icon, { name = "landscape", size = 22, color = Tokens.color.accentIcon, layoutOrder = 1 }),
				Text = label("World options", Tokens.type.panelTitle, 2),
			}),
			Reset = e(PillButton, {
				variant = "round",
				size = Tokens.size.small.size,
				icon = "restart_alt",
				iconSize = Tokens.size.small.icon,
				anchorPoint = Vector2.new(1, 0),
				position = UDim2.new(1, -skin.px(Tokens.size.small.size + 8), 0, 0),
				sound = "back",
				onActivated = function()
					props.onReset(section)
				end,
			}),
			Close = e(PillButton, {
				variant = "round",
				size = Tokens.size.small.size,
				icon = "close",
				iconSize = Tokens.size.small.icon,
				anchorPoint = Vector2.new(1, 0),
				position = UDim2.fromScale(1, 0),
				sound = false, -- closing plays the swipe-off
				onActivated = props.onClose,
			}),
		}),
		Tabs = e(PillTabs, {
			tabs = TABS,
			activeId = section,
			onSelect = setSection,
			tabWidth = math.floor((Tokens.size.sidePanelWidth - 18 - 14) / 3),
			height = TABS_HEIGHT,
			position = UDim2.fromOffset(0, tabsTop),
		}),
		Body = e("ScrollingFrame", {
			Position = UDim2.fromOffset(0, bodyTop),
			Size = UDim2.new(1, 0, 1, -bodyTop),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			-- Explicit canvas height from the measured content (AutomaticCanvasSize
			-- mis-sizes under the canvas UIScale).
			CanvasSize = UDim2.fromOffset(0, contentHeight + skin.px(8)),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = skin.px(6),
			ScrollBarImageColor3 = Tokens.color.accent,
		}, {
			Inset = e("UIPadding", {
				PaddingTop = UDim.new(0, skin.px(3)),
				PaddingLeft = UDim.new(0, skin.px(3)),
				PaddingRight = UDim.new(0, skin.px(14)),
			}),
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(10)),
				ref = layoutRef,
			}),
			-- One section at a time (the tabs above).
			Sky = if section == "sky"
				then e(React.Fragment, nil, {
				TimeHeader = valueHeader(skin, "Time of day", formatTime(options.time), 1),
				TimeSlider = slider("time", config.timeMin, config.timeMax, config.timeStep, 2),
				SkyLabel = label("Sky", Tokens.type.sectionLabel, 3),
				Skies = row(skin, 4, 36, 6, skyButtons),
				LightHeader = valueHeader(skin, "Lighting", percent(options.brightness), 14),
				LightSlider = slider("brightness", config.brightnessMin, config.brightnessMax, config.brightnessStep, 15),
				Shadows = e("Frame", {
					Size = UDim2.new(1, 0, 0, skin.px(28)),
					BackgroundTransparency = 1,
					LayoutOrder = 16,
				}, {
					Label = row(skin, 1, 28, 0, {
						Text = label("Shadows", Tokens.type.bodyStrong, 1),
					}),
					Toggle = e(Toggle, {
						on = options.shadows,
						anchorPoint = Vector2.new(1, 0.5),
						position = UDim2.fromScale(1, 0.5),
						onToggle = function(on: boolean)
							props.onChange({ shadows = on })
							props.onCommit({ shadows = on })
						end,
					}),
				}),
				Hint = if config.flight.enabled
					then row(skin, 17, 20, 6, {
						Icon = e(Icon, { name = "flight", size = 18, color = Tokens.color.accentText, layoutOrder = 1 }),
						Text = label("Double-jump to fly. Use it to find a quiet spot.", Tokens.type.hint, 2, nil, Tokens.alpha.textSoft),
					})
					else nil,
				})
				else nil,
			Floor = if section == "floor"
				then e(React.Fragment, nil, {
				-- Pairs, each header + its slider + its choices: floor colour
				-- (lightness), pattern colour (lightness), pattern texture (strength).
				-- Headers carry their slider's value.
				FloorHeader = valueHeader(skin, "Floor", percent(options.floorLightness), 5),
				FloorLightness = slider("floorLightness", config.lightnessMin, config.lightnessMax, config.lightnessStep, 6),
				Floors = row(skin, 7, SWATCH, SWATCH_GAP, swatches(config.floorColors, "floor", "floorLightness")),
				PatternColourHeader = valueHeader(skin, "Pattern colour", percent(options.patternLightness), 8),
				PatternLightness = slider("patternLightness", config.lightnessMin, config.lightnessMax, config.lightnessStep, 9),
				PatternColors = row(
					skin,
					10,
					SWATCH,
					SWATCH_GAP,
					swatches(config.patternColors, "patternColor", "patternLightness")
				),
				PatternHeader = valueHeader(skin, "Pattern", percent(options.patternStrength), 11),
				Strength = slider(
					"patternStrength",
					config.patternStrengthMin,
					config.patternStrengthMax,
					config.patternStrengthStep,
					12
				),
				Patterns = patternGrid(skin, 13, #config.patterns, patternTiles),
				-- The floor as a whole: down to invisible (still solid).
				OpacityHeader = valueHeader(skin, "Floor opacity", percent(options.floorOpacity), 14),
				Opacity = slider(
					"floorOpacity",
					config.floorOpacityMin,
					config.floorOpacityMax,
					config.floorOpacityStep,
					15
				),
				})
				else nil,
			Music = if section == "music" and props.music
				then e(MusicPanel, { music = props.music, layoutOrder = 1 })
				else nil,
		}),
	})
end

return WorldOptionsView
