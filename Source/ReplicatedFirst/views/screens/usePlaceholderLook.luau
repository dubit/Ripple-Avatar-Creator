--!strict

--[[
	usePlaceholderLook

	What the avatar is wearing and what's in the basket, for the HUD's badges,
	counts, lists and buttons.

	  · Wearing is real (Task 5): it mirrors Network.State.Avatar (persisted,
	    server-authoritative), and try on / take off / wear all / take
	    everything off / undo / reset are intents to AvatarController. The
	    character itself changes on the server, so everyone sees it. Worn
	    entries are turned into items with CatalogueClient.remember.
	  · Favourites are real (Task 9): Network.State.Favourites (persisted),
	    toggled through FavouritesController.
	  · The basket is real (Task 10): Network.State.Basket (persisted),
	    changed through BasketController. Changes show at once
	    (optimistic): each is held as pending over the server's list until
	    the server's state agrees, or for PENDING_SECONDS if it never does
	    (a dropped or rejected request), after which the server's list wins.
	    "Try on everything" goes to AvatarController's WearMany like any
	    wear-all.

	  · Ownership and buying are real (Task 11): Network.State.Ownership
	    (session only). Worn and basket items are checked with
	    PurchaseController.Check (each once a session; checkOwned does the
	    same for an item page) and known-owned items get `owned = true`.
	    buy sends PurchaseController.Buy with a request id; the result comes
	    back as `purchase` (state, reason, keys bought) carrying that id.

	  · Outfits are real (Task 12): Network.State.Outfits (persisted), changed
	    through OutfitsController by outfit id (the server holds the items).
	  · Community (Task 16): the player's lists ride on the same state
	    (published, communityFavourites, communityRecent); publishing,
	    starring, reporting and opening go to CommunityController.

	Mock items (the prototype's placeholder data, no thumbnail) can't be
	worn, put in the basket or bought: the intents skip them and report it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))
local BodyScale = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("BodyScale"))

local views = script.Parent.Parent
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))
local CatalogueClient = require(views:WaitForChild("catalogue"):WaitForChild("CatalogueClient"))
local CommunityOutfits = require(views:WaitForChild("catalogue"):WaitForChild("CommunityOutfits"))
local useBoltState = require(views:WaitForChild("hooks"):WaitForChild("useBoltState"))

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))

export type SavedOutfit = {
	id: number,
	name: string,
	items: { number }, -- item ids, in the order they were put on
	skin: SkinColours.Colours, -- the skin colours saved with it ({} = the wearer's own)
	scale: any, -- the body scale saved with it ({} = the wearer's own)
	code: string?, -- its share code, once shared
}

export type Look = {
	worn: { number }, -- item ids, in the order put on
	basket: { number },
	canUndo: boolean,
	isWorn: (id: number) -> boolean,
	inBasket: (id: number) -> boolean,
	canWear: (id: number) -> boolean, -- a real catalogue item (not a mock)
	toggleWear: (id: number) -> boolean, -- false if the item can't be worn
	wearAll: (ids: { number }, skin: SkinColours.Colours?, scale: any?) -> number, -- how many could be worn; `skin` / `scale` set those too
	scale: any, -- chosen body scale (BodyScale; one left out is your own)
	ownScale: any, -- your own avatar's scale
	setScale: (scale: any) -> (),
	moveLayer: (id: number, direction: number) -> (), -- a layered item in (-1) or out (+1)
	skin: SkinColours.Colours, -- chosen skin colours by body part (a part left out is your own)
	ownSkin: SkinColours.Colours, -- your own avatar's colours, all six parts
	setSkin: (skin: SkinColours.Colours) -> (),
	refreshOwn: () -> (), -- re-read your Roblox avatar (it may have changed since you joined)
	takeOffAll: () -> (),
	takeOffMany: (ids: { number }) -> (), -- as one change (e.g. a body's parts)
	undo: () -> (),
	reset: () -> (), -- back to the player's own Roblox avatar
	isFavourite: (id: number) -> boolean,
	toggleFavourite: (id: number) -> boolean, -- false for mock items
	toggleBasket: (id: number) -> boolean, -- false for mock items
	addToBasket: (ids: { number }) -> number, -- how many were sent
	clearBasket: () -> (),
	checkOwned: (ids: { number }) -> (), -- ask the server, once a session each
	buy: (ids: { number }) -> number?, -- the request id; nil if nothing to buy
	purchase: Network.PurchaseResult, -- the latest purchase's outcome
	outfits: { SavedOutfit }, -- the player's saved outfits, oldest first
	currentOutfit: SavedOutfit?, -- the saved outfit being worn exactly, if any
	own: { number }, -- the player's own Roblox avatar's items (what Reset puts back)
	wearRobloxOutfit: (outfitId: number) -> (), -- an outfit saved on Roblox
	wearUserLook: (userId: number) -> (), -- another user's look (their items, your body)
	following: { number }, -- user ids followed here, newest first
	isFollowing: (userId: number) -> boolean,
	toggleFollow: (userId: number) -> (),
	saveOutfit: () -> boolean, -- save what's worn; false if nothing is
	overwriteOutfit: (id: number) -> (), -- replace its items with what's worn
	renameOutfit: (id: number, name: string) -> (),
	shareOutfit: (id: number) -> (), -- give it a share code (kept)
	shareCreation: (outfitId: number, name: string, check: boolean?) -> (), -- share a Roblox-saved outfit (`check`: only detach a stale code)
	creationCodes: { [string]: string }, -- share codes of shared Roblox-saved outfits, by outfit id
	wearShared: (code: string) -> (), -- wear a shared outfit exactly
	deleteOutfit: (id: number) -> (),
	wearOutfit: (id: number) -> (), -- exactly the outfit (replaces the look)
	wearOutfitItems: (id: number, indices: { number }, withSkin: boolean?, withScale: boolean?) -> (), -- over the look
	basketTotal: number, -- Robux for unowned basket items
	published: { string }, -- codes published to Community (Mine), newest first
	communityFavourites: { string }, -- Community codes starred, newest first
	communityRecent: { string }, -- Community codes opened lately, newest first
	isPublished: (code: string?) -> boolean,
	isCommunityFavourite: (code: string) -> boolean,
	publish: (target: { [string]: any }) -> (), -- { id } | { outfitId, name } | { code }
	unpublish: (code: string) -> (),
	toggleCommunityFavourite: (code: string) -> (),
	reportCommunity: (code: string) -> (),
	openCommunity: (code: string) -> (), -- its page was opened (Recent)
}

local DEFAULT_AVATAR = { worn = {}, canUndo = false }
local DEFAULT_FAVOURITES = { items = {} }
local DEFAULT_BASKET = { items = {} }
local DEFAULT_OUTFITS = { outfits = {} }
local DEFAULT_OWNERSHIP = { owned = {}, purchase = { id = 0, state = "idle", reason = "", bought = {} } }
local MAX_CHECK = 50 -- items per ownership check (PurchaseController's limit)
local MAX_BUY = 20 -- items per purchase prompt (PurchaseController's limit)
-- How long an optimistic basket change waits for the server to agree.
local PENDING_SECONDS = 3

-- An optimistic basket change: in or out, and when it was made.
type Pending = { add: boolean, at: number }

-- An item's favourites key: "Asset:123" / "Bundle:45" (nil for mock items).
local function favouriteKey(id: number): string?
	local item = PlaceholderData.item(id)
	if not item or item.thumbnail == "" then
		return nil
	end
	return item.kind .. ":" .. item.targetId
end

local function canWear(id: number): boolean
	local item = PlaceholderData.item(id)
	return item ~= nil and item.thumbnail ~= ""
end

local function ref(id: number)
	local item = PlaceholderData.item(id)
	return { targetId = item.targetId, kind = item.kind }
end

-- Keys already sent for an ownership check this session.
local requested: { [string]: boolean } = {}
local lastRequestId = 0

-- Ask the server who owns these (skipping mocks and keys already asked).
local function checkOwned(ids: { number })
	local refs = {}
	for _, id in ids do
		local key = favouriteKey(id)
		if key and not requested[key] then
			requested[key] = true
			table.insert(refs, ref(id))
			if #refs == MAX_CHECK then
				Network.Intent.Purchase:FireServer(Network.Actions.Purchase.Check, refs)
				refs = {}
			end
		end
	end
	if #refs > 0 then
		Network.Intent.Purchase:FireServer(Network.Actions.Purchase.Check, refs)
	end
end

local function usePlaceholderLook(): Look
	local avatar = useBoltState(Network.State.Avatar, DEFAULT_AVATAR :: any)
	local favourites = useBoltState(Network.State.Favourites, DEFAULT_FAVOURITES :: any)
	local favouriteSet = {}
	for _, key in favourites.items or {} do
		favouriteSet[key] = true
	end
	local basketState = useBoltState(Network.State.Basket, DEFAULT_BASKET :: any)
	local ownership = useBoltState(Network.State.Ownership, DEFAULT_OWNERSHIP :: any)
	local outfitState = useBoltState(Network.State.Outfits, DEFAULT_OUTFITS :: any)
	local outfits: { SavedOutfit } = {}
	for _, outfit in outfitState.outfits or {} do
		local ids = {}
		for _, entry in outfit.items or {} do
			table.insert(ids, CatalogueClient.remember(entry).id)
		end
		table.insert(outfits, {
			id = outfit.id,
			name = outfit.name,
			items = ids,
			skin = SkinColours.normalise(outfit.skin),
			scale = BodyScale.normalise(outfit.scale),
			code = outfit.code,
		})
	end
	-- Known-owned items show as owned wherever they appear (items are shared).
	for _, key in ownership.owned or {} do
		local kind, targetId = string.match(key, "^(%a+):(%d+)$")
		local number = tonumber(targetId)
		if kind and number then
			local item = PlaceholderData.item(if kind == "Bundle" then -number else number)
			if item then
				item.owned = true
			end
		end
	end
	local _ownedVersion, setOwnedVersion = React.useState(0)
	-- Optimistic basket changes by item id.
	local pending: { [number]: Pending }, setPending = React.useState({} :: { [number]: Pending })

	-- The server's basket, as item ids.
	local serverBasket = {}
	local serverSet = {}
	for _, entry in basketState.items or {} do
		local item = CatalogueClient.remember(entry)
		table.insert(serverBasket, item.id)
		serverSet[item.id] = true
	end

	-- Drop pending changes the server now agrees with, and stale ones.
	local function settle(current: { [number]: Pending }): { [number]: Pending }
		local now = os.clock()
		local result = nil
		for id, change in current do
			if (serverSet[id] == true) == change.add or now - change.at > PENDING_SECONDS then
				result = result or table.clone(current)
				result[id] = nil
			end
		end
		return result or current
	end
	React.useEffect(function()
		setPending(settle)
		return nil
	end, { basketState })
	-- Give up on the oldest outstanding change once it's stale.
	React.useEffect(function()
		local oldest = math.huge
		for _, change in pending do
			oldest = math.min(oldest, change.at)
		end
		if oldest == math.huge then
			return nil
		end
		local thread = task.delay(math.max(oldest + PENDING_SECONDS - os.clock(), 0) + 0.05, function()
			setPending(settle)
		end)
		return function()
			task.cancel(thread)
		end
	end, { pending })

	local function expect(ids: { number }, add: boolean)
		setPending(function(current: { [number]: Pending })
			local result = table.clone(current)
			local now = os.clock()
			for _, id in ids do
				result[id] = { add = add, at = now }
			end
			return result
		end)
	end

	-- Re-render when a worn or basket item's details (name, price) arrive.
	React.useEffect(function()
		local connection = CatalogueClient.changed:Connect(function()
			setOwnedVersion(function(n: number)
				return n + 1
			end)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local own = {}
	for _, entry in avatar.own or {} do
		table.insert(own, CatalogueClient.remember(entry).id)
	end

	local worn = {}
	local wornSet = {}
	for _, entry in avatar.worn or {} do
		local item = CatalogueClient.remember(entry)
		table.insert(worn, item.id)
		wornSet[item.id] = true
	end

	-- What the player sees: the server's basket with pending changes on top
	-- (pending adds at the end, in the order made).
	local basket = {}
	local basketSet = {}
	for _, id in serverBasket do
		local change = pending[id]
		if not change or change.add then
			table.insert(basket, id)
			basketSet[id] = true
		end
	end
	local added = {}
	for id, change in pending do
		if change.add and not basketSet[id] then
			table.insert(added, id)
		end
	end
	table.sort(added, function(a, b)
		return pending[a].at < pending[b].at
	end)
	for _, id in added do
		table.insert(basket, id)
		basketSet[id] = true
	end

	-- Check ownership of what's worn and in the basket (new items only).
	React.useEffect(function()
		local ids = table.clone(worn)
		for _, id in serverBasket do
			table.insert(ids, id)
		end
		checkOwned(ids)
		return nil
	end, { avatar, basketState })

	-- The saved outfit being worn exactly (same items, nothing more or less).
	local currentOutfit: SavedOutfit? = nil
	for _, outfit in outfits do
		if #outfit.items == #worn and #worn > 0 then
			local all = true
			for _, id in outfit.items do
				if not wornSet[id] then
					all = false
					break
				end
			end
			if all then
				currentOutfit = outfit
				break
			end
		end
	end

	local function isWorn(id: number): boolean
		return wornSet[id] == true
	end
	local function inBasket(id: number): boolean
		return basketSet[id] == true
	end

	local total = 0
	for _, id in basket do
		local item = PlaceholderData.item(id)
		if item and not item.owned then
			total += item.price
		end
	end

	local intent = Network.Intent.Avatar
	local actions = Network.Actions.Avatar

	return {
		worn = worn,
		basket = basket,
		canUndo = avatar.canUndo == true,
		isWorn = isWorn,
		inBasket = inBasket,
		canWear = canWear,
		toggleWear = function(id: number): boolean
			if not canWear(id) then
				return false
			end
			intent:FireServer(if isWorn(id) then actions.TakeOff else actions.TryOn, ref(id))
			return true
		end,
		skin = SkinColours.normalise(avatar.skin),
		ownSkin = SkinColours.normalise(avatar.ownSkin),
		setSkin = function(skin: SkinColours.Colours)
			intent:FireServer(actions.SetSkin, skin)
		end,
		refreshOwn = function()
			intent:FireServer(actions.RefreshOwn)
		end,
		scale = BodyScale.normalise(avatar.scale),
		ownScale = BodyScale.normalise(avatar.ownScale),
		setScale = function(scale: any)
			intent:FireServer(actions.SetScale, scale)
		end,
		moveLayer = function(id: number, direction: number)
			if canWear(id) then
				intent:FireServer(actions.MoveLayer, ref(id), direction)
			end
		end,
		wearAll = function(ids: { number }, skin: SkinColours.Colours?, scale: any?): number
			local refs = {}
			for _, id in ids do
				if canWear(id) then
					table.insert(refs, ref(id))
				end
			end
			-- The server takes up to maxWearMany; keep the most recent.
			while #refs > AvatarConfig.maxWearMany do
				table.remove(refs, 1)
			end
			if #refs > 0 or skin or scale then
				intent:FireServer(actions.WearMany, refs, { skin = skin, scale = scale })
			end
			return #refs + (if skin then 1 else 0) + (if scale then 1 else 0)
		end,
		takeOffAll = function()
			intent:FireServer(actions.TakeOffAll)
		end,
		takeOffMany = function(ids: { number })
			local refs = {}
			for _, id in ids do
				if canWear(id) then
					table.insert(refs, ref(id))
				end
			end
			if #refs > 0 then
				intent:FireServer(actions.TakeOffMany, refs)
			end
		end,
		undo = function()
			intent:FireServer(actions.Undo)
		end,
		reset = function()
			intent:FireServer(actions.Reset)
		end,
		isFavourite = function(id: number): boolean
			local key = favouriteKey(id)
			return key ~= nil and favouriteSet[key] == true
		end,
		toggleFavourite = function(id: number): boolean
			if not favouriteKey(id) then
				return false
			end
			Network.Intent.Favourites:FireServer(Network.Actions.Favourites.Toggle, ref(id))
			return true
		end,
		toggleBasket = function(id: number): boolean
			if not canWear(id) then
				return false
			end
			local basketActions = Network.Actions.Basket
			local adding = not inBasket(id)
			expect({ id }, adding)
			Network.Intent.Basket:FireServer(if adding then basketActions.Add else basketActions.Remove, ref(id))
			return true
		end,
		addToBasket = function(ids: { number }): number
			local refs, sent = {}, {}
			for _, id in ids do
				-- The server takes up to maxWearMany per request.
				if canWear(id) and not inBasket(id) and #refs < AvatarConfig.maxWearMany then
					table.insert(refs, ref(id))
					table.insert(sent, id)
				end
			end
			if #refs > 0 then
				expect(sent, true)
				Network.Intent.Basket:FireServer(Network.Actions.Basket.AddMany, refs)
			end
			return #refs
		end,
		clearBasket = function()
			if #basket > 0 then
				expect(basket, false)
				Network.Intent.Basket:FireServer(Network.Actions.Basket.Clear)
			end
		end,
		checkOwned = checkOwned,
		buy = function(ids: { number }): number?
			local refs = {}
			for _, id in ids do
				local item = PlaceholderData.item(id)
				if item and canWear(id) and not item.owned and #refs < MAX_BUY then
					table.insert(refs, ref(id))
				end
			end
			if #refs == 0 then
				return nil
			end
			lastRequestId += 1
			Network.Intent.Purchase:FireServer(Network.Actions.Purchase.Buy, { id = lastRequestId, items = refs })
			return lastRequestId
		end,
		purchase = ownership.purchase or DEFAULT_OWNERSHIP.purchase,
		outfits = outfits,
		currentOutfit = currentOutfit,
		own = own,
		wearRobloxOutfit = function(outfitId: number)
			intent:FireServer(actions.WearRobloxOutfit, outfitId)
		end,
		wearUserLook = function(userId: number)
			intent:FireServer(actions.WearUserLook, userId)
		end,
		following = outfitState.following or {},
		isFollowing = function(userId: number): boolean
			return table.find(outfitState.following or {}, userId) ~= nil
		end,
		toggleFollow = function(userId: number)
			Network.Intent.Outfits:FireServer(Network.Actions.Outfits.Follow, { userId = userId })
		end,
		saveOutfit = function(): boolean
			if #worn == 0 then
				return false
			end
			Network.Intent.Outfits:FireServer(Network.Actions.Outfits.Save)
			return true
		end,
		overwriteOutfit = function(id: number)
			if #worn > 0 then
				Network.Intent.Outfits:FireServer(Network.Actions.Outfits.Overwrite, { id = id })
			end
		end,
		shareOutfit = function(id: number)
			Network.Intent.Outfits:FireServer(Network.Actions.Outfits.Share, { id = id })
		end,
		shareCreation = function(outfitId: number, name: string, check: boolean?)
			Network.Intent.Outfits:FireServer(Network.Actions.Outfits.ShareCreation, { outfitId = outfitId, name = name, check = check == true })
		end,
		creationCodes = outfitState.creationCodes or {},
		wearShared = function(code: string)
			Network.Intent.Outfits:FireServer(Network.Actions.Outfits.WearShared, { code = code })
		end,
		renameOutfit = function(id: number, name: string)
			Network.Intent.Outfits:FireServer(Network.Actions.Outfits.Rename, { id = id, name = name })
		end,
		deleteOutfit = function(id: number)
			Network.Intent.Outfits:FireServer(Network.Actions.Outfits.Delete, { id = id })
		end,
		wearOutfit = function(id: number)
			Network.Intent.Outfits:FireServer(Network.Actions.Outfits.WearAll, { id = id })
		end,
		wearOutfitItems = function(id: number, indices: { number }, withSkin: boolean?, withScale: boolean?)
			if #indices > 0 or withSkin or withScale then
				Network.Intent.Outfits:FireServer(
					Network.Actions.Outfits.WearSelected,
					{ id = id, indices = indices, skin = withSkin == true, scale = withScale == true }
				)
			end
		end,
		basketTotal = total,
		published = outfitState.published or {},
		communityFavourites = outfitState.communityFavourites or {},
		communityRecent = outfitState.communityRecent or {},
		isPublished = function(code: string?): boolean
			return code ~= nil and table.find(outfitState.published or {}, code) ~= nil
		end,
		isCommunityFavourite = function(code: string): boolean
			return table.find(outfitState.communityFavourites or {}, code) ~= nil
		end,
		publish = function(target: { [string]: any })
			Network.Intent.Community:FireServer(Network.Actions.Community.Publish, target)
			task.delay(2, CommunityOutfits.reset) -- once the server has it
		end,
		unpublish = function(code: string)
			Network.Intent.Community:FireServer(Network.Actions.Community.Unpublish, { code = code })
			task.delay(2, CommunityOutfits.reset) -- once the server has it
		end,
		toggleCommunityFavourite = function(code: string)
			Network.Intent.Community:FireServer(Network.Actions.Community.Favourite, { code = code })
		end,
		reportCommunity = function(code: string)
			Network.Intent.Community:FireServer(Network.Actions.Community.Report, { code = code })
			task.delay(2, CommunityOutfits.reset) -- once the server has it
		end,
		openCommunity = function(code: string)
			Network.Intent.Community:FireServer(Network.Actions.Community.Open, { code = code })
		end,
	}
end

return usePlaceholderLook
