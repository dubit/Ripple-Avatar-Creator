--!strict

--[[
	PurchaseController

	Buying catalogue items through Roblox's own purchase prompt, and
	checking what the player owns.

	Roblox splits the bulk purchase prompt across the boundary: only the
	server can open it (MarketplaceService:PromptBulkPurchase) and only the
	client hears how it ended (PromptBulkPurchaseFinished). So:

	  1. Buy: the client sends a request id and the items. The server looks
	     each one up (AvatarService.resolve), drops what the player already
	     owns, and opens one prompt for the rest. OwnershipModel.purchase
	     goes to "waiting".
	  2. Finished: the client reports how the prompt ended. The server
	     doesn't take its word: it asks Roblox afresh which items are now
	     owned (OwnershipService), takes those out of the basket, and sets
	     purchase to "done", "cancelled" or "failed" with a reason (the
	     client's per-item statuses only pick the wording).

	A purchase the client never reports goes stale after PROMPT_TIMEOUT, and
	a new one can start.

	In Studio, purchases are only tests: Roblox reports them but grants
	nothing. So there (only), an item the client reports as bought counts as
	owned for the session, so the rest of the flow (basket removal, Owned
	labels) can be tried out.

	Check(items): look up ownership of up to MAX_CHECK items (the worn list,
	the basket, an item page); each is looked up once a session.

	A Buy made from a store page carries the store's code (`store`): the
	purchase analytics say which store it was (not when its owner buys),
	so store owners could be rewarded later.

	Analytics: purchase_prompted, purchase_completed (item ids, Robux spent as
	the client reported it, store_code), purchase_cancelled (with the reason).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AbstractController = require(script.Parent.AbstractController)
local OwnershipModel = require(script.Parent.Parent.models.userSession.OwnershipModel)
local BasketModel = require(script.Parent.Parent.models.user.BasketModel)
local AvatarService = require(ServerScriptService.services.game.AvatarService)
local OwnershipService = require(ServerScriptService.services.game.OwnershipService)
local SharedContentService = require(ServerScriptService.services.game.SharedContentService)
local StoresService = require(ServerScriptService.services.game.StoresService)
local Network = require(ReplicatedStorage.Network)

local PurchaseController = {}
PurchaseController.__index = PurchaseController
setmetatable(PurchaseController, AbstractController)

export type PurchaseController = typeof(setmetatable({}, PurchaseController)) & AbstractController.AbstractController

local MAX_BUY = 20 -- items in one purchase prompt
local MAX_CHECK = 50 -- items in one ownership check
local PROMPT_TIMEOUT = 180 -- seconds before an unreported purchase goes stale
local CHECK_BUDGET = { requests = 8, seconds = 10 }
local RECHECK_DELAY = 2 -- seconds before asking again about an item Roblox said was bought

-- Why an item wasn't bought, from Roblox's per-item status.
local REASONS: { [string]: string } = {
	InsufficientRobux = "You don't have enough Robux",
	NotForSale = "It's not for sale",
	SoldOut = "It's sold out",
	AlreadyOwned = "You already own it",
	NotAvailableForPurchaser = "It's not available to you",
	QuantityLimitExceeded = "You've reached the limit for it",
	QuotaExceeded = "You've reached the limit for it",
	PriceMismatch = "Its price changed",
	PurchaserIsSeller = "You made it",
	InsufficientMembership = "It needs Premium",
}
local GENERIC_FAILURE = "Roblox couldn't complete the purchase"

local recentChecks: { [Player]: { number } } = {}
-- Players whose Buy or Finished is mid-way (both wait on Roblox lookups).
local busy: { [Player]: boolean } = {}

-- Lazy, like AbstractController (avoids a load-order dependency).
local analytics: any = nil
local function track(player: Player, eventName: string, params: { [string]: any })
	if analytics == nil then
		local ok, service = pcall(function()
			return require(script.Parent.Parent.services.framework.AnalyticsService)
		end)
		analytics = if ok then service else false
	end
	if analytics and analytics.isEnabled then
		analytics:trackEvent(player, eventName, params)
	end
end

local function idList(keys: { string }): string
	return table.concat(keys, ",")
end

-- { targetId, kind } from the client, shape-checked (not looked up).
local function refOf(raw: any): OwnershipService.Ref?
	if type(raw) ~= "table" then
		return nil
	end
	local targetId, kind = raw.targetId, raw.kind
	if type(targetId) ~= "number" or targetId ~= targetId or targetId <= 0 or targetId % 1 ~= 0 then
		return nil
	end
	if kind ~= "Asset" and kind ~= "Bundle" then
		return nil
	end
	return { targetId = targetId, kind = kind }
end

local function refsOf(raw: any, limit: number): { OwnershipService.Ref }
	local refs = {}
	local seen = {}
	if type(raw) ~= "table" then
		return refs
	end
	for index, entry in raw do
		if type(index) ~= "number" or index > limit then
			continue
		end
		local ref = refOf(entry)
		if ref then
			local key = OwnershipService.keyOf(ref.targetId, ref.kind)
			if not seen[key] then
				seen[key] = true
				table.insert(refs, ref)
			end
		end
	end
	return refs
end

local function buy(player: Player, model: any, raw: any)
	if type(raw) ~= "table" or type(raw.id) ~= "number" or raw.id % 1 ~= 0 then
		return
	end
	local id = raw.id
	local pending = model._pending
	if pending and os.clock() - pending.at < PROMPT_TIMEOUT then
		return -- one purchase at a time (the client waits for it)
	end
	-- Only real catalogue items.
	local refs = {}
	for _, ref in refsOf(raw.items, MAX_BUY) do
		if AvatarService.resolve(ref.targetId, ref.kind) then
			table.insert(refs, ref)
		end
	end
	if #refs == 0 then
		model:finishPurchase(id, "failed", "Those items couldn't be found", {})
		return
	end
	OwnershipService.check(player, model, refs)
	local items: { OwnershipModel.PendingItem } = {}
	local lineItems = {}
	for _, ref in refs do
		local key = OwnershipService.keyOf(ref.targetId, ref.kind)
		if not model:owns(key) then
			table.insert(items, { targetId = ref.targetId, kind = ref.kind, key = key })
			table.insert(lineItems, {
				Type = if ref.kind == "Bundle"
					then Enum.MarketplaceProductType.AvatarBundle
					else Enum.MarketplaceProductType.AvatarAsset,
				Id = tostring(ref.targetId),
			})
		end
	end
	if #items == 0 then
		model:finishPurchase(id, "done", "You already own " .. (if #refs == 1 then "it" else "them"), {})
		return
	end
	model:startPurchase(id, items)
	-- Bought through a store (a published one, not the buyer's own).
	local store = SharedContentService.normalise(raw.store)
	local record = store and SharedContentService.lookup(store)
	if store and StoresService.isListed(record) and record.ownerId ~= player.UserId then
		model._pending.store = store
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptBulkPurchase(player, lineItems, {})
	end)
	if not ok then
		warn("[PurchaseController] PromptBulkPurchase failed:", err)
		model:finishPurchase(id, "failed", "Roblox couldn't open the purchase", {})
		return
	end
	local keys = {}
	for _, item in items do
		table.insert(keys, item.key)
	end
	track(player, "purchase_prompted", { item_ids = idList(keys), item_count = #keys, store_code = model._pending.store })
end

local function finished(player: Player, model: any, raw: any)
	local pending = model._pending
	if not pending or type(raw) ~= "table" then
		return
	end
	local id = model.purchase.id
	-- What the client says happened, per item (wording only; not trusted).
	local said: { [string]: string } = {}
	if type(raw.items) == "table" then
		for index, entry in raw.items do
			if type(index) == "number" and index <= MAX_BUY and type(entry) == "table" then
				local itemId, itemType, status = tonumber(entry.id), entry.type, entry.status
				if itemId and type(itemType) == "string" and type(status) == "string" then
					local kind = if itemType:find("Bundle") then "Bundle" else "Asset"
					said[OwnershipService.keyOf(itemId, kind)] = status
				end
			end
		end
	end

	-- Ask Roblox afresh; items it said were bought get one more look if
	-- ownership hasn't caught up yet.
	local refs = {}
	for _, item in pending.items do
		table.insert(refs, { targetId = item.targetId, kind = item.kind })
	end
	OwnershipService.check(player, model, refs, true)
	local late = {}
	for _, item in pending.items do
		if not model:owns(item.key) and said[item.key] == "Success" then
			table.insert(late, { targetId = item.targetId, kind = item.kind })
		end
	end
	if #late > 0 and not RunService:IsStudio() then -- (Studio never grants them)
		task.wait(RECHECK_DELAY)
		if not player.Parent then
			return
		end
		OwnershipService.check(player, model, late, true)
	end
	if RunService:IsStudio() then
		local tested: { [string]: boolean } = {}
		for _, item in pending.items do
			if not model:owns(item.key) and said[item.key] == "Success" then
				tested[item.key] = true
			end
		end
		model:record(tested)
	end

	local bought = {}
	local failure: string? = nil
	for _, item in pending.items do
		if model:owns(item.key) then
			table.insert(bought, item.key)
		elseif not failure then
			failure = REASONS[said[item.key] or ""]
		end
	end
	if #bought > 0 then
		local basket = BasketModel.get(tostring(player.UserId))
		if basket then
			local taken = {}
			for _, item in pending.items do
				if model:owns(item.key) then
					table.insert(taken, { targetId = item.targetId, kind = item.kind })
				end
			end
			basket:take(taken)
		end
	end

	local total = #pending.items
	if #bought == total then
		model:finishPurchase(id, "done", "", bought)
	elseif #bought > 0 then
		model:finishPurchase(id, "done", "Bought " .. #bought .. " of " .. total .. ". " .. (failure or GENERIC_FAILURE), bought)
	elseif raw.status == "Aborted" and not failure then
		model:finishPurchase(id, "cancelled", "Purchase cancelled", {})
	else
		model:finishPurchase(id, "failed", failure or GENERIC_FAILURE, {})
	end

	if #bought > 0 then
		track(player, "purchase_completed", {
			item_ids = idList(bought),
			item_count = #bought,
			robux_spent = if type(raw.robuxSpent) == "number" then raw.robuxSpent else nil,
			store_code = pending.store,
		})
	else
		track(player, "purchase_cancelled", { item_count = total, reason = model.purchase.reason })
	end
end

local function check(player: Player, model: any, raw: any)
	local now = os.clock()
	local times = recentChecks[player] or {}
	recentChecks[player] = times
	while times[1] and now - times[1] > CHECK_BUDGET.seconds do
		table.remove(times, 1)
	end
	if #times >= CHECK_BUDGET.requests then
		return
	end
	table.insert(times, now)
	OwnershipService.check(player, model, refsOf(raw, MAX_CHECK))
end

-- One Buy / Finished at a time per player; the flag clears even on error.
local function exclusive(handler: (Player, any, any) -> ()): (Player, any, any) -> ()
	return function(player: Player, model: any, raw: any)
		if busy[player] then
			return
		end
		busy[player] = true
		local ok, err = pcall(handler, player, model, raw)
		busy[player] = nil
		if not ok then
			warn("[PurchaseController]", err)
		end
	end
end

local ACTIONS = {
	[Network.Actions.Purchase.Buy] = exclusive(buy),
	[Network.Actions.Purchase.Finished] = exclusive(finished),
	[Network.Actions.Purchase.Check] = check,
}

function PurchaseController:executeAction(player: Player, action: Network.PurchaseAction, raw: any)
	local model = OwnershipModel.get(tostring(player.UserId))
	if not model then
		return
	end
	self:dispatchAction(ACTIONS, action, player, player, model, raw)
end

function PurchaseController.new(): PurchaseController
	local self = AbstractController.new("PurchaseController") :: any
	setmetatable(self, PurchaseController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.PurchaseAction, raw: any)
		self:executeAction(player, action, raw)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		recentChecks[player] = nil
		busy[player] = nil
	end)

	return self :: PurchaseController
end

return PurchaseController
