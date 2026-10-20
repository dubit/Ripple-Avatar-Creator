--!strict

--[[
	StoresScreen (design frames 5h Stores home, 5c store page)

	Root: tabs Popular · Top rated · Favourites · My stores (Sponsored is
	paused: PLAN 17.1) beside a search box. With no tab chosen it's the
	home: a carousel per tab (its first ROW_CARDS stores) with See all;
	empty ones are left out. Tapping a tab (or See all) shows that list as
	a grid, a page at a time as you scroll; tapping it again returns home.
	Stores come from StoresClient (StoresController).

	Search: the loaded stores by name, plus (after a pause in typing) the
	store whose code or exact name it is, from any server.

	A store card: a mosaic of its first items, its name, and its
	favourites and visits (rating is favourites: PLAN 17.1). A star marks
	your favourites. Your drafts read "Draft"; your hidden ones "Hidden".
	My stores (row and tab) starts with a Create store card while you have
	room for another (the Create store dialog: StoreDialogs).

	Store page (5c), one scrolling column:
	  · header: the mosaic, name, "by @owner · N favourites · N visits",
	    Favourite (the star; your own too) and Share (its code and QR: the
	    share dialog), and Report (twice) on someone else's store
	  · then the owner's rows, in their order (StoresClient.Row): items or
	    outfits, hand-filled or found by a search (StoreRow runs a search
	    row's catalogue query, or loads its Community sort), up to the
	    row's limit, in its style: Square / Wide carousels, Hero (2 to 6
	    portrait cards across, no scrolling: with 2 both are wide, with 3
	    or 4 the first is), Single (one at a time with arrows:
	    Try on, Basket, and its picture or name opens the item page), Grid
	    (no scrolling) or Tile (opens the row as its own grid). A
	    hand-filled row longer than its limit has See all
	Item cards have the card menu (Try · basket · Buy · View, and the store
	button once you have a store); outfits rows show outfit cards in the
	same styles, their pictures laid out to fit (OutfitsScreen.mosaic), and
	a Single outfit has Wear all items. Opening someone's published store
	is a visit (once a day).

	Your own store is edited in place (PLAN 19.1): its name is editable (the
	pencil saves it), and a bar under the header says where it stands and
	has Publish / Unpublish and Delete (twice). Every row shows, even empty,
	with what it is, its menu (StoreRowMenu, opening from the button), up /
	down and remove (twice); Add row at the bottom opens the same menu. A
	hand-filled row's Add items (or Add outfits) fills it: items through the
	Catalogue in pick mode (Hud: kept until Done), outfits through the Add
	outfits dialog. Its reorder button puts the row in a line with arrows on
	each card, until Cancel or Done (SetRowItems).
	An items search row's search is chosen in the Catalogue's setup mode. Items also go in and out
	through the store button on any item card, outfits from your shared
	outfit's page (the store picker: StoreDialogs).

	StoresScreen.Root props: nav, look
	StoresScreen.Store props: nav, look, code
	StoresScreen.Section props: nav, look, code, section (a row's id: all
	of it as a grid)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local Sounds = require(views:WaitForChild("Sounds"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useInteraction = require(hooks:WaitForChild("useInteraction"))
local useSessionState = require(hooks:WaitForChild("useSessionState"))
local useBackInput = require(hooks:WaitForChild("useBackInput"))
local TextTab = require(components:WaitForChild("TextTab"))
local ShadowText = require(components:WaitForChild("ShadowText"))
local PillButton = require(components:WaitForChild("PillButton"))
local ConfirmButton = require(components:WaitForChild("ConfirmButton"))
local SearchBox = require(components:WaitForChild("SearchBox"))
local Icon = require(components:WaitForChild("Icon"))
local Spinner = require(components:WaitForChild("Spinner"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))
local OutfitsScreen = require(script.Parent:WaitForChild("OutfitsScreen"))
local StoresClient = require(views:WaitForChild("catalogue"):WaitForChild("StoresClient"))
local HudContext = require(views:WaitForChild("HudContext"))
local StoreDialogs = require(script.Parent:WaitForChild("StoreDialogs"))
local StoreRowMenu = require(script.Parent:WaitForChild("StoreRowMenu"))
local CommunityOutfits = require(views:WaitForChild("catalogue"):WaitForChild("CommunityOutfits"))
local useCatalogue = require(hooks:WaitForChild("useCatalogue"))
local useColourFilter = require(hooks:WaitForChild("useColourFilter"))
local useLocalSize = require(hooks:WaitForChild("useLocalSize"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local StoresConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoresConfig"))

local e = React.createElement

local SEARCH_WIDTH = 270
local SEARCH_DELAY = 0.6 -- seconds after typing stops before a code / name lookup
local ROW_CARDS = 10 -- stores in a home carousel
local STORE_CARD = 150 -- design px: a store card's width in a carousel
local ITEM_CARD = 132 -- design px: an item card's width in a carousel
local SECTION_GAP = 18
local HERO_HEIGHT = 230
local TILE_HEIGHT = 110
local TILE_COLOURS = { "Orange", "Purple", "Blue" }

local EMPTY = {
	popular = "No one has published a store yet",
	toprated = "No one has published a store yet",
	favourites = "Star stores to keep them here",
	mine = "Stores you make show here",
}
local DRAFT_HINT = "Add items with a row's Add items, or the store button on any item card"
local STYLE_LABELS = { square = "Square", wide = "Wide", hero = "Hero", single = "Single", grid = "Grid", tile = "Tile" }
local WIDE_CARD = 264 -- design px: a Wide row's card
local WIDE_THUMB = 132
local HERO_THUMB = 300 -- design px: a Hero row's cards, above their labels
local HERO_MAX = 6 -- cards across a Hero row
local GRID_COLUMNS = 6
local CONTROL = 30 -- design px: a row control's diameter
local OWNER_HEADING = 36 -- design px: a row heading on your own store (the name field's pencil)

local PERSONAL = { favourites = "storeFavourites", mine = "myStores" }

-- Codes reported this session (Report shows as done).
local reported: { [string]: boolean } = {}

-- "1 visit" / "2.4K visits"
local function plural(n: number, word: string): string
	return PlaceholderData.formatCount(n) .. " " .. word .. (if n == 1 then "" else "s")
end

local function storeSub(card: StoresClient.Card): string
	if card.hidden then
		return "Hidden after reports"
	elseif not card.published then
		return "Draft · " .. plural(card.itemCount, "item")
	end
	return plural(card.favourites, "favourite") .. " · " .. plural(card.visits, "visit")
end

local function Message(props: { text: string, position: UDim2? })
	local skin = useSkin()
	return e("Frame", {
		Position = props.position,
		Size = UDim2.new(1, 0, 0, skin.px(40)),
		BackgroundTransparency = 1,
	}, {
		Text = e(ShadowText, {
			text = props.text,
			style = Tokens.type.cardTitle,
			transparency = Tokens.alpha.textDim,
			shadow = false,
		}),
	})
end

local function StoreCard(props: { card: StoresClient.Card, favourite: boolean, onActivated: () -> (), layoutOrder: number })
	local skin = useSkin()
	local interaction = useInteraction()
	local card = props.card
	local cells = OutfitsScreen.mosaic(card.preview)
	local function open()
		Sounds.play("press")
		props.onActivated()
	end
	return e("TextButton", {
		Name = "StoreCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(open),
		[React.Event.Activated] = Press.activated(open),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
		[React.Event.MouseButton1Down] = interaction.onDown,
		[React.Event.MouseButton1Up] = interaction.onUp,
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Tokens.color.white,
			radius = 14,
			hovered = interaction.hovered,
			pressed = interaction.pressed,
			caption = if next(cells) then nil else "store",
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
			Mosaic = e(React.Fragment, nil, cells),
			Star = if props.favourite
				then e(Icon, {
					name = "star",
					size = 20,
					color = Tokens.color.accentText,
					anchorPoint = Vector2.new(1, 0),
					position = UDim2.new(1, -skin.px(6), 0, skin.px(6)),
					zIndex = 2,
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
				Size = UDim2.new(1, 0, 0, skin.textPx(13) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = card.name,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(13),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			}),
			Sub = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(12) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = storeSub(card),
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
		}),
	})
end

-- My stores' first card: make a new store (the Create store dialog).
local function CreateCard(props: { layoutOrder: number })
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local interaction = useInteraction()
	local function create()
		hud.createStore()
	end
	return e("TextButton", {
		Name = "CreateStoreCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(create),
		[React.Event.Activated] = Press.activated(create),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
		[React.Event.MouseButton1Down] = interaction.onDown,
		[React.Event.MouseButton1Up] = interaction.onUp,
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Tokens.color.accent,
			radius = 14,
			hovered = interaction.hovered,
			pressed = interaction.pressed,
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
			Icon = e(Icon, {
				name = "add_business",
				size = 44,
				anchorPoint = Vector2.new(0.5, 0.5),
				position = UDim2.fromScale(0.5, 0.5),
			}),
		}),
		Meta = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, skin.px(36)),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(2)) }),
			Name = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(13) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = "Create store",
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(13),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),
			Sub = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(12) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = "Pick items for others to shop",
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
		}),
	})
end

-- A row's heading on a store page: its name, See all, and on your own
-- store its controls: Add items (a hand-filled row), the row's menu (its
-- settings, from that button), reorder (a hand-filled row of two or more),
-- up / down, and remove (twice). While reordering: Cancel and Done.
type RowOwner = {
	sub: string, -- what the row is ("By hand · Square · 20")
	first: boolean,
	last: boolean,
	busy: boolean,
	onMenu: (anchor: GuiObject) -> (),
	onMove: (by: number) -> (),
	onRemove: () -> (),
	onReorder: (() -> ())?,
	reordering: { saving: boolean, onCancel: () -> (), onDone: () -> () }?,
}

local function RemoveControl(props: { disabled: boolean, onConfirm: () -> (), layoutOrder: number })
	local armed, setArmed = React.useState(false)
	React.useEffect(function()
		if not armed then
			return nil
		end
		local thread = task.delay(3, function()
			setArmed(false)
		end)
		return function()
			task.cancel(thread)
		end
	end, { armed })
	return e(PillButton, {
		variant = "round",
		size = CONTROL,
		icon = "delete",
		iconSize = 17,
		active = armed,
		disabled = props.disabled,
		glowRadius = 0,
		sound = if armed then "confirm" else "press",
		layoutOrder = props.layoutOrder,
		onActivated = function()
			if armed then
				setArmed(false)
				props.onConfirm()
			else
				setArmed(true)
			end
		end,
	})
end

local function TextLink(props: { text: string, width: number, layoutOrder: number, onActivated: () -> () })
	local skin = useSkin()
	local function press()
		Sounds.play("press")
		props.onActivated()
	end
	return e("TextButton", {
		Size = UDim2.fromOffset(skin.px(props.width), skin.px(24)),
		BackgroundTransparency = 1,
		Text = props.text,
		TextColor3 = Tokens.color.accentText,
		TextSize = skin.textPx(13.5),
		FontFace = Tokens.font(800),
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(press),
		[React.Event.Activated] = Press.activated(press),
	})
end

-- The row menu's button, wrapped so the menu can open from where it is.
local function MenuControl(props: { disabled: boolean, onMenu: (anchor: GuiObject) -> (), layoutOrder: number })
	local skin = useSkin()
	local ref = React.useRef(nil :: Frame?)
	return e("Frame", {
		Size = UDim2.fromOffset(skin.px(CONTROL), skin.px(CONTROL)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		ref = ref,
	}, {
		Button = e(PillButton, {
			variant = "round",
			size = CONTROL,
			icon = "edit",
			iconSize = 16,
			disabled = props.disabled,
			glowRadius = 0,
			sound = false, -- the menu plays its own sound
			onActivated = function()
				if ref.current then
					props.onMenu(ref.current)
				end
			end,
		}),
	})
end

local function roundControl(icon: string, disabled: boolean, order: number, onActivated: () -> ()): any
	return e(PillButton, {
		variant = "round",
		size = CONTROL,
		icon = icon,
		iconSize = 19,
		disabled = disabled,
		glowRadius = 0,
		layoutOrder = order,
		onActivated = onActivated,
	})
end

local function pillControl(label: string, width: number, order: number, extra: { [string]: any }): any
	local props: { [string]: any } = {
		variant = "pill",
		size = CONTROL,
		width = width,
		label = label,
		textStyle = { size = 13.5, weight = 800 },
		glowRadius = 0,
		layoutOrder = order,
	}
	for key, value in extra do
		props[key] = value
	end
	return e(PillButton, props)
end

local function RowHeading(props: {
	text: string,
	layoutOrder: number?,
	onSeeAll: (() -> ())?,
	onAdd: (() -> ())?,
	addLabel: string?,
	owner: RowOwner?,
})
	local skin = useSkin()
	local owner = props.owner
	local reordering = owner and owner.reordering
	local controls: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(6)),
		}),
	}
	local width = 0
	if reordering then
		controls.Cancel = pillControl("Cancel", 90, 1, {
			disabled = reordering.saving,
			sound = "back",
			onActivated = reordering.onCancel,
		})
		controls.Done = pillControl("Done", 100, 2, {
			icon = "check",
			iconSize = 16,
			active = true,
			loading = reordering.saving,
			sound = false, -- the outcome plays its own sound
			onActivated = reordering.onDone,
		})
		width += 90 + 100 + 12
	else
		if props.onSeeAll then
			controls.SeeAll = e(TextLink, { text = "See all", width = 70, layoutOrder = 1, onActivated = props.onSeeAll })
			width += 76
		end
		if props.onAdd then
			controls.Add = pillControl(props.addLabel or "Add items", 132, 2, {
				icon = "add_circle",
				iconSize = 17,
				disabled = owner ~= nil and owner.busy,
				onActivated = props.onAdd,
			})
			width += 138
		end
		if owner then
			controls.Menu = e(MenuControl, { disabled = owner.busy, onMenu = owner.onMenu, layoutOrder = 3 })
			local count = 4
			if owner.onReorder then
				controls.Reorder = roundControl("swap_horiz", owner.busy, 4, owner.onReorder)
				count += 1
			end
			controls.Up = roundControl("expand_less", owner.first or owner.busy, 5, function()
				owner.onMove(-1)
			end)
			controls.Down = roundControl("expand_more", owner.last or owner.busy, 6, function()
				owner.onMove(1)
			end)
			controls.Remove = e(RemoveControl, { disabled = owner.busy, layoutOrder = 7, onConfirm = owner.onRemove })
			width += count * (CONTROL + 6)
		end
	end
	local height = if owner then OWNER_HEADING else 24
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(height)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
	}, {
		Title = e("Frame", {
			Size = UDim2.new(1, -skin.px(width + 8), 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, skin.px(10)),
			}),
			Text = e(ShadowText, { text = props.text, style = { size = 18, weight = 900 }, shadow = false, layoutOrder = 1 }),
			-- Your own: what the row is, at a glance.
			Sub = if owner
				then e(ShadowText, {
					text = if reordering then "Reordering: move them with the arrows" else owner.sub,
					style = Tokens.type.meta,
					transparency = if reordering then 0 else Tokens.alpha.textDim,
					color = if reordering then Tokens.color.accentText else nil,
					shadow = false,
					layoutOrder = 2,
				})
				else nil,
		}),
		Controls = e("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, skin.px(width), 1, 0),
			BackgroundTransparency = 1,
		}, controls),
	})
end

-- Add row, at the bottom of your own store (its menu opens from it).
local function AddRowButton(props: { disabled: boolean, layoutOrder: number, onOpen: (anchor: GuiObject) -> () })
	local skin = useSkin()
	local ref = React.useRef(nil :: Frame?)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(Tokens.size.ctaHeight)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Anchor = e("Frame", {
			Size = UDim2.fromOffset(skin.px(170), skin.px(Tokens.size.ctaHeight)),
			BackgroundTransparency = 1,
			ref = ref,
		}, {
			Button = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				width = 170,
				icon = "add_circle",
				iconSize = 19,
				label = "Add row",
				disabled = props.disabled,
				sound = false, -- the menu plays its own sound
				onActivated = function()
					if ref.current then
						props.onOpen(ref.current)
					end
				end,
			}),
		}),
	})
end

-- Every list, loaded (and re-rendered as pages arrive). The personal lists
-- reload when the player's own list changes.
local function useStoreLists(look: any, sorts: { string })
	local _version, setVersion = React.useState(0)
	local keys = {}
	for _, sort in sorts do
		local field = PERSONAL[sort]
		keys[sort] = if field then table.concat(look[field] or {}, ",") else ""
	end
	local signature = table.concat(sorts, "|")
	for _, sort in sorts do
		signature ..= "|" .. keys[sort]
	end
	React.useEffect(function()
		local function loadAll()
			for _, sort in sorts do
				StoresClient.load(sort, keys[sort])
			end
		end
		local connection = StoresClient.changed:Connect(function()
			loadAll() -- again if the lists were reset
			setVersion(function(v: number)
				return v + 1
			end)
		end)
		loadAll()
		return function()
			connection:Disconnect()
		end
	end, { signature })
end

-- The store a search names (a code, or an exact name), after a pause.
local function useStoreSearch(query: string): (StoresClient.Page?, string?, boolean)
	local trimmed = string.match(query, "^%s*(.-)%s*$") or ""
	local state, setState = React.useState(nil :: { text: string, page: StoresClient.Page?, error: string? }?)
	React.useEffect(function()
		if #trimmed < 3 then
			return nil
		end
		local alive = true
		local thread = task.delay(SEARCH_DELAY, function()
			local page, err = StoresClient.find(trimmed)
			if alive then
				setState({ text = trimmed, page = page, error = err })
			end
		end)
		return function()
			alive = false
			task.cancel(thread)
		end
	end, { trimmed })
	if #trimmed < 3 or not state or state.text ~= trimmed then
		return nil, nil, #trimmed >= 3
	end
	return state.page, state.error, false
end

local function cardFromPage(page: StoresClient.Page): StoresClient.Card
	return {
		code = page.code,
		name = page.name,
		by = page.by,
		mine = page.mine,
		published = page.published,
		hidden = page.hidden,
		visits = page.visits,
		favourites = page.favourites,
		itemCount = #page.items,
		preview = table.move(page.items, 1, math.min(#page.items, 4), 1, {}),
	}
end

local function StoresScreen(props: { nav: any, look: any })
	local skin = useSkin()
	local look = props.look
	local storedSort, setSort = useSessionState("stores.sort", "")
	local sort = if EMPTY[storedSort] then storedSort else "" -- "" = home
	local query, setQuery = useSessionState("stores.query", "")
	local searching = string.match(query, "%S") ~= nil

	local sorts = {}
	for _, entry in StoresClient.SORTS do
		table.insert(sorts, entry.id)
	end
	useStoreLists(look, if sort ~= "" and not searching then { sort } else sorts)
	local found, findError, finding = useStoreSearch(query)

	local function open(card: StoresClient.Card)
		props.nav.push({ kind = "store", id = card.code, label = card.name })
	end
	local function storeCard(card: StoresClient.Card, order: number)
		return e(StoreCard, {
			card = card,
			favourite = look.isStoreFavourite(card.code),
			layoutOrder = order,
			onActivated = function()
				open(card)
			end,
		})
	end

	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(22)),
		}),
	}
	for index, entry in StoresClient.SORTS do
		tabs["Tab" .. index] = e(TextTab, {
			label = entry.label,
			active = entry.id == sort,
			layoutOrder = index,
			onActivated = function()
				-- The chosen tab again goes back home.
				setSort(if entry.id == sort then "" else entry.id)
			end,
		})
	end

	local tabsHeight = skin.px(Tokens.size.textTabHeight)
	local searchWidth = skin.px(SEARCH_WIDTH)
	local bodyTop = tabsHeight + skin.px(14)
	local body: any
	local message: string? = nil

	if searching then
		-- The loaded stores whose names match, and the store the search names.
		local needle = string.lower(string.match(query, "^%s*(.-)%s*$") or "")
		local cards: { [string]: any } = {}
		local count = 0
		local listed: { [string]: boolean } = {}
		if found then
			count += 1
			listed[found.code] = true
			cards["Found"] = storeCard(cardFromPage(found), count)
		end
		for _, id in sorts do
			for _, card in StoresClient.get(id).cards do
				if not listed[card.code] and string.find(string.lower(card.name), needle, 1, true) then
					listed[card.code] = true
					count += 1
					cards["Store" .. card.code] = storeCard(card, count)
				end
			end
		end
		if finding then
			count += 1
			cards.Loading = e(Parts.LoadingCard, { layoutOrder = count })
		elseif count == 0 then
			message = if findError == "busy" then "Too many lookups. Try again in a moment" else "No store has that name or code"
		end
		body = e(Parts.CardGrid, {
			columns = 6,
			extraHeight = 40,
			count = count,
			position = UDim2.fromOffset(0, bodyTop),
			size = UDim2.new(1, 0, 1, -bodyTop),
		}, cards)
	elseif sort ~= "" then
		local list = StoresClient.get(sort)
		local cards: { [string]: any } = {}
		local count = 0
		if sort == "mine" and #look.myStores < StoresConfig.maxStores then
			count += 1
			cards.Create = e(CreateCard, { layoutOrder = count })
		end
		for _, card in list.cards do
			count += 1
			cards["Store" .. card.code] = storeCard(card, count)
		end
		if list.loading then
			count += 1
			cards.Loading = e(Parts.LoadingCard, { layoutOrder = count })
		elseif count == 0 then
			message = if list.error == "busy" then "Too many requests. Try again in a moment"
				elseif list.error then "Couldn't load stores. Try again"
				else EMPTY[sort]
		end
		body = e(Parts.CardGrid, {
			columns = 6,
			extraHeight = 40,
			count = count,
			position = UDim2.fromOffset(0, bodyTop),
			size = UDim2.new(1, 0, 1, -bodyTop),
			scrollKey = "stores|" .. sort,
			onNearEnd = function()
				StoresClient.more(sort)
			end,
		}, cards)
	else
		-- Home: a carousel per list that has stores (or is still loading).
		local rows: { Parts.HomeRow } = {}
		local anyLoading = false
		for index, entry in StoresClient.SORTS do
			local list = StoresClient.get(entry.id)
			local cells: { [string]: any } = {}
			local count = 0
			if entry.id == "mine" and #look.myStores < StoresConfig.maxStores then
				count += 1
				cells.Create = e(CreateCard, { layoutOrder = count })
			end
			for _, card in list.cards do
				if count >= ROW_CARDS then
					break
				end
				count += 1
				cells["Store" .. card.code] = storeCard(card, count)
			end
			if count == 0 and list.loading then
				anyLoading = true
				count = 1
				cells.Loading = e(Parts.LoadingCard, { layoutOrder = 1 })
			end
			if count > 0 then
				table.insert(rows, {
					key = entry.id,
					title = entry.label,
					onSeeAll = function()
						setSort(entry.id)
					end,
					cardWidth = STORE_CARD,
					count = count,
					cells = cells,
				})
			end
		end
		if #rows == 0 and not anyLoading then
			message = "No one has published a store yet"
		end
		body = e(Parts.HomeRows, {
			rows = rows,
			position = UDim2.fromOffset(0, bodyTop),
			size = UDim2.new(1, 0, 1, -bodyTop),
		})
	end

	return e("Frame", {
		Name = "StoresScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Top = e("Frame", {
			Size = UDim2.new(1, 0, 0, tabsHeight),
			BackgroundTransparency = 1,
		}, {
			Tabs = e("Frame", {
				Size = UDim2.new(1, -(searchWidth + skin.px(16)), 1, 0),
				BackgroundTransparency = 1,
			}, tabs),
			Rule = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, -(searchWidth + skin.px(16)), 0, skin.stroke(1)),
				BackgroundColor3 = Tokens.color.white,
				BackgroundTransparency = 0.9,
				BorderSizePixel = 0,
			}),
			Search = e(SearchBox, {
				text = query,
				placeholder = "Search or enter store code",
				onChange = setQuery,
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.fromScale(1, 0.5),
				size = UDim2.fromOffset(searchWidth, skin.px(40)),
			}),
		}),
		Body = body,
		Message = if message then e(Message, { text = message, position = UDim2.fromOffset(0, bodyTop) }) else nil,
	})
end

-- The store page's data: cached, or fetched (and again after a reset).
local function useStorePage(code: string): (StoresClient.Page?, string?)
	local state, setState = React.useState(function()
		local cached = StoresClient.cached(code)
		return if cached then { code = code, page = cached, error = nil } else nil
	end :: () -> { code: string, page: StoresClient.Page?, error: string? }?)
	React.useEffect(function()
		local alive = true
		local loading = false
		local function load()
			if loading then
				return
			end
			local cached = StoresClient.cached(code)
			if cached then
				setState({ code = code, page = cached, error = nil })
				return
			end
			loading = true
			task.spawn(function()
				local page, err = StoresClient.find(code)
				loading = false
				if alive then
					setState({ code = code, page = page, error = err })
				end
			end)
		end
		local connection = StoresClient.changed:Connect(load)
		load()
		return function()
			alive = false
			connection:Disconnect()
		end
	end, { code })
	if not state or state.code ~= code then
		return nil, nil
	end
	return state.page, state.error
end

-- Item cards with the card menu, one menu open at a time on a page.
local function useItemCards(look: any, nav: any, store: string)
	local hud = React.useContext(HudContext)
	local menuId, setMenuId = React.useState(nil :: number?)
	useBackInput(function()
		-- Stays mounted (hidden) under pushed pages; only act when showing.
		if nav.top and nav.top.kind ~= "store" and nav.top.kind ~= "storeSection" then
			return false
		end
		if menuId then
			Sounds.play("back")
			setMenuId(nil)
			return true
		end
		return false
	end)
	return function(id: number, order: number, fill: boolean?)
		local item = PlaceholderData.item(id)
		if not item then
			return nil
		end
		return e(Parts.ItemCard, {
			item = item,
			wearing = look.isWorn(id),
			inBasket = look.inBasket(id),
			favourite = look.isFavourite(id),
			fill = fill,
			layoutOrder = order,
			menu = {
				open = menuId == id,
				onToggle = function()
					setMenuId(if menuId == id then nil else id)
				end,
				onTry = function()
					setMenuId(nil)
					look.toggleWear(id)
				end,
				onBasket = function()
					look.toggleBasket(id)
				end,
				onBuy = function()
					-- The menu stays open so its Buy button can spin.
					hud.buy({ id }, nil, store)
				end,
				onView = function()
					setMenuId(nil)
					nav.push({ kind = "item", id = id, label = item.name })
				end,
				onStore = if #look.myStores > 0
					then function()
						setMenuId(nil)
						hud.addToStore({ kind = "item", id = id })
					end
					else nil,
			},
		})
	end
end

-- A Single row: one item (or outfit) at a time, with arrows. An item has
-- its picture, name, price, Try on and Basket; an outfit its pictures,
-- name, who shared it, Wear all items and View. Either's picture or name
-- opens its page.
local function Featured(props: { look: any, nav: any, items: { number }?, outfits: { CommunityOutfits.Card }?, layoutOrder: number })
	local skin = useSkin()
	local index, setIndex = React.useState(1)
	local count = if props.outfits then #props.outfits else #(props.items or {})
	if count == 0 then
		return nil
	end
	local at = ((index - 1) % count) + 1
	local height = skin.px(HERO_HEIGHT)
	local function step(delta: number)
		setIndex(((at - 1 + delta) % count) + 1)
	end

	local picture: any, pictureWidth: number, title: string, line: any, buttons: { [string]: any }, view: () -> ()
	if props.outfits then
		local card = props.outfits[at]
		local outfit = OutfitsScreen.sharedView(card)
		local wearing = OutfitsScreen.wearingExactly(props.look, outfit.items)
		local first = PlaceholderData.item(outfit.items[1])
		pictureWidth = math.floor(height * 1.6)
		title = card.name
		view = function()
			Sounds.play("press")
			props.nav.push({ kind = "outfit", id = { source = "Shared", index = card.code }, label = card.name })
		end
		local cells = OutfitsScreen.mosaic(outfit.items, "wide")
		picture = e(Parts.Thumb, {
			colour = Parts.swatch(if first then first.colour else ""),
			radius = 20,
			selected = wearing,
			caption = if next(cells) then nil else "outfit",
			size = UDim2.fromScale(1, 1),
		}, cells)
		line = e(ShadowText, {
			text = OutfitsScreen.communitySub(card),
			style = { size = 15, weight = 800 },
			transparency = Tokens.alpha.textSoft,
			shadow = false,
			layoutOrder = 3,
		})
		buttons = {
			Wear = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				width = 170,
				icon = "checkroom",
				iconSize = 18,
				label = if wearing then "Wearing" else "Wear all items",
				active = not wearing,
				disabled = #outfit.items == 0,
				sound = false, -- the look change plays its own sound
				layoutOrder = 1,
				onActivated = function()
					props.look.wearShared(card.code)
					-- Counted at once (the server counts others' wears).
					if not card.mine then
						CommunityOutfits.noteWear(card.code, CommunityOutfits.wears(card.code, card.wears))
					end
				end,
			}),
			View = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				width = 110,
				icon = "visibility",
				iconSize = 18,
				label = "View",
				layoutOrder = 2,
				sound = false, -- view plays it
				onActivated = view,
			}),
		}
	else
		local id = (props.items :: { number })[at]
		local item = PlaceholderData.item(id)
		if not item then
			return nil
		end
		local wearing = props.look.isWorn(id)
		local inBasket = props.look.inBasket(id)
		pictureWidth = height
		title = item.name
		view = function()
			Sounds.play("press")
			props.nav.push({ kind = "item", id = id, label = item.name })
		end
		picture = e(Parts.Thumb, {
			colour = Parts.swatch(item.colour),
			image = Parts.image(item),
			radius = 20,
			caption = string.lower(item.sub),
			size = UDim2.fromScale(1, 1),
		})
		line = e(Parts.PriceTag, { item = item, size = 18, layoutOrder = 3 })
		buttons = {
			Try = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				width = 130,
				icon = if wearing then "remove" else "checkroom",
				iconSize = 18,
				label = if wearing then "Take off" else "Try on",
				active = not wearing,
				sound = false, -- the look change plays its own sound
				layoutOrder = 1,
				onActivated = function()
					props.look.toggleWear(id)
				end,
			}),
			Basket = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				width = 140,
				icon = if inBasket then "remove_shopping_cart" else "add_shopping_cart",
				iconSize = 18,
				label = if inBasket then "In basket" else "Basket",
				sound = false, -- the look change plays its own sound
				layoutOrder = 2,
				onActivated = function()
					props.look.toggleBasket(id)
				end,
			}),
		}
	end
	buttons.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, skin.px(8)),
	})

	return e(Parts.Thumb, {
		colour = Parts.swatch("Orange"),
		radius = 20,
		size = UDim2.new(1, 0, 0, height),
		layoutOrder = props.layoutOrder,
	}, {
		Picture = e("TextButton", {
			Size = UDim2.fromOffset(pictureWidth, height),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			[React.Event.InputBegan] = Press.began(view),
			[React.Event.Activated] = Press.activated(view),
		}, {
			Thumb = picture,
		}),
		Info = e("Frame", {
			Position = UDim2.fromOffset(pictureWidth + skin.px(24), 0),
			Size = UDim2.new(1, -(pictureWidth + skin.px(24) + skin.px(24)), 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, skin.px(10)),
			}),
			Label = e(ShadowText, {
				text = "FEATURED · " .. at .. " / " .. count,
				style = { size = 12.5, weight = 800 },
				color = Tokens.color.accentText,
				shadow = false,
				layoutOrder = 1,
			}),
			Name = e("TextButton", {
				Size = UDim2.new(1, 0, 0, skin.textPx(28) + skin.px(4)),
				BackgroundTransparency = 1,
				Text = title,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(28),
				FontFace = Tokens.font(900),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				AutoButtonColor = false,
				LayoutOrder = 2,
				[React.Event.InputBegan] = Press.began(view),
				[React.Event.Activated] = Press.activated(view),
			}),
			Line = line,
			Actions = e("Frame", {
				Size = UDim2.new(1, 0, 0, skin.px(Tokens.size.ctaHeight)),
				BackgroundTransparency = 1,
				LayoutOrder = 4,
			}, buttons),
		}),
		Arrows = if count > 1
			then e("Frame", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -skin.px(14), 1, -skin.px(14)),
				Size = UDim2.fromOffset(skin.px(82), skin.px(38)),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(6)),
				}),
				Prev = e(PillButton, {
					variant = "round",
					size = 38,
					icon = "chevron_left",
					iconSize = 22,
					glowRadius = 0,
					sound = "tab",
					layoutOrder = 1,
					onActivated = function()
						step(-1)
					end,
				}),
				Next = e(PillButton, {
					variant = "round",
					size = 38,
					icon = "chevron_right",
					iconSize = 22,
					glowRadius = 0,
					sound = "tab",
					layoutOrder = 2,
					onActivated = function()
						step(1)
					end,
				}),
			})
			else nil,
	})
end

local function CollectionTile(props: { section: StoresClient.Section, colour: string, sub: string?, onActivated: () -> (), layoutOrder: number })
	local skin = useSkin()
	local interaction = useInteraction()
	local function open()
		Sounds.play("press")
		props.onActivated()
	end
	return e("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(open),
		[React.Event.Activated] = Press.activated(open),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
		[React.Event.MouseButton1Down] = interaction.onDown,
		[React.Event.MouseButton1Up] = interaction.onUp,
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Parts.swatch(props.colour),
			radius = 16,
			hovered = interaction.hovered,
			pressed = interaction.pressed,
			size = UDim2.fromScale(1, 1),
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, skin.px(14)),
				PaddingBottom = UDim.new(0, skin.px(12)),
			}),
			Text = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, skin.px(42)),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Bottom,
					Padding = UDim.new(0, skin.px(2)),
				}),
				Name = e(ShadowText, { text = props.section.name, style = { size = 17, weight = 900 }, layoutOrder = 1 }),
				Count = e(ShadowText, {
					text = props.sub or plural(#props.section.items, "item"),
					style = { size = 12.5, weight = 800 },
					transparency = 0.3,
					shadow = false,
					layoutOrder = 2,
				}),
			}),
		}),
	})
end

-- A search row's catalogue query (category "" = no search: not an items
-- search row).
local function searchQuery(row: StoresClient.Row): any
	local search = row.search or {}
	local active = row.content == "items" and row.source == "search" and type(search.category) == "string"
	return {
		category = if active then search.category else "",
		chip = search.chip,
		keyword = search.keyword or "",
		minPrice = search.minPrice,
		maxPrice = search.maxPrice,
		sort = search.sort,
		sortWindow = search.sortWindow,
		creator = search.creator or "",
		salesType = search.salesType,
		includeOffSale = search.includeOffSale,
	}
end

-- What a row shows: a manual row's own items / outfits, or what its search
-- finds (the catalogue, or Community outfits), up to its limit. Also
-- whether a search is still going, and how many there are in all.
local function useRowContent(row: StoresClient.Row): ({ number }, { any }, boolean, number)
	local results = useCatalogue(searchQuery(row))
	local filtered = useColourFilter(results, if row.content == "items" and row.source == "search" and row.search then row.search.colour or "" else "")
	local sort = if row.content == "outfits" and row.source == "search" and row.search then row.search.sort else nil
	local _version, setVersion = React.useState(0)
	React.useEffect(function()
		if not sort then
			return nil
		end
		local connection = CommunityOutfits.changed:Connect(function()
			CommunityOutfits.load(sort)
			setVersion(function(v: number)
				return v + 1
			end)
		end)
		CommunityOutfits.load(sort)
		return function()
			connection:Disconnect()
		end
	end, { sort or "" })

	local limit = math.max(1, row.limit)
	local function first(list: { any }): { any }
		return table.move(list, 1, math.min(#list, limit), 1, {})
	end
	if row.source == "manual" then
		local ids = row.items or {}
		local outfits = row.outfits or {}
		return first(ids), first(outfits), false, if row.content == "items" then #ids else #outfits
	end
	if row.content == "items" then
		local ids = {}
		for _, item in filtered.items or {} do
			table.insert(ids, item.id)
		end
		return first(ids), {}, filtered.status == "loading", #ids
	end
	local list = if sort then CommunityOutfits.get(sort) else { cards = {}, loading = false }
	return {}, first(list.cards), list.loading and #list.cards == 0, #list.cards
end

local function rowSub(row: StoresClient.Row): string
	local style = STYLE_LABELS[row.style] or row.style
	local source = if row.source == "search" then "Search" else "By hand"
	return `{source} · {style} · {row.limit}`
end

-- Reorder mode's arrows on a card: move it one place left or right.
local function MoveArrows(props: { first: boolean, last: boolean, onMove: (by: number) -> () })
	local skin = useSkin()
	local function arrow(icon: string, by: number, disabled: boolean, anchor: number): any
		return e(PillButton, {
			variant = "round",
			size = CONTROL,
			icon = icon,
			iconSize = 20,
			disabled = disabled,
			glowRadius = 0,
			sound = "tab",
			anchorPoint = Vector2.new(anchor, 0),
			position = UDim2.new(anchor, (if anchor == 0 then 1 else -1) * skin.px(6), 0, skin.px(6)),
			zIndex = 5,
			onActivated = function()
				props.onMove(by)
			end,
		})
	end
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, {
		Left = arrow("chevron_left", -1, props.first, 0),
		Right = arrow("chevron_right", 1, props.last, 1),
	})
end

-- One row of a store page, in its style.
local function StoreRow(props: {
	row: StoresClient.Row,
	page: StoresClient.Page,
	code: string,
	look: any,
	nav: any,
	position: number,
	rowCount: number,
	busy: boolean,
	width: number, -- local px across the page (for Grid / Hero cells)
	itemCard: (id: number, order: number, fill: boolean?) -> any,
	onAct: (action: string, payload: { [string]: any }, after: (() -> ())?, failed: (() -> ())?) -> (),
	onMenu: (row: StoresClient.Row, anchor: GuiObject) -> (),
	layoutOrder: number,
})
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local row, page = props.row, props.page
	local mine = page.mine
	local ids, outfits, loading, total = useRowContent(row)
	local manual = row.source == "manual"
	local isItems = row.content == "items"
	local style = row.style
	-- Reordering your own hand-filled row: its order so far (item ids, or
	-- outfit codes). Once saved it shows until the page has it.
	local reorder, setReorder = React.useState(nil :: { order: { any }, saving: boolean }?)
	React.useEffect(function()
		setReorder(function(current: any)
			return if current and current.saving then nil else current
		end)
		return nil
	end, { row } :: { any })

	-- A manual outfits row's cards by code (for its order).
	local byCode: { [string]: any } = {}
	for _, card in row.outfits or {} do
		byCode[card.code] = card
	end
	if reorder then
		local list = if reorder.saving then table.move(reorder.order, 1, math.min(#reorder.order, math.max(1, row.limit)), 1, {}) else reorder.order
		if isItems then
			ids = list
		else
			outfits = {}
			for _, code in list do
				if byCode[code] then
					table.insert(outfits, byCode[code])
				end
			end
		end
	end
	local editingOrder = reorder ~= nil and not reorder.saving

	-- What it shows, as cards to make (a key, and how to make one: at a
	-- place, filling its cell or square, its pictures in a shape).
	local entries: { { key: string, make: (order: number, fill: boolean?, shape: string?) -> any } } = {}
	if isItems then
		for _, id in ids do
			if PlaceholderData.item(id) then
				table.insert(entries, {
					key = "Item" .. id,
					make = function(order: number, fill: boolean?)
						return props.itemCard(id, order, fill)
					end,
				})
			end
		end
	else
		for _, card in outfits do
			table.insert(entries, {
				key = "Outfit" .. card.code,
				make = function(order: number, fill: boolean?, shape: string?)
					local view = OutfitsScreen.sharedView(card)
					return e(OutfitsScreen.OutfitCard, {
						outfit = view,
						sub = OutfitsScreen.communitySub(card),
						ring = OutfitsScreen.wearingExactly(props.look, view.items),
						fill = fill,
						shape = shape,
						layoutOrder = order,
						onActivated = function()
							Sounds.play("press")
							props.nav.push({ kind = "outfit", id = { source = "Shared", index = card.code }, label = card.name })
						end,
					})
				end,
			})
		end
	end
	local shownCount = #entries

	-- Visitors don't see empty rows.
	if not mine and shownCount == 0 and not loading then
		return nil
	end

	local function addHere()
		hud.pickForRow({
			code = props.code,
			row = row.id,
			kind = if isItems then "items" else "outfits",
			storeName = page.name,
			rowName = row.name,
			ids = row.items,
		})
	end
	local function seeAll()
		props.nav.push({ kind = "storeSection", id = { code = props.code, section = row.id }, label = row.name })
	end
	local function startReorder()
		local order = {}
		if isItems then
			order = table.clone(row.items or {})
		else
			for _, card in row.outfits or {} do
				table.insert(order, card.code)
			end
		end
		setReorder({ order = order, saving = false })
	end
	local function moveEntry(index: number, by: number)
		setReorder(function(current: any)
			if not current then
				return current
			end
			local order = table.clone(current.order)
			local target = index + by
			if target < 1 or target > #order then
				return current
			end
			order[index], order[target] = order[target], order[index]
			return { order = order, saving = false }
		end)
	end
	local function saveOrder()
		if not reorder then
			return
		end
		local payload: { [string]: any } = { code = props.code, row = row.id }
		if isItems then
			local keys = {}
			for _, id in reorder.order do
				local item = PlaceholderData.item(id)
				if item and item.targetId then
					table.insert(keys, item.kind .. ":" .. item.targetId)
				end
			end
			if #keys ~= #reorder.order then
				Sounds.play("error")
				return -- (an item we can't name: don't drop it)
			end
			payload.items = keys
		else
			local codes = table.clone(reorder.order)
			-- (Outfits no longer listed stay in the row, after the rest.)
			for _, code in row.outfitCodes or {} do
				if not table.find(codes, code) then
					table.insert(codes, code)
				end
			end
			payload.outfits = codes
		end
		setReorder({ order = reorder.order, saving = true })
		props.onAct(Network.Actions.Stores.SetRowItems, payload, nil, function()
			setReorder(function(current: any)
				return if current then { order = current.order, saving = false } else nil
			end)
		end)
	end

	local addLabel = if isItems then "Add items" else "Add outfits"
	local heading = e(RowHeading, {
		text = if row.name ~= "" then row.name else "Row",
		layoutOrder = 1,
		onSeeAll = if manual and total > shownCount and style ~= "tile" and not reorder then seeAll else nil,
		onAdd = if mine and manual then addHere else nil,
		addLabel = addLabel,
		owner = if mine
			then {
				sub = rowSub(row),
				first = props.position <= 1,
				last = props.position >= props.rowCount,
				busy = props.busy,
				onMenu = function(anchor: GuiObject)
					props.onMenu(row, anchor)
				end,
				onMove = function(by: number)
					props.onAct(Network.Actions.Stores.MoveRow, { code = props.code, row = row.id, by = by })
				end,
				onRemove = function()
					props.onAct(Network.Actions.Stores.RemoveRow, { code = props.code, row = row.id })
				end,
				onReorder = if manual and total >= 2 then startReorder else nil,
				reordering = if editingOrder or (reorder and reorder.saving)
					then {
						saving = reorder ~= nil and reorder.saving,
						onCancel = function()
							setReorder(nil)
						end,
						onDone = saveOrder,
					}
					else nil,
			}
			else nil,
	})
	local headingHeight = skin.px(if mine then OWNER_HEADING else 24)

	-- The first `max` entries as cards, keyed for React.
	local function cells(fill: boolean?, shape: string?, max: number?): ({ [string]: any }, number)
		local list: { [string]: any } = {}
		local count = math.min(#entries, max or math.huge)
		for index = 1, count do
			list[entries[index].key] = entries[index].make(index, fill, shape)
		end
		return list, count
	end

	local body: any
	local bodyHeight: number
	local gap = skin.px(12)
	local note: string? = nil
	if shownCount == 0 then
		note = if loading then "Loading…"
			elseif manual then `Empty: use {addLabel}`
			else "Nothing matches this search yet"
	end
	local cardWidth = if isItems then ITEM_CARD else STORE_CARD
	if note then
		bodyHeight = skin.px(24)
		body = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, bodyHeight),
			BackgroundTransparency = 1,
			Text = note,
			TextColor3 = Tokens.color.white,
			TextTransparency = Tokens.alpha.textDim,
			TextSize = skin.textPx(13.5),
			FontFace = Tokens.font(800),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
		})
	elseif editingOrder then
		-- Reordering: all of it in a line (whatever its style), each with
		-- arrows.
		local list: { [string]: any } = {}
		for index, entry in entries do
			list[entry.key] = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				LayoutOrder = index,
			}, {
				Card = entry.make(index),
				Move = e(MoveArrows, {
					first = index == 1,
					last = index == #entries,
					onMove = function(by: number)
						moveEntry(index, by)
					end,
				}),
			})
		end
		bodyHeight = Parts.cardRowHeight(skin, cardWidth)
		body = e(Parts.CardRow, { cardWidth = cardWidth, count = #entries, layoutOrder = 2 }, list)
	elseif style == "single" then
		bodyHeight = skin.px(HERO_HEIGHT)
		body = e(Featured, {
			look = props.look,
			nav = props.nav,
			items = if isItems then ids else nil,
			outfits = if isItems then nil else outfits,
			layoutOrder = 2,
		})
	elseif style == "tile" then
		bodyHeight = skin.px(TILE_HEIGHT)
		body = e("Frame", {
			Size = UDim2.new(1, 0, 0, bodyHeight),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, {
			Tile = e("Frame", {
				Size = UDim2.new(1 / 3, -skin.px(8), 1, 0),
				BackgroundTransparency = 1,
			}, {
				Tile = e(CollectionTile, {
					section = { name = row.name, items = ids },
					colour = TILE_COLOURS[(props.position - 1) % #TILE_COLOURS + 1],
					sub = if isItems then plural(total, "item") else plural(total, "outfit"),
					layoutOrder = 1,
					onActivated = seeAll,
				}),
			}),
		})
	elseif style == "grid" then
		local list, count = cells(true)
		local columns = GRID_COLUMNS
		local cellWidth = math.floor((props.width - gap * (columns - 1)) / columns)
		local cellHeight = cellWidth + skin.px(40)
		local lines = math.max(1, math.ceil(count / columns))
		bodyHeight = lines * cellHeight + (lines - 1) * gap
		list.Grid = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(cellWidth, cellHeight),
			CellPadding = UDim2.fromOffset(gap, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		body = e("Frame", {
			Size = UDim2.new(1, 0, 0, bodyHeight),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, list)
	elseif style == "hero" then
		-- 2 to 6 portrait cards across the row, no scrolling. With few, some
		-- are wide (two units): 1–2 all wide, 3–4 the first, 5–6 none. (One
		-- alone is as wide as half the row.) An outfit's pictures follow its
		-- cell: wide, or tall.
		local count = math.min(#entries, HERO_MAX)
		local units, wide = 0, {}
		for index = 1, count do
			wide[index] = count <= 2 or (count <= 4 and index == 1)
			units += if wide[index] then 2 else 1
		end
		local unit = (props.width - gap * math.max(0, count - 1)) / math.max(units, 4)
		bodyHeight = skin.px(HERO_THUMB) + skin.px(40)
		local list: { [string]: any } = {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, gap),
			}),
		}
		for index = 1, count do
			list["Cell" .. index] = e("Frame", {
				Size = UDim2.new(0, math.floor(unit * (if wide[index] then 2 else 1) + (if wide[index] then gap else 0)), 1, 0),
				BackgroundTransparency = 1,
				LayoutOrder = index,
			}, { Card = entries[index].make(index, true, if wide[index] then "wide" else "tall") })
		end
		body = e("Frame", {
			Size = UDim2.new(1, 0, 0, bodyHeight),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, list)
	elseif style == "wide" then
		local list, count = cells(true, "wide")
		bodyHeight = Parts.cardRowHeight(skin, WIDE_CARD, 40, WIDE_THUMB)
		body = e(Parts.CardRow, { cardWidth = WIDE_CARD, thumbHeight = WIDE_THUMB, count = count, layoutOrder = 2 }, list)
	else
		local list, count = cells()
		bodyHeight = Parts.cardRowHeight(skin, cardWidth)
		body = e(Parts.CardRow, { cardWidth = cardWidth, count = count, layoutOrder = 2 }, list)
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, headingHeight + skin.px(10) + bodyHeight),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(10)) }),
		Heading = heading,
		Body = body,
	})
end

local function StoreScreen(props: { nav: any, look: any, code: string })
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local look = props.look
	local code = props.code
	local page, problem = useStorePage(code)
	local itemCard = useItemCards(look, props.nav, code)
	local _reportedVersion, setReportedVersion = React.useState(0)
	-- Your own store: the action under way (its button spins) and why the
	-- last one failed.
	local working, setWorking = React.useState(nil :: string?)
	local ownerProblem, setOwnerProblem = React.useState(nil :: string?)
	-- The row menu, open from a button: Add row, or a row's settings.
	local menu, setMenu = React.useState(nil :: { mode: "add" | "edit", row: StoresClient.Row?, anchor: GuiObject }?)
	-- The row as the menu would make it (shown in its place, or at the
	-- bottom for a new one); kept after a save until the page reloads, so
	-- it doesn't flick back first.
	local preview, setPreview = React.useState(nil :: { row: StoresClient.Row, keep: boolean }?)
	React.useEffect(function()
		if preview and preview.keep then
			setPreview(nil)
		end
		return nil
	end, { page } :: { any })
	-- The page's size (Grid / Tall cells) and its rows' height (the scroll).
	local rootRef = React.useRef(nil :: Frame?)
	local rootSize = useLocalSize(rootRef)
	local contentHeight, setContentHeight = React.useState(0)

	-- Keep the breadcrumb in step with a rename.
	React.useEffect(function()
		local top = props.nav.top
		if page and top and top.kind == "store" and top.id == code and top.label ~= page.name then
			props.nav.replaceTop({ kind = top.kind, id = top.id, label = page.name })
		end
		return nil
	end, { page and page.name })

	local function act(action: string, payload: { [string]: any }, after: (() -> ())?, failed: (() -> ())?)
		if working then
			return
		end
		setWorking(action)
		setOwnerProblem(nil)
		task.spawn(function()
			local ok, _, err = StoresClient.act(action, payload)
			setWorking(nil)
			if ok then
				Sounds.play("confirm")
				if after then
					after()
				end
			else
				Sounds.play("error")
				setOwnerProblem(StoreDialogs.message(err, "store"))
				if failed then
					failed()
				end
			end
		end)
	end

	-- Someone else's published store: opening it is a visit.
	local visited = React.useRef(nil :: string?)
	React.useEffect(function()
		if page and page.published and not page.mine and visited.current ~= code then
			visited.current = code
			look.openStore(code)
		end
		return nil
	end, { page ~= nil, code } :: { any })

	if not page then
		return e("Frame", {
			Name = "StoreScreen",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ref = rootRef, -- (the same frame as the page's: measured from the start)
		}, {
			Waiting = if problem
				then e(Message, {
					text = if problem == "busy" then "Too many lookups. Try again in a moment" else "This store isn't available",
				})
				else e(Spinner, { size = 40, anchorPoint = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.4) }),
		})
	end

	local starred = look.isStoreFavourite(code)
	local favourites = math.max(0, page.favourites + (if starred ~= page.favourited then (if starred then 1 else -1) else 0))
	local byText = (if page.mine then "Yours" else "by @" .. page.by)
		.. (if page.hidden then " · Hidden after reports"
			elseif not page.published then " · Draft: only you can see it"
			else " · " .. plural(favourites, "favourite") .. " · " .. plural(page.visits, "visit"))

	local sections: { [string]: any } = {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(SECTION_GAP)),
		}),
		-- Keep See all clear of the scroll bar, as the other lists do.
		Inset = e("UIPadding", { PaddingRight = UDim.new(0, skin.px(8)) }),
	}
	local height = 0
	local shown = 0
	local function add(key: string, element: any, sectionHeight: number)
		shown += 1
		height += sectionHeight
		sections[key] = element
	end

	-- Header: the store's picture, name and counts; Favourite, Share, Report.
	local headerHeight = skin.px(72)
	local buttons = 0
	local actions: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(8)),
		}),
	}
	if page.published and not page.hidden then
		buttons += 150 + 120 + 16
		actions.Favourite = e(PillButton, {
			variant = "pill",
			size = 44,
			width = 150,
			icon = "star",
			iconSize = 21,
			iconColor = if starred then Tokens.color.accentText else nil,
			label = if starred then "Favourited" else "Favourite",
			glowRadius = 0,
			sound = if starred then "back" else "confirm",
			layoutOrder = 1,
			onActivated = function()
				look.toggleStoreFavourite(code)
			end,
		})
		actions.Share = e(PillButton, {
			variant = "pill",
			size = 44,
			width = 120,
			icon = "ios_share",
			iconSize = 21,
			label = "Share",
			glowRadius = 0,
			sound = false, -- the dialog plays its own sound
			layoutOrder = 2,
			onActivated = function()
				hud.share(code, "store", page.name)
				look.shareStore(code)
			end,
		})
		if not page.mine then
			buttons += 170 + 8
			actions.Report = e("Frame", {
				Size = UDim2.fromOffset(skin.px(170), skin.px(Tokens.size.ctaHeight)),
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, {
				Button = e(ConfirmButton, {
					label = if reported[code] then "Reported" else "Report",
					icon = "flag",
					armedLabel = "Tap again",
					disabled = reported[code] == true,
					onConfirm = function()
						Sounds.play("confirm")
						reported[code] = true
						look.reportStore(code)
						setReportedVersion(function(v: number)
							return v + 1
						end)
					end,
				}),
			})
		end
	end
	add("Header", e("Frame", {
		Size = UDim2.new(1, 0, 0, headerHeight),
		BackgroundTransparency = 1,
		LayoutOrder = -2,
	}, {
		Logo = e(Parts.Thumb, {
			colour = Tokens.color.white,
			radius = 18,
			size = UDim2.fromOffset(headerHeight, headerHeight),
		}, { Mosaic = e(React.Fragment, nil, OutfitsScreen.mosaic(page.items)) }),
		Text = e("Frame", {
			Position = UDim2.fromOffset(headerHeight + skin.px(12), 0),
			Size = UDim2.new(1, -(headerHeight + skin.px(12) + skin.px(buttons)), 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, skin.px(3)),
			}),
			-- Your own: edit the name in place (the pencil saves it).
			Name = if page.mine
				then e(OutfitsScreen.NameField, {
					name = page.name,
					editable = true,
					maxLength = StoresConfig.nameLength.max,
					size = 26,
					layoutOrder = 1,
					onRename = function(name: string)
						act(Network.Actions.Stores.Rename, { code = code, name = name })
					end,
				})
				else e("TextLabel", {
					Size = UDim2.new(1, 0, 0, skin.textPx(26) + skin.px(4)),
					BackgroundTransparency = 1,
					Text = page.name,
					TextColor3 = Tokens.color.white,
					TextSize = skin.textPx(26),
					FontFace = Tokens.font(900),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = 1,
				}),
			By = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(13.5) + skin.px(4)),
				BackgroundTransparency = 1,
				Text = byText,
				TextColor3 = Tokens.color.white,
				TextTransparency = 0.35,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
		}),
		Actions = e("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, skin.px(buttons), 1, 0),
			BackgroundTransparency = 1,
		}, actions),
	}), headerHeight)

	-- Your own store: where it stands, Publish / Unpublish and Delete.
	if page.mine then
		-- (Hand-picked items and outfits count; a search row is enough.)
		local count = #page.items + #page.outfits
		local searchRow = false
		for _, row in page.rows do
			if row.source == "search" then
				searchRow = true
			end
		end
		local ready = searchRow or count >= StoresConfig.minItems
		local status = if ownerProblem then ownerProblem
			elseif page.hidden then "Hidden after reports: only you can see it"
			elseif page.published then "Published: anyone can find it"
			elseif not ready then `Draft · {count} of {StoresConfig.minItems} items to publish. {DRAFT_HINT}`
			else "Draft: ready to publish"
		local barHeight = skin.px(Tokens.size.ctaHeight)
		local publishWidth = 160
		local deleteWidth = 170
		add("Owner", e("Frame", {
			Size = UDim2.new(1, 0, 0, barHeight),
			BackgroundTransparency = 1,
			LayoutOrder = -1,
		}, {
			Status = e("TextLabel", {
				Size = UDim2.new(1, -skin.px(publishWidth + deleteWidth + 24), 1, 0),
				BackgroundTransparency = 1,
				Text = status,
				TextColor3 = if ownerProblem then Tokens.color.accentText else Tokens.color.white,
				TextTransparency = if ownerProblem then 0 else Tokens.alpha.textSoft,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Buttons = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, skin.px(publishWidth + deleteWidth + 8), 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(8)),
				}),
				Publish = e(PillButton, {
					variant = "pill",
					size = Tokens.size.ctaHeight,
					width = publishWidth,
					icon = if page.published then "lock" else "storefront",
					iconSize = 19,
					label = if page.published then "Unpublish" else "Publish",
					active = not page.published,
					disabled = not page.published and (page.hidden or not ready),
					loading = working == Network.Actions.Stores.Publish or working == Network.Actions.Stores.Unpublish,
					sound = false, -- the outcome plays its own sound
					layoutOrder = 1,
					onActivated = function()
						act(if page.published then Network.Actions.Stores.Unpublish else Network.Actions.Stores.Publish, { code = code })
					end,
				}),
				Delete = e("Frame", {
					Size = UDim2.fromOffset(skin.px(deleteWidth), barHeight),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, {
					Button = e(ConfirmButton, {
						label = "Delete",
						icon = "delete",
						armedLabel = "Tap again",
						disabled = working ~= nil,
						onConfirm = function()
							act(Network.Actions.Stores.Delete, { code = code }, function()
								props.nav.back()
							end)
						end,
					}),
				}),
			}),
		}), barHeight)
	end

	-- The rows, in the owner's order (PLAN 19.1). On your own store each
	-- shows even when empty, with its controls.
	local mine = page.mine
	local rowCount = #page.rows
	local rowWidth = math.max(0, rootSize.X - skin.px(8) - skin.px(8)) -- less the pad and the scroll bar
	for position, saved in page.rows do
		local row = if preview and preview.row.id == saved.id then preview.row else saved
		add("Row" .. row.id, e(StoreRow, {
			row = row,
			page = page,
			code = code,
			look = look,
			nav = props.nav,
			position = position,
			rowCount = rowCount,
			busy = working ~= nil,
			width = rowWidth,
			itemCard = itemCard,
			onAct = act,
			onMenu = function(target: StoresClient.Row, anchor: GuiObject)
				Sounds.play("open")
				setMenu({ mode = "edit", row = target, anchor = anchor })
			end,
			layoutOrder = position,
		}), 0)
	end

	-- A new row, as the menu has it so far.
	if preview and preview.row.id == "preview" then
		add("RowPreview", e(StoreRow, {
			row = preview.row,
			page = page,
			code = code,
			look = look,
			nav = props.nav,
			position = rowCount + 1,
			rowCount = rowCount + 1,
			busy = true,
			width = rowWidth,
			itemCard = itemCard,
			onAct = function() end,
			onMenu = function() end,
			layoutOrder = rowCount + 1,
		}), 0)
	end

	-- Your own: a new row at the bottom (its menu opens from the button).
	if mine then
		add("AddRow", e(AddRowButton, {
			disabled = rowCount >= StoresConfig.maxRows or working ~= nil,
			layoutOrder = rowCount + 2,
			onOpen = function(anchor: GuiObject)
				Sounds.play("open")
				setMenu({ mode = "add", row = nil, anchor = anchor })
			end,
		}), skin.px(Tokens.size.ctaHeight))
	end

	-- The scroll fits the rows as laid out (they size themselves), in local
	-- px (the layout reports screen px).
	local scale = if rootRef.current and rootSize.X > 0 then rootRef.current.AbsoluteSize.X / rootSize.X else 1
	sections.Layout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, skin.px(SECTION_GAP)),
		[React.Change.AbsoluteContentSize] = function(layout: UIListLayout)
			setContentHeight(layout.AbsoluteContentSize.Y)
		end,
	})

	return e("Frame", {
		Name = "StoreScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ref = rootRef,
	}, {
		Scroll = e("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, math.ceil(contentHeight / scale) + skin.px(4)),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = skin.px(8),
			ScrollBarImageColor3 = Tokens.color.accent,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		}, sections),
		Menu = if menu and rootRef.current
			then e(StoreRowMenu, {
				mode = menu.mode,
				row = menu.row,
				code = code,
				storeName = page.name,
				anchor = menu.anchor,
				root = rootRef.current,
				onPreview = function(row: StoresClient.Row?)
					setPreview(if row then { row = row, keep = false } else nil)
				end,
				onClose = function(saved: boolean)
					setMenu(nil)
					setPreview(function(current)
						return if saved and current then { row = current.row, keep = true } else nil
					end)
				end,
			})
			else nil,
	})
end

-- A store row as a grid of everything in it: See all, or a Tile.
local function SectionGrid(props: { nav: any, look: any, code: string, row: StoresClient.Row })
	local itemCard = useItemCards(props.look, props.nav, props.code)
	-- (Everything: a manual row's whole list, a search row's limit.)
	local all = table.clone(props.row)
	if all.source == "manual" then
		all.limit = math.max(#(all.items or {}), #(all.outfits or {}), 1)
	end
	local ids, outfits, loading = useRowContent(all)
	local cards: { [string]: any } = {}
	local count = 0
	for _, id in ids do
		local card = itemCard(id, count + 1)
		if card then
			count += 1
			cards["Item" .. id] = card
		end
	end
	for _, card in outfits do
		count += 1
		local view = OutfitsScreen.sharedView(card)
		cards["Outfit" .. card.code] = e(OutfitsScreen.OutfitCard, {
			outfit = view,
			sub = OutfitsScreen.communitySub(card),
			ring = OutfitsScreen.wearingExactly(props.look, view.items),
			layoutOrder = count,
			onActivated = function()
				Sounds.play("press")
				props.nav.push({ kind = "outfit", id = { source = "Shared", index = card.code }, label = card.name })
			end,
		})
	end
	if loading then
		count += 1
		cards.Loading = e(Parts.LoadingCard, { layoutOrder = count })
	end
	return e(Parts.CardGrid, {
		columns = 6,
		extraHeight = 40,
		count = count,
	}, cards)
end

local function SectionScreen(props: { nav: any, look: any, code: string, section: string })
	local page, problem = useStorePage(props.code)
	if not page and problem then
		return e(Message, { text = "This store isn't available" })
	elseif not page then
		return e(Spinner, { size = 40, anchorPoint = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.4) })
	end
	for _, row in page.rows do
		if row.id == props.section then
			return e(SectionGrid, { nav = props.nav, look = props.look, code = props.code, row = row })
		end
	end
	return e(Message, { text = "That row has gone" })
end

return {
	Root = StoresScreen,
	Store = StoreScreen,
	Section = SectionScreen,
}
