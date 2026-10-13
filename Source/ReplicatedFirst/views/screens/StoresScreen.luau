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

	Store page (5c), one scrolling column:
	  · header: the mosaic, name, "by @owner · N favourites · N visits",
	    Favourite (the star; your own too) and Share (its code and QR: the
	    share dialog), and Report (twice) on someone else's store
	  · Featured: the store's first items, one at a time with arrows: Try
	    on, Basket, and its picture or name opens the item page
	  · Bestsellers and New arrivals carousels with See all
	  · Outfits: the store's Community outfits (their own pages)
	  · Collections: tiles that open their own grid
	Item cards have the card menu (Try · basket · Buy · View); buying from a
	store counts towards its Bestsellers. Opening someone's published store
	is a visit (once a day).

	StoresScreen.Root props: nav, look
	StoresScreen.Store props: nav, look, code
	StoresScreen.Section props: nav, look, code, section ("bestsellers" |
	"newArrivals" | a collection's name)
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
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Tokens.color.white,
			radius = 14,
			hovered = interaction.hovered,
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

-- "Title ........ See all"
local function SectionHeading(props: { text: string, onSeeAll: (() -> ())?, layoutOrder: number? })
	local skin = useSkin()
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(24)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
	}, {
		Title = e(ShadowText, { text = props.text, style = { size = 18, weight = 900 }, shadow = false }),
		SeeAll = if props.onSeeAll
			then e("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.fromOffset(skin.px(90), skin.px(24)),
				BackgroundTransparency = 1,
				Text = "See all",
				TextColor3 = Tokens.color.accentText,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Right,
				[React.Event.InputBegan] = Press.began(function()
					Sounds.play("press")
					;(props.onSeeAll :: () -> ())()
				end),
				[React.Event.Activated] = Press.activated(function()
					Sounds.play("press")
					;(props.onSeeAll :: () -> ())()
				end),
			})
			else nil,
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
		local rows: { [string]: any } = {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(20)),
			}),
		}
		local rowHeight = skin.px(24) + skin.px(10) + Parts.cardRowHeight(skin, STORE_CARD)
		local shown = 0
		local anyLoading = false
		for index, entry in StoresClient.SORTS do
			local list = StoresClient.get(entry.id)
			local cells: { [string]: any } = {}
			local count = 0
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
				shown += 1
				rows["Row" .. index] = e("Frame", {
					Size = UDim2.new(1, 0, 0, rowHeight),
					BackgroundTransparency = 1,
					LayoutOrder = index,
				}, {
					Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(10)) }),
					Heading = e(SectionHeading, {
						text = entry.label,
						layoutOrder = 1,
						onSeeAll = function()
							setSort(entry.id)
						end,
					}),
					Cards = e(Parts.CardRow, { cardWidth = STORE_CARD, count = count, layoutOrder = 2 }, cells),
				})
			end
		end
		if shown == 0 and not anyLoading then
			message = "No one has published a store yet"
		end
		body = e("ScrollingFrame", {
			Position = UDim2.fromOffset(0, bodyTop),
			Size = UDim2.new(1, 0, 1, -bodyTop),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, shown * rowHeight + math.max(0, shown - 1) * skin.px(20)),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = skin.px(8),
			ScrollBarImageColor3 = Tokens.color.accent,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		}, rows)
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
	return function(id: number, order: number)
		local item = PlaceholderData.item(id)
		if not item then
			return nil
		end
		return e(Parts.ItemCard, {
			item = item,
			wearing = look.isWorn(id),
			inBasket = look.inBasket(id),
			favourite = look.isFavourite(id),
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
			},
		})
	end
end

local function Featured(props: { look: any, nav: any, items: { number }, layoutOrder: number })
	local skin = useSkin()
	local index, setIndex = React.useState(1)
	local count = #props.items
	local at = ((index - 1) % count) + 1
	local id = props.items[at]
	local item = PlaceholderData.item(id)
	if not item then
		return nil
	end
	local wearing = props.look.isWorn(id)
	local inBasket = props.look.inBasket(id)
	local height = skin.px(HERO_HEIGHT)
	local function view()
		Sounds.play("press")
		props.nav.push({ kind = "item", id = id, label = item.name })
	end
	local function step(delta: number)
		setIndex(((at - 1 + delta) % count) + 1)
	end
	return e(Parts.Thumb, {
		colour = Parts.swatch("Orange"),
		radius = 20,
		size = UDim2.new(1, 0, 0, height),
		layoutOrder = props.layoutOrder,
	}, {
		Picture = e("TextButton", {
			Size = UDim2.fromOffset(height, height),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			[React.Event.InputBegan] = Press.began(view),
			[React.Event.Activated] = Press.activated(view),
		}, {
			Thumb = e(Parts.Thumb, {
				colour = Parts.swatch(item.colour),
				image = Parts.image(item),
				radius = 20,
				caption = string.lower(item.sub),
				size = UDim2.fromScale(1, 1),
			}),
		}),
		Info = e("Frame", {
			Position = UDim2.fromOffset(height + skin.px(24), 0),
			Size = UDim2.new(1, -(height + skin.px(24) + skin.px(24)), 1, 0),
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
				Text = item.name,
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
			Price = e(Parts.PriceTag, { item = item, size = 18, layoutOrder = 3 }),
			Actions = e("Frame", {
				Size = UDim2.new(1, 0, 0, skin.px(Tokens.size.ctaHeight)),
				BackgroundTransparency = 1,
				LayoutOrder = 4,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(8)),
				}),
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
			}),
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

local function CollectionTile(props: { section: StoresClient.Section, colour: string, onActivated: () -> (), layoutOrder: number })
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
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Parts.swatch(props.colour),
			radius = 16,
			hovered = interaction.hovered,
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
					text = plural(#props.section.items, "item"),
					style = { size = 12.5, weight = 800 },
					transparency = 0.3,
					shadow = false,
					layoutOrder = 2,
				}),
			}),
		}),
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
		LayoutOrder = 1,
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
			Name = e("TextLabel", {
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

	if #page.featured > 0 then
		add("Featured", e(Featured, { look = look, nav = props.nav, items = page.featured, layoutOrder = 2 }), skin.px(HERO_HEIGHT))
	end

	local rowHeight = skin.px(24) + skin.px(10) + Parts.cardRowHeight(skin, ITEM_CARD)
	local function itemRow(key: string, title: string, ids: { number }, section: string, order: number)
		if #ids == 0 then
			return
		end
		local cells: { [string]: any } = {}
		local count = 0
		for _, id in ids do
			if count >= StoresConfig.sectionSize then
				break
			end
			local card = itemCard(id, count + 1)
			if card then
				count += 1
				cells["Item" .. id] = card
			end
		end
		add(key, e("Frame", {
			Size = UDim2.new(1, 0, 0, rowHeight),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(10)) }),
			Heading = e(SectionHeading, {
				text = title,
				layoutOrder = 1,
				onSeeAll = if #ids > count
					then function()
						props.nav.push({ kind = "storeSection", id = { code = code, section = section }, label = title })
					end
					else nil,
			}),
			Cards = e(Parts.CardRow, { cardWidth = ITEM_CARD, count = count, layoutOrder = 2 }, cells),
		}), rowHeight)
	end
	itemRow("Bestsellers", "Bestsellers", page.bestsellers, "bestsellers", 3)
	itemRow("NewArrivals", "New arrivals", page.newArrivals, "newArrivals", 4)

	-- The store's outfits: Community outfits with their own pages.
	if #page.outfits > 0 then
		local outfitRow = skin.px(24) + skin.px(10) + Parts.cardRowHeight(skin, STORE_CARD)
		local cells: { [string]: any } = {}
		for index, card in page.outfits do
			local view = OutfitsScreen.sharedView(card)
			cells["Outfit" .. card.code] = e(OutfitsScreen.OutfitCard, {
				outfit = view,
				sub = OutfitsScreen.communitySub(card),
				ring = OutfitsScreen.wearingExactly(look, view.items),
				layoutOrder = index,
				onActivated = function()
					Sounds.play("press")
					props.nav.push({ kind = "outfit", id = { source = "Shared", index = card.code }, label = card.name })
				end,
			})
		end
		add("Outfits", e("Frame", {
			Size = UDim2.new(1, 0, 0, outfitRow),
			BackgroundTransparency = 1,
			LayoutOrder = 5,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(10)) }),
			Heading = e(SectionHeading, { text = "Outfits", layoutOrder = 1 }),
			Cards = e(Parts.CardRow, { cardWidth = STORE_CARD, count = #page.outfits, layoutOrder = 2 }, cells),
		}), outfitRow)
	end

	if #page.collections > 0 then
		local tiles: { [string]: any } = {
			Grid = e("UIGridLayout", {
				CellSize = UDim2.new(1 / 3, -skin.px(8), 0, skin.px(TILE_HEIGHT)),
				CellPadding = UDim2.fromOffset(skin.px(12), skin.px(12)),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}
		for index, section in page.collections do
			tiles["Tile" .. index] = e(CollectionTile, {
				section = section,
				colour = TILE_COLOURS[(index - 1) % #TILE_COLOURS + 1],
				layoutOrder = index,
				onActivated = function()
					props.nav.push({ kind = "storeSection", id = { code = code, section = section.name }, label = section.name })
				end,
			})
		end
		local rows = math.ceil(#page.collections / 3)
		local tilesHeight = rows * skin.px(TILE_HEIGHT) + (rows - 1) * skin.px(12)
		local blockHeight = skin.px(24) + skin.px(10) + tilesHeight
		add("Collections", e("Frame", {
			Size = UDim2.new(1, 0, 0, blockHeight),
			BackgroundTransparency = 1,
			LayoutOrder = 6,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(10)) }),
			Heading = e(SectionHeading, { text = "Collections", layoutOrder = 1 }),
			Tiles = e("Frame", {
				Size = UDim2.new(1, 0, 0, tilesHeight),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}, tiles),
		}), blockHeight)
	end

	if #page.items == 0 then
		add("Empty", e(Message, { text = if page.mine then "Add items to your store and they show here" else "Nothing here yet" }), skin.px(40))
	end

	return e("ScrollingFrame", {
		Name = "StoreScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, height + math.max(0, shown - 1) * skin.px(SECTION_GAP) + skin.px(4)),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = skin.px(8),
		ScrollBarImageColor3 = Tokens.color.accent,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
	}, sections)
end

-- A store's section as a grid: See all, or a collection's tile.
local function SectionScreen(props: { nav: any, look: any, code: string, section: string })
	local page, problem = useStorePage(props.code)
	local itemCard = useItemCards(props.look, props.nav, props.code)
	if not page and problem then
		return e(Message, { text = "This store isn't available" })
	elseif not page then
		return e(Spinner, { size = 40, anchorPoint = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.4) })
	end
	local ids: { number } = {}
	if props.section == "bestsellers" then
		ids = page.bestsellers
	elseif props.section == "newArrivals" then
		ids = page.newArrivals
	else
		for _, section in page.collections do
			if section.name == props.section then
				ids = section.items
			end
		end
	end
	local cards: { [string]: any } = {}
	local count = 0
	for _, id in ids do
		local card = itemCard(id, count + 1)
		if card then
			count += 1
			cards["Item" .. id] = card
		end
	end
	return e(Parts.CardGrid, {
		columns = 6,
		extraHeight = 40,
		count = count,
	}, cards)
end

return {
	Root = StoresScreen,
	Store = StoreScreen,
	Section = SectionScreen,
}
