--!strict

--[[
	WorldHud (design frame 5a: the HUD over the world)

	Tab bar top centre. Down the middle of the left edge, Wearing then Basket;
	down the middle of the right edge, the World options toggle (as big as
	them) with Create avatar, Save to Roblox and Reset avatar under it, and World options'
	side panel opens just inside that column. Both bottom corners stay clear
	for Roblox's touch controls (thumbstick, jump: issue #1), and the top-left
	for Roblox's own top-bar buttons (the tab bar is centred).

	Hidden while the full panel is open — the design's panel covers it. When it
	comes back, the side columns slide in from their edges, and they slide
	back out as the panel opens (`leaving`, while Hud keeps it for its leave);
	World options slides in and out from the right; the Basket badge total
	rolls.
	Basket and Wearing carry a callout once they hold anything: the basket's
	Robux total (or its item count when everything in it is free), and how
	many items are being worn. Create avatar (save the look as a new Roblox
	outfit) and Save to Roblox (make it their Roblox avatar) open Roblox's own
	prompts (AccountPrompts). Reset avatar, at the bottom of the right
	column, puts your own Roblox avatar back (undoable; Outfits › Current
	does it too). It asks first: the first press slides it out leftwards
	into an orange "Tap again to reset" pill for CONFIRM_SECONDS, and a
	second press within that resets.

	Props:
		nav, look
		tabs: { PillTabs.Tab }
		world: useWorldOptions result { options, config, change, commit }
		music: useMusic result?   for World options' Music section
		leaving: boolean?   the panel is opening over it: the columns slide away
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useSpring = require(hooks:WaitForChild("useSpring"))
local useSpringNumber = require(hooks:WaitForChild("useSpringNumber"))
local useTextWidth = require(hooks:WaitForChild("useTextWidth"))
local useTransition = require(hooks:WaitForChild("useTransition"))
local PillButton = require(components:WaitForChild("PillButton"))
local AccountPrompts = require(views:WaitForChild("AccountPrompts"))
local PillTabs = require(components:WaitForChild("PillTabs"))
local Badge = require(components:WaitForChild("Badge"))
local WorldOptionsView = require(views:WaitForChild("WorldOptionsView"))
local Sounds = require(views:WaitForChild("Sounds"))

local e = React.createElement

-- Callouts on Basket / Wearing: how far past the button's top-right corner
-- (design px).
local CALLOUT_RIGHT = 6
local CALLOUT_UP = 6

export type Props = {
	nav: any,
	look: any,
	tabs: { any },
	world: any,
	music: any?,
	leaving: boolean?,
}

local COLUMN_GAP = 12 -- design px between the buttons in a side column
local CONFIRM_SECONDS = 3 -- how long Reset avatar waits for its second press
local CONFIRM_LABEL = "Tap again to reset"

-- A round action button that asks before it acts: the first press slides it
-- out to the left (it sits at the right edge) as an orange pill with
-- CONFIRM_LABEL; a second press within CONFIRM_SECONDS acts, otherwise it
-- slides back.
local function ConfirmAction(props: { icon: string, onConfirm: () -> (), layoutOrder: number })
	local skin = useSkin()
	local action = Tokens.size.action
	local armed, setArmed = React.useState(false)
	React.useEffect(function()
		if not armed then
			return nil
		end
		local thread = task.delay(CONFIRM_SECONDS, function()
			setArmed(false)
		end)
		return function()
			task.cancel(thread)
		end
	end, { armed })
	local style = Tokens.type.cta
	local textWidth = useTextWidth(CONFIRM_LABEL, Tokens.font(style.weight), skin.textPx(style.size))
	-- Design px: icon, gaps and padding around the label.
	local full = math.ceil(textWidth) + action.icon + 44
	local width = useSpringNumber(if armed then full else action.size, Tokens.spring.state)
	-- The slot keeps its place in the column; the button grows out of it.
	return e("Frame", {
		Size = UDim2.fromOffset(skin.px(action.size), skin.px(action.size)),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		ZIndex = 2,
	}, {
		Button = e(PillButton, {
			variant = "pill",
			size = action.size,
			width = math.max(width, action.size),
			icon = props.icon,
			iconSize = action.icon,
			label = if armed and width >= full - 4 then CONFIRM_LABEL else nil,
			-- Opening: the icon keeps its place at the left as the pill grows,
			-- so the label arriving doesn't move it.
			contentInset = if armed then (action.size - action.icon) / 2 else nil,
			active = armed,
			glowRadius = action.glow,
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.fromScale(1, 0),
			zIndex = 2,
			sound = if armed then false else nil, -- the reset plays its own sound
			onActivated = function()
				if armed then
					setArmed(false)
					props.onConfirm()
				else
					setArmed(true)
				end
			end,
		}),
	})
end

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
	-- The side columns slide in from their edges when it mounts, and back out
	-- while it's leaving.
	local shown, setShown = React.useState(false)
	React.useEffect(function()
		setShown(true)
	end, {})
	local rise = useSpring(
		{ t = if props.leaving then 0 elseif shown then 1 else 0 },
		if props.leaving then Tokens.spring.panelOut else Tokens.spring.slide
	).t
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
			inset = Tokens.size.edgeInset + basket.size + COLUMN_GAP, -- clear of the right column
			options = props.world.options,
			config = props.world.config,
			onChange = props.world.change,
			onCommit = props.world.commit,
			onReset = props.world.reset,
			music = props.music,
			onClose = function()
				setWorld(false)
			end,
		})
	end

	-- A callout pinned over a big round button's top-right corner.
	local function callout(text: string)
		return e(Badge, {
			kind = "count",
			tone = "orange",
			text = text,
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.fromOffset(skin.px(CALLOUT_RIGHT), -skin.px(CALLOUT_UP)),
			zIndex = 6,
		})
	end

	local function actionButton(icon: string, order: number, onActivated: (() -> ())?, sound: any?)
		return e(PillButton, {
			sound = sound,
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
		-- Down the middle of the left edge (clear of the thumbstick corner).
		Left = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = rise:map(function(t: number)
				return UDim2.new(0, edge - (1 - t) * skin.px(basket.size + Tokens.size.edgeInset), 0.5, 0)
			end),
			Size = UDim2.fromOffset(skin.px(basket.size), skin.px(basket.size * 2 + COLUMN_GAP)),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(COLUMN_GAP)),
			}),
			Basket = e(PillButton, {
				variant = "round",
				size = basket.size,
				icon = "shopping_basket",
				iconSize = basket.icon,
				glowRadius = basket.glow,
				layoutOrder = 2,
				zIndex = 2,
				sound = false, -- opening the panel plays its own sound
				onActivated = function()
					props.nav.resume("Basket")
				end,
				badge = if #props.look.basket == 0 then nil
					elseif props.look.basketTotal > 0 then callout(Tokens.robux(total))
					else callout(tostring(basketCount)),
			}),
			-- As big as Basket: the other way into your look.
			Wearing = e(PillButton, {
				variant = "round",
				size = basket.size,
				icon = "checkroom",
				iconSize = basket.icon,
				glowRadius = basket.glow,
				layoutOrder = 1,
				zIndex = 2,
				sound = false, -- opening the panel plays its own sound
				onActivated = function()
					props.nav.resume("Wearing")
				end,
				badge = if #props.look.worn > 0 then callout(tostring(wornCount)) else nil,
			}),
		}),
		-- Down the middle of the right edge (clear of the jump button corner).
		Right = e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = rise:map(function(t: number)
				return UDim2.new(1, -edge + (1 - t) * skin.px(basket.size + Tokens.size.edgeInset), 0.5, 0)
			end),
			Size = UDim2.fromOffset(skin.px(basket.size), skin.px(basket.size + action.size * 3 + COLUMN_GAP * 3)),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(COLUMN_GAP)),
			}),
			WorldToggle = e(PillButton, {
				variant = "round",
				size = basket.size,
				icon = "landscape",
				iconSize = basket.icon,
				glowRadius = basket.glow,
				active = worldOpen,
				layoutOrder = 1,
				zIndex = 2,
				sound = false, -- the slide plays its own swipe
				onActivated = function()
					setWorld(not worldOpen)
				end,
			}),
			CreateAvatar = actionButton("person_add", 2, AccountPrompts.createOutfit),
			SaveToRoblox = actionButton("cloud_upload", 3, AccountPrompts.saveAvatar),
			-- Back to your own Roblox avatar, after a second press (its own
			-- sound; Undo reverses it).
			ResetAvatar = e(ConfirmAction, { icon = "restart_alt", onConfirm = props.look.reset, layoutOrder = 4 }),
		}),
		World = e(React.Fragment, nil, worldPanels),
	})
end

return WorldHud
