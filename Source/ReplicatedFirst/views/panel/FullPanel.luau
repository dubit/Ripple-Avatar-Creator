--!strict

--[[
	FullPanel (design frames 5b–5h: the full-screen panel's chrome)

	Covers the world when a tab, Basket or Wearing is open:
	  · tab bar (tapping the open tab closes the panel) and close button
	  · left column: avatar-preview card (live 3D copy of your character,
	    AvatarPreview) with Undo and a "Wearing · N" bar
	    (opens Wearing), and the Basket card with count + CTA (opens Basket);
	    each card gets the orange border while its screen is open
	  · content area: breadcrumbs/back once deeper than a tab (always on the
	    Basket / Wearing lists), then the current screen

	Swallows input so nothing underneath reacts. The avatar preview is a
	placeholder until Task 6.

	Motion: Hud drives `t` (0 closed → 1 open) — the background fades in and
	the body drops into place and fades (CanvasGroup); the tab bar stays put so
	it reads as the same bar as the world HUD's. Each screen slides in when it
	mounts (keyed by where we are), and the basket/wearing counts roll.

	Props:
		nav: useNavigation.Navigation
		look: usePlaceholderLook.Look
		tabs: { PillTabs.Tab }
		t: binding?   open progress (default fully open)
		closing: boolean?   the panel is animating out — drop the tab bar and
		                    close button at once (the world HUD's own tab bar
		                    takes over), only the body fades
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local screens = views:WaitForChild("screens")
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useAppear = require(hooks:WaitForChild("useAppear"))
local useSpringNumber = require(hooks:WaitForChild("useSpringNumber"))
local PillButton = require(components:WaitForChild("PillButton"))
local PillTabs = require(components:WaitForChild("PillTabs"))
local GlassPanel = require(components:WaitForChild("GlassPanel"))
local Icon = require(components:WaitForChild("Icon"))
local ShadowText = require(components:WaitForChild("ShadowText"))
local Breadcrumbs = require(script.Parent:WaitForChild("Breadcrumbs"))
local Sounds = require(views:WaitForChild("Sounds"))
local CatalogueScreen = require(screens:WaitForChild("CatalogueScreen"))
local SkinToneScreen = require(screens:WaitForChild("SkinToneScreen"))
local ItemScreen = require(screens:WaitForChild("ItemScreen"))
local StoresScreen = require(screens:WaitForChild("StoresScreen"))
local OutfitsScreen = require(screens:WaitForChild("OutfitsScreen"))
local ListScreens = require(screens:WaitForChild("ListScreens"))
local PlaceholderData = require(screens:WaitForChild("PlaceholderData"))
local AvatarPreview = require(script.Parent:WaitForChild("AvatarPreview"))
local AnimationBar = require(script.Parent:WaitForChild("AnimationBar"))

local e = React.createElement

local LEFT_WIDTH = 250
local BASKET_CARD = 112
local GAP = 16

-- Full-size invisible button so a whole card is tappable under its contents.
-- The image of a worn avatar background, if any (shown behind the preview).
local function backdropOf(look: any): string?
	for _, id in look.worn do
		local item = PlaceholderData.item(id)
		if item and item.typeName == "AvatarBackground" then
			return `rbxthumb://type=Asset&id={item.targetId}&w=420&h=420`
		end
	end
	return nil
end

-- "9 items · ₹260": the count, and the Robux for what isn't owned (if any).
local function summary(count: number, cost: number): string
	local items = if count == 1 then "1 item" else `{count} items`
	return if cost > 0 then `{items} · {Tokens.robux(cost)}` else items
end

-- A card's title row: icon + name, top left.
local function cardHeader(skin, icon: string, title: string)
	return e("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(skin.px(14), skin.px(14)),
		Size = UDim2.new(1, -skin.px(28), 0, skin.px(22)),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(6)),
		}),
		Icon = e(Icon, { name = icon, size = 20, color = Tokens.color.accentText, layoutOrder = 1, zIndex = 3 }),
		Title = e(ShadowText, { text = title, style = Tokens.type.cardTitle, layoutOrder = 2, zIndex = 3 }),
	})
end

-- A card's orange button, centred along the bottom: opens the card's list.
local function cardButton(skin, label: string, onActivated: () -> ())
	return e("Frame", {
		Name = "Open",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -skin.px(12)),
		Size = UDim2.new(1, -skin.px(24), 0, skin.px(Tokens.size.ctaHeight)),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		Button = e(PillButton, {
			variant = "pill",
			size = Tokens.size.ctaHeight,
			label = "View " .. label,
			icon = "chevron_right",
			iconSize = 20,
			iconAfter = true,
			active = true,
			zIndex = 3,
			sound = false, -- openList plays the switch
			onActivated = onActivated,
		}),
	})
end

-- Wearing and Basket cards share a layout: icon + title top left, and an
-- orange "View N items · ₹X ›" button along the bottom that opens the list. Only
-- the button opens it, so the Wearing card's avatar can be turned freely.
local function PreviewCard(props: { nav: any, look: any, openList: (root: string) -> () })
	local skin = useSkin()
	local selected = props.nav.root == "Wearing"
	local undo = Tokens.size.undo
	local cost = 0
	for _, id in props.look.worn do
		local item = PlaceholderData.item(id)
		if item and not item.owned then
			cost += item.price
		end
	end
	local wornCount = useSpringNumber(#props.look.worn, Tokens.spring.count)
	local wornCost = useSpringNumber(cost, Tokens.spring.count)
	local animation, setAnimation = React.useState(AnimationBar.DEFAULT)

	-- Trying on an emote or animation pack shows it straight away: an emote
	-- plays, a pack walks (where a pack shows most).
	local seenWorn = React.useRef(nil :: { [number]: boolean }?)
	React.useEffect(function()
		local now: { [number]: boolean } = {}
		for _, id in props.look.worn do
			now[id] = true
		end
		local before = seenWorn.current
		seenWorn.current = now
		if not before then
			return -- first render: nothing was "just" tried on
		end
		for _, id in props.look.worn do
			if not before[id] then
				local item = PlaceholderData.item(id)
				if item and item.typeName == "EmoteAnimation" then
					setAnimation(AnimationBar.emoteChoice(item.targetId, item.name))
				elseif item and item.typeName == "Animations" then
					setAnimation(AnimationBar.choice("move/walk") or AnimationBar.DEFAULT)
				end
			end
		end
	end, { table.concat(props.look.worn, ",") })

	-- Emotes to preview: the ones being worn, then any in the basket.
	local emotes = {}
	local listed = {}
	for _, list in { props.look.worn, props.look.basket } do
		for _, id in list do
			local item = PlaceholderData.item(id)
			if item and item.typeName == "EmoteAnimation" and item.thumbnail ~= "" and not listed[item.targetId] then
				listed[item.targetId] = true
				table.insert(emotes, { id = item.targetId, name = item.name })
			end
		end
	end
	return e(GlassPanel, {
		variant = "light",
		cornerRadius = Tokens.radius.contentPanel,
		borderColor = if selected then Tokens.color.accent else nil,
		borderTransparency = if selected then 0 else nil,
		size = UDim2.new(1, 0, 1, -skin.px(BASKET_CARD + 12)),
	}, {
		-- The preview fills the card, edge to edge, behind everything else.
		Preview = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, {
			Avatar = e(AvatarPreview, {
				backdrop = backdropOf(props.look),
				cornerRadius = Tokens.radius.contentPanel,
				animation = animation,
			}),
		}),
		-- What the preview is doing: idle, walk, run… or an emote.
		Animations = e(AnimationBar.Bar, {
			selected = animation.key,
			emotes = emotes,
			onSelect = setAnimation,
			anchorPoint = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -skin.px(12 + Tokens.size.ctaHeight + 8)),
		}),
		Header = cardHeader(skin, "checkroom", "Wearing"),
		Undo = e(PillButton, {
			variant = "round",
			size = undo.size,
			icon = "undo",
			iconSize = undo.icon,
			glowRadius = undo.glow,
			disabled = not props.look.canUndo, -- greyed out with nothing to undo
			sound = false, -- look.undo plays it
			onActivated = props.look.undo,
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, -skin.px(10), 0, skin.px(10)),
			zIndex = 3,
		}),
		Open = cardButton(skin, summary(wornCount, wornCost), function()
			props.openList("Wearing")
		end),
	})
end

local function BasketCard(props: { nav: any, look: any, openList: (root: string) -> () })
	local skin = useSkin()
	local selected = props.nav.root == "Basket"
	local total = useSpringNumber(props.look.basketTotal, Tokens.spring.count)
	local count = useSpringNumber(#props.look.basket, Tokens.spring.count)
	return e(GlassPanel, {
		variant = "light",
		cornerRadius = Tokens.radius.basketCard,
		borderColor = if selected then Tokens.color.accent else nil,
		borderTransparency = if selected then 0 else nil,
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.fromScale(0, 1),
		size = UDim2.new(1, 0, 0, skin.px(BASKET_CARD)),
	}, {
		Header = cardHeader(skin, "shopping_basket", "Basket"),
		Open = cardButton(skin, summary(count, total), function()
			props.openList("Basket")
		end),
	})
end

-- The page pushed on top of the root (item, store, outfit), or nil.
local function deepScreen(nav: any, look: any)
	local top = nav.top
	if top then
		if top.kind == "item" then
			return e(ItemScreen, { nav = nav, look = look, itemId = top.id })
		elseif top.kind == "store" then
			return e(StoresScreen.Store, { nav = nav, look = look, storeId = top.id })
		elseif top.kind == "outfit" then
			return e(OutfitsScreen.Outfit, { nav = nav, look = look, source = top.id.source, index = top.id.index })
		elseif top.kind == "skin" then
			return e(SkinToneScreen, { nav = nav, look = look, colours = top.id.colours, from = top.id.from })
		end
	end
	return nil
end

local function rootScreen(nav: any, look: any)
	if nav.root == "Catalogue" then
		return e(CatalogueScreen, { nav = nav, look = look })
	elseif nav.root == "Stores" then
		return e(StoresScreen.Root, { nav = nav, look = look })
	elseif nav.root == "Outfits" then
		return e(OutfitsScreen.Root, { nav = nav, look = look })
	elseif nav.root == "Basket" then
		return e(ListScreens.Basket, { nav = nav, look = look })
	elseif nav.root == "Wearing" then
		return e(ListScreens.Wearing, { nav = nav, look = look })
	end
	return nil
end

-- Slides its screen in from the right when it mounts.
local function ScreenAppear(props: { children: any })
	local skin = useSkin()
	local t = useAppear(Tokens.spring.screen)
	return e("Frame", {
		Name = "ScreenAppear",
		Position = t:map(function(v: number)
			return UDim2.fromOffset((1 - v) * skin.px(Tokens.motion.screenSlide), 0)
		end),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, props.children)
end

export type Props = {
	nav: any,
	look: any,
	tabs: { any },
	t: any?,
	closing: boolean?,
}

local function FullPanel(props: Props)
	local skin = useSkin()
	local nav = props.nav
	local isList = nav.root == "Basket" or nav.root == "Wearing"
	local hasCrumbs = #nav.stack > 0 or isList
	local crumbsHeight = if hasCrumbs then skin.px(Tokens.size.back.size + 12) else 0
	local close = Tokens.size.close

	-- The root screen stays mounted (hidden) under pushed pages, so going back
	-- returns to it as it was: same tab, chip, search, filters, loaded items
	-- and scroll. Pushed pages are keyed by where we are, so each one starts
	-- fresh. Switching tab or closing the panel resets the root.
	local deep = deepScreen(nav, props.look)
	local deepKey = (nav.root or "") .. "/" .. #nav.stack .. "/" .. (if nav.top then nav.top.label else "")
	local open = props.t or React.createBinding(1)
	local baseTransparency = if skin.glass == "blur" then 0.25 else 0
	local margin = skin.px(6)

	-- Basket / Wearing from inside the open panel: same "switch" as changing tab.
	local function openList(root: string)
		if nav.root ~= root then
			Sounds.play("switch")
		end
		nav.openRoot(root)
	end

	return e("Frame", {
		Name = "FullPanel",
		Size = UDim2.fromScale(1, 1),
		Active = true, -- swallow input so nothing beneath reacts
		BackgroundColor3 = Tokens.color.white,
		-- With blur glass, the blurred world shows faintly through.
		BackgroundTransparency = open:map(function(t: number)
			return 1 - (1 - baseTransparency) * math.clamp(t, 0, 1)
		end),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, {
		Gradient = e("UIGradient", { Color = Tokens.gradient.fullPanel, Rotation = Tokens.gradient.rotation }),
		Tabs = if props.closing then nil else e(PillTabs, {
			tabs = props.tabs,
			activeId = if isList then nil else nav.root,
			sound = false,
			onSelect = function(id: string)
				-- Tapping the open tab closes the panel (Hud plays "close");
				-- any other tab switches windows.
				if id ~= nav.root then
					Sounds.play("switch")
				end
				nav.toggleTab(id)
			end,
			anchorPoint = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, skin.px(16)),
			zIndex = 12,
		}),
		Close = if props.closing then nil else e(PillButton, {
			variant = "round",
			size = close.size,
			icon = "close",
			iconSize = close.icon,
			glowRadius = close.glow,
			sound = false, -- closing the panel plays its own sound
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, -skin.px(Tokens.size.edgeInset), 0, skin.px(16)),
			onActivated = nav.close,
			zIndex = 12,
		}),
		-- CanvasGroup (for the fade) clips at its bounds, so it's grown by a
		-- margin and padded back in — card outlines sit just outside their edges.
		Body = e("CanvasGroup", {
			Position = open:map(function(t: number)
				return UDim2.fromOffset(skin.px(28) - margin, skin.px(84) - margin - (1 - t) * skin.px(Tokens.motion.panelDrop))
			end),
			Size = UDim2.new(1, -skin.px(56) + margin * 2, 1, -skin.px(84 + 24) + margin * 2),
			GroupTransparency = open:map(function(t: number)
				return 1 - math.clamp(t, 0, 1)
			end),
			BackgroundTransparency = 1,
			ZIndex = 11,
		}, {
			Margin = e("UIPadding", {
				PaddingTop = UDim.new(0, margin),
				PaddingBottom = UDim.new(0, margin),
				PaddingLeft = UDim.new(0, margin),
				PaddingRight = UDim.new(0, margin),
			}),
			Left = e("Frame", {
				Size = UDim2.new(0, skin.px(LEFT_WIDTH), 1, 0),
				BackgroundTransparency = 1,
				ZIndex = 11,
			}, {
				Preview = e(PreviewCard, { nav = nav, look = props.look, openList = openList }),
				Basket = e(BasketCard, { nav = nav, look = props.look, openList = openList }),
			}),
			Content = e(GlassPanel, {
				variant = "light",
				cornerRadius = Tokens.radius.contentPanel,
				position = UDim2.fromOffset(skin.px(LEFT_WIDTH + GAP), 0),
				size = UDim2.new(1, -skin.px(LEFT_WIDTH + GAP), 1, 0),
				zIndex = 11,
			}, {
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, skin.px(14)),
					PaddingBottom = UDim.new(0, skin.px(14)),
					PaddingLeft = UDim.new(0, skin.px(16)),
					PaddingRight = UDim.new(0, skin.px(16)),
				}),
				Crumbs = if hasCrumbs
					then e(Breadcrumbs, {
						rootLabel = nav.root :: string,
						stack = nav.stack,
						onBack = nav.back,
						onPopTo = nav.popTo,
					})
					else nil,
				Screen = e("Frame", {
					Position = UDim2.fromOffset(0, crumbsHeight),
					Size = UDim2.new(1, 0, 1, -crumbsHeight),
					BackgroundTransparency = 1,
				}, {
					["Root/" .. (nav.root or "")] = e("Frame", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Visible = deep == nil,
					}, {
						Appear = e(ScreenAppear, nil, { Screen = rootScreen(nav, props.look) }),
					}),
					[deepKey] = if deep then e(ScreenAppear, nil, { Screen = deep }) else nil,
				}),
			}),
		}),
	})
end

return FullPanel
