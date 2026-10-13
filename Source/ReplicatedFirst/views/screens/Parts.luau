--!strict

--[[
	Parts

	Building blocks shared by the full-panel screens (design frames 5b–5h):

	  Thumb      tinted tile (the design's colour-washed card art) with the
	             item's thumbnail on it when it has one
	  PriceTag   "Owned" / "Free" / "₹65"
	  ItemCard   catalogue card: thumb with wearing / in-basket / favourite
	             markers, name, price;
	             with `menu`, a tap opens the design's card menu over the thumb
	             (Try · basket · Buy · View) instead of calling onActivated
	  ListRow    Basket/Wearing/Outfit row: thumb, name, sub-line, price, actions
	  LoadingCard  a grid cell holding a spinner: "more results are on the way"
	  CardGrid   scrolling grid with an explicit column count — cells and scroll
	             extent sized from measured width (no AutomaticCanvasSize, which
	             mis-sizes under the canvas UIScale)
	  Heading    section title with optional "See all"-style trailing element
	  CardRow    a carousel: one row of cells that scrolls sideways

	Real catalogue items show their thumbnail over the tint; mock items show
	their sub-category caption instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local Sounds = require(views:WaitForChild("Sounds"))
local Press = require(views:WaitForChild("Press"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useInteraction = require(hooks:WaitForChild("useInteraction"))
local useLocalSize = require(hooks:WaitForChild("useLocalSize"))
local useTextWidth = require(hooks:WaitForChild("useTextWidth"))
local Badge = require(components:WaitForChild("Badge"))
local Icon = require(components:WaitForChild("Icon"))
local ShadowText = require(components:WaitForChild("ShadowText"))
local PillButton = require(components:WaitForChild("PillButton"))
local Spinner = require(components:WaitForChild("Spinner"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))
local HudContext = require(views:WaitForChild("HudContext"))

local e = React.createElement

local Parts = {}

local CARD_BASE = Color3.fromHex("#1c1c1c")
local FREE_GREEN = Color3.fromHex("#9be37a")

-- CSS linear-gradient(160deg, <colour>55, #1c1c1c 75%) → UIGradient at
-- Rotation 70 (CSS angle - 90), colour at ~33% over the card base.
local function tint(colour: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, CARD_BASE:Lerp(colour, 0.33)),
		ColorSequenceKeypoint.new(0.75, CARD_BASE),
		ColorSequenceKeypoint.new(1, CARD_BASE),
	})
end

-- Single body parts (worn as items; shown together as one Body row).
Parts.BODY_PARTS = { Torso = true, LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true }

function Parts.isBodyPart(item: any): boolean
	return item ~= nil and Parts.BODY_PARTS[item.typeName] == true
end

-- A name for a set of body parts: the words their names share
-- ("Zombie Left Arm", "Zombie Torso" → "Zombie"), else "Body".
function Parts.bodyName(items: { any }): string
	local words: { string }? = nil
	local shared = 0
	for _, item in items do
		local mine = string.split(item.name or "", " ")
		if not words then
			words = mine
			shared = #mine
		else
			local n = 0
			while n < shared and mine[n + 1] == (words :: { string })[n + 1] do
				n += 1
			end
			shared = n
		end
	end
	if not words or shared == 0 then
		return "Body"
	end
	return table.concat(words, " ", 1, shared) .. " body"
end

function Parts.swatch(colourName: string): Color3
	return (Tokens.swatch :: any)[colourName] or Tokens.swatch.Orange
end

-- The item's thumbnail, or nil for mock items (which have none).
function Parts.image(item: PlaceholderData.Item): string?
	return if item.thumbnail ~= "" then item.thumbnail else nil
end

export type ThumbProps = {
	colour: Color3,
	image: string?, -- thumbnail drawn over the tint; hides the caption
	flat: boolean?, -- the plain colour, no shading (a colour swatch)
	radius: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	hovered: boolean?,
	selected: boolean?,
	caption: string?,
	layoutOrder: number?,
	zIndex: number?,
	children: any,
}

function Parts.Thumb(props: ThumbProps)
	local skin = useSkin()
	local z = props.zIndex or 1
	local caption = if props.image then nil else props.caption
	return e("Frame", {
		Name = "Thumb",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder or 0,
		BackgroundColor3 = if props.flat then props.colour else Tokens.color.white,
		BorderSizePixel = 0,
		ZIndex = z,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(props.radius or Tokens.radius.itemCard)) }),
		Gradient = if props.flat then nil else e("UIGradient", { Color = tint(props.colour), Rotation = 70 }),
		Ring = e("UIStroke", {
			Color = if props.selected or props.hovered then Tokens.color.accentText else Tokens.color.white,
			Transparency = if props.selected then 0 elseif props.hovered then 1 - 0.7 else 1 - 0.1,
			Thickness = skin.stroke(if props.selected then 2 else 1),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Image = if props.image
			then e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.92, 0.92),
				BackgroundTransparency = 1,
				Image = props.image,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = z,
			})
			else nil,
		Caption = if caption
			then e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = caption,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(11),
				FontFace = Tokens.font(700),
				ZIndex = z,
			})
			else nil,
		Children = e(React.Fragment, nil, props.children),
	})
end

export type PriceProps = { item: PlaceholderData.Item, size: number?, layoutOrder: number? }

function Parts.PriceTag(props: PriceProps)
	local skin = useSkin()
	local item = props.item
	local size = props.size or 12.5
	local label, colour, transparency
	if item.owned then
		label, colour, transparency = "Owned", Tokens.color.white, Tokens.alpha.textDim
	elseif item.price == 0 then
		label, colour, transparency = "Free", FREE_GREEN, 0
	else
		label, colour, transparency = Tokens.robux(item.price), Tokens.color.accentText, 0
	end
	-- Sized to its content so it sits next to whatever follows it in a row.
	local textWidth = useTextWidth(label, Tokens.font(900), skin.textPx(size))
	return e("Frame", {
		Name = "Price",
		Size = UDim2.fromOffset(textWidth, skin.px(size + 4)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(2)),
		}),
		Label = e(ShadowText, {
			text = label,
			style = { size = size, weight = 900 },
			color = colour,
			transparency = transparency,
			shadow = false,
			layoutOrder = 2,
		}),
	})
end

-- The card menu (design 5b): Try / Take off, basket toggle, Buy, View.
export type CardMenu = {
	open: boolean,
	onToggle: () -> (), -- a tap on the card opens/closes its menu
	onTry: () -> (),
	onBasket: () -> (),
	onBuy: () -> (),
	onView: () -> (),
}

export type ItemCardProps = {
	item: PlaceholderData.Item,
	wearing: boolean,
	inBasket: boolean,
	favourite: boolean?, -- a star badge
	onActivated: (() -> ())?, -- plain tap (cards without a menu)
	menu: CardMenu?,
	layoutOrder: number?,
}

local MENU_BUTTON = 30
local MENU_TEXT = { size = 13.5, weight = 900 }

local function CardMenuOverlay(props: { item: PlaceholderData.Item, wearing: boolean, inBasket: boolean, menu: CardMenu })
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local item, menu = props.item, props.menu
	local gap = skin.px(5)
	local buyLabel = if item.owned then "Owned" elseif item.price == 0 then "Get" else "Buy"
	return e("Frame", {
		Name = "Menu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Tokens.color.black,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(Tokens.radius.itemCard)) }),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(9)),
			PaddingBottom = UDim.new(0, skin.px(9)),
			PaddingLeft = UDim.new(0, skin.px(9)),
			PaddingRight = UDim.new(0, skin.px(9)),
		}),
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, gap),
		}),
		Try = e(PillButton, {
			variant = "pill",
			size = MENU_BUTTON,
			icon = if props.wearing then "remove" else "checkroom",
			iconSize = 16,
			label = if props.wearing then "Take off" else "Try",
			textStyle = MENU_TEXT,
			active = true,
			glowRadius = 0,
			sound = false, -- the look change plays its own sound
			layoutOrder = 1,
			zIndex = 3,
			onActivated = menu.onTry,
		}),
		Row = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(MENU_BUTTON)),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			ZIndex = 3,
		}, {
			-- flex 1 : 1.4, as in the design
			Basket = e("Frame", {
				Size = UDim2.new(1 / 2.4, -gap / 2, 1, 0),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, {
				Button = e(PillButton, {
					variant = "pill",
					size = MENU_BUTTON,
					icon = if props.inBasket then "remove_shopping_cart" else "add_shopping_cart",
					iconSize = 17,
					glowRadius = 0,
					sound = false, -- the look change plays its own sound
					zIndex = 3,
					onActivated = menu.onBasket,
				}),
			}),
			Buy = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(1.4 / 2.4, -gap / 2, 1, 0),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, {
				Button = e(PillButton, {
					variant = "pill",
					size = MENU_BUTTON,
					label = buyLabel,
					textStyle = MENU_TEXT,
					disabled = item.owned,
					loading = hud.buying("item:" .. item.id),
					glowRadius = 0,
					zIndex = 3,
					onActivated = menu.onBuy,
				}),
			}),
		}),
		View = e(PillButton, {
			variant = "pill",
			size = MENU_BUTTON,
			icon = "visibility",
			iconSize = 16,
			label = "View",
			textStyle = MENU_TEXT,
			glowRadius = 0,
			layoutOrder = 3,
			zIndex = 3,
			onActivated = menu.onView,
		}),
	})
end

function Parts.ItemCard(props: ItemCardProps)
	local skin = useSkin()
	local interaction = useInteraction()
	local item = props.item
	local nameSize = skin.textPx(13)

	local function onPress()
		Sounds.play("press")
		if props.menu then
			props.menu.onToggle()
		elseif props.onActivated then
			props.onActivated()
		end
	end

	return e("TextButton", {
		Name = "ItemCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder or 0,
		[React.Event.InputBegan] = Press.began(onPress),
		[React.Event.Activated] = Press.activated(onPress),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Parts.swatch(item.colour),
			image = Parts.image(item),
			caption = string.lower(item.sub),
			hovered = interaction.hovered,
			-- Square: the thumb is as tall as the card is wide.
			size = UDim2.fromScale(1, 1),
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
			Markers = e("Frame", {
				Position = UDim2.fromOffset(skin.px(6), skin.px(6)),
				Size = UDim2.fromOffset(skin.px(80), skin.px(24)),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(4)),
				}),
				Wearing = if props.wearing
					then e(Badge, { kind = "marker", tone = "orange", icon = "checkroom", layoutOrder = 1, zIndex = 2 })
					else nil,
				InBasket = if props.inBasket
					then e(Badge, { kind = "marker", tone = "orange", icon = "shopping_basket", layoutOrder = 2, zIndex = 2 })
					else nil,
				Favourite = if props.favourite
					then e(Badge, { kind = "marker", tone = "white", icon = "star", layoutOrder = 3, zIndex = 2 })
					else nil,
			}),
			Menu = if props.menu and props.menu.open
				then e(CardMenuOverlay, {
					item = item,
					wearing = props.wearing,
					inBasket = props.inBasket,
					menu = props.menu,
				})
				else nil,
		}),
		Meta = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, skin.px(36)),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(2)) }),
			Name = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, nameSize + skin.px(2)),
				BackgroundTransparency = 1,
				Text = item.name,
				TextColor3 = Tokens.color.white,
				TextSize = nameSize,
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			}),
			Price = e(Parts.PriceTag, { item = item, layoutOrder = 2 }),
		}),
	})
end

export type ListRowProps = {
	title: string,
	subtitle: string?,
	colour: Color3,
	image: string?,
	trailing: any?, -- elements on the right (price, buttons)
	trailingWidth: number?, -- design px for them (default 250)
	leading: any?, -- element before the thumb (e.g. a checkbox)
	flat: boolean?, -- the thumb is a plain colour swatch
	onActivated: (() -> ())?,
	layoutOrder: number?,
}

function Parts.ListRow(props: ListRowProps)
	local skin = useSkin()
	local interaction = useInteraction()
	local height = skin.px(64)
	local thumb = skin.px(48)
	local leadingWidth = if props.leading then skin.px(34) else 0
	local trailingWidth = skin.px(props.trailingWidth or 250)

	return e("TextButton", {
		Name = "ListRow",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Tokens.color.white,
		BackgroundTransparency = if interaction.hovered then 1 - 0.07 else 1 - 0.04,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder or 0,
		[React.Event.InputBegan] = Press.began(props.onActivated),
		[React.Event.Activated] = Press.activated(props.onActivated),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
		Stroke = e("UIStroke", {
			Color = if interaction.hovered then Tokens.color.accentText else Tokens.color.white,
			Transparency = if interaction.hovered then 1 - 0.6 else 1 - 0.08,
			Thickness = skin.stroke(1),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Leading = if props.leading
			then e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, skin.px(10), 0.5, 0),
				Size = UDim2.fromOffset(leadingWidth, leadingWidth),
				BackgroundTransparency = 1,
			}, { Child = props.leading })
			else nil,
		Thumb = e(Parts.Thumb, {
			colour = props.colour,
			image = props.image,
			flat = props.flat,
			radius = 10,
			anchorPoint = Vector2.new(0, 0.5),
			position = UDim2.new(0, skin.px(8) + leadingWidth + (if props.leading then skin.px(8) else 0), 0.5, 0),
			size = UDim2.fromOffset(thumb, thumb),
		}),
		Text = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, skin.px(8) + leadingWidth + (if props.leading then skin.px(8) else 0) + thumb + skin.px(12), 0.5, 0),
			Size = UDim2.new(1, -(skin.px(8) + leadingWidth + thumb + skin.px(12) + trailingWidth), 0, skin.px(40)),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, skin.px(2)),
			}),
			Title = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(15) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.title,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(15),
				FontFace = Tokens.font(900),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			}),
			Subtitle = if props.subtitle
				then e("TextLabel", {
					Size = UDim2.new(1, 0, 0, skin.textPx(12.5) + skin.px(2)),
					BackgroundTransparency = 1,
					Text = props.subtitle,
					TextColor3 = Tokens.color.white,
					TextTransparency = Tokens.alpha.textDim,
					TextSize = skin.textPx(12.5),
					FontFace = Tokens.font(800),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = 2,
				})
				else nil,
		}),
		Trailing = e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -skin.px(10), 0.5, 0),
			Size = UDim2.fromOffset(trailingWidth, skin.px(40)),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(8)),
			}),
			Children = e(React.Fragment, nil, props.trailing),
		}),
	})
end

-- A grid cell with a spinning arc where the next result will land.
function Parts.LoadingCard(props: { layoutOrder: number? })
	return e("Frame", {
		Name = "LoadingCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Tokens.color.white,
			size = UDim2.fromScale(1, 1),
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
			Spinner = e(Spinner, {
				size = 34,
				anchorPoint = Vector2.new(0.5, 0.5),
				position = UDim2.fromScale(0.5, 0.5),
			}),
		}),
	})
end

export type CardGridProps = {
	columns: number,
	gap: number?, -- design px
	extraHeight: number?, -- design px added below each square cell (labels)
	cellAspect: number?, -- width / height of the square part (default 1)
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	children: any, -- cells, keyed, with LayoutOrder
	count: number, -- number of cells (for the scroll extent)
	onNearEnd: (() -> ())?, -- scrolled within a screenful of the end (load more)
	scrollKey: string?, -- remember the scroll position under this key for the session
}

-- Session memory of grid scroll positions (CardGrid.scrollKey).
local scrollPositions: { [string]: number } = {}

function Parts.CardGrid(props: CardGridProps)
	local skin = useSkin()
	local ref = React.useRef(nil :: GuiObject?)
	local size = useLocalSize(ref)
	local gap = skin.px(props.gap or 12)
	local scrollbar = skin.px(14)
	-- Inset so strokes/glows drawn just outside each cell aren't clipped by
	-- the ScrollingFrame at the grid's edges (the design pads its grid 2px).
	local inset = skin.px(3)
	local columns = props.columns
	local usable = math.max(0, size.X - scrollbar - inset * 2 - gap * (columns - 1))
	local cellWidth = math.floor(usable / columns)
	local cellHeight = math.floor(cellWidth / (props.cellAspect or 1)) + skin.px(props.extraHeight or 0)
	local rows = math.ceil(props.count / columns)
	local canvasHeight = rows * cellHeight + math.max(0, rows - 1) * gap + inset * 2

	-- Put the scroll back where it was for this key, once there's enough
	-- content to scroll that far (cached results arrive a frame or two late).
	local restoredKey = React.useRef(nil :: string?)
	React.useEffect(function()
		local key = props.scrollKey
		local frame = ref.current :: ScrollingFrame?
		if not key or not frame or restoredKey.current == key then
			return
		end
		local saved = scrollPositions[key] or 0
		if saved <= 0 then
			-- A browse not seen before starts at the top.
			frame.CanvasPosition = Vector2.zero
			restoredKey.current = key
			return
		end
		if frame.AbsoluteCanvasSize.Y - frame.AbsoluteWindowSize.Y >= saved then
			frame.CanvasPosition = Vector2.new(0, saved)
			restoredKey.current = key
		end
	end, { props.scrollKey or "", canvasHeight } :: { any })

	return e("ScrollingFrame", {
		Name = "CardGrid",
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		LayoutOrder = props.layoutOrder or 0,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, canvasHeight),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = skin.px(8),
		ScrollBarImageColor3 = Tokens.color.accent,
		ref = ref,
		[React.Change.CanvasPosition] = function(rbx: ScrollingFrame)
			-- Only record once this key's position has been restored (or there
			-- was none), so the reset to 0 on a new browse doesn't overwrite it.
			if props.scrollKey and restoredKey.current == props.scrollKey then
				scrollPositions[props.scrollKey] = rbx.CanvasPosition.Y
			end
			if props.onNearEnd then
				local remaining = rbx.AbsoluteCanvasSize.Y - (rbx.CanvasPosition.Y + rbx.AbsoluteWindowSize.Y)
				if remaining < rbx.AbsoluteWindowSize.Y then
					props.onNearEnd()
				end
			end
		end,
	}, {
		Inset = e("UIPadding", {
			PaddingTop = UDim.new(0, inset),
			PaddingBottom = UDim.new(0, inset),
			PaddingLeft = UDim.new(0, inset),
			PaddingRight = UDim.new(0, inset),
		}),
		Grid = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(cellWidth, cellHeight),
			CellPadding = UDim2.fromOffset(gap, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Cells = e(React.Fragment, nil, props.children),
	})
end

export type CardRowProps = {
	cardWidth: number, -- design px
	extraHeight: number?, -- design px below each square cell (labels; default 40)
	gap: number?, -- design px
	count: number,
	layoutOrder: number?,
	children: any, -- cells, keyed, with LayoutOrder
}

-- The row's height in pixels for these props (to lay out what's around it).
function Parts.cardRowHeight(skin: any, cardWidth: number, extraHeight: number?): number
	return skin.px(cardWidth) + skin.px(extraHeight or 40) + skin.px(3) * 2 + skin.px(12)
end

-- A carousel: one row of fixed-width cells that scrolls sideways (drag on
-- touch, or the scroll bar under it).
function Parts.CardRow(props: CardRowProps)
	local skin = useSkin()
	local width = skin.px(props.cardWidth)
	local height = width + skin.px(props.extraHeight or 40)
	local gap = skin.px(props.gap or 12)
	local inset = skin.px(3) -- room for strokes and glows, as in CardGrid
	local count = props.count
	return e("ScrollingFrame", {
		Name = "CardRow",
		Size = UDim2.new(1, 0, 0, Parts.cardRowHeight(skin, props.cardWidth, props.extraHeight)),
		LayoutOrder = props.layoutOrder or 0,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(count * width + math.max(0, count - 1) * gap + inset * 2, 0),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = skin.px(6),
		ScrollBarImageColor3 = Tokens.color.accent,
		HorizontalScrollBarInset = Enum.ScrollBarInset.Always,
	}, {
		Inset = e("UIPadding", {
			PaddingTop = UDim.new(0, inset),
			PaddingLeft = UDim.new(0, inset),
			PaddingRight = UDim.new(0, inset),
		}),
		Grid = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(width, height),
			CellPadding = UDim2.fromOffset(gap, gap),
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Cells = e(React.Fragment, nil, props.children),
	})
end

export type HeadingProps = { text: string, trailing: any?, layoutOrder: number? }

function Parts.Heading(props: HeadingProps)
	local skin = useSkin()
	return e("Frame", {
		Name = "Heading",
		Size = UDim2.new(1, 0, 0, skin.px(24)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
	}, {
		Text = e(ShadowText, {
			text = props.text,
			style = Tokens.type.cardTitle,
			shadow = false,
		}),
		Trailing = if props.trailing
			then e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),
				Child = props.trailing,
			})
			else nil,
	})
end

return Parts
