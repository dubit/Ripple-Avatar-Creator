--!strict

--[[
	Hud

	Root of the react-luau HUD, mounted by HudApp. Owns:
	  · navigation (useNavigation) and the panel's open/close motion — the panel
	    stays mounted through its exit animation, showing the screen it had
	  · the placeholder look (worn / basket) until the server models land,
	    wrapped so every change confirms itself with a sound
	  · buying, reachable anywhere through HudContext: straight to Roblox's
	    own purchase prompt (no confirmation of ours in front of it), with a
	    sound when it ends
	  · tapping your own avatar in the world opens Wearing (useTapAvatar)
	  · back input (mouse back button, Backspace): pops a breadcrumb, then
	    closes the panel
	  · World options (saved + live draft, useWorldOptions) and the renderer
	    that applies them to this client's world

	Renders inside a SkinRoot with the Task 1 decisions: `fill` sizing scaled
	by height, `blur` glass.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local Sounds = require(views:WaitForChild("Sounds"))
local HudContext = require(views:WaitForChild("HudContext"))
local SkinRoot = require(components:WaitForChild("SkinRoot"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useGlassBlur = require(hooks:WaitForChild("useGlassBlur"))
local useNavigation = require(hooks:WaitForChild("useNavigation"))
local useBackInput = require(hooks:WaitForChild("useBackInput"))
local useTapAvatar = require(hooks:WaitForChild("useTapAvatar"))
local useTransition = require(hooks:WaitForChild("useTransition"))
local useWorldOptions = require(hooks:WaitForChild("useWorldOptions"))
local PlaceholderData = require(views:WaitForChild("screens"):WaitForChild("PlaceholderData"))
local usePlaceholderLook = require(views:WaitForChild("screens"):WaitForChild("usePlaceholderLook"))
local WorldHud = require(views:WaitForChild("WorldHud"))
local FullPanel = require(views:WaitForChild("panel"):WaitForChild("FullPanel"))
local WorldRenderer = require(views:WaitForChild("WorldRenderer"))

local e = React.createElement

-- Seconds a Buy button may spin waiting for the purchase's outcome.
local BUY_SPINNER_TIMEOUT = 60

local TABS = {
	{ id = "Catalogue", label = "Catalogue", icon = "apparel" },
	{ id = "Stores", label = "Stores", icon = "storefront" },
	{ id = "Outfits", label = "Outfits", icon = "checkroom" },
}

-- Lives inside SkinRoot so it reads the glass mode from context.
local function BlurDriver(props: { active: boolean })
	local skin = useSkin()
	useGlassBlur(props.active and skin.glass == "blur")
	return nil
end

-- Wraps the placeholder look so each change plays its sound. No toasts:
-- confirmation lives where the player is looking (the item, the avatar).
local function withFeedback(look: any)
	local feedback = table.clone(look)
	feedback.toggleWear = function(id: number): boolean
		if not look.canWear(id) then
			Sounds.play("error") -- a mock item: nothing real to put on
			return false
		end
		Sounds.play(if look.isWorn(id) then "back" else "tryOn")
		return look.toggleWear(id)
	end
	feedback.toggleBasket = function(id: number): boolean
		if not look.canWear(id) then
			Sounds.play("error") -- a mock item: nothing real to buy
			return false
		end
		Sounds.play(if look.inBasket(id) then "back" else "confirm")
		return look.toggleBasket(id)
	end
	feedback.saveOutfit = function(): boolean
		local saved = look.saveOutfit()
		Sounds.play(if saved then "confirm" else "error") -- nothing worn to save
		return saved
	end
	feedback.overwriteOutfit = function(id: number)
		Sounds.play("confirm")
		look.overwriteOutfit(id)
	end
	feedback.wearOutfit = function(id: number)
		Sounds.play("tryOn")
		look.wearOutfit(id)
	end
	feedback.wearOutfitItems = function(id: number, indices: { number }, withSkin: boolean?)
		Sounds.play(if #indices > 0 or withSkin then "tryOn" else "error")
		look.wearOutfitItems(id, indices, withSkin)
	end
	feedback.toggleFollow = function(userId: number)
		Sounds.play(if look.isFollowing(userId) then "back" else "confirm")
		look.toggleFollow(userId)
	end
	feedback.wearUserLook = function(userId: number)
		Sounds.play("tryOn")
		look.wearUserLook(userId)
	end
	feedback.wearRobloxOutfit = function(outfitId: number)
		Sounds.play("tryOn")
		look.wearRobloxOutfit(outfitId)
	end
	feedback.deleteOutfit = function(id: number)
		Sounds.play("back")
		look.deleteOutfit(id)
	end
	feedback.clearBasket = function()
		Sounds.play("back")
		look.clearBasket()
	end
	feedback.addToBasket = function(ids: { number }): number
		local count = look.addToBasket(ids)
		Sounds.play(if count > 0 then "confirm" else "error")
		return count
	end
	feedback.setSkin = function(skin: any)
		Sounds.play("tryOn")
		look.setSkin(skin)
	end
	feedback.wearAll = function(ids: { number }, skin: any?): number
		local count = look.wearAll(ids, skin)
		Sounds.play(if count > 0 then "tryOn" else "error")
		return count
	end
	feedback.takeOffAll = function()
		Sounds.play("back")
		look.takeOffAll()
	end
	feedback.undo = function()
		if look.canUndo then
			Sounds.play("back")
			look.undo()
		end
	end
	feedback.reset = function()
		Sounds.play("back")
		look.reset()
	end
	return feedback
end

local function Hud()
	local nav = useNavigation()
	local rawLook = usePlaceholderLook()
	-- The latest purchase we sent (its request id), to sound its outcome,
	-- and the button that sent it (spinning until the outcome arrives).
	local buyRequest, setBuyRequest = React.useState(nil :: number?)
	local buyingKey, setBuyingKey = React.useState(nil :: string?)
	local world = useWorldOptions()
	local look = withFeedback(rawLook)
	local latestLook = React.useRef(rawLook)
	latestLook.current = rawLook

	-- Roblox's prompt shows what happened; we just sound it.
	local purchase = rawLook.purchase
	React.useEffect(function()
		if not buyRequest or purchase.id ~= buyRequest or purchase.state == "waiting" then
			return
		end
		if #purchase.bought > 0 then
			Sounds.play("purchase")
		elseif purchase.state == "failed" then
			Sounds.play("error")
		end
		setBuyRequest(nil)
		setBuyingKey(nil)
	end, { purchase })
	-- Don't spin forever if no outcome ever comes back.
	React.useEffect(function()
		if not buyingKey then
			return nil
		end
		local thread = task.delay(BUY_SPINNER_TIMEOUT, function()
			setBuyingKey(nil)
		end)
		return function()
			task.cancel(thread)
		end
	end, { buyingKey })

	useBackInput(function()
		if #nav.stack > 0 then
			Sounds.play("back")
			nav.back()
		elseif nav.isOpen then
			nav.close() -- the close sound plays from the effect below
		else
			return false
		end
		return true
	end)

	-- Tapping your own avatar in the world opens Wearing (design 5a).
	useTapAvatar(function()
		nav.openRoot("Wearing") -- the open sound plays from the effect below
	end, not nav.isOpen)

	-- Open / close sounds on panel state changes.
	local wasOpen = React.useRef(false)
	React.useEffect(function()
		if nav.isOpen ~= wasOpen.current then
			Sounds.play(if nav.isOpen then "open" else "close")
			wasOpen.current = nav.isOpen
		end
	end, { nav.isOpen })

	-- Keep the last open navigation so the panel shows its screen while leaving.
	local lastOpenNav = React.useRef(nav)
	if nav.isOpen then
		lastOpenNav.current = nav
	end
	local panelTransitions = useTransition(nav.isOpen, {
		from = { t = 0 },
		enter = { t = 1 },
		leave = { t = 0 },
		config = Tokens.spring.panelIn,
		leaveConfig = Tokens.spring.panelOut,
	})

	local actions = React.useMemo(function()
		return {
			buy = function(itemIds: { number }, key: string?)
				local unowned = {}
				for _, id in itemIds do
					local item = PlaceholderData.item(id)
					if item and item.thumbnail ~= "" and not item.owned then
						table.insert(unowned, id)
					end
				end
				local request = if #unowned > 0 then latestLook.current.buy(unowned) else nil
				if request then
					setBuyRequest(request)
					setBuyingKey(key or (if #itemIds == 1 then "item:" .. itemIds[1] else "items"))
				else
					Sounds.play("error") -- nothing here left to buy
				end
			end,
			buying = function(key: string): boolean
				return buyingKey == key
			end,
		}
	end, { buyingKey })

	local panels: { [string]: any } = {}
	for _, transition in panelTransitions do
		panels["Panel"] = e(FullPanel, {
			nav = if nav.isOpen then nav else lastOpenNav.current,
			look = look,
			tabs = TABS,
			t = transition.springProps.t,
			closing = not nav.isOpen,
		})
	end

	return e(HudContext.Provider, { value = actions }, {
		Skin = e(SkinRoot, {
			sizing = "fill",
			axis = "height",
			glass = "blur",
		}, {
			Blur = e(BlurDriver, { active = nav.isOpen }),
			Renderer = e(WorldRenderer, { options = world.options, config = world.config }),
			World = if nav.isOpen then nil else e(WorldHud, { nav = nav, look = look, tabs = TABS, world = world }),
			Panel = e(React.Fragment, nil, panels),
		}),
	})
end

return Hud
