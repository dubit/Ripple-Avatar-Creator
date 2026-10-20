--!strict

--[[
	CatalogueFilters (design frame 5b bottom bar + popovers)

	The Catalogue's filter state and the pieces that edit it:

	  defaults()          a fresh Filters (everything off, default sort)
	  FilterButton        a bar button: label + chevron, orange when its
	                      filter is doing something
	  Popover             the floating glass card the popovers share; opens
	                      upward from the bar, right-aligned
	  SortPopover         sort order, plus a time window for windowed sorts
	  PricePopover        two-handle Robux range, presets, Clear
	  FiltersPopover      creator (anyone / Roblox / a typed name), sales type,
	                      include off-sale
	  ColourPopover       Any + the colour swatches (client-side filter,
	                      useColourFilter)

	  sortLabel / priceLabel / filtersLabel  the bar buttons' text

	Everything but colour maps onto CatalogSearchParams
	(CatalogueClient.Query); colour filters the loaded results by their
	thumbnails' colours (ItemColour). Sizes are fixed per popover
	rather than automatic (AutomaticSize mis-sizes under the canvas UIScale).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local CatalogueConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CatalogueConfig"))

local views = script.Parent.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local Sounds = require(views:WaitForChild("Sounds"))
local Press = require(views:WaitForChild("Press"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useAppear = require(hooks:WaitForChild("useAppear"))
local useTextWidth = require(hooks:WaitForChild("useTextWidth"))
local GlassPanel = require(components:WaitForChild("GlassPanel"))
local PillButton = require(components:WaitForChild("PillButton"))
local Chip = require(components:WaitForChild("Chip"))
local Icon = require(components:WaitForChild("Icon"))
local Toggle = require(components:WaitForChild("Toggle"))
local RangeSlider = require(components:WaitForChild("RangeSlider"))

local e = React.createElement

local CatalogueFilters = {}

export type Filters = {
	sort: string, -- Enum.CatalogSortType name
	sortWindow: string, -- Enum.CatalogSortAggregation name
	minPrice: number?,
	maxPrice: number?,
	creator: string, -- "" = anyone
	salesType: string, -- Enum.SalesTypeFilter name
	includeOffSale: boolean,
	colour: string, -- "" = any
}

export type Popover = "sort" | "price" | "filters" | "colour"

local TITLE = { size = 14, weight = 900 }
local SECTION = { size = 13, weight = 800 }
local BUTTON_TEXT = { size = 14, weight = 900 }

function CatalogueFilters.defaults(): Filters
	return {
		sort = CatalogueConfig.sort,
		sortWindow = CatalogueConfig.sortAggregation,
		minPrice = nil,
		maxPrice = nil,
		creator = "",
		salesType = CatalogueConfig.salesTypes[1].filter,
		includeOffSale = CatalogueConfig.includeOffSale,
		colour = "",
	}
end

local function sortOption(sortType: string)
	for _, option in CatalogueConfig.sorts do
		if option.sortType == sortType then
			return option
		end
	end
	return CatalogueConfig.sorts[1]
end

function CatalogueFilters.sortLabel(f: Filters): string
	if f.sort == CatalogueConfig.sort then
		return "Sort"
	end
	return sortOption(f.sort).label
end

function CatalogueFilters.priceLabel(f: Filters): string
	local low, high = f.minPrice, f.maxPrice
	if low == nil and high == nil then
		return "Price"
	elseif high == 0 then
		return "Free"
	elseif low and high then
		return if low == high then tostring(low) else `{low}–{high}`
	elseif low then
		return `{low}+`
	end
	return `Up to {high}`
end

-- How many of the Filters popover's settings are away from their defaults.
function CatalogueFilters.activeCount(f: Filters): number
	local defaults = CatalogueFilters.defaults()
	local count = 0
	if f.creator ~= "" then
		count += 1
	end
	if f.salesType ~= defaults.salesType then
		count += 1
	end
	if f.includeOffSale ~= defaults.includeOffSale then
		count += 1
	end
	return count
end

function CatalogueFilters.colourLabel(f: Filters): string
	return if f.colour == "" then "Colour" else f.colour
end

function CatalogueFilters.filtersLabel(f: Filters): string
	local count = CatalogueFilters.activeCount(f)
	return if count > 0 then `Filters · {count}` else "Filters"
end

-- A bar button's width for its label (local px). design: padding
-- 0 14px 0 10px, 6px gap, 18px chevron.
function CatalogueFilters.useButtonWidth(label: string): number
	local skin = useSkin()
	local textWidth = useTextWidth(label, Tokens.font(BUTTON_TEXT.weight), skin.textPx(BUTTON_TEXT.size))
	return textWidth + skin.px(14 + 10 + 6 + 18)
end

-- Bar button: label + trailing chevron, sized to its text.
function CatalogueFilters.FilterButton(props: {
	label: string,
	active: boolean,
	open: boolean,
	onActivated: () -> (),
	layoutOrder: number?,
})
	local skin = useSkin()
	local width = CatalogueFilters.useButtonWidth(props.label)
	return e("Frame", {
		Name = "FilterButton",
		Size = UDim2.fromOffset(width, skin.px(38)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
	}, {
		Button = e(PillButton, {
			variant = "pill",
			size = 38,
			icon = "expand_less", -- popovers open upward
			iconSize = 18,
			iconAfter = true,
			label = props.label,
			textStyle = BUTTON_TEXT,
			active = props.active,
			glowRadius = 0,
			sound = "tab",
			onActivated = props.onActivated,
		}),
	})
end

local function sectionLabel(skin, text: string, order: number)
	return e("TextLabel", {
		Size = UDim2.new(1, 0, 0, skin.textPx(SECTION.size) + skin.px(4)),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Tokens.color.white,
		TextTransparency = Tokens.alpha.textDim,
		TextSize = skin.textPx(SECTION.size),
		FontFace = Tokens.font(SECTION.weight),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
	})
end

-- A row of chips that wraps onto `rows` lines (fixed height).
local function chipRows(skin, rows: number, order: number, children: { [string]: any })
	local chipHeight = skin.px(Tokens.size.chipHeight)
	local gap = skin.px(6)
	children.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Wraps = true,
		Padding = UDim.new(0, gap),
	})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, rows * chipHeight + (rows - 1) * gap),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, children)
end

-- The shared popover card. `height` in design px; `onClear` adds a Clear link.
function CatalogueFilters.Popover(props: {
	title: string,
	width: number,
	height: number,
	bottom: number, -- local px from the screen's bottom edge
	onClear: (() -> ())?,
	children: any,
})
	local skin = useSkin()
	local appear = useAppear(Tokens.spring.state)
	local titleHeight = skin.px(20)
	local function clear()
		local onClear = props.onClear
		if onClear then
			Sounds.play("back")
			onClear()
		end
	end
	-- A blank button under the card swallows taps on its empty areas, so they
	-- don't fall through to the item cards beneath.
	return e("TextButton", {
		Name = "Popover",
		AnchorPoint = Vector2.new(1, 1),
		Position = appear:map(function(v: number)
			return UDim2.new(1, -skin.px(8), 1, -props.bottom + (1 - v) * skin.px(12))
		end),
		Size = UDim2.fromOffset(skin.px(props.width), skin.px(props.height)),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
	}, {
		Appear = e("UIScale", {
			Scale = appear:map(function(v: number)
				return 0.94 + 0.06 * v
			end),
		}),
		Card = e(GlassPanel, {
			variant = "bar",
			cornerRadius = 18,
			shadow = true,
			zIndex = 5,
		}, {
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, skin.px(14)),
				PaddingBottom = UDim.new(0, skin.px(14)),
				PaddingLeft = UDim.new(0, skin.px(14)),
				PaddingRight = UDim.new(0, skin.px(14)),
			}),
			Title = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, titleHeight),
				BackgroundTransparency = 1,
				Text = props.title,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(TITLE.size),
				FontFace = Tokens.font(TITLE.weight),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Clear = if props.onClear
				then e("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.new(0, skin.px(60), 0, titleHeight),
					BackgroundTransparency = 1,
					Text = "Clear",
					TextColor3 = Tokens.color.accentText,
					TextSize = skin.textPx(13),
					FontFace = Tokens.font(800),
					TextXAlignment = Enum.TextXAlignment.Right,
					[React.Event.InputBegan] = Press.began(clear),
					[React.Event.Activated] = Press.activated(clear),
				})
				else nil,
			Body = e("Frame", {
				Position = UDim2.fromOffset(0, titleHeight + skin.px(12)),
				Size = UDim2.new(1, 0, 1, -(titleHeight + skin.px(12))),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(10)),
				}),
				Children = e(React.Fragment, nil, props.children),
			}),
		}),
	})
end

type PopoverProps = {
	filters: Filters,
	-- Merge changes into the filters. Price goes as `price = { min, max }`,
	-- since either bound can be nil.
	set: (changes: { [string]: any }) -> (),
	bottom: number,
}

function CatalogueFilters.SortPopover(props: PopoverProps)
	local skin = useSkin()
	local f = props.filters
	local option = sortOption(f.sort)

	local sorts: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(6)) }),
	}
	for index, entry in CatalogueConfig.sorts do
		sorts["Sort" .. index] = e(Chip, {
			label = entry.label,
			active = entry.sortType == f.sort,
			layoutOrder = index,
			onActivated = function()
				props.set({ sort = entry.sortType })
			end,
		})
	end
	local count = #CatalogueConfig.sorts
	local listHeight = count * Tokens.size.chipHeight + (count - 1) * 6

	local windows: { [string]: any } = {}
	for index, entry in CatalogueConfig.sortWindows do
		windows["Window" .. index] = e(Chip, {
			label = entry.label,
			active = entry.aggregation == f.sortWindow,
			layoutOrder = index,
			onActivated = function()
				props.set({ sortWindow = entry.aggregation })
			end,
		})
	end

	local height = 14 + 20 + 12 + listHeight + 28 + (if option.windowed then 10 + 18 + 10 + Tokens.size.chipHeight * 2 + 6 else 0)
	return e(CatalogueFilters.Popover, {
		title = "Sort by",
		width = 300,
		height = height,
		bottom = props.bottom,
	}, {
		List = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(listHeight)),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, sorts),
		WindowLabel = if option.windowed then sectionLabel(skin, "Over", 2) else nil,
		Windows = if option.windowed then chipRows(skin, 2, 3, windows) else nil,
	})
end

function CatalogueFilters.PricePopover(props: PopoverProps & { countLabel: string })
	local skin = useSkin()
	local f = props.filters
	local max = CatalogueConfig.priceMax
	-- Live values while dragging; the search runs on release.
	local drag, setDrag = React.useState(nil :: { low: number, high: number }?)
	local low = if drag then drag.low else (f.minPrice or 0)
	local high = if drag then drag.high else math.min(f.maxPrice or max, max)

	local presets: { [string]: any } = {}
	for index, preset in CatalogueConfig.pricePresets do
		presets["Preset" .. index] = e(Chip, {
			label = preset.label,
			active = f.minPrice == preset.min and f.maxPrice == preset.max,
			layoutOrder = index,
			onActivated = function()
				props.set({ price = { min = preset.min, max = preset.max } })
			end,
		})
	end

	local valueStyle = { size = 20, weight = 900 }
	return e(CatalogueFilters.Popover, {
		title = "Price (Robux)",
		width = 300,
		-- presets get two rows: four chips don't fit one at this width
		height = 14 + 20 + 12 + 26 + 10 + 30 + 10 + Tokens.size.chipHeight * 2 + 6 + 10 + 18 + 14,
		bottom = props.bottom,
		onClear = function()
			props.set({ price = {} })
		end,
	}, {
		Value = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(26)),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(4)),
			}),
			Text = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = `{Tokens.robux(low)} – {if high >= max then "Any" else Tokens.robux(high)}`,
				TextColor3 = Tokens.color.accentText,
				TextSize = skin.textPx(valueStyle.size),
				FontFace = Tokens.font(valueStyle.weight),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
			}),
		}),
		Slider = e(RangeSlider, {
			low = low,
			high = high,
			min = 0,
			max = max,
			step = CatalogueConfig.priceStep,
			layoutOrder = 2,
			onChange = function(l: number, h: number)
				setDrag({ low = l, high = h })
			end,
			onCommit = function(l: number, h: number)
				setDrag(nil)
				props.set({
					price = {
						min = if l <= 0 then nil else l,
						max = if h >= max then nil else h,
					},
				})
			end,
		}),
		Presets = chipRows(skin, 2, 3, presets),
		Count = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, skin.px(18)),
			BackgroundTransparency = 1,
			Text = props.countLabel,
			TextColor3 = Tokens.color.white,
			TextTransparency = Tokens.alpha.textDim,
			TextSize = skin.textPx(12.5),
			FontFace = Tokens.font(700),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 4,
		}),
	})
end

function CatalogueFilters.FiltersPopover(props: PopoverProps)
	local skin = useSkin()
	local f = props.filters
	local isRoblox = string.lower(f.creator) == "roblox"
	-- The typed name, kept separately so picking Roblox/Anyone doesn't lose it.
	local typed, setTyped = React.useState(if f.creator ~= "" and not isRoblox then f.creator else "")
	local focused, setFocused = React.useState(false)

	local creators: { [string]: any } = {
		Anyone = e(Chip, {
			label = "Anyone",
			active = f.creator == "",
			layoutOrder = 1,
			onActivated = function()
				props.set({ creator = "" })
			end,
		}),
		Roblox = e(Chip, {
			label = "Roblox",
			active = isRoblox,
			layoutOrder = 2,
			onActivated = function()
				props.set({ creator = "Roblox" })
			end,
		}),
	}

	local sales: { [string]: any } = {}
	for index, entry in CatalogueConfig.salesTypes do
		sales["Sales" .. index] = e(Chip, {
			label = entry.label,
			active = f.salesType == entry.filter,
			layoutOrder = index,
			onActivated = function()
				props.set({ salesType = entry.filter })
			end,
		})
	end

	return e(CatalogueFilters.Popover, {
		title = "Filters",
		width = 300,
		height = 14 + 20 + 12 + (18 + 10 + Tokens.size.chipHeight + 10 + 38) + 10 + (18 + 10 + Tokens.size.chipHeight) + 10 + 28 + 14,
		bottom = props.bottom,
		onClear = function()
			setTyped("")
			local d = CatalogueFilters.defaults()
			props.set({ creator = d.creator, salesType = d.salesType, includeOffSale = d.includeOffSale })
		end,
	}, {
		CreatorLabel = sectionLabel(skin, "Creator", 1),
		Creators = chipRows(skin, 1, 2, creators),
		CreatorName = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(38)),
			BackgroundColor3 = Tokens.color.inputWell,
			BorderSizePixel = 0,
			LayoutOrder = 3,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Stroke = e("UIStroke", {
				Color = if f.creator ~= "" and not isRoblox then Tokens.color.accent else Tokens.color.black,
				Thickness = skin.stroke(1),
			}),
			Box = e("TextBox", {
				Position = UDim2.fromOffset(skin.px(14), 0),
				Size = UDim2.new(1, -skin.px(28), 1, 0),
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				Text = typed,
				PlaceholderText = if focused then "" else "Creator name",
				PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(Tokens.type.search.size),
				FontFace = Tokens.font(Tokens.type.search.weight),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				[React.Change.Text] = function(box: TextBox)
					if box.Text ~= typed then
						setTyped(box.Text)
						props.set({ creator = box.Text }) -- the search debounces typing
					end
				end,
				[React.Event.Focused] = function()
					setFocused(true)
				end,
				[React.Event.FocusLost] = function()
					setFocused(false)
				end,
			}),
		}),
		SalesLabel = sectionLabel(skin, "Sales type", 4),
		Sales = chipRows(skin, 1, 5, sales),
		OffSale = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(28)),
			BackgroundTransparency = 1,
			LayoutOrder = 6,
		}, {
			Label = e("TextLabel", {
				Size = UDim2.new(1, -skin.px(60), 1, 0),
				BackgroundTransparency = 1,
				Text = "Include off-sale items",
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Toggle = e(Toggle, {
				on = f.includeOffSale,
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.fromScale(1, 0.5),
				onToggle = function(on: boolean)
					props.set({ includeOffSale = on })
				end,
			}),
		}),
	})
end

local SWATCH = 36

local function Swatch(props: { name: string, selected: boolean, onPick: () -> (), layoutOrder: number })
	local skin = useSkin()
	local isAny = props.name == ""
	local function onPress()
		Sounds.play("tab")
		props.onPick()
	end
	return e("TextButton", {
		Name = "Swatch",
		Size = UDim2.fromOffset(skin.px(SWATCH), skin.px(SWATCH)),
		BackgroundColor3 = if isAny then Color3.fromHex("#333333") else (Tokens.swatch :: any)[props.name] or Tokens.color.white,
		AutoButtonColor = false,
		Text = if isAny then "Any" else "",
		TextColor3 = Tokens.color.white,
		TextSize = skin.textPx(11),
		FontFace = Tokens.font(900),
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(onPress),
		[React.Event.Activated] = Press.activated(onPress),
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		-- Border mode: on a button a UIStroke otherwise outlines the text.
		Ring = e("UIStroke", {
			Color = if props.selected then Tokens.color.accentText else Tokens.color.black,
			Thickness = skin.stroke(if props.selected then 3 else 1),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Gradient = if isAny
			then nil
			else e("UIGradient", {
				-- inset highlight / shade, as on the design's swatches
				Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
				Rotation = 90,
			}),
	})
end

function CatalogueFilters.ColourPopover(props: PopoverProps & { onPicked: () -> () })
	local skin = useSkin()
	local f = props.filters
	local names = { "" }
	for _, name in CatalogueConfig.colours do
		table.insert(names, name)
	end
	local perRow = 6
	local rows = math.ceil(#names / perRow)
	local gap = 10

	local swatches: { [string]: any } = {
		Grid = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(skin.px(SWATCH), skin.px(SWATCH)),
			CellPadding = UDim2.fromOffset(skin.px(gap), skin.px(gap)),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, name in names do
		swatches["Swatch" .. index] = e(Swatch, {
			name = name,
			selected = f.colour == name,
			layoutOrder = index,
			onPick = function()
				props.set({ colour = name })
				props.onPicked() -- picking closes the popover, as in the design
			end,
		})
	end

	local gridWidth = perRow * SWATCH + (perRow - 1) * gap
	return e(CatalogueFilters.Popover, {
		title = "Colour",
		width = gridWidth + 28,
		height = 14 + 20 + 12 + rows * SWATCH + (rows - 1) * gap + 14,
		bottom = props.bottom,
	}, {
		Swatches = e("Frame", {
			Size = UDim2.fromOffset(skin.px(gridWidth), skin.px(rows * SWATCH + (rows - 1) * gap)),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, swatches),
	})
end

return CatalogueFilters
