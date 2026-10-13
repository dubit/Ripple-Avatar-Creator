--!strict

--[[
	SharedContentService

	Content one player shares with everyone, across servers, by a short code:
	"7KQ2XM". It lives in a global DataStore ("SharedContent"), keyed by
	code, so any server can look it up. (Decided in Task 14: Roblox
	DataStores for shared content; OrderedDataStore for rankings and
	MemoryStore for caches when later tasks need them.)

	All kinds of shared things (outfits now; stores later) share one pool of
	codes: the record says what it is, so a lookup knows what it found
	before showing it:
		{ kind, ownerId, ownerName, updated, ... the content ... }

	Codes are 6 characters from the design's alphabet (no I, O, 0 or 1: about
	a billion codes), picked at random and claimed atomically (UpdateAsync
	only writes if the key is free), so two things can't share one. The
	record is a frozen copy: what the code opens never changes (an edit to
	the original detaches its code, and sharing again claims a new one), so
	a popular code can't be turned into something else. Removing a record
	revokes its code (admin takedown).

	Lookups are cached per server for CACHE_SECONDS; each player gets
	LOOKUP_BUDGET lookups per window.

	API:
		claim(record) -> string?                  a new code holding `record`
		update(code, record) -> boolean           replace a code's record
		remove(code)                              revoke a code
		modify(code, fn) -> record?               change a record in place
		                                          (UpdateAsync; `fn` edits
		                                          the record, or returns false
		                                          to leave it); the new record
		anonymise(code)                           drop the owner's name from a
		                                          code's record (its owner
		                                          deleted what it copies)
		outfitRecord(player, name, items, skin, scale)   a new outfit record
		sameOutfit(record, name, items, skin, scale) -> boolean   does a copy
		                                          still match its original?
		filterName(player, text) -> string?       Roblox text filtering for a
		                                          name everyone may see
		lookup(code) -> record?                   cached; nil if unknown
		normalise(text) -> string?                " 7kq2xm " -> "7KQ2XM"
		allowed(player) -> boolean                the lookup budget
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))
local BodyScale = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("BodyScale"))

local SharedContentService = {}

local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local CODE_LENGTH = 6
local MAX_ATTEMPTS = 5
local CACHE_SECONDS = 30
local LOOKUP_BUDGET = { requests = 15, seconds = 30 }

local store: DataStore? = nil
local cache: { [string]: { record: any, at: number } } = {}
local recentLookups: { [Player]: { number } } = {}
local random = Random.new()

local function dataStore(): DataStore?
	if store == nil then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore("SharedContent")
		end)
		if ok then
			store = result
		else
			warn("[SharedContentService] No DataStore:", result)
		end
	end
	return store
end

local function newCode(): string
	local chars = table.create(CODE_LENGTH)
	for i = 1, CODE_LENGTH do
		local n = random:NextInteger(1, #ALPHABET)
		chars[i] = string.sub(ALPHABET, n, n)
	end
	return table.concat(chars)
end

function SharedContentService.normalise(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local body = string.match(string.upper(text), "^%s*(%w+)%s*$")
	if not body or #body ~= CODE_LENGTH then
		return nil
	end
	for i = 1, #body do
		if not string.find(ALPHABET, string.sub(body, i, i), 1, true) then
			return nil
		end
	end
	return body
end

function SharedContentService.claim(record: any): string?
	local ds = dataStore()
	if not ds then
		return nil
	end
	for _ = 1, MAX_ATTEMPTS do
		local code = newCode()
		local claimed = false
		local ok, err = pcall(function()
			ds:UpdateAsync(code, function(old: any)
				if old ~= nil then
					return nil -- taken: leave it alone and try another
				end
				claimed = true
				return record
			end)
		end)
		if not ok then
			warn("[SharedContentService] claim failed:", err)
			return nil
		end
		if claimed then
			cache[code] = { record = record, at = os.clock() }
			return code
		end
	end
	return nil
end

function SharedContentService.update(code: string, record: any): boolean
	local ds = dataStore()
	if not ds then
		return false
	end
	local ok, err = pcall(function()
		ds:SetAsync(code, record)
	end)
	if not ok then
		warn("[SharedContentService] update failed:", err)
		return false
	end
	cache[code] = { record = record, at = os.clock() }
	return true
end

function SharedContentService.remove(code: string)
	local ds = dataStore()
	cache[code] = { record = false, at = os.clock() }
	if not ds then
		return
	end
	local ok, err = pcall(function()
		ds:RemoveAsync(code)
	end)
	if not ok then
		warn("[SharedContentService] remove failed:", err)
	end
end

function SharedContentService.modify(code: string, fn: (record: any) -> boolean?): any?
	local ds = dataStore()
	if not ds then
		return nil
	end
	local result: any = nil
	local ok, err = pcall(function()
		ds:UpdateAsync(code, function(old: any)
			if type(old) ~= "table" or fn(old) == false then
				return nil
			end
			result = old
			return old
		end)
	end)
	if not ok then
		warn("[SharedContentService] modify failed:", err)
		return nil
	end
	if result then
		cache[code] = { record = result, at = os.clock() }
	end
	return result
end

function SharedContentService.anonymise(code: string)
	SharedContentService.modify(code, function(record: any)
		if record.anonymous then
			return false
		end
		record.ownerName = nil
		record.anonymous = true
		return true
	end)
end

function SharedContentService.outfitRecord(player: Player, name: string, items: { any }, skin: any, scale: any): { [string]: any }
	return {
		kind = "outfit",
		ownerId = player.UserId,
		ownerName = player.Name,
		updated = os.time(),
		name = name,
		items = items,
		skin = SkinColours.normalise(skin),
		scale = BodyScale.normalise(scale),
	}
end

function SharedContentService.sameOutfit(record: any, name: string, items: { any }, skin: any, scale: any): boolean
	if type(record) ~= "table" or record.name ~= name or type(record.items) ~= "table" or #record.items ~= #items then
		return false
	end
	for index, item in items do
		local copied = record.items[index]
		if type(copied) ~= "table" or copied.targetId ~= item.targetId or copied.kind ~= item.kind then
			return false
		end
	end
	return SkinColours.equal(SkinColours.normalise(record.skin), SkinColours.normalise(skin))
		and BodyScale.equal(BodyScale.normalise(record.scale), BodyScale.normalise(scale))
end

function SharedContentService.filterName(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" then
		return nil
	end
	return result
end

function SharedContentService.lookup(code: string): any?
	local cached = cache[code]
	if cached and os.clock() - cached.at < CACHE_SECONDS then
		return cached.record or nil
	end
	local ds = dataStore()
	if not ds then
		return nil
	end
	local ok, record = pcall(function()
		return ds:GetAsync(code)
	end)
	if not ok then
		warn("[SharedContentService] lookup failed:", record)
		return nil
	end
	cache[code] = { record = record or false, at = os.clock() }
	return record
end

function SharedContentService.allowed(player: Player): boolean
	local now = os.clock()
	local times = recentLookups[player] or {}
	recentLookups[player] = times
	while times[1] and now - times[1] > LOOKUP_BUDGET.seconds do
		table.remove(times, 1)
	end
	if #times >= LOOKUP_BUDGET.requests then
		return false
	end
	table.insert(times, now)
	return true
end

function SharedContentService.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		recentLookups[player] = nil
	end)
end

return SharedContentService
