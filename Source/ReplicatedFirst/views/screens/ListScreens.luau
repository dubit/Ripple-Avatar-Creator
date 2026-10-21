--!strict

--[[
	ListScreens (design frames 5f Basket / 5g Wearing, placeholder data)

	Basket: one row per item (Try on / Remove), a summary (items, already owned,
	total) with Buy all, Try on everything, Add what I'm wearing (the unowned
	worn items not already in it) and Remove all (press twice). Wearing: what's on the avatar
	(price or Owned, Basket toggle, Take off) with Buy all (the unowned ones),
	Add unowned to basket, Save as new outfit / Save over existing outfit (a
	picker over the rows), and Take everything off (press twice). Once the
	look is a saved outfit it offers Go to <outfit> instead of saving. Rows
	open the item page.

	Buy / Get and Buy all open Roblox's purchase prompt; Save as outfit saves
	the look to Outfits › Mine.

	ListScreens.Basket / ListScreens.Wearing props: nav, look
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useContentHeight = require(hooks:WaitForChild("useContentHeight"))
local PillButton = require(components:WaitForChild("PillButton"))
local ConfirmButton = require(components:WaitForChild("ConfirmButton"))
local GlassPanel = require(components:WaitForChild("GlassPanel"))
local ShadowText = require(components:WaitForChild("ShadowText"))
local Icon = require(components:WaitForChild("Icon"))
local Sounds = require(views:WaitForChild("Sounds"))
local useBackInput = require(hooks:WaitForChild("useBackInput"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))
local HudContext = require(views:WaitForChild("HudContext"))

local e = React.createElement

local SIDE_WIDTH = 250
local ROW_BUTTON = 84 -- design px per row button
-- Price + up to three buttons on the right of each row.
local ROW_TRAILING = 60 + ROW_BUTTON * 3 + 8 * 3

-- Buy (or Get, when free) for an item that isn't owned; nil when it is.
local function buyButton(item: any, order: number, hud: any)
	if item.owned then
		return nil
	end
	return e(PillButton, {
		variant = "pill",
		size = 32,
		width = ROW_BUTTON,
		label = if item.price == 0 then "Get" else "Buy",
		textStyle = Tokens.type.small,
		active = true,
		loading = hud.buying("item:" .. item.id),
		layoutOrder = order,
		onActivated = function()
			hud.buy({ item.id })
		end,
	})
end

local function smallButton(label: string, order: number, active: boolean?, onActivated: () -> ())
	return e(PillButton, {
		variant = "pill",
		size = 32,
		width = ROW_BUTTON,
		label = label,
		textStyle = Tokens.type.small,
		active = active,
		sound = false, -- row actions change the look, which plays its own sound
		layoutOrder = order,
		onActivated = onActivated,
	})
end

-- The rows, scrolling (sized to them: a narrow row is two lines tall), or a
-- message when there are none.
local function RowList(props: { rows: { [string]: any }, count: number, emptyText: string, fullWidth: boolean? })
	local skin = useSkin()
	local layoutRef, contentHeight = useContentHeight()
	local rows, count, emptyText, fullWidth = props.rows, props.count, props.emptyText, props.fullWidth
	local width = if fullWidth then UDim2.fromScale(1, 1) else UDim2.new(1, -skin.px(SIDE_WIDTH + 16), 1, 0)
	if count == 0 then
		return e("Frame", {
			Size = width,
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			Text = e(ShadowText, { text = emptyText, style = Tokens.type.cardTitle, transparency = Tokens.alpha.textDim, shadow = false }),
		})
	end
	rows.Layout = e("UIListLayout", { ref = layoutRef, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(8)) })
	-- Inset so row strokes at the edges aren't clipped by the ScrollingFrame.
	rows.Inset = e("UIPadding", {
		PaddingTop = UDim.new(0, skin.px(3)),
		PaddingBottom = UDim.new(0, skin.px(3)),
		PaddingLeft = UDim.new(0, skin.px(3)),
		PaddingRight = UDim.new(0, skin.px(8)),
	})
	return e("ScrollingFrame", {
		Size = width,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, math.max(contentHeight, count * (skin.px(64) + skin.px(8))) + skin.px(6)),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = skin.px(8),
		ScrollBarImageColor3 = Tokens.color.accent,
		-- Rows shrink to make room when the scroll bar shows (plus the padding
		-- above), so they never run under it.
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, rows)
end

local function summaryLine(skin, label: string, value: string, order: number, strong: boolean?)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.px(22)),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		Label = e(ShadowText, {
			text = label,
			style = if strong then Tokens.type.bodyStrong else Tokens.type.meta,
			transparency = if strong then 0 else Tokens.alpha.textSoft,
			shadow = false,
		}),
		Value = e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = value,
			TextColor3 = if strong then Tokens.color.accentText else Tokens.color.white,
			TextSize = skin.textPx(if strong then 16 else 14),
			FontFace = Tokens.font(900),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Top, -- line up with the label
		}),
	})
end

local function sidePanel(skin, title: string, lines: { any }, buttons: { any })
	local children: { [string]: any } = {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(14)),
			PaddingBottom = UDim.new(0, skin.px(14)),
			PaddingLeft = UDim.new(0, skin.px(14)),
			PaddingRight = UDim.new(0, skin.px(14)),
		}),
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(8)) }),
		Title = e(ShadowText, { text = title, style = Tokens.type.cardTitle, layoutOrder = 0 }),
	}
	for index, line in lines do
		children["Line" .. index] = line
	end
	for index, button in buttons do
		children["Button" .. index] = button
	end
	return e(GlassPanel, {
		variant = "light",
		cornerRadius = Tokens.radius.basketCard,
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.new(0, skin.px(SIDE_WIDTH), 1, 0),
	}, children)
end

local function wideButton(
	label: string,
	icon: string?,
	order: number,
	active: boolean?,
	onActivated: (() -> ())?,
	sound: any?,
	disabled: boolean?,
	loading: boolean?
)
	return e(PillButton, {
		variant = "pill",
		size = Tokens.size.ctaHeight,
		label = label,
		icon = icon,
		iconSize = 18,
		active = active,
		sound = sound,
		disabled = disabled,
		loading = loading,
		layoutOrder = order,
		onActivated = onActivated,
	})
end

-- After saving, the save button reads "Saved to Outfits" for a moment.
local SAVED_SECONDS = 1.5

-- Over the Wearing rows: pick which saved outfit to save over. A tap arms a
-- row ("Tap again to replace"); a second tap replaces that outfit's items
-- with what's worn. Back or the close button shuts it.
local function OutfitPicker(props: { look: any, onPicked: () -> (), onClose: () -> () })
	local skin = useSkin()
	local armed, setArmed = React.useState(nil :: number?)
	useBackInput(function()
		props.onClose()
		return true
	end)
	React.useEffect(function()
		if not armed then
			return nil
		end
		local thread = task.delay(3, function()
			setArmed(nil)
		end)
		return function()
			task.cancel(thread)
		end
	end, { armed })

	local rows: { [string]: any } = {}
	for index, outfit in props.look.outfits do
		local first = PlaceholderData.item(outfit.items[1])
		local isArmed = armed == outfit.id
		rows["Row" .. outfit.id] = e(Parts.ListRow, {
			title = outfit.name,
			subtitle = if isArmed then "Tap again to replace it with what you're wearing" else #outfit.items .. " items",
			colour = Parts.swatch(if first then first.colour else ""),
			image = if first then Parts.image(first) else nil,
			layoutOrder = index,
			trailingWidth = 40,
			trailing = {
				Mark = if isArmed then e(Icon, { name = "check_circle", size = 22, color = Tokens.color.accentText }) else nil,
			},
			onActivated = function()
				if isArmed then
					props.look.overwriteOutfit(outfit.id)
					props.onPicked()
				else
					Sounds.play("press")
					setArmed(outfit.id)
				end
			end,
		})
	end
	local count = #props.look.outfits
	local titleHeight = skin.px(40)
	return e(GlassPanel, {
		variant = "bar",
		cornerRadius = Tokens.radius.basketCard,
		size = UDim2.new(1, -skin.px(SIDE_WIDTH + 16), 1, 0),
		shadow = true,
		zIndex = 5,
	}, {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(12)),
			PaddingBottom = UDim.new(0, skin.px(12)),
			PaddingLeft = UDim.new(0, skin.px(14)),
			PaddingRight = UDim.new(0, skin.px(12)),
		}),
		Title = e(ShadowText, { text = "Save over which outfit?", style = Tokens.type.cardTitle }),
		Close = e(PillButton, {
			variant = "round",
			size = Tokens.size.small.size,
			icon = "close",
			iconSize = Tokens.size.small.icon,
			glowRadius = 0,
			sound = "back",
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.fromScale(1, 0),
			onActivated = props.onClose,
		}),
		List = e("Frame", {
			Position = UDim2.fromOffset(0, titleHeight),
			Size = UDim2.new(1, 0, 1, -titleHeight),
			BackgroundTransparency = 1,
		}, { Rows = e(RowList, { rows = rows, count = count, emptyText = "No saved outfits yet", fullWidth = true }) }),
	})
end

local function BasketScreen(props: { nav: any, look: any })
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local look = props.look
	local rows: { [string]: any } = {}
	local owned = 0
	-- Worn items that could go in: not owned, not already there.
	local wornToAdd = {}
	for _, id in look.worn do
		local item = PlaceholderData.item(id)
		if item and not item.owned and not look.inBasket(id) then
			table.insert(wornToAdd, id)
		end
	end
	for index, id in look.basket do
		local item = PlaceholderData.item(id)
		if item.owned then
			owned += 1
		end
		local wearing = look.isWorn(id)
		rows["Row" .. id] = e(Parts.ListRow, {
			title = item.name,
			subtitle = item.main .. " · " .. item.sub .. " · by " .. item.creator,
			colour = Parts.swatch(item.colour),
			image = Parts.image(item),
			layoutOrder = index,
			trailingWidth = ROW_TRAILING,
			trailing = {
				Price = e(Parts.PriceTag, { item = item, size = 14, layoutOrder = 1 }),
				Buy = buyButton(item, 2, hud),
				Try = smallButton(if wearing then "Wearing" else "Try on", 3, wearing, function()
					look.toggleWear(id)
				end),
				Remove = smallButton("Remove", 4, false, function()
					look.toggleBasket(id)
				end),
			},
			onActivated = function()
				props.nav.push({ kind = "item", id = id, label = item.name })
			end,
		})
	end

	return e("Frame", {
		Name = "BasketScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Rows = e(RowList, { rows = rows, count = #look.basket, emptyText = "Your basket is empty" }),
		Summary = sidePanel(skin, "Summary", {
			summaryLine(skin, "Items", tostring(#look.basket), 1),
			summaryLine(skin, "Already owned", tostring(owned), 2),
			summaryLine(skin, "Total", Tokens.robux(look.basketTotal), 3, true),
		}, {
			wideButton("Buy all", "shopping_basket", 10, true, function()
				hud.buy(look.basket, "basket")
			end, nil, #look.basket == owned, hud.buying("basket")),
			wideButton("Try on everything", "checkroom", 11, false, function()
				look.wearAll(look.basket)
			end, false, #look.basket == 0),
			wideButton("Add what I'm wearing", "add_shopping_cart", 12, false, function()
				look.addToBasket(wornToAdd)
			end, false, #wornToAdd == 0),
			e(ConfirmButton, {
				label = "Remove all",
				icon = "remove_shopping_cart",
				layoutOrder = 13,
				disabled = #look.basket == 0,
				onConfirm = look.clearBasket,
			}),
		}),
	})
end

local function WearingScreen(props: { nav: any, look: any })
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local look = props.look
	local picking, setPicking = React.useState(false)
	local justSaved, setJustSaved = React.useState(false)
	React.useEffect(function()
		if not justSaved then
			return nil
		end
		local thread = task.delay(SAVED_SECONDS, function()
			setJustSaved(false)
		end)
		return function()
			task.cancel(thread)
		end
	end, { justSaved })
	local current = look.currentOutfit
	local rows: { [string]: any } = {}
	local unowned, cost = 0, 0
	-- Unowned paid items first (dearest first), then free, then owned; the
	-- order put on breaks ties.
	local function rank(item): number
		return if item.owned then 3 elseif item.price > 0 then 1 else 2
	end
	local ordered = table.clone(look.worn)
	local putOn = {}
	for index, id in look.worn do
		putOn[id] = index
	end
	table.sort(ordered, function(a, b)
		local itemA, itemB = PlaceholderData.item(a), PlaceholderData.item(b)
		local rankA, rankB = rank(itemA), rank(itemB)
		if rankA ~= rankB then
			return rankA < rankB
		elseif rankA == 1 and itemA.price ~= itemB.price then
			return itemA.price > itemB.price
		end
		return putOn[a] < putOn[b]
	end)
	-- Body parts (from someone's look) show as one Body row.
	local bodyIds: { number } = {}
	local bodyItems = {}
	for _, id in ordered do
		local item = PlaceholderData.item(id)
		if Parts.isBodyPart(item) then
			table.insert(bodyIds, id)
			table.insert(bodyItems, item)
		end
	end
	local bodyShown = false
	for index, id in ordered do
		local item = PlaceholderData.item(id)
		if not item.owned then
			unowned += 1
			cost += item.price
		end
		if Parts.isBodyPart(item) then
			if bodyShown then
				continue
			end
			bodyShown = true
			local torso = item
			for _, part in bodyItems do
				if part.typeName == "Torso" then
					torso = part
				end
			end
			rows["Body"] = e(Parts.ListRow, {
				title = Parts.bodyName(bodyItems),
				subtitle = "Body · " .. #bodyItems .. " part" .. (if #bodyItems == 1 then "" else "s"),
				colour = Parts.swatch(torso.colour),
				image = Parts.image(torso),
				layoutOrder = index,
				trailingWidth = ROW_TRAILING,
				trailing = {
					TakeOff = smallButton("Take off", 4, false, function()
						look.takeOffMany(bodyIds)
					end),
				},
				onActivated = function()
					props.nav.push({ kind = "item", id = torso.id, label = torso.name })
				end,
			})
			continue
		end
		local inBasket = look.inBasket(id)
		rows["Row" .. id] = e(Parts.ListRow, {
			title = item.name,
			subtitle = item.main .. " · " .. item.sub,
			colour = Parts.swatch(item.colour),
			image = Parts.image(item),
			layoutOrder = index,
			trailingWidth = ROW_TRAILING,
			trailing = {
				Price = e(Parts.PriceTag, { item = item, size = 14, layoutOrder = 1 }),
				Buy = buyButton(item, 2, hud),
				Basket = if item.owned
					then nil
					else smallButton(if inBasket then "In basket" else "Basket", 3, inBasket, function()
						look.toggleBasket(id)
					end),
				TakeOff = smallButton("Take off", 4, false, function()
					look.toggleWear(id)
				end),
			},
			onActivated = function()
				props.nav.push({ kind = "item", id = id, label = item.name })
			end,
		})
	end

	return e("Frame", {
		Name = "WearingScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- (Hidden under the picker: glass shows what's behind it.)
		Rows = if picking then nil else e(RowList, { rows = rows, count = #look.worn - math.max(#bodyIds - 1, 0), emptyText = "You're not wearing anything" }),
		Picker = if picking
			then e(OutfitPicker, {
				look = look,
				onPicked = function()
					setPicking(false)
					setJustSaved(true)
				end,
				onClose = function()
					setPicking(false)
				end,
			})
			else nil,
		Summary = sidePanel(skin, "Wearing", {
			summaryLine(skin, "Items", tostring(#look.worn), 1),
			summaryLine(skin, "Not owned", unowned .. " · " .. (if cost > 0 then Tokens.robux(cost) else "Free"), 2),
		}, {
			wideButton("Buy all", "shopping_basket", 9, true, function()
				hud.buy(look.worn, "wearing")
			end, nil, unowned == 0, hud.buying("wearing")),
			wideButton("Add unowned to basket", "add_shopping_cart", 10, false, function()
				local unownedIds = {}
				for _, id in look.worn do
					if not PlaceholderData.item(id).owned then
						table.insert(unownedIds, id)
					end
				end
				look.addToBasket(unownedIds)
			end, false),
			-- Saving: as a new outfit or over one you have. Once what you're
			-- wearing is a saved outfit (just saved, or put on), this is a way
			-- to that outfit instead, until the look changes.
			if justSaved
				then wideButton("Saved to Outfits", "check", 11, false, nil, false)
				elseif current then wideButton("Go to " .. current.name, "checkroom", 11, false, function()
					props.nav.push({ kind = "outfit", id = { source = "Mine", index = current.id }, label = current.name })
				end)
				else wideButton("Save as new outfit", "bookmark_add", 11, false, function()
					if look.saveOutfit() then
						setJustSaved(true)
					end
				end, false, #look.worn == 0),
			if justSaved or current
				then nil
				else wideButton("Save over existing outfit", "checkroom", 12, false, function()
					setPicking(true)
				end, nil, #look.worn == 0 or #look.outfits == 0),
			e(ConfirmButton, {
				label = "Take everything off",
				icon = "delete_sweep",
				layoutOrder = 13,
				disabled = #look.worn == 0,
				onConfirm = look.takeOffAll,
			}),
		}),
	})
end

return {
	Basket = BasketScreen,
	Wearing = WearingScreen,
}
