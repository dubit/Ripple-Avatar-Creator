--!strict

--[[
	RankedPages

	Rankings across servers (OrderedDataStores keyed by code), and paging
	through them, for Community outfits (CommunityService) and stores
	(StoresService).

	Pages are PAGE_SIZE keys, highest first, cached per server for
	CACHE_SECONDS (up to MAX_PAGES deep); `forget` drops a ranking's cached
	pages so the next read is fresh (after this server changed it).

	API:
		set(name, key, value)
		increment(name, key, delta)            never below 0
		remove(name, key)
		forget(name)
		page(name, index) -> ({ string }, boolean)   keys, and whether more
		                                       pages follow
]]

local DataStoreService = game:GetService("DataStoreService")

local RankedPages = {}

local PAGE_SIZE = 24
local MAX_PAGES = 10
local CACHE_SECONDS = 60

type Pager = {
	at: number,
	pages: { { string } },
	source: DataStorePages?,
	finished: boolean,
	loading: boolean,
}

local stores: { [string]: OrderedDataStore } = {}
local pagers: { [string]: Pager } = {}

local function ordered(name: string): OrderedDataStore?
	if not stores[name] then
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(name)
		end)
		if not ok then
			warn("[RankedPages] No OrderedDataStore", name, result)
			return nil
		end
		stores[name] = result
	end
	return stores[name]
end

function RankedPages.set(name: string, key: string, value: number)
	local store = ordered(name)
	if store then
		local ok, err = pcall(function()
			store:SetAsync(key, math.floor(value))
		end)
		if not ok then
			warn("[RankedPages] set failed:", name, err)
		end
	end
end

function RankedPages.increment(name: string, key: string, delta: number)
	local store = ordered(name)
	if store and delta ~= 0 then
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old: number?)
				return math.max(0, math.floor((old or 0) + delta))
			end)
		end)
		if not ok then
			warn("[RankedPages] increment failed:", name, err)
		end
	end
end

function RankedPages.remove(name: string, key: string)
	local store = ordered(name)
	if store then
		pcall(function()
			store:RemoveAsync(key)
		end)
	end
end

function RankedPages.forget(name: string)
	pagers[name] = nil
end

function RankedPages.page(name: string, index: number): ({ string }, boolean)
	local store = ordered(name)
	if not store or index < 1 or index > MAX_PAGES then
		return {}, false
	end
	local pager = pagers[name]
	if not pager or os.clock() - pager.at > CACHE_SECONDS then
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
				local keys = {}
				for _, entry in source:GetCurrentPage() do
					table.insert(keys, entry.key)
				end
				table.insert(pager.pages, keys)
				if source.IsFinished or #keys == 0 then
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
			warn("[RankedPages] page failed:", name, err)
			pagers[name] = nil
			return {}, false
		end
	end
	local keys = pager.pages[index] or {}
	local more = index < MAX_PAGES and (#pager.pages > index or not pager.finished)
	return keys, more
end

return RankedPages
