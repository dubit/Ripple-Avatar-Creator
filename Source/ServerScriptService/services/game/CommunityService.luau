--!strict

--[[
	CommunityService (loop-based: flushes counts every FLUSH_SECONDS)

	Outfits players publish for everyone, across servers. A Community entry
	is a frozen shared copy (SharedContentService, a code's record) marked
	`listed`, so its code, page and preview are the ones sharing already
	has. Publishing never changes what the copy holds.

	Ordering: three OrderedDataStores keyed by code:
	  · CommunityNewest       publish time
	  · CommunityPopular      wears + FAVOURITE_WEIGHT × favourites
	  · CommunityTrending_<w> wears in week w (a new store each week, so it
	                          never needs clearing)
	Wears and favourites are counted per server and written every
	FLUSH_SECONDS (and on shutdown), keeping DataStore requests low; the
	record keeps its own `wears` / `favourites` for the cards.

	Browsing: pages of PAGE_SIZE codes per ordering, cached per server for
	PAGE_CACHE_SECONDS (up to MAX_PAGES deep), turned into cards from the
	records (cached by SharedContentService). Hidden or unpublished entries
	are dropped from a page, even if an ordering still lists them.

	Moderation: names are text-filtered when shared. Players report an
	entry (once each, CommunityReports store); at REPORTS_TO_HIDE distinct
	reports it's hidden until an admin restores it. Admins (isAdmin) hide,
	restore or take down (revoke the code) by code.

	API:
		publish(code, ownerId) -> boolean       list a copy (its owner only)
		unpublish(code, ownerId) -> boolean
		hide(code, reason) / restore(code) / takedown(code)
		countWear(code) / countFavourite(code, delta)
		flush()                                 write the counted changes now
		page(sort, index) -> ({ string }, boolean)   codes, and whether more
		                                        pages follow; sort is
		                                        "popular" | "trending" | "newest"
		cards(codes, viewer) -> { Card }        listed, visible entries only
		report(player, code) -> boolean         false if already reported
		isAdmin(player) -> boolean
		isListed(record) -> boolean
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SharedContentService = require(script.Parent.SharedContentService)

local CommunityService = {}

export type Card = {
	code: string,
	name: string,
	by: string?, -- the creator's username (nil once anonymous)
	mine: boolean,
	wears: number,
	favourites: number,
	items: { any },
	skin: any,
	scale: any,
}

local PAGE_SIZE = 24
local MAX_PAGES = 10
local PAGE_CACHE_SECONDS = 60
local FLUSH_SECONDS = 60
local FAVOURITE_WEIGHT = 3
local REPORTS_TO_HIDE = 3
local MAX_REPORTERS = 50
local ADMIN_RANK = 200
local WEEK = 7 * 24 * 60 * 60

type Pager = {
	at: number,
	pages: { { string } },
	source: DataStorePages?,
	finished: boolean,
	loading: boolean,
}

local stores: { [string]: OrderedDataStore } = {}
local pagers: { [string]: Pager } = {}
local pending: { [string]: { wears: number, favourites: number } } = {}

local function ordered(name: string): OrderedDataStore?
	if not stores[name] then
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(name)
		end)
		if not ok then
			warn("[CommunityService] No OrderedDataStore", name, result)
			return nil
		end
		stores[name] = result
	end
	return stores[name]
end

-- Weeks start on Monday (the Unix epoch was a Thursday).
local function trendingName(): string
	return "CommunityTrending_" .. math.floor((os.time() + 3 * 24 * 60 * 60) / WEEK)
end

local function storeFor(sort: string): string?
	if sort == "popular" then
		return "CommunityPopular"
	elseif sort == "newest" then
		return "CommunityNewest"
	elseif sort == "trending" then
		return trendingName()
	end
	return nil
end

local function score(record: any): number
	return math.floor((tonumber(record.wears) or 0) + FAVOURITE_WEIGHT * (tonumber(record.favourites) or 0))
end

local function set(storeName: string, code: string, value: number)
	local store = ordered(storeName)
	if store then
		local ok, err = pcall(function()
			store:SetAsync(code, value)
		end)
		if not ok then
			warn("[CommunityService] set failed:", storeName, err)
		end
	end
end

local function increment(storeName: string, code: string, delta: number)
	local store = ordered(storeName)
	if store and delta ~= 0 then
		local ok, err = pcall(function()
			store:UpdateAsync(code, function(old: number?)
				return math.max(0, (old or 0) + delta)
			end)
		end)
		if not ok then
			warn("[CommunityService] increment failed:", storeName, err)
		end
	end
end

local function unset(storeName: string, code: string)
	local store = ordered(storeName)
	if store then
		pcall(function()
			store:RemoveAsync(code)
		end)
	end
end

local function forget(sort: string)
	local name = storeFor(sort)
	if name then
		pagers[name] = nil
	end
end

-- Take an entry off every ordering (its counts stay on the record).
local function delist(code: string)
	unset("CommunityNewest", code)
	unset("CommunityPopular", code)
	unset(trendingName(), code)
	forget("newest")
	forget("popular")
	forget("trending")
end

-- Put a listed entry back on the orderings.
local function relist(code: string, record: any)
	set("CommunityNewest", code, tonumber(record.publishedAt) or os.time())
	set("CommunityPopular", code, score(record))
	forget("newest")
	forget("popular")
end

function CommunityService.isListed(record: any): boolean
	return type(record) == "table" and record.kind == "outfit" and record.listed == true and record.hidden ~= true
end

function CommunityService.publish(code: string, ownerId: number): boolean
	local record = SharedContentService.modify(code, function(record: any)
		if record.kind ~= "outfit" or record.ownerId ~= ownerId or record.hidden then
			return false
		end
		record.listed = true
		record.publishedAt = record.publishedAt or os.time()
		record.wears = record.wears or 0
		record.favourites = record.favourites or 0
		return true
	end)
	if not record then
		return false
	end
	relist(code, record)
	return true
end

function CommunityService.unpublish(code: string, ownerId: number): boolean
	local record = SharedContentService.modify(code, function(record: any)
		if record.ownerId ~= ownerId or not record.listed then
			return false
		end
		record.listed = false
		return true
	end)
	if not record then
		return false
	end
	delist(code)
	return true
end

function CommunityService.hide(code: string, reason: string)
	local record = SharedContentService.modify(code, function(record: any)
		if record.hidden then
			return false
		end
		record.hidden = true
		record.hiddenReason = reason
		return true
	end)
	if record then
		delist(code)
		warn(string.format("[CommunityService] Hid %s (%s): %q", code, reason, tostring(record.name)))
	end
end

function CommunityService.restore(code: string)
	local record = SharedContentService.modify(code, function(record: any)
		if not record.hidden then
			return false
		end
		record.hidden = nil
		record.hiddenReason = nil
		return true
	end)
	if record and record.listed then
		relist(code, record)
	end
end

function CommunityService.takedown(code: string)
	delist(code)
	SharedContentService.remove(code)
end

function CommunityService.countWear(code: string)
	local entry = pending[code] or { wears = 0, favourites = 0 }
	entry.wears += 1
	pending[code] = entry
end

function CommunityService.countFavourite(code: string, delta: number)
	local entry = pending[code] or { wears = 0, favourites = 0 }
	entry.favourites += delta
	pending[code] = entry
end

function CommunityService.flush()
	local batch = pending
	pending = {}
	for code, delta in batch do
		local record = SharedContentService.lookup(code)
		if not CommunityService.isListed(record) then
			continue
		end
		local updated = SharedContentService.modify(code, function(current: any)
			current.wears = math.max(0, (tonumber(current.wears) or 0) + delta.wears)
			current.favourites = math.max(0, (tonumber(current.favourites) or 0) + delta.favourites)
			return true
		end)
		if updated and CommunityService.isListed(updated) then
			increment("CommunityPopular", code, delta.wears + FAVOURITE_WEIGHT * delta.favourites)
			increment(trendingName(), code, delta.wears)
		end
	end
end

function CommunityService.page(sort: string, index: number): ({ string }, boolean)
	local name = storeFor(sort)
	local store = name and ordered(name)
	if not name or not store or index < 1 or index > MAX_PAGES then
		return {}, false
	end
	local pager = pagers[name]
	if not pager or os.clock() - pager.at > PAGE_CACHE_SECONDS then
		pager = { at = os.clock(), pages = {}, source = nil, finished = false, loading = false }
		pagers[name] = pager
	end
	while pager.loading do
		task.wait(0.1)
	end
	if #pager.pages < index and not pager.finished then
		pager.loading = true
		local ok, err = pcall(function()
			if not pager.source then
				pager.source = store:GetSortedAsync(false, PAGE_SIZE)
			else
				(pager.source :: DataStorePages):AdvanceToNextPageAsync()
			end
			local source = pager.source :: DataStorePages
			while true do
				local codes = {}
				for _, entry in source:GetCurrentPage() do
					table.insert(codes, entry.key)
				end
				table.insert(pager.pages, codes)
				if source.IsFinished or #codes == 0 then
					pager.finished = true
					break
				end
				if #pager.pages >= index then
					break
				end
				source:AdvanceToNextPageAsync()
			end
		end)
		pager.loading = false
		if not ok then
			warn("[CommunityService] page failed:", sort, err)
			pagers[name] = nil
			return {}, false
		end
	end
	local codes = pager.pages[index] or {}
	local more = index < MAX_PAGES and (#pager.pages > index or not pager.finished)
	return codes, more
end

function CommunityService.cards(codes: { string }, viewer: Player?): { Card }
	local records: { any } = table.create(#codes)
	local remaining = #codes
	local thread = coroutine.running()
	if remaining == 0 then
		return {}
	end
	for index, code in codes do
		task.spawn(function()
			records[index] = SharedContentService.lookup(code)
			remaining -= 1
			if remaining == 0 and coroutine.status(thread) == "suspended" then
				task.spawn(thread)
			end
		end)
	end
	if remaining > 0 then
		coroutine.yield()
	end
	local cards: { Card } = {}
	for index, code in codes do
		local record = records[index]
		if CommunityService.isListed(record) then
			table.insert(cards, {
				code = code,
				name = tostring(record.name or "Outfit"),
				by = if record.anonymous then nil else record.ownerName,
				mine = viewer ~= nil and record.ownerId == viewer.UserId,
				wears = tonumber(record.wears) or 0,
				favourites = tonumber(record.favourites) or 0,
				items = record.items or {},
				skin = record.skin,
				scale = record.scale,
			})
		end
	end
	return cards
end

function CommunityService.report(player: Player, code: string): boolean
	local reports: DataStore? = nil
	local ok = pcall(function()
		reports = DataStoreService:GetDataStore("CommunityReports")
	end)
	if not ok or not reports then
		return false
	end
	local count = 0
	local added = false
	local updated = pcall(function()
		(reports :: DataStore):UpdateAsync(code, function(old: any)
			local reporters = if type(old) == "table" then old else {}
			if table.find(reporters, player.UserId) or #reporters >= MAX_REPORTERS then
				count = #reporters
				return nil
			end
			table.insert(reporters, player.UserId)
			count = #reporters
			added = true
			return reporters
		end)
	end)
	if updated and added and count >= REPORTS_TO_HIDE then
		CommunityService.hide(code, "reports")
	end
	return updated and added
end

function CommunityService.isAdmin(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank >= ADMIN_RANK
	end
	return RunService:IsStudio() or player.UserId == game.CreatorId
end

function CommunityService.init()
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			CommunityService.flush()
		end
	end)
	game:BindToClose(CommunityService.flush)
	Players.PlayerRemoving:Connect(function()
		if #Players:GetPlayers() <= 1 then
			task.spawn(CommunityService.flush)
		end
	end)
end

return CommunityService
