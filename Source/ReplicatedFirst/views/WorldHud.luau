--!strict

--[[
	WorldHud (design frame 5a: the HUD over the world)

	Tab bar top centre; bottom-left the Basket button, then Wearing, Create
	avatar and Save to Roblox; bottom-right the World options
	toggle and its side panel. The top-left is left clear for Roblox's own
	top-bar buttons (the tab bar is centred, so nothing reaches it).

	Hidden while the full panel is open — the design's panel covers it. When it
	comes back, the bottom buttons rise into place; World options slides in and
	out from the right; the Basket badge total rolls.
	Basket and Wearing carry a callout once they hold anything: the basket's
	Robux total (or its item count when everything in it is free), and how
	many items are being worn. Create avatar (save the look as a new Roblox
	outfit) and Save to Roblox (make it their Roblox avatar) open Roblox's own
	prompts (AccountPrompts). There's no Reset here: Outfits › Mine's "Your
	avatar" does it.

	Props:
		nav, look
		tabs: { PillTabs.Tab }
		world: useWorldOptions result { options, config, change, commit }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useAppear = require(hooks:WaitForChild("useAppear"))
local useSpringNumber = require(hooks:WaitForChild("useSpringNumber"))
local useTransition = require(hooks:WaitForChild("useTransition"))
local PillButton = require(components:WaitForChild("PillButton"))
local AccountPrompts = require(views:WaitForChild("AccountPrompts"))
local PillTabs = require(components:WaitForChild("PillTabs"))
local Badge = require(components:WaitForChild("Badge"))
local WorldOptionsView = require(views:WaitForChild("WorldOptionsView"))
local Sounds = require(views:WaitForChild("Sounds"))

local e = React.createElement

export type Props = {
	nav: any,
	look: any,
	tabs: { any },
	world: any,
}

local function WorldHud(props: Props)
	local skin = useSkin()
	local worldOpen, setWorldOpen = React.useState(false)
	local function setWorld(open: boolean)
		Sounds.play(if open then "worldIn" else "worldOut")
		setWorldOpen(open)
	end

	local basket = Tokens.size.basket
	local action = Tokens.size.action
	local edge = skin.px(Tokens.size.edgeInset)
	local total = useSpringNumber(props.look.basketTotal, Tokens.spring.count)
	local basketCount = useSpringNumber(#props.look.basket, Tokens.spring.count)
	local wornCount = useSpringNumber(#props.look.worn, Tokens.spring.count)
	local rise = useAppear(Tokens.spring.slide)
	local worldTransitions = useTransition(worldOpen, {
		from = { t = 0 },
		enter = { t = 1 },
		leave = { t = 0 },
		config = Tokens.spring.slide,
		leaveConfig = Tokens.spring.panelOut,
	})
	local worldPanels: { [string]: any } = {}
	for _, transition in worldTransitions do
		worldPanels.World = e(WorldOptionsView, {
			t = transition.springProps.t,
			options = props.world.options,
			config = props.world.config,
			onChange = props.world.change,
			onCommit = props.world.commit,
			onReset = props.world.reset,
			onClose = function()
				setWorld(false)
			end,
		})
	end

	-- A callout pinned to a round button's top-right (design: top -8, right -18
	-- on the 84 Basket button; scaled down for the smaller ones).
	local function callout(text: string, size: number)
		return e(Badge, {
			kind = "count",
			tone = "orange",
			text = text,
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.fromOffset(skin.px(18 * size / basket.size), -skin.px(8)),
			zIndex = 6,
		})
	end

	local function actionButton(icon: string, order: number, onActivated: (() -> ())?, sound: any?, badge: any?)
		return e(PillButton, {
			sound = sound,
			badge = badge,
			variant = "round",
			size = action.size,
			icon = icon,
			iconSize = action.icon,
			glowRadius = action.glow,
			layoutOrder = order,
			zIndex = 2,
			onActivated = onActivated,
		})
	end

	return e("Frame", {
		Name = "WorldHud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Tabs = e(PillTabs, {
			tabs = props.tabs,
			activeId = nil,
			sound = false, -- opening the panel plays its own sound
			onSelect = props.nav.toggleTab,
			anchorPoint = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, skin.px(16)),
			zIndex = 2,
		}),
		BottomLeft = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = rise:map(function(t: number)
				return UDim2.new(0, edge, 1, -edge + (1 - t) * skin.px(basket.size + edge))
			end),
			Size = UDim2.fromOffset(skin.px(basket.size + 12 * 3 + action.size * 3), skin.px(basket.size)),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(12)),
			}),
			Basket = e(PillButton, {
				variant = "round",
				size = basket.size,
				icon = "shopping_basket",
				iconSize = basket.icon,
				glowRadius = basket.glow,
				layoutOrder = 1,
				zIndex = 2,
				sound = false, -- opening the panel plays its own sound
				onActivated = function()
					props.nav.openRoot("Basket")
				end,
				badge = if #props.look.basket == 0 then nil
					elseif props.look.basketTotal > 0 then callout(Tokens.robux(total), basket.size)
					else callout(tostring(basketCount), basket.size),
			}),
			Wearing = actionButton("checkroom", 2, function()
				props.nav.openRoot("Wearing")
			end, false, if #props.look.worn > 0 then callout(tostring(wornCount), action.size) else nil),
			CreateAvatar = actionButton("person_add", 3, AccountPrompts.createOutfit),
			SaveToRoblox = actionButton("cloud_upload", 4, AccountPrompts.saveAvatar),
		}),
		WorldToggle = e(PillButton, {
			variant = "round",
			size = action.size,
			icon = "landscape",
			iconSize = action.icon,
			glowRadius = action.glow,
			active = worldOpen,
			anchorPoint = Vector2.new(1, 1),
			position = rise:map(function(t: number)
				return UDim2.new(1, -edge, 1, -edge + (1 - t) * skin.px(action.size + edge))
			end),
			zIndex = 2,
			sound = false, -- the slide plays its own swipe
			onActivated = function()
				setWorld(not worldOpen)
			end,
		}),
		World = e(React.Fragment, nil, worldPanels),
	})
end

return WorldHud
