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
local Bolt = require(ReplicatedStorage:WaitForChild("Bolt"))

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
local SessionStore = require(hooks:WaitForChild("SessionStore"))
local PlaceholderData = require(views:WaitForChild("screens"):WaitForChild("PlaceholderData"))
local usePlaceholderLook = require(views:WaitForChild("screens"):WaitForChild("usePlaceholderLook"))
local WorldHud = require(views:WaitForChild("WorldHud"))
local FullPanel = require(views:WaitForChild("panel"):WaitForChild("FullPanel"))
local WorldRenderer = require(views:WaitForChild("WorldRenderer"))
local ShareDialog = require(views:WaitForChild("screens"):WaitForChild("ShareDialog"))
local StoreDialogs = require(views:WaitForChild("screens"):WaitForChild("StoreDialogs"))
local StoresClient = require(views:WaitForChild("catalogue"):WaitForChild("StoresClient"))
local CatalogueFilters = require(views:WaitForChild("screens"):WaitForChild("CatalogueFilters"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

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
	feedback.wearOutfitItems = function(id: number, indices: { number }, withSkin: boolean?, withScale: boolean?)
		Sounds.play(if #indices > 0 or withSkin or withScale then "tryOn" else "error")
		look.wearOutfitItems(id, indices, withSkin, withScale)
	end
	feedback.toggleFollow = function(userId: number)
		Sounds.play(if look.isFollowing(userId) then "back" else "confirm")
		look.toggleFollow(userId)
	end
	feedback.wearShared = function(code: string)
		Sounds.play("tryOn")
		look.wearShared(code)
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
	feedback.setScale = function(scale: any)
		Sounds.play("tryOn")
		look.setScale(scale)
	end
	feedback.moveLayer = function(id: number, direction: number)
		Sounds.play("tryOn")
		look.moveLayer(id, direction)
	end
	feedback.wearAll = function(ids: { number }, skin: any?, scale: any?): number
		local count = look.wearAll(ids, skin, scale)
		Sounds.play(if count > 0 then "tryOn" else "error")
		return count
	end
	feedback.takeOffMany = function(ids: { number })
		Sounds.play("back")
		look.takeOffMany(ids)
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
	-- What the share dialog is open for, if anything: a saved outfit, one
	-- saved on Roblox (a creation), or a store (id = its code).
	local shareTarget, setShareTarget = React.useState(nil :: { kind: string, id: any, name: string }?)
	-- The store picker or the Create store dialog, if one is open.
	local storeDialog, setStoreDialog = React.useState(nil :: StoreDialogs.Dialog?)
	-- Filling one of your store's rows from the Catalogue (pick mode): the
	-- row, the store page's crumbs to go back to, and the row as it'll be
	-- (`order`, kept here until Done saves it; Cancel leaves the row be).
	local picking, setPicking = React.useState(nil :: {
		code: string,
		row: string,
		storeName: string,
		rowName: string,
		stack: { any },
		start: { number },
		order: { number },
		waiting: boolean,
		problem: string?,
	}?)
	local latestPicking = React.useRef(picking)
	latestPicking.current = picking
	local latestNav = React.useRef(nav)
	latestNav.current = nav
	-- Choosing an items search row's search in the Catalogue (setup mode):
	-- the row, the store page's crumbs, and the Catalogue's own browse
	-- from before (put back after).
	local searching, setSearching = React.useState(nil :: {
		code: string,
		row: string,
		storeName: string,
		rowName: string,
		stack: { any },
		saved: { [string]: any },
		waiting: boolean,
		problem: string?,
	}?)
	local latestSearching = React.useRef(searching)
	latestSearching.current = searching
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
		if shareTarget then
			Sounds.play("back")
			setShareTarget(nil)
		elseif storeDialog then
			Sounds.play("back")
			setStoreDialog(nil)
		elseif picking and #nav.stack == 0 then
			Sounds.play("back") -- (as Cancel)
			setPicking(nil)
			nav.restore("Stores", picking.stack)
		elseif searching and #nav.stack == 0 then
			Sounds.play("back")
			for key, value in searching.saved do
				SessionStore[key] = value
			end
			setSearching(nil)
			nav.restore("Stores", searching.stack)
		elseif #nav.stack > 0 then
			Sounds.play("back")
			nav.back()
		elseif nav.isOpen then
			nav.close() -- the close sound plays from the effect below
		else
			return false
		end
		return true
	end)

	-- Pick mode and search setup are only for the Catalogue: moving off it
	-- (or closing) ends them (setup mode puts the Catalogue's browse back).
	-- Only a move off it: they start just before the Catalogue opens, and
	-- (started from a task) needn't land in the same render.
	local lastRoot = React.useRef(nav.root)
	React.useEffect(function()
		local left = lastRoot.current == "Catalogue" and nav.root ~= "Catalogue"
		lastRoot.current = nav.root
		if not left then
			return nil
		end
		if picking or searching then
			Sounds.play("back") -- unsaved picks or setup are dropped, as Cancel would
		end
		if picking then
			setPicking(nil)
		end
		if searching then
			for key, value in searching.saved do
				SessionStore[key] = value
			end
			setSearching(nil)
		end
		return nil
	end, { nav.root } :: { any })

	-- Joined through a share link (DeepLinkService): open what it shares,
	-- an outfit under Outfits › Community, a store under Stores. Kinds we
	-- don't show yet are skipped.
	React.useEffect(function()
		local thread = task.spawn(function()
			local ok, link = pcall(function()
				return Bolt.RemoteFunction("TakeJoinLink"):InvokeServer()
			end)
			if not ok or type(link) ~= "table" or type(link.code) ~= "string" then
				return
			end
			if link.kind == "outfit" then
				SessionStore["outfits.source"] = "Community"
				SessionStore["outfits.query"] = ""
				nav.openRoot("Outfits")
				nav.push({ kind = "outfit", id = { source = "Shared", index = link.code }, label = "Shared outfit" })
			elseif link.kind == "store" then
				nav.openRoot("Stores")
				nav.push({ kind = "store", id = link.code, label = "Store" })
			end
		end)
		return function()
			task.cancel(thread)
		end
	end, {})

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

	-- Navigation analytics (NavigationController): every change of the panel's
	-- root or page, and closing it.
	local depth = #nav.stack
	local screen = if nav.top then nav.top.kind else "home"
	local reported = React.useRef(false)
	React.useEffect(function()
		if not nav.root and not reported.current then
			return nil -- still closed since joining
		end
		reported.current = nav.root ~= nil
		Network.Intent.Navigation:FireServer(Network.Actions.Navigation.View, {
			root = nav.root,
			screen = screen,
			depth = depth,
		})
		return nil
	end, { nav.root or "", screen, depth } :: { any })

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
			buy = function(itemIds: { number }, key: string?, store: string?)
				local unowned = {}
				for _, id in itemIds do
					local item = PlaceholderData.item(id)
					if item and item.thumbnail ~= "" and not item.owned then
						table.insert(unowned, id)
					end
				end
				local request = if #unowned > 0 then latestLook.current.buy(unowned, store) else nil
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
			setupSearch = function(target: any)
				-- The Catalogue opens fresh from the session store, so set the
				-- row's search there (keeping what was there to put back).
				local keys = { "catalogue.category", "catalogue.sub", "catalogue.query", "catalogue.filters" }
				local saved = {}
				for _, key in keys do
					saved[key] = SessionStore[key]
				end
				local search = target.search
				if type(search) == "table" and type(search.category) == "string" then
					local filters = CatalogueFilters.defaults()
					filters.minPrice = search.minPrice
					filters.maxPrice = search.maxPrice
					filters.sort = search.sort or filters.sort
					filters.sortWindow = search.sortWindow or filters.sortWindow
					filters.creator = search.creator or ""
					filters.salesType = search.salesType or filters.salesType
					if search.includeOffSale ~= nil then
						filters.includeOffSale = search.includeOffSale
					end
					filters.colour = search.colour or ""
					SessionStore["catalogue.category"] = search.category
					SessionStore["catalogue.sub"] = search.chip or "All"
					SessionStore["catalogue.query"] = search.keyword or ""
					SessionStore["catalogue.filters"] = filters
				end
				Sounds.play("open")
				setPicking(nil)
				setSearching({
					code = target.code,
					row = target.row,
					storeName = target.storeName,
					rowName = target.rowName,
					stack = table.clone(latestNav.current.stack),
					saved = saved,
					waiting = false,
					problem = nil,
				})
				latestNav.current.openRoot("Catalogue")
			end,
			searching = if searching
				then { storeName = searching.storeName, rowName = searching.rowName, waiting = searching.waiting, problem = searching.problem }
				else nil,
			useSearch = function(browse: any)
				local current = latestSearching.current
				if not current or current.waiting then
					return
				end
				setSearching(function(old: any)
					if not old then
						return old
					end
					local new = table.clone(old)
					new.waiting = true
					new.problem = nil
					return new
				end)
				task.spawn(function()
					local ok, _, err = StoresClient.act(Network.Actions.Stores.SetRowSearch, {
						code = current.code,
						row = current.row,
						content = "items",
						search = browse,
					})
					if ok then
						Sounds.play("confirm")
						for key, value in current.saved do
							SessionStore[key] = value
						end
						setSearching(nil)
						latestNav.current.restore("Stores", current.stack)
					else
						Sounds.play("error")
						setSearching(function(old: any)
							if not old then
								return old
							end
							local new = table.clone(old)
							new.waiting = false
							new.problem = if err == "bad" then "That can't be a search (try a category tab)" else StoreDialogs.message(err, "row")
							return new
						end)
					end
				end)
			end,
			endSearch = function()
				local current = latestSearching.current
				if current then
					Sounds.play("back")
					for key, value in current.saved do
						SessionStore[key] = value
					end
					setSearching(nil)
					latestNav.current.restore("Stores", current.stack)
				end
			end,
			pickForRow = function(target: any)
				if target.kind == "outfits" then
					Sounds.play("open")
					setStoreDialog({ kind = "outfits", code = target.code, row = target.row, storeName = target.storeName, rowName = target.rowName })
					return
				end
				Sounds.play("open")
				setPicking({
					code = target.code,
					row = target.row,
					storeName = target.storeName,
					rowName = target.rowName,
					stack = table.clone(latestNav.current.stack),
					start = table.clone(target.ids or {}),
					order = table.clone(target.ids or {}),
					waiting = false,
					problem = nil,
				})
				latestNav.current.openRoot("Catalogue")
			end,
			picking = if picking
				then {
					code = picking.code,
					row = picking.row,
					storeName = picking.storeName,
					rowName = picking.rowName,
					count = #picking.order,
					waiting = picking.waiting,
					problem = picking.problem,
				}
				else nil,
			isPicked = function(id: number): boolean
				return picking ~= nil and table.find(picking.order, id) ~= nil
			end,
			pickToggle = function(id: number)
				local current = latestPicking.current
				local item = PlaceholderData.item(id)
				if not current or current.waiting or not item or not item.targetId then
					return
				end
				Sounds.play("press")
				setPicking(function(old: any)
					if not old or old.code ~= current.code or old.row ~= current.row then
						return old
					end
					local new = table.clone(old)
					new.order = table.clone(old.order)
					new.problem = nil
					local index = table.find(new.order, id)
					if index then
						table.remove(new.order, index)
					else
						table.insert(new.order, id) -- new ones at the end
					end
					return new
				end)
			end,
			endPicking = function(save: boolean)
				local current = latestPicking.current
				if not current or current.waiting then
					return
				end
				local function leave()
					setPicking(nil)
					latestNav.current.restore("Stores", current.stack)
				end
				local same = #current.order == #current.start
				for index, id in current.order do
					if current.start[index] ~= id then
						same = false
					end
				end
				if not save or same then
					Sounds.play("back")
					leave()
					return
				end
				local keys = {}
				for _, id in current.order do
					local item = PlaceholderData.item(id)
					if item and item.targetId then
						table.insert(keys, item.kind .. ":" .. item.targetId)
					end
				end
				setPicking(function(old: any)
					if not old then
						return old
					end
					local new = table.clone(old)
					new.waiting = true
					new.problem = nil
					return new
				end)
				task.spawn(function()
					local ok, _, err = StoresClient.act(Network.Actions.Stores.SetRowItems, { code = current.code, row = current.row, items = keys })
					if ok then
						Sounds.play("confirm")
						leave()
					else
						Sounds.play("error")
						setPicking(function(old: any)
							if not old then
								return old
							end
							local new = table.clone(old)
							new.waiting = false
							new.problem = StoreDialogs.message(err, "item")
							return new
						end)
					end
				end)
			end,
			addToStore = function(target: any)
				Sounds.play("open")
				setStoreDialog({ kind = "pick", target = target })
			end,
			createStore = function()
				Sounds.play("open")
				setStoreDialog({ kind = "create" })
			end,
			share = function(id: any, kind: string?, name: string?)
				Sounds.play("open")
				setShareTarget({ kind = kind or "saved", id = id, name = name or "" })
				if kind == "store" then
					return -- a store always has its code
				end
				-- An outfit with a code shows it at once, so make sure the code
				-- is listed on Community (one shared before codes were listed).
				if kind == "creation" then
					-- If it was edited on Roblox since it was shared, its old
					-- code is detached (Reveal then makes a new one); if not,
					-- it's listed.
					if latestLook.current.creationCodes[tostring(id)] then
						latestLook.current.shareCreation(id, name or "", true)
					end
				else
					for _, outfit in latestLook.current.outfits do
						if outfit.id == id and outfit.code and not latestLook.current.isPublished(outfit.code) then
							latestLook.current.shareOutfit(id)
						end
					end
				end
			end,
		}
	end, { buyingKey, picking, searching } :: { any })

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
			Share = e(ShareDialog, {
				outfit = (function()
					local target = shareTarget
					if not target then
						return nil
					end
					if target.kind == "creation" then
						return { id = target.id, name = target.name, code = rawLook.creationCodes[tostring(target.id)] }
					elseif target.kind == "store" then
						return { id = 0, name = target.name, code = target.id, kind = "store" }
					end
					for _, outfit in rawLook.outfits do
						if outfit.id == target.id then
							return outfit
						end
					end
					return nil
				end)(),
				onReveal = function(id: number)
					local target = shareTarget
					if target and target.kind == "creation" then
						rawLook.shareCreation(id, target.name)
					else
						rawLook.shareOutfit(id)
					end
				end,
				onClose = function()
					setShareTarget(nil)
				end,
			}),
			Stores = e(StoreDialogs.Dialog, {
				dialog = storeDialog,
				myStores = rawLook.myStores,
				published = rawLook.published,
				onCreated = function(code: string, name: string)
					setStoreDialog(nil)
					nav.push({ kind = "store", id = code, label = name })
				end,
				onClose = function()
					setStoreDialog(nil)
				end,
			}),
		}),
	})
end

return Hud
