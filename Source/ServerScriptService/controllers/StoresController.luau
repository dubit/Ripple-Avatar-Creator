--!strict

--[[
	StoresController

	Making, editing, browsing, starring and reporting player stores
	(StoresService). Requests carry codes, names and item ids only: items
	are looked up on Roblox (AvatarService.resolve) before they go in a
	store, and an outfit must be one of the player's own Community outfits
	(OutfitsModel.published: sharing an outfit publishes it in its own
	right). Requests closer together than COOLDOWN are dropped, and edits
	(each one a DataStore write) have their own budget.

	Actions (as intents, so also slash commands with positional args:
	/storescontroller AddItem 7KQ2XM 1234 Asset), or through the
	"StoreAction"(action, ...) Bolt remote function, which answers
	{ ok, code?, error? } so the UI can say why not:
		Create(name)                       a new draft store ("full",
		                                   "length", "filtered", "taken")
		Rename(code, name)
		AddItem(code, targetId, kind)      a catalogue item ("full", "dupe",
		                                   "notfound")
		RemoveItem(code, targetId, kind)
		AddOutfit(code, outfitCode)        one of the player's own Community
		                                   outfits
		RemoveOutfit(code, outfitCode)
		Publish(code)                      needs StoresConfig.minItems items
		                                   ("items", "hidden")
		Unpublish(code)
		Delete(code)
		Favourite(code)                    star / unstar a published store
		                                   (your own too)
		Report(code)                       once per player; enough hide it
		Open(code)                         the player opened its page: a
		                                   visit (once a day, not the owner's)
		Share(code)                        the player opened its share dialog
		                                   (analytics only)
		Moderate(code, op)                 admins only, op "hide" |
		                                   "restore" | "takedown"

	"BrowseStores"(sort, page) (Bolt remote function) -> { ok, cards, more }:
	sort "popular" | "toprated" | "newest" (everyone's published stores)
	or "favourites" | "mine" (the player's own lists; mine includes
	drafts); page from 1. Cards: StoresService.Card.

	"GetStore"(text) (Bolt remote function) -> { ok, store = Page +
	{ favourited } } or { ok = false, error = "notfound" | "busy" }: text
	is a code ("7KQ2XM") or a published store's exact name.

	Analytics: store_create, store_publish, store_unpublish, store_delete,
	store_open, store_favourite, store_share, store_report.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AbstractController = require(script.Parent.AbstractController)
local StoresModel = require(script.Parent.Parent.models.user.StoresModel)
local OutfitsModel = require(script.Parent.Parent.models.user.OutfitsModel)
local AvatarService = require(ServerScriptService.services.game.AvatarService)
local SharedContentService = require(ServerScriptService.services.game.SharedContentService)
local CommunityService = require(ServerScriptService.services.game.CommunityService)
local StoresService = require(ServerScriptService.services.game.StoresService)
local Network = require(ReplicatedStorage.Network)
local Bolt = require(ReplicatedStorage.Bolt)

local StoresConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoresConfig"))

local StoresController = {}
StoresController.__index = StoresController
setmetatable(StoresController, AbstractController)

export type StoresController = typeof(setmetatable({}, StoresController)) & AbstractController.AbstractController

local COOLDOWN = 0.25
local PAGE_SIZE = 24 -- for the player's own lists (StoresService pages its own)
local BUDGETS = {
	edit = { requests = 30, seconds = 60 },
	browse = { requests = 20, seconds = 30 },
	report = { requests = 5, seconds = 300 },
}
local PERSONAL = { favourites = true, mine = true }

local lastRequest: { [Player]: number } = {}
local budgets: { [string]: { [Player]: { number } } } = { edit = {}, browse = {}, report = {} }

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

local function allowed(kind: string, player: Player): boolean
	local budget = BUDGETS[kind]
	local now = os.clock()
	local times = budgets[kind][player] or {}
	budgets[kind][player] = times
	while times[1] and now - times[1] > budget.seconds do
		table.remove(times, 1)
	end
	if #times >= budget.requests then
		return false
	end
	table.insert(times, now)
	return true
end

local function codeOf(value: any): string?
	return SharedContentService.normalise(if type(value) == "number" then tostring(value) else value)
end

-- Positional args, or one table: { code, name, targetId, kind, outfit, op }.
local function args(raw: any, ...: any): { [string]: any }
	if type(raw) == "table" then
		return raw
	end
	return { code = raw, rest = { ... } }
end

-- Words back into one string (slash commands split at spaces).
local function joined(list: { any }): string
	local words = {}
	for _, word in list do
		table.insert(words, tostring(word))
	end
	return table.concat(words, " ")
end

-- The code of one of the player's own stores, or nil.
local function ownCode(player: Player, model: any, value: any): string?
	local code = codeOf(value)
	if code and model:owns(code) then
		return code
	end
	return nil
end

type Result = { ok: boolean, code: string?, error: string? }

local function fail(why: string): Result
	return { ok = false, error = why }
end

local function done(code: string?): Result
	return { ok = true, code = code }
end

-- Making and editing ---------------------------------------------------------

local function create(player: Player, model: any, raw: any, ...: any): Result
	-- (A slash command splits the name at spaces: put it back together.)
	local name = if type(raw) == "table" then raw.name
		elseif raw ~= nil then joined({ raw, ... })
		else nil
	if #model.mine >= StoresConfig.maxStores then
		-- Drop stores that have gone (taken down) before saying it's full.
		for index = #model.mine, 1, -1 do
			if not StoresService.isStore(SharedContentService.lookup(model.mine[index])) then
				model:removeMine(model.mine[index])
			end
		end
		if #model.mine >= StoresConfig.maxStores then
			return fail("full")
		end
	end
	local cleaned, problem = StoresService.cleanName(player, name)
	if not cleaned then
		return fail(problem or "bad")
	end
	local code, why = StoresService.create(player, cleaned)
	if not code then
		return fail(why or "busy")
	end
	model:addMine(code)
	track(player, "store_create", { code = code })
	return done(code)
end

local function rename(player: Player, model: any, raw: any, ...: any): Result
	local a = args(raw, ...)
	local code = ownCode(player, model, a.code)
	if not code then
		return fail("bad")
	end
	local cleaned, problem = StoresService.cleanName(player, a.name or (a.rest and joined(a.rest)))
	if not cleaned then
		return fail(problem or "bad")
	end
	local why = StoresService.rename(code, player.UserId, cleaned)
	return if why then fail(why) else done(code)
end

local function itemOf(a: { [string]: any }): (number?, string?)
	local targetId = tonumber(a.targetId or (a.rest and a.rest[1]))
	local kind = a.kind or (a.rest and a.rest[2]) or "Asset"
	if not targetId or targetId ~= targetId or targetId <= 0 or targetId % 1 ~= 0 then
		return nil, nil
	end
	if kind ~= "Asset" and kind ~= "Bundle" then
		return nil, nil
	end
	return targetId, kind
end

local function addItem(player: Player, model: any, raw: any, ...: any): Result
	local a = args(raw, ...)
	local code = ownCode(player, model, a.code)
	local targetId, kind = itemOf(a)
	if not code or not targetId or not kind then
		return fail("bad")
	end
	local item = AvatarService.resolve(targetId, kind :: any)
	if not item then
		return fail("notfound")
	end
	local problem: string? = nil
	local record = StoresService.edit(code, player.UserId, function(record: any)
		record.items = record.items or {}
		for _, existing in record.items do
			if existing.targetId == targetId and existing.kind == kind then
				problem = "dupe"
				return false
			end
		end
		if #record.items >= StoresConfig.maxItems then
			problem = "full"
			return false
		end
		table.insert(record.items, { targetId = item.targetId, kind = item.kind, typeName = item.typeName, name = item.name })
		return true
	end)
	if problem then
		return fail(problem)
	end
	return if record then done(code) else fail("busy")
end

local function removeItem(player: Player, model: any, raw: any, ...: any): Result
	local a = args(raw, ...)
	local code = ownCode(player, model, a.code)
	local targetId, kind = itemOf(a)
	if not code or not targetId or not kind then
		return fail("bad")
	end
	StoresService.edit(code, player.UserId, function(record: any)
		for index, existing in record.items or {} do
			if existing.targetId == targetId and existing.kind == kind then
				table.remove(record.items, index)
				return true
			end
		end
		return false
	end)
	return done(code)
end

local function addOutfit(player: Player, model: any, raw: any, ...: any): Result
	local a = args(raw, ...)
	local code = ownCode(player, model, a.code)
	local outfit = codeOf(a.outfit or (a.rest and a.rest[1]))
	if not code or not outfit then
		return fail("bad")
	end
	local outfits = OutfitsModel.get(tostring(player.UserId))
	if not outfits or not table.find(outfits.published or {}, outfit) then
		return fail("notfound") -- only your own Community outfits
	end
	if not CommunityService.isListed(SharedContentService.lookup(outfit)) then
		return fail("notfound")
	end
	local problem: string? = nil
	local record = StoresService.edit(code, player.UserId, function(record: any)
		record.outfits = record.outfits or {}
		if table.find(record.outfits, outfit) then
			problem = "dupe"
			return false
		end
		if #record.outfits >= StoresConfig.maxOutfits then
			problem = "full"
			return false
		end
		table.insert(record.outfits, outfit)
		return true
	end)
	if problem then
		return fail(problem)
	end
	return if record then done(code) else fail("busy")
end

local function removeOutfit(player: Player, model: any, raw: any, ...: any): Result
	local a = args(raw, ...)
	local code = ownCode(player, model, a.code)
	local outfit = codeOf(a.outfit or (a.rest and a.rest[1]))
	if not code or not outfit then
		return fail("bad")
	end
	StoresService.edit(code, player.UserId, function(record: any)
		local index = table.find(record.outfits or {}, outfit)
		if not index then
			return false
		end
		table.remove(record.outfits, index)
		return true
	end)
	return done(code)
end

local function publish(player: Player, model: any, raw: any): Result
	local code = ownCode(player, model, args(raw).code)
	if not code then
		return fail("bad")
	end
	local why = StoresService.publish(code, player.UserId)
	if why then
		return fail(why)
	end
	track(player, "store_publish", { code = code })
	return done(code)
end

local function unpublish(player: Player, model: any, raw: any): Result
	local code = ownCode(player, model, args(raw).code)
	if not code then
		return fail("bad")
	end
	if StoresService.unpublish(code, player.UserId) then
		track(player, "store_unpublish", { code = code })
	end
	return done(code)
end

local function delete(player: Player, model: any, raw: any): Result
	local code = ownCode(player, model, args(raw).code)
	if not code then
		return fail("bad")
	end
	if StoresService.delete(code, player.UserId) then
		track(player, "store_delete", { code = code })
	end
	model:removeMine(code)
	return done(code)
end

-- Everyone's ------------------------------------------------------------------

local function favourite(player: Player, model: any, raw: any): Result
	local code = codeOf(args(raw).code)
	if not code then
		return fail("bad")
	end
	local starred = table.find(model.favourites, code) ~= nil
	if not starred and not StoresService.isListed(SharedContentService.lookup(code)) then
		return fail("notfound") -- only published stores (unstarring always works)
	end
	local now = model:toggleFavourite(code)
	StoresService.countFavourite(code, if now then 1 else -1)
	track(player, "store_favourite", { code = code, on = now })
	return done(code)
end

local function report(player: Player, _model: any, raw: any): Result
	local code = codeOf(args(raw).code)
	if not code or not allowed("report", player) then
		return fail("bad")
	end
	if StoresService.report(player, code) then
		track(player, "store_report", { code = code })
	end
	return done(code)
end

local function open(player: Player, model: any, raw: any): Result
	local code = codeOf(args(raw).code)
	local record = code and SharedContentService.lookup(code)
	if not code or not StoresService.isListed(record) then
		return fail("notfound")
	end
	local own = record.ownerId == player.UserId
	if not own and model:noteVisit(code) then
		StoresService.countVisit(code)
	end
	track(player, "store_open", { code = code, own = own })
	return done(code)
end

local function share(player: Player, _model: any, raw: any): Result
	local code = codeOf(args(raw).code)
	local record = code and SharedContentService.lookup(code)
	if not code or not StoresService.isListed(record) then
		return fail("notfound")
	end
	track(player, "store_share", { code = code, own = record.ownerId == player.UserId })
	return done(code)
end

local function moderate(player: Player, _model: any, raw: any, ...: any): Result
	if not CommunityService.isAdmin(player) then
		return fail("bad")
	end
	local a = args(raw, ...)
	local code = codeOf(a.code)
	local op = a.op or (a.rest and a.rest[1])
	if not code then
		return fail("bad")
	end
	if op == "hide" then
		StoresService.hide(code, "admin " .. player.UserId)
	elseif op == "restore" then
		StoresService.restore(code)
	elseif op == "takedown" then
		StoresService.delete(code)
	else
		return fail("bad")
	end
	return done(code)
end

-- Edits write to DataStores, so they share a budget.
local function budgeted(handler: (Player, any, any, ...any) -> Result): (Player, any, any, ...any) -> Result
	return function(player: Player, model: any, raw: any, ...: any): Result
		if not allowed("edit", player) then
			return fail("busy")
		end
		return handler(player, model, raw, ...)
	end
end

local ACTIONS: { [string]: (Player, any, any, ...any) -> Result } = {
	[Network.Actions.Stores.Create] = budgeted(create),
	[Network.Actions.Stores.Rename] = budgeted(rename),
	[Network.Actions.Stores.AddItem] = budgeted(addItem),
	[Network.Actions.Stores.RemoveItem] = budgeted(removeItem),
	[Network.Actions.Stores.AddOutfit] = budgeted(addOutfit),
	[Network.Actions.Stores.RemoveOutfit] = budgeted(removeOutfit),
	[Network.Actions.Stores.Publish] = budgeted(publish),
	[Network.Actions.Stores.Unpublish] = budgeted(unpublish),
	[Network.Actions.Stores.Delete] = budgeted(delete),
	[Network.Actions.Stores.Favourite] = favourite,
	[Network.Actions.Stores.Report] = report,
	[Network.Actions.Stores.Open] = open,
	[Network.Actions.Stores.Share] = share,
	[Network.Actions.Stores.Moderate] = moderate,
}

-- Run an action for a player; nil when it was dropped (cooldown, no model).
local function run(player: Player, action: any, raw: any, ...: any): Result?
	local handler = ACTIONS[action]
	if not handler then
		return nil
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < COOLDOWN then
		return fail("busy")
	end
	lastRequest[player] = now
	local model = StoresModel.get(tostring(player.UserId))
	if not model then
		return nil
	end
	local ok, result = pcall(handler, player, model, raw, ...)
	if not ok then
		warn("[StoresController]", action, result)
		return fail("busy")
	end
	return result
end

-- Intents (and slash commands) run the same handlers, dropping the result.
local INTENTS: { [string]: (...any) -> () } = {}
for action in ACTIONS do
	INTENTS[action] = function(player: Player, raw: any, ...: any)
		run(player, action, raw, ...)
	end
end

function StoresController:executeAction(player: Player, action: Network.StoresAction, raw: any, ...: any)
	self:dispatchAction(INTENTS, action, player, player, raw, ...)
end

local function browse(player: Player, sort: any, page: any): any
	if type(sort) ~= "string" or type(page) ~= "number" or page < 1 or page % 1 ~= 0 then
		return { ok = false, error = "bad" }
	end
	if not allowed("browse", player) then
		return { ok = false, error = "busy" }
	end
	local codes: { string }
	local more: boolean
	if PERSONAL[sort] then
		local model = StoresModel.get(tostring(player.UserId))
		local list = if model then (model :: any)[sort] or {} else {}
		local first = (page - 1) * PAGE_SIZE + 1
		codes = table.move(list, first, math.min(#list, first + PAGE_SIZE - 1), 1, {})
		more = #list > first + PAGE_SIZE - 1
	else
		codes, more = StoresService.page(sort, page)
	end
	return { ok = true, cards = StoresService.cards(codes, player), more = more }
end

local function getStore(player: Player, text: any): any
	if type(text) ~= "string" or #text > 60 then
		return { ok = false, error = "notfound" }
	end
	if not SharedContentService.allowed(player) then
		return { ok = false, error = "busy" }
	end
	local code = SharedContentService.normalise(text) or StoresService.findByName(text)
	local store = code and StoresService.view(code, player)
	if not code or not store then
		return { ok = false, error = "notfound" }
	end
	local model = StoresModel.get(tostring(player.UserId))
	local result = table.clone(store) :: any
	result.favourited = model ~= nil and table.find(model.favourites, code) ~= nil
	return { ok = true, store = result }
end

function StoresController.new(): StoresController
	local self = AbstractController.new("StoresController") :: any
	setmetatable(self, StoresController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.StoresAction, raw: any, ...: any)
		self:executeAction(player, action, raw, ...)
	end)

	Bolt.RemoteFunction("StoreAction").OnServerInvoke = function(player: Player, action: any, raw: any, ...: any): any
		return run(player, action, raw, ...) or fail("bad")
	end
	Bolt.RemoteFunction("BrowseStores").OnServerInvoke = browse
	Bolt.RemoteFunction("GetStore").OnServerInvoke = getStore

	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequest[player] = nil
		for _, list in budgets do
			list[player] = nil
		end
	end)

	return self :: StoresController
end

return StoresController
