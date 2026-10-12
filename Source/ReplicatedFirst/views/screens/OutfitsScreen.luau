--!strict

--[[
	OutfitsScreen (design frame 5d: Outfits root and the outfit page)

	Root: source tabs (Mine · Community · Roblox) beside a search box, and a
	grid of outfit cards. Mine holds, in order:
	  · Your avatar: your own Roblox avatar as it is (a restart badge; its
	    Wear all reads "Reset to this": it's what Reset puts back)
	  · Save what I'm wearing, then your saved outfits (look.outfits)
	  · the outfits saved on Roblox itself, outside experiences
	    (RobloxOutfits), marked with a "Roblox" badge. Roblox only lists them
	    once you allow it, so until then a "Show my Roblox outfits" card asks.
	The outfit you're wearing exactly gets the orange ring. Search filters by
	name. Community and Roblox still show placeholder outfits (Tasks 13 and
	16). Cards show a 2×2 mosaic of item thumbnails, the most telling first:
	bodies, then heads, layered clothing, accessories, classic clothing, and
	animations last.

	Outfit page: on the left the preview (your avatar wearing it, for a saved
	outfit: OutfitPreview), the name (tap to rename a saved one), Wear all and
	Delete (press twice). On the right "N items · M selected" with Select
	all / none, a row per item with a checkbox (the row itself opens the item
	page: Outfits › Name › Item), and Wear selected · Add to basket · Buy
	selected (priced for the unowned items selected).

	OutfitsScreen.Root props: nav, look
	OutfitsScreen.Outfit props: nav, look, source, index (a saved outfit's id
	for Mine; the placeholder list position otherwise)
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
local TextTab = require(components:WaitForChild("TextTab"))
local PillButton = require(components:WaitForChild("PillButton"))
local ConfirmButton = require(components:WaitForChild("ConfirmButton"))
local SearchBox = require(components:WaitForChild("SearchBox"))
local ShadowText = require(components:WaitForChild("ShadowText"))
local Icon = require(components:WaitForChild("Icon"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))
local OutfitPreview = require(script.Parent:WaitForChild("OutfitPreview"))
local RobloxOutfits = require(views:WaitForChild("catalogue"):WaitForChild("RobloxOutfits"))
local Badge = require(components:WaitForChild("Badge"))
local HudContext = require(views:WaitForChild("HudContext"))

local e = React.createElement

local SEARCH_WIDTH = 270
local LEFT_WIDTH = 300

-- An outfit as the screens see it, whichever source it came from.
type OutfitView = {
	kind: "saved" | "own" | "roblox" | "placeholder",
	id: number?, -- the saved / Roblox outfit's id
	source: string, -- nav source: "Mine" (saved), "Own", "RobloxSaved", or a placeholder tab
	index: number, -- nav index: the id, or the placeholder list position
	name: string,
	by: string,
	items: { number },
}

-- Card / page order of a type's thumbnail: the most telling first.
local function rank(typeName: string?): number
	local t = typeName or ""
	if t == "BodyParts" or t == "DynamicHeadAvatar" or t == "Torso" or string.match(t, "^%a+Arm$") or string.match(t, "^%a+Leg$") then
		return 1 -- the character
	elseif t == "DynamicHead" or t == "Head" then
		return 2
	elseif t == "Shoes" or (string.match(t, "Accessory$") and (string.find(t, "Shirt") or string.find(t, "Pants") or string.find(t, "Jacket")
		or string.find(t, "Sweater") or string.find(t, "Shorts") or string.find(t, "Dress") or string.find(t, "Shoe"))) then
		return 3 -- layered clothing
	elseif t == "Shirt" or t == "Pants" or t == "TShirt" then
		return 5 -- classic clothing
	elseif string.find(t, "Animation") or t == "Animations" then
		return 6
	elseif string.find(t, "Background") then
		return 7
	end
	return 4 -- accessories, hair, makeup, gear
end

-- Wearing exactly this outfit: the same items, nothing more or less.
local function wearingExactly(look: any, items: { number }): boolean
	if #items == 0 or #items ~= #look.worn then
		return false
	end
	for _, id in items do
		if not look.isWorn(id) then
			return false
		end
	end
	return true
end

local function savedView(outfit: any): OutfitView
	return { kind = "saved", id = outfit.id, source = "Mine", index = outfit.id, name = outfit.name, by = "Your outfit", items = outfit.items }
end

local function ownView(look: any): OutfitView
	return { kind = "own", id = nil, source = "Own", index = 0, name = "Your avatar", by = "Your Roblox avatar", items = look.own }
end

local function robloxView(outfit: RobloxOutfits.Outfit): OutfitView
	return { kind = "roblox", id = outfit.id, source = "RobloxSaved", index = outfit.id, name = outfit.name, by = "Saved on Roblox", items = outfit.items }
end

local function outfitsFor(look: any, source: string): { OutfitView }
	local list: { OutfitView } = {}
	if source == "Mine" then
		for _, outfit in look.outfits do
			table.insert(list, savedView(outfit))
		end
	else
		for index, outfit in (PlaceholderData.outfits :: any)[source] or {} do
			table.insert(list, { kind = "placeholder", id = nil, source = source, index = index, name = outfit.name, by = outfit.by, items = outfit.items })
		end
	end
	return list
end

local function findOutfit(look: any, source: string, index: number): OutfitView?
	if source == "Mine" then
		for _, outfit in look.outfits do
			if outfit.id == index then
				return savedView(outfit)
			end
		end
		return nil
	elseif source == "Own" then
		return ownView(look)
	elseif source == "RobloxSaved" then
		for _, outfit in RobloxOutfits.outfits() do
			if outfit.id == index then
				return robloxView(outfit)
			end
		end
		return nil
	end
	local outfit = ((PlaceholderData.outfits :: any)[source] or {})[index]
	return if outfit
		then { kind = "placeholder", id = nil, source = source, index = index, name = outfit.name, by = outfit.by, items = outfit.items }
		else nil
end

-- Re-render when the Roblox-saved outfits (or their items) arrive.
local function useRobloxOutfits(active: boolean)
	local _version, setVersion = React.useState(0)
	React.useEffect(function()
		local connection = RobloxOutfits.changed:Connect(function()
			setVersion(function(v: number)
				return v + 1
			end)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	React.useEffect(function()
		if active then
			RobloxOutfits.check()
		end
		return nil
	end, { active })
end

-- Up to four item thumbnails in a 2×2 grid (items with pictures first).
local function mosaic(items: { number }): { [string]: any }
	local ordered = {}
	for index, id in items do
		local item = PlaceholderData.item(id)
		if item then
			table.insert(ordered, { item = item, rank = rank(item.typeName), index = index })
		end
	end
	table.sort(ordered, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.index < b.index
	end)
	local images = {}
	for _, entry in ordered do
		local image = Parts.image(entry.item)
		if image then
			table.insert(images, image)
			if #images == 4 then
				break
			end
		end
	end
	local cells: { [string]: any } = {}
	for index, image in images do
		local column, row = (index - 1) % 2, (index - 1) // 2
		local single = #images == 1
		cells["Cell" .. index] = e("ImageLabel", {
			AnchorPoint = if single then Vector2.new(0.5, 0.5) else Vector2.zero,
			Position = if single then UDim2.fromScale(0.5, 0.5) else UDim2.fromScale(0.04 + column * 0.48, 0.04 + row * 0.48),
			Size = if single then UDim2.fromScale(0.9, 0.9) else UDim2.fromScale(0.44, 0.44),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
		})
	end
	return cells
end

local function OutfitCard(props: {
	outfit: OutfitView,
	sub: string,
	ring: boolean,
	badge: any?, -- top-left marker (your avatar / from Roblox)
	onActivated: () -> (),
	layoutOrder: number,
})
	local skin = useSkin()
	local interaction = useInteraction()
	local first = PlaceholderData.item(props.outfit.items[1])
	local cells = mosaic(props.outfit.items)
	return e("TextButton", {
		Name = "OutfitCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(props.onActivated),
		[React.Event.Activated] = Press.activated(props.onActivated),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Parts.swatch(if first then first.colour else ""),
			radius = 14,
			hovered = interaction.hovered,
			selected = props.ring,
			caption = if next(cells) then nil else "outfit",
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
			Mosaic = e(React.Fragment, nil, cells),
			Badge = if props.badge
				then e("Frame", {
					Position = UDim2.fromOffset(skin.px(8), skin.px(8)),
					Size = UDim2.fromOffset(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					ZIndex = 2,
				}, { Badge = props.badge })
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
				Size = UDim2.new(1, 0, 0, skin.textPx(13.5) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.outfit.name,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			}),
			Sub = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(12) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.sub,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(700),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
		}),
	})
end

-- A dashed orange action card in the grid: save what you're wearing, or
-- show your Roblox outfits.
local function ActionCard(props: {
	icon: string,
	label: string, -- inside the card
	title: string, -- under it, like an outfit's name
	sub: string,
	onActivated: () -> (),
	layoutOrder: number,
})
	local skin = useSkin()
	local interaction = useInteraction()
	local orange = Tokens.color.accentText
	return e("TextButton", {
		Name = "ActionCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(props.onActivated),
		[React.Event.Activated] = Press.activated(props.onActivated),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Well = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Tokens.color.accent,
			BackgroundTransparency = if interaction.hovered then 0.86 else 0.94,
			BorderSizePixel = 0,
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
			Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
			Stroke = e("UIStroke", {
				Color = orange,
				Transparency = 0.3,
				Thickness = skin.stroke(1.5),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			Layout = e("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(4)),
			}),
			Icon = e(Icon, { name = props.icon, size = 36, color = orange, layoutOrder = 1 }),
			Label = e("TextLabel", {
				Size = UDim2.new(1, -skin.px(12), 0, skin.textPx(13) * 2 + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.label,
				TextColor3 = orange,
				TextSize = skin.textPx(13),
				FontFace = Tokens.font(900),
				TextWrapped = true,
				LayoutOrder = 2,
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
				Size = UDim2.new(1, 0, 0, skin.textPx(13.5) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.title,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),
			Sub = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(12) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.sub,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(700),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
			}),
		}),
	})
end

local function OutfitsScreen(props: { nav: any, look: any })
	local skin = useSkin()
	local look = props.look
	local source, setSource = useSessionState("outfits.source", "Mine")
	local query, setQuery = useSessionState("outfits.query", "")

	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(22)),
		}),
	}
	for index, name in PlaceholderData.outfitSources do
		tabs["Tab" .. index] = e(TextTab, {
			label = name,
			active = name == source,
			layoutOrder = index,
			onActivated = function()
				setSource(name)
			end,
		})
	end

	local mine = source == "Mine"
	useRobloxOutfits(mine)
	local needle = string.lower(query)
	local function matches(name: string): boolean
		return needle == "" or string.find(string.lower(name), needle, 1, true) ~= nil
	end
	local cards: { [string]: any } = {}
	local count = 0
	local function addOutfit(outfit: OutfitView, sub: string, badge: any?)
		if not matches(outfit.name) then
			return
		end
		count += 1
		cards["Outfit" .. count] = e(OutfitCard, {
			outfit = outfit,
			sub = sub,
			ring = wearingExactly(look, outfit.items),
			badge = badge,
			layoutOrder = count,
			onActivated = function()
				props.nav.push({
					kind = "outfit",
					id = { source = outfit.source, index = outfit.index },
					label = outfit.name,
				})
			end,
		})
	end
	local function addAction(key: string, card: { [string]: any })
		count += 1
		card.layoutOrder = count
		cards[key] = e(ActionCard, card :: any)
	end

	if mine then
		-- Your own Roblox avatar first: wearing it is a reset.
		if #look.own > 0 then
			addOutfit(ownView(look), "Reset to your avatar", e(Badge, { kind = "marker", tone = "white", icon = "restart_alt" }))
		end
		if needle == "" then
			addAction("Save", {
				icon = "add_circle",
				label = "Save what I'm wearing",
				title = "New outfit",
				sub = #look.worn .. " items",
				onActivated = look.saveOutfit,
			})
		end
		for _, outfit in outfitsFor(look, "Mine") do
			addOutfit(outfit, #outfit.items .. " items")
		end
		-- Then the ones saved on Roblox itself (once Roblox lets us see them).
		local status = RobloxOutfits.status()
		if status == "ready" then
			for _, outfit in RobloxOutfits.outfits() do
				addOutfit(robloxView(outfit), "Saved on Roblox", e(Badge, { kind = "count", tone = "white", text = "Roblox" }))
			end
		elseif status == "loading" then
			count += 1
			cards.RobloxLoading = e(Parts.LoadingCard, { layoutOrder = count })
		elseif (status == "locked" or status == "denied") and needle == "" then
			addAction("Roblox", {
				icon = "lock",
				label = "Show my Roblox outfits",
				title = "Outfits on Roblox",
				sub = if status == "denied" then "Roblox needs your OK" else "Saved outside this game",
				onActivated = function()
					Sounds.play("press")
					RobloxOutfits.request()
				end,
			})
		end
	else
		for _, outfit in outfitsFor(look, source) do
			addOutfit(outfit, "by " .. outfit.by)
		end
	end

	local tabsHeight = skin.px(Tokens.size.textTabHeight)
	local searchWidth = skin.px(SEARCH_WIDTH)
	return e("Frame", {
		Name = "OutfitsScreen",
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
				placeholder = if source == "Roblox" then "Search a username" else "Search outfits",
				onChange = setQuery,
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.fromScale(1, 0.5),
				size = UDim2.fromOffset(searchWidth, skin.px(40)),
			}),
		}),
		Grid = e(Parts.CardGrid, {
			columns = 5,
			extraHeight = 40,
			count = count,
			position = UDim2.fromOffset(0, tabsHeight + skin.px(14)),
			size = UDim2.new(1, 0, 1, -(tabsHeight + skin.px(14))),
			scrollKey = "outfits|" .. source .. "|" .. query,
		}, cards),
	})
end

-- A row's checkbox: orange with a tick when selected.
local function Checkbox(props: { on: boolean, onToggle: () -> () })
	local skin = useSkin()
	local function toggle()
		Sounds.play("press")
		props.onToggle()
	end
	return e("TextButton", {
		Name = "Checkbox",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(skin.px(28), skin.px(28)),
		BackgroundColor3 = if props.on then Tokens.color.accent else Color3.fromHex("#111111"),
		AutoButtonColor = false,
		Text = "",
		[React.Event.InputBegan] = Press.began(toggle),
		[React.Event.Activated] = Press.activated(toggle),
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(8)) }),
		Stroke = e("UIStroke", { Color = Tokens.color.black, Thickness = skin.stroke(1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Tick = if props.on
			then e(Icon, {
				name = "check",
				size = 19,
				anchorPoint = Vector2.new(0.5, 0.5),
				position = UDim2.fromScale(0.5, 0.5),
			})
			else nil,
	})
end

-- The outfit's name: a saved outfit's can be edited in place (renamed when
-- the box loses focus).
local function NameField(props: { name: string, editable: boolean, onRename: (name: string) -> () })
	local skin = useSkin()
	local style = { size = 24, weight = 900 }
	if not props.editable then
		return e(ShadowText, { text = props.name, style = style, maxWidth = skin.px(LEFT_WIDTH), layoutOrder = 2 })
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, skin.textPx(24) + skin.px(6)),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, {
		Box = e("TextBox", {
			Size = UDim2.new(1, -skin.px(26), 1, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			Text = props.name,
			TextColor3 = Tokens.color.white,
			TextSize = skin.textPx(24),
			FontFace = Tokens.font(900),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			[React.Event.FocusLost] = function(box: TextBox)
				local text = box.Text
				if text ~= props.name and string.match(text, "%S") then
					props.onRename(text)
				else
					box.Text = props.name
				end
			end,
		}),
		Pencil = e(Icon, {
			name = "edit",
			size = 18,
			transparency = 0.45,
			anchorPoint = Vector2.new(1, 0.5),
			position = UDim2.fromScale(1, 0.5),
		}),
	})
end

local function smallIcon(name: string, color: Color3, order: number)
	return e(Icon, { name = name, size = 20, color = color, layoutOrder = order })
end

local function OutfitScreen(props: { nav: any, look: any, source: string, index: number })
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local look = props.look
	useRobloxOutfits(props.source == "RobloxSaved")
	local outfit = findOutfit(look, props.source, props.index)
	-- Selected rows by position; everything starts selected.
	local deselected, setDeselected = React.useState({} :: { [number]: boolean })

	-- Find out what's owned, for prices and the Buy label.
	React.useEffect(function()
		if outfit then
			look.checkOwned(outfit.items)
		end
		return nil
	end, { props.source, props.index })

	-- Keep the breadcrumb in step with a rename.
	React.useEffect(function()
		local top = props.nav.top
		if outfit and top and top.kind == "outfit" and top.label ~= outfit.name then
			props.nav.replaceTop({ kind = top.kind, id = top.id, label = outfit.name })
		end
		return nil
	end, { outfit and outfit.name })

	if not outfit then
		-- Deleted (or gone): nothing to show; the Delete handler goes back.
		return e("Frame", { Name = "OutfitScreen", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	end

	local items = outfit.items
	local selected: { number } = {} -- positions
	local selectedIds: { number } = {}
	local cost = 0
	for index, id in items do
		if not deselected[index] then
			table.insert(selected, index)
			table.insert(selectedIds, id)
			local item = PlaceholderData.item(id)
			if item and not item.owned then
				cost += item.price
			end
		end
	end
	local allSelected = #selected == #items
	local ring = wearingExactly(look, items)

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(6)) }),
		-- Inset so row strokes at the edges aren't clipped by the ScrollingFrame.
		Inset = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(3)),
			PaddingBottom = UDim.new(0, skin.px(3)),
			PaddingLeft = UDim.new(0, skin.px(3)),
			PaddingRight = UDim.new(0, skin.px(8)),
		}),
	}
	for index, id in items do
		local item = PlaceholderData.item(id)
		if not item then
			continue
		end
		local on = not deselected[index]
		rows["Row" .. index] = e(Parts.ListRow, {
			title = item.name,
			subtitle = item.main .. " · " .. item.sub,
			colour = Parts.swatch(item.colour),
			image = Parts.image(item),
			layoutOrder = index,
			trailingWidth = 150,
			leading = e(Checkbox, {
				on = on,
				onToggle = function()
					setDeselected(function(current: { [number]: boolean })
						local result = table.clone(current)
						result[index] = if on then true else nil
						return result
					end)
				end,
			}),
			trailing = {
				Price = e(Parts.PriceTag, { item = item, size = 14, layoutOrder = 1 }),
				Wearing = if look.isWorn(id) then smallIcon("checkroom", Tokens.color.accentText, 2) else nil,
				InBasket = if look.inBasket(id) then smallIcon("shopping_basket", Tokens.color.white, 3) else nil,
			},
			onActivated = function()
				props.nav.push({ kind = "item", id = id, label = item.name })
			end,
		})
	end

	local function bottomButton(label: string, icon: string, order: number, disabled: boolean, onActivated: () -> (), extra: { [string]: any }?)
		local button = {
			variant = "pill",
			size = Tokens.size.ctaHeight,
			label = label,
			icon = icon,
			iconSize = 18,
			disabled = disabled,
			sound = false, -- each action plays its own sound
			onActivated = onActivated,
		}
		for key, value in extra or {} do
			(button :: any)[key] = value
		end
		return e("Frame", {
			Size = UDim2.new(1 / 3, -skin.px(6), 1, 0),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, { Button = e(PillButton, button :: any) })
	end

	local saved = outfit.kind == "saved"
	local outfitId = outfit.id
	local kind = outfit.kind
	local leftWidth = skin.px(LEFT_WIDTH)
	local buttonsHeight = skin.px(Tokens.size.ctaHeight)
	local headerHeight = skin.px(26)

	return e("Frame", {
		Name = "OutfitScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Left = e("Frame", {
			Size = UDim2.new(0, leftWidth, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(10)),
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
			}),
			Preview = e("Frame", {
				-- Whatever height the details below leave.
				Size = UDim2.new(1, 0, 1, -(skin.textPx(24) + skin.px(6) + skin.px(18) + buttonsHeight * (if saved then 2 else 1) + skin.px(10) * (if saved then 4 else 3))),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				View = if kind ~= "placeholder"
					then e(OutfitPreview, { kind = kind, outfitId = outfitId, ring = ring })
					else e(Parts.Thumb, {
						colour = Parts.swatch(""),
						radius = 20,
						caption = if next(mosaic(items)) then nil else "outfit preview",
						selected = ring,
					}, mosaic(items)),
			}),
			Name = e(NameField, {
				name = outfit.name,
				editable = saved,
				onRename = function(name: string)
					if outfitId then
						look.renameOutfit(outfitId, name)
					end
				end,
			}),
			By = e("Frame", {
				Size = UDim2.new(1, 0, 0, skin.px(18)),
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, {
				Text = e(ShadowText, {
					text = outfit.by .. " · " .. #items .. " items",
					style = Tokens.type.meta,
					transparency = Tokens.alpha.textSoft,
					shadow = false,
				}),
			}),
			WearAll = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				icon = if kind == "own" then "restart_alt" else "checkroom",
				iconSize = 18,
				label = if kind == "own" then "Reset to this" else "Wear all",
				active = true,
				sound = false, -- the look change plays its own sound
				layoutOrder = 4,
				onActivated = function()
					if kind == "own" then
						look.reset()
					elseif kind == "roblox" and outfitId then
						look.wearRobloxOutfit(outfitId)
					elseif kind == "saved" and outfitId then
						look.wearOutfit(outfitId)
					else
						look.wearAll(items)
					end
				end,
			}),
			Delete = if saved
				then e(ConfirmButton, {
					label = "Delete outfit",
					icon = "delete",
					armedLabel = "Tap again to delete",
					layoutOrder = 5,
					onConfirm = function()
						if outfitId then
							look.deleteOutfit(outfitId)
							props.nav.back()
						end
					end,
				})
				else nil,
		}),
		Right = e("Frame", {
			Position = UDim2.fromOffset(leftWidth + skin.px(20), 0),
			Size = UDim2.new(1, -(leftWidth + skin.px(20)), 1, 0),
			BackgroundTransparency = 1,
		}, {
			Header = e("Frame", {
				Size = UDim2.new(1, 0, 0, headerHeight),
				BackgroundTransparency = 1,
			}, {
				Count = e(ShadowText, {
					text = #items .. " items · " .. #selected .. " selected",
					style = { size = 17, weight = 900 },
				}),
				Toggle = e("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.new(0, skin.px(110), 1, 0),
					BackgroundTransparency = 1,
					Text = if allSelected then "Select none" else "Select all",
					TextColor3 = Tokens.color.accentText,
					TextSize = skin.textPx(13.5),
					FontFace = Tokens.font(800),
					TextXAlignment = Enum.TextXAlignment.Right,
					[React.Event.InputBegan] = Press.began(function()
						Sounds.play("press")
						if allSelected then
							local none = {}
							for index in items do
								none[index] = true
							end
							setDeselected(none)
						else
							setDeselected({})
						end
					end),
				}),
			}),
			Rows = e("ScrollingFrame", {
				Position = UDim2.fromOffset(0, headerHeight + skin.px(10)),
				Size = UDim2.new(1, 0, 1, -(headerHeight + skin.px(10) + buttonsHeight + skin.px(10))),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromOffset(0, #items * (skin.px(64) + skin.px(6)) + skin.px(6)),
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = skin.px(8),
				ScrollBarImageColor3 = Tokens.color.accent,
				VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			}, rows),
			Buttons = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, buttonsHeight),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(8)),
				}),
				WearSelected = bottomButton("Wear selected", "checkroom", 1, #selected == 0, function()
					if saved and outfitId then
						look.wearOutfitItems(outfitId, selected)
					else
						look.wearAll(selectedIds)
					end
				end),
				Basket = bottomButton("Add to basket", "add_shopping_cart", 2, #selected == 0, function()
					local unowned = {}
					for _, id in selectedIds do
						local item = PlaceholderData.item(id)
						if item and not item.owned then
							table.insert(unowned, id)
						end
					end
					look.addToBasket(unowned)
				end),
				Buy = bottomButton(
					if cost > 0 then "Buy · " .. Tokens.robux(cost) else "Buy",
					"toll",
					3,
					#selected == 0,
					function()
						hud.buy(selectedIds, "outfit")
					end,
					{ loading = hud.buying("outfit") }
				),
			}),
		}),
	})
end

return {
	Root = OutfitsScreen,
	Outfit = OutfitScreen,
}
