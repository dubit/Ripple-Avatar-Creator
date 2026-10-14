--!strict

--[[
	StoreRowMenu (no design: PLAN 19.1)

	A row's settings on your own store page, opening from the button that
	asked for it (Add row, or a row's menu button), like a context menu
	that's modal: the page behind dims and ignores taps, a tap outside or
	Back closes it.

	  Add row: Items or Outfits; filled By hand or By search; a style; how
	  many it shows; for a hand-filled row its order, for an outfits search
	  its Community sort; its name. An items search row then opens the
	  Catalogue in search setup mode (Hud) to choose its search.
	  A row's menu: the same, without content and fill (they stay as made),
	  plus Change search for an items search row.

	Props:
		mode: "add" | "edit"
		row: StoresClient.Row?      edit: the row
		code: string                the store
		storeName: string
		anchor: GuiObject           the button it opens from
		root: GuiObject             the screen it's drawn over
		onClose: () -> ()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local Sounds = require(views:WaitForChild("Sounds"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local useLocalSize = require(views:WaitForChild("hooks"):WaitForChild("useLocalSize"))
local useBackInput = require(views:WaitForChild("hooks"):WaitForChild("useBackInput"))
local PillButton = require(views:WaitForChild("components"):WaitForChild("PillButton"))
local GlassPanel = require(views:WaitForChild("components"):WaitForChild("GlassPanel"))
local ShadowText = require(views:WaitForChild("components"):WaitForChild("ShadowText"))
local Chip = require(views:WaitForChild("components"):WaitForChild("Chip"))
local StoresClient = require(views:WaitForChild("catalogue"):WaitForChild("StoresClient"))
local HudContext = require(views:WaitForChild("HudContext"))
local StoreDialogs = require(script.Parent:WaitForChild("StoreDialogs"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local StoresConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoresConfig"))

local e = React.createElement

local WIDTH = 380
local PAD = 16
local LABEL = 18
local GAP = 10

type Choice = { id: string, label: string }

local CONTENTS: { Choice } = { { id = "items", label = "Items" }, { id = "outfits", label = "Outfits" } }
local SOURCES: { Choice } = { { id = "manual", label = "By hand" }, { id = "search", label = "By search" } }
local ITEM_STYLES: { Choice } = {
	{ id = "square", label = "Square" },
	{ id = "wide", label = "Wide" },
	{ id = "tall", label = "Tall" },
	{ id = "single", label = "Single" },
	{ id = "grid", label = "Grid" },
	{ id = "tile", label = "Tile" },
}
local OUTFIT_STYLES: { Choice } = {
	{ id = "square", label = "Square" },
	{ id = "grid", label = "Grid" },
	{ id = "tile", label = "Tile" },
}
local ORDERS: { Choice } = {
	{ id = "added", label = "As added" },
	{ id = "newest", label = "Newest first" },
	{ id = "bestselling", label = "Bestselling" },
}
local OUTFIT_SORTS: { Choice } = {
	{ id = "popular", label = "Popular" },
	{ id = "trending", label = "Trending" },
	{ id = "newest", label = "Newest" },
}
local LIMITS = { 1, 4, 10, 20, 30, 60 }

-- A labelled line of chips (`lines` chip rows tall).
local function ChipLine(props: { label: string, choices: { Choice }, value: string, lines: number, onPick: (id: string) -> (), layoutOrder: number })
	local skin = useSkin()
	local chips: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(6)),
			Wraps = true,
		}),
	}
	for index, choice in props.choices do
		chips["Chip" .. choice.id] = e(Chip, {
			label = choice.label,
			active = props.value == choice.id,
			layoutOrder = index,
			onActivated = function()
				props.onPick(choice.id)
			end,
		})
	end
	local chipsHeight = props.lines * skin.px(Tokens.size.chipHeight) + (props.lines - 1) * skin.px(6)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(LABEL) + skin.px(4) + chipsHeight),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Label = e(ShadowText, { text = props.label, style = Tokens.type.meta, transparency = Tokens.alpha.textSoft, shadow = false }),
		Chips = e("Frame", {
			Position = UDim2.fromOffset(0, skin.px(LABEL) + skin.px(4)),
			Size = UDim2.new(1, 0, 0, chipsHeight),
			BackgroundTransparency = 1,
		}, chips),
	})
end

local function chipLineHeight(skin: any, lines: number): number
	return skin.px(LABEL) + skin.px(4) + lines * skin.px(Tokens.size.chipHeight) + (lines - 1) * skin.px(6)
end

local function RowMenu(props: {
	mode: "add" | "edit",
	row: StoresClient.Row?,
	code: string,
	storeName: string,
	anchor: GuiObject,
	root: GuiObject,
	onClose: () -> (),
})
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local row = props.row
	local editing = props.mode == "edit" and row ~= nil
	local content, setContent = React.useState(if row then row.content else "items")
	local source, setSource = React.useState(if row then row.source else "manual")
	local style, setStyle = React.useState(if row then row.style else "square")
	local limit, setLimit = React.useState(if row then row.limit else StoresConfig.rowLimit.default)
	local order, setOrder = React.useState(if row and row.order then row.order else "added")
	local sort, setSort = React.useState(if row and row.search and row.search.sort then row.search.sort else "popular")
	local name, setName = React.useState(if row then row.name else "")
	local waiting, setWaiting = React.useState(false)
	local problem, setProblem = React.useState(nil :: string?)
	local alive = React.useRef(true)
	React.useEffect(function()
		alive.current = true
		return function()
			alive.current = false
		end
	end, {})

	useBackInput(function()
		Sounds.play("back")
		props.onClose()
		return true
	end)

	local styles = if content == "outfits" then OUTFIT_STYLES else ITEM_STYLES
	local styleOk = false
	for _, choice in styles do
		if choice.id == style then
			styleOk = true
		end
	end
	if not styleOk then
		style = "square"
	end
	local outfitSearch = content == "outfits" and source == "search"
	local itemSearch = content == "items" and source == "search"

	local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
	local ready = not waiting and (utf8.len(trimmed) or 0) >= StoresConfig.rowNameLength.min

	local function finish(err: string?)
		if not alive.current then
			return
		end
		setWaiting(false)
		if err then
			Sounds.play("error")
			setProblem(StoreDialogs.message(err, "row"))
		else
			Sounds.play("confirm")
			props.onClose()
		end
	end

	local function submit()
		if not ready then
			return
		end
		setWaiting(true)
		setProblem(nil)
		local spec = { code = props.code, content = content, source = source, style = style, limit = limit, order = order, name = trimmed }
		task.spawn(function()
			if editing and row then
				spec.row = row.id
				local ok, _, err = StoresClient.act(Network.Actions.Stores.EditRow, spec)
				if ok and outfitSearch and (not row.search or row.search.sort ~= sort) then
					ok, _, err = StoresClient.act(Network.Actions.Stores.SetRowSearch, { code = props.code, row = row.id, content = content, search = { sort = sort } })
				end
				finish(if ok then nil else err)
				return
			end
			local ok, _, err, rowId = StoresClient.act(Network.Actions.Stores.AddRow, spec)
			if ok and rowId and outfitSearch then
				ok, _, err = StoresClient.act(Network.Actions.Stores.SetRowSearch, { code = props.code, row = rowId, content = content, search = { sort = sort } })
			end
			finish(if ok then nil else err)
			-- An items search row: choose its search now.
			if ok and rowId and itemSearch then
				hud.setupSearch({ code = props.code, row = rowId, storeName = props.storeName, rowName = trimmed, search = nil })
			end
		end)
	end

	-- Lines, top to bottom.
	local children: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(GAP)) }),
	}
	local height = 0
	local count = 0
	local function line(key: string, element: any, lineHeight: number)
		count += 1
		children[key] = element
		height += lineHeight
	end
	line("Title", e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(24)),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, {
		Text = e(ShadowText, { text = if editing then "Row settings" else "Add row", style = { size = 18, weight = 900 } }),
	}), skin.px(24))
	if not editing then
		line("Content", e(ChipLine, { label = "Shows", choices = CONTENTS, value = content, lines = 1, onPick = setContent, layoutOrder = 2 }), chipLineHeight(skin, 1))
		line("Source", e(ChipLine, { label = "Filled", choices = SOURCES, value = source, lines = 1, onPick = setSource, layoutOrder = 3 }), chipLineHeight(skin, 1))
	end
	local styleLines = if #styles > 3 then 2 else 1
	line("Style", e(ChipLine, { label = "Style", choices = styles, value = style, lines = styleLines, onPick = setStyle, layoutOrder = 4 }), chipLineHeight(skin, styleLines))
	local limitChoices: { Choice } = {}
	for _, n in LIMITS do
		table.insert(limitChoices, { id = tostring(n), label = tostring(n) })
	end
	line("Limit", e(ChipLine, {
		label = if style == "tall" then "How many (Tall shows up to 5)" else "How many it shows",
		choices = limitChoices,
		value = tostring(limit),
		lines = 1,
		onPick = function(id: string)
			setLimit(tonumber(id) or StoresConfig.rowLimit.default)
		end,
		layoutOrder = 5,
	}), chipLineHeight(skin, 1))
	if source == "manual" then
		line("Order", e(ChipLine, { label = "Order", choices = ORDERS, value = order, lines = 1, onPick = setOrder, layoutOrder = 6 }), chipLineHeight(skin, 1))
	elseif outfitSearch then
		line("Sort", e(ChipLine, { label = "Community outfits", choices = OUTFIT_SORTS, value = sort, lines = 1, onPick = setSort, layoutOrder = 6 }), chipLineHeight(skin, 1))
	end
	line("Name", e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(44)),
		BackgroundColor3 = Tokens.color.inputWell,
		BorderSizePixel = 0,
		LayoutOrder = 7,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(12)) }),
		Padding = e("UIPadding", { PaddingLeft = UDim.new(0, skin.px(12)), PaddingRight = UDim.new(0, skin.px(12)) }),
		Box = e("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			Text = name,
			PlaceholderText = if content == "outfits" then "Row name, e.g. Full looks" else "Row name, e.g. Pink hats",
			PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
			TextColor3 = Tokens.color.white,
			TextSize = skin.textPx(16),
			FontFace = Tokens.font(900),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			[React.Change.Text] = function(box: TextBox)
				local text = box.Text
				local cap = StoresConfig.rowNameLength.max
				if (utf8.len(text) or 0) > cap then
					text = string.sub(text, 1, (utf8.offset(text, cap + 1) or (#text + 1)) - 1)
					box.Text = text
				end
				setName(text)
			end,
			[React.Event.FocusLost] = function(_box: TextBox, enterPressed: boolean)
				if enterPressed then
					submit()
				end
			end,
		}),
	}), skin.px(44))
	if problem then
		line("Error", e("TextLabel", {
			Size = UDim2.new(1, 0, 0, skin.px(18)),
			BackgroundTransparency = 1,
			Text = problem,
			TextColor3 = Tokens.color.accentText,
			TextSize = skin.textPx(13),
			FontFace = Tokens.font(800),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 8,
		}), skin.px(18))
	end
	local buttons: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(8)),
		}),
		Cancel = e(PillButton, {
			variant = "pill",
			size = 38,
			width = 100,
			label = "Cancel",
			sound = "back",
			layoutOrder = 2,
			onActivated = props.onClose,
		}),
		Save = e(PillButton, {
			variant = "pill",
			size = 38,
			width = 110,
			label = if editing then "Save" else "Add",
			active = true,
			disabled = not ready and not waiting,
			loading = waiting,
			sound = false, -- the outcome plays its own sound
			layoutOrder = 3,
			onActivated = submit,
		}),
	}
	if editing and row and itemSearch then
		buttons.Search = e(PillButton, {
			variant = "pill",
			size = 38,
			width = 140,
			icon = "search",
			iconSize = 17,
			label = "Change search",
			sound = false,
			layoutOrder = 1,
			onActivated = function()
				props.onClose()
				hud.setupSearch({ code = props.code, row = row.id, storeName = props.storeName, rowName = row.name, search = row.search })
			end,
		})
	end
	line("Buttons", e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(38)),
		BackgroundTransparency = 1,
		LayoutOrder = 9,
	}, buttons), skin.px(38))

	local panelHeight = height + (count - 1) * skin.px(GAP) + skin.px(PAD) * 2
	local panelWidth = skin.px(WIDTH)

	-- Where: by the button. Below it if there's room, else above it (its
	-- right edge lined up with the button's); if it fits neither, beside
	-- it (right, else left), as level with the button as the screen allows.
	local rootRef = React.useRef(props.root)
	local rootSize = useLocalSize(rootRef)
	local scale = if rootSize.X > 0 then props.root.AbsoluteSize.X / rootSize.X else 1
	local anchorPos = (props.anchor.AbsolutePosition - props.root.AbsolutePosition) / scale
	local anchorSize = props.anchor.AbsoluteSize / scale
	local gap = skin.px(6)
	local maxX = math.max(0, rootSize.X - panelWidth)
	local maxY = math.max(0, rootSize.Y - panelHeight)
	local below = anchorPos.Y + anchorSize.Y + gap
	local above = anchorPos.Y - gap - panelHeight
	local x, y
	if below + panelHeight <= rootSize.Y or above >= 0 then
		x = math.clamp(anchorPos.X + anchorSize.X - panelWidth, 0, maxX)
		y = if below + panelHeight <= rootSize.Y then below else above
	else
		local right = anchorPos.X + anchorSize.X + gap
		x = if right + panelWidth <= rootSize.X then right else math.clamp(anchorPos.X - gap - panelWidth, 0, maxX)
		y = math.clamp(anchorPos.Y + anchorSize.Y / 2 - panelHeight / 2, 0, maxY)
	end

	return e("TextButton", {
		Name = "RowMenu",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Tokens.color.black,
		BackgroundTransparency = 0.55,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 20,
		-- A tap outside closes it (it's modal: nothing behind takes the tap).
		[React.Event.InputBegan] = Press.began(function()
			Sounds.play("back")
			props.onClose()
		end),
	}, {
		Panel = e("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(panelWidth, panelHeight),
			BackgroundTransparency = 1,
			ZIndex = 21,
		}, {
			-- Swallow taps on the panel so they don't close it.
			Block = e("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 0,
			}),
			Glass = e(GlassPanel, {
				variant = "bar",
				cornerRadius = 16,
				shadow = true,
			}, {
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, skin.px(PAD)),
					PaddingBottom = UDim.new(0, skin.px(PAD)),
					PaddingLeft = UDim.new(0, skin.px(PAD)),
					PaddingRight = UDim.new(0, skin.px(PAD)),
				}),
				Lines = e(React.Fragment, nil, children),
			}),
		}),
	})
end

return RowMenu
