--!strict

--[[
	CatalogueScreen (design frame 5b root)

	Category text tabs + search, sub-category chips, and a 6-column grid of
	real catalogue items (useCatalogue → CatalogueClient, Task 7). Tabs and
	chips come from CatalogueConfig; the search box is a catalogue keyword
	search within the current tab and chip.

	Tapping a card opens its menu over the thumb (Try · basket · Buy · View;
	one open at a time, Backspace closes it). The grid loads the next page as
	it scrolls near the end. The bottom bar takes a pasted marketplace link
	or id and opens that item, shows how many items are loaded, and holds the
	Sort / Colour / Price / Filters buttons; each opens its popover upward
	(CatalogueFilters). One overlay at a time: opening a popover closes a card
	menu and vice versa, and Backspace closes whichever is open first.

	Props: nav, look
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local Sounds = require(views:WaitForChild("Sounds"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local TextTab = require(components:WaitForChild("TextTab"))
local Chip = require(components:WaitForChild("Chip"))
local Icon = require(components:WaitForChild("Icon"))
local SearchBox = require(components:WaitForChild("SearchBox"))
local PillButton = require(components:WaitForChild("PillButton"))
local GlassPanel = require(components:WaitForChild("GlassPanel"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local useCatalogue = require(hooks:WaitForChild("useCatalogue"))
local useColourFilter = require(hooks:WaitForChild("useColourFilter"))
local useBackInput = require(hooks:WaitForChild("useBackInput"))
local useSessionState = require(hooks:WaitForChild("useSessionState"))
local useTextWidth = require(hooks:WaitForChild("useTextWidth"))
local CatalogueFilters = require(script.Parent:WaitForChild("CatalogueFilters"))
local HudContext = require(views:WaitForChild("HudContext"))
local CatalogueClient = require(views:WaitForChild("catalogue"):WaitForChild("CatalogueClient"))
local CatalogueConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CatalogueConfig"))

local e = React.createElement

local MESSAGES = {
	loading = "Loading…",
	error = "The catalogue isn't answering right now. Try again in a moment.",
	empty = "No items found",
	unavailable = "The colour filter isn't available here (thumbnails can't be read).",
}

local PASTE_MESSAGES = {
	looking = "Looking it up…",
	invalid = "That isn't a catalogue link or ID",
	notFound = "No avatar item with that link or ID",
}

local BAR_HEIGHT = 52

local function CatalogueScreen(props: { nav: any, look: any })
	local skin = useSkin()
	-- Where you were browsing survives closing the panel (session memory), as
	-- going into an item and back does; the grid keeps its scroll too.
	local category, setCategory = useSessionState("catalogue.category", CatalogueConfig.categories[1].name)
	local sub, setSub = useSessionState("catalogue.sub", "All")
	local query, setQuery = useSessionState("catalogue.query", "")
	local pasteFocused, setPasteFocused = React.useState(false)
	local filters, setFilters = useSessionState("catalogue.filters", CatalogueFilters.defaults)
	local popover, setPopover = React.useState(nil :: CatalogueFilters.Popover?)
	local results = useCatalogue({
		category = category,
		chip = if sub == "All" then nil else sub,
		keyword = query,
		minPrice = filters.minPrice,
		maxPrice = filters.maxPrice,
		sort = filters.sort,
		sortWindow = filters.sortWindow,
		creator = filters.creator,
		salesType = filters.salesType,
		includeOffSale = filters.includeOffSale,
	})
	-- Colour narrows the loaded results client-side (thumbnail colours).
	local catalogue = useColourFilter(results, filters.colour)
	local hud = React.useContext(HudContext)
	local menuId, setMenuId = React.useState(nil :: number?)

	local function setFilter(changes: { [string]: any })
		setFilters(function(current)
			local next = table.clone(current)
			for key, value in changes do
				if key == "price" then
					-- Bounds can be nil, which a plain merge would skip.
					next.minPrice, next.maxPrice = value.min, value.max
				else
					next[key] = value
				end
			end
			return next
		end)
	end

	local function togglePopover(which: CatalogueFilters.Popover)
		setMenuId(nil)
		setPopover(if popover == which then nil else which)
	end
	local paste, setPaste = React.useState("")
	local pasteStatus, setPasteStatus = React.useState(nil :: string?)
	local pasteGeneration = React.useRef(0)

	-- A new tab, chip or search closes any open card menu.
	React.useEffect(function()
		setMenuId(nil)
	end, { category, sub, query })

	useBackInput(function()
		-- Stays mounted (hidden) under pushed pages; only act when showing.
		if #props.nav.stack > 0 then
			return false
		elseif popover then
			Sounds.play("back")
			setPopover(nil)
			return true
		elseif menuId then
			Sounds.play("back")
			setMenuId(nil)
			return true
		end
		return false
	end)

	local function openItem(item: CatalogueClient.Item)
		props.nav.push({ kind = "item", id = item.id, label = item.name })
	end

	-- Paste a marketplace link or id: resolve it and open the item page.
	local function resolvePaste(text: string)
		pasteGeneration.current += 1
		local mine = pasteGeneration.current
		if string.match(text, "^%s*$") then
			setPasteStatus(nil)
			return
		end
		local targetId, kind = CatalogueClient.parseLink(text)
		if not targetId then
			setPasteStatus(PASTE_MESSAGES.invalid)
			return
		end
		setPasteStatus(PASTE_MESSAGES.looking)
		task.spawn(function()
			local ok, result = CatalogueClient.lookup(targetId, kind)
			if pasteGeneration.current ~= mine then
				return -- the field changed while we were looking
			end
			if ok then
				setPasteStatus(nil)
				setPaste("")
				openItem(result :: CatalogueClient.Item)
			else
				Sounds.play("error")
				setPasteStatus(PASTE_MESSAGES.notFound)
			end
		end)
	end

	-- "All" plus the tab's chips; a single-chip tab (Backgrounds) shows none.
	local subs = {}
	for _, entry in CatalogueConfig.categories do
		if entry.name == category and #entry.chips > 1 then
			subs = { "All" }
			for _, chip in entry.chips do
				table.insert(subs, chip.name)
			end
		end
	end

	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(20)),
		}),
	}
	for index, entry in CatalogueConfig.categories do
		tabs["Tab" .. index] = e(TextTab, {
			label = entry.name,
			active = entry.name == category,
			layoutOrder = index,
			onActivated = function()
				setCategory(entry.name)
				setSub("All")
			end,
		})
	end

	local chips: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(8)),
		}),
	}
	for index, name in subs do
		chips["Chip" .. index] = e(Chip, {
			label = name,
			active = name == sub,
			layoutOrder = index,
			onActivated = function()
				-- Tapping the active filter clears it (same as tapping All).
				setSub(if name == sub then "All" else name)
			end,
		})
	end

	local cards: { [string]: any } = {}
	local count = 0
	for _, item in catalogue.items do
		count += 1
		cards["Item" .. item.id] = e(Parts.ItemCard, {
			item = item,
			wearing = props.look.isWorn(item.id),
			inBasket = props.look.inBasket(item.id),
			favourite = props.look.isFavourite(item.id),
			layoutOrder = count,
			menu = {
				open = menuId == item.id,
				onToggle = function()
					setPopover(nil)
					setMenuId(if menuId == item.id then nil else item.id)
				end,
				onTry = function()
					setMenuId(nil)
					props.look.toggleWear(item.id)
				end,
				onBasket = function()
					props.look.toggleBasket(item.id)
				end,
				onBuy = function()
					-- The menu stays open so its Buy button can spin.
					hud.buy({ item.id })
				end,
				onView = function()
					setMenuId(nil)
					openItem(item)
				end,
			},
		})
	end
	-- Still finding matches (colour classification under way): a spinner card
	-- holds the next empty slot. With nothing yet, the message says so instead.
	if count > 0 and catalogue.status == "loading" then
		cards.Loading = e(Parts.LoadingCard, { layoutOrder = count + 1 })
	end
	local cells = count + (if cards.Loading then 1 else 0)
	local message = if count > 0 then nil
		elseif catalogue.status == "ready" then MESSAGES.empty
		elseif catalogue.status == "loading" and filters.colour ~= "" then `Finding {string.lower(filters.colour)} items…`
		else MESSAGES[catalogue.status]
	-- The catalogue doesn't report a total, so "60+" while more pages remain.
	local countLabel = if count == 0 then "" else `{count}{if catalogue.exhausted then "" else "+"} items`
	local countWidth = useTextWidth(if countLabel == "" then " " else countLabel, Tokens.font(800), skin.textPx(13.5))
	local sortLabel = CatalogueFilters.sortLabel(filters)
	local priceLabel = CatalogueFilters.priceLabel(filters)
	local filtersLabel = CatalogueFilters.filtersLabel(filters)
	local colourLabel = CatalogueFilters.colourLabel(filters)
	local filterButtonsWidth = CatalogueFilters.useButtonWidth(sortLabel)
		+ CatalogueFilters.useButtonWidth(colourLabel)
		+ CatalogueFilters.useButtonWidth(priceLabel)
		+ CatalogueFilters.useButtonWidth(filtersLabel)
		+ skin.px(8) * 4

	local searchWidth = skin.px(230)
	local tabsHeight = skin.px(Tokens.size.textTabHeight)
	local gridTop = if #subs > 0
		then tabsHeight + skin.px(Tokens.size.chipHeight) + skin.px(22)
		else tabsHeight + skin.px(12)
	local barSpace = skin.px(BAR_HEIGHT + 10)

	return e("Frame", {
		Name = "CatalogueScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		TopRow = e("Frame", {
			Size = UDim2.new(1, 0, 0, tabsHeight),
			BackgroundTransparency = 1,
		}, {
			Tabs = e("ScrollingFrame", {
				Size = UDim2.new(1, -(searchWidth + skin.px(16)), 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollingDirection = Enum.ScrollingDirection.X,
				ScrollBarThickness = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				CanvasSize = UDim2.new(),
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
				placeholder = "Search catalogue",
				onChange = setQuery,
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.fromScale(1, 0.5),
				size = UDim2.fromOffset(searchWidth, skin.px(40)),
			}),
		}),
		Chips = if #subs == 0 then nil else e("Frame", {
			Position = UDim2.fromOffset(0, tabsHeight + skin.px(10)),
			Size = UDim2.new(1, 0, 0, skin.px(Tokens.size.chipHeight)),
			BackgroundTransparency = 1,
		}, chips),
		Grid = e(Parts.CardGrid, {
			columns = 6,
			extraHeight = 40,
			count = cells,
			position = UDim2.fromOffset(0, gridTop),
			size = UDim2.new(1, 0, 1, -(gridTop + barSpace)),
			onNearEnd = catalogue.loadMore,
			-- One remembered scroll per browse (tab / chip / search / filters).
			scrollKey = table.concat({ category, sub, query, filters.sort, filters.sortWindow, tostring(filters.minPrice), tostring(filters.maxPrice), filters.creator, filters.salesType, tostring(filters.includeOffSale), filters.colour }, "|"),
		}, cards),
		Bar = e(GlassPanel, {
			variant = "bar",
			cornerRadius = 16,
			anchorPoint = Vector2.new(0, 1),
			position = UDim2.fromScale(0, 1),
			size = UDim2.new(1, 0, 0, skin.px(BAR_HEIGHT)),
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, skin.px(7)),
				PaddingRight = UDim.new(0, skin.px(14)),
			}),
			Paste = e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromOffset(skin.px(320), skin.px(38)),
				BackgroundColor3 = Tokens.color.inputWell,
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				Stroke = e("UIStroke", { Color = Tokens.color.black, Thickness = skin.stroke(1) }),
				Icon = e(Icon, {
					name = "link",
					size = 19,
					transparency = 0.45,
					anchorPoint = Vector2.new(0, 0.5),
					position = UDim2.new(0, skin.px(14), 0.5, 0),
				}),
				Box = e("TextBox", {
					Position = UDim2.fromOffset(skin.px(40), 0),
					Size = UDim2.new(1, -skin.px(54), 1, 0),
					BackgroundTransparency = 1,
					ClearTextOnFocus = false,
					Text = paste,
					PlaceholderText = if pasteFocused then "" else "Paste item link or ID",
					PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
					TextColor3 = Tokens.color.white,
					TextSize = skin.textPx(Tokens.type.search.size),
					FontFace = Tokens.font(Tokens.type.search.weight),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					[React.Change.Text] = function(box: TextBox)
						if box.Text ~= paste then
							setPaste(box.Text)
							resolvePaste(box.Text)
						end
					end,
					[React.Event.Focused] = function()
						setPasteFocused(true)
					end,
					[React.Event.FocusLost] = function()
						setPasteFocused(false)
					end,
				}),
			}),
			Status = if pasteStatus
				then e("TextLabel", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, skin.px(334), 0.5, 0),
					Size = UDim2.new(1, -(skin.px(334 + 14) + countWidth + filterButtonsWidth + skin.px(8)), 1, 0),
					BackgroundTransparency = 1,
					Text = pasteStatus,
					TextColor3 = if pasteStatus == PASTE_MESSAGES.looking then Tokens.color.white else Tokens.color.accentText,
					TextTransparency = if pasteStatus == PASTE_MESSAGES.looking then Tokens.alpha.textDim else 0,
					TextSize = skin.textPx(13.5),
					FontFace = Tokens.font(800),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				})
				else nil,
			Right = e("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.new(0, countWidth + filterButtonsWidth, 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(8)),
				}),
				Count = e("TextLabel", {
					Size = UDim2.new(0, countWidth, 1, 0),
					BackgroundTransparency = 1,
					Text = countLabel,
					TextColor3 = Tokens.color.white,
					TextTransparency = Tokens.alpha.textDim,
					TextSize = skin.textPx(13.5),
					FontFace = Tokens.font(800),
					TextXAlignment = Enum.TextXAlignment.Right,
					LayoutOrder = 1,
				}),
				Sort = e(CatalogueFilters.FilterButton, {
					label = sortLabel,
					active = filters.sort ~= CatalogueConfig.sort,
					open = popover == "sort",
					layoutOrder = 2,
					onActivated = function()
						togglePopover("sort")
					end,
				}),
				Colour = e(CatalogueFilters.FilterButton, {
					label = colourLabel,
					active = filters.colour ~= "",
					open = popover == "colour",
					layoutOrder = 3,
					onActivated = function()
						togglePopover("colour")
					end,
				}),
				Price = e(CatalogueFilters.FilterButton, {
					label = priceLabel,
					active = filters.minPrice ~= nil or filters.maxPrice ~= nil,
					open = popover == "price",
					layoutOrder = 4,
					onActivated = function()
						togglePopover("price")
					end,
				}),
				Filters = e(CatalogueFilters.FilterButton, {
					label = filtersLabel,
					active = CatalogueFilters.activeCount(filters) > 0,
					open = popover == "filters",
					layoutOrder = 5,
					onActivated = function()
						togglePopover("filters")
					end,
				}),
			}),
		}),
		SortPopover = if popover == "sort"
			then e(CatalogueFilters.SortPopover, { filters = filters, set = setFilter, bottom = barSpace })
			else nil,
		PricePopover = if popover == "price"
			then e(CatalogueFilters.PricePopover, {
				filters = filters,
				set = setFilter,
				bottom = barSpace,
				countLabel = if countLabel == "" then "" else countLabel .. " match",
			})
			else nil,
		FiltersPopover = if popover == "filters"
			then e(CatalogueFilters.FiltersPopover, { filters = filters, set = setFilter, bottom = barSpace })
			else nil,
		ColourPopover = if popover == "colour"
			then e(CatalogueFilters.ColourPopover, {
				filters = filters,
				set = setFilter,
				bottom = barSpace,
				onPicked = function()
					setPopover(nil)
				end,
			})
			else nil,
		Message = if message
			then e("TextLabel", {
				Position = UDim2.fromOffset(0, gridTop),
				Size = UDim2.new(1, 0, 0, skin.px(120)),
				BackgroundTransparency = 1,
				Text = message,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(Tokens.type.bodyStrong.size),
				FontFace = Tokens.font(Tokens.type.bodyStrong.weight),
			})
			else nil,
	})
end

return CatalogueScreen
