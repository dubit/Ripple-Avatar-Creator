--!strict

--[[
	RobloxAvatarLookupService (event-driven)

	Other people's looks for Outfits › Roblox. Roblox doesn't let a game list
	another user's saved outfits, only their current avatar, so a "look" is:
	  · for a player in this server: what they're wearing here right now
	    (their AvatarModel.worn, tried-on items and all)
	  · for anyone else: their current Roblox avatar's wearable items
	Either way it's the items only; wearing one keeps your own body.

	Results are cached (CACHE_SECONDS) and each player gets BUDGET lookups per
	window across both remote functions (Bolt), past which they're told to
	wait:
	  "FindRobloxUser"(name)  -> { ok, user = { userId, username, displayName } }
	                             or { ok = false, error = "notfound" | "busy" | "failed" }
	                             (an exact username: Roblox offers games no
	                             partial or display-name search)
	  "RobloxUserLook"(userId) -> { ok, look = { userId, username, displayName,
	                             inServer, items } } or { ok = false, error }
	  "RobloxUserInfos"(userIds) -> { User } for up to MAX_INFOS ids (names
	                             for the Following cards; one batched,
	                             cached call, outside the budget)

	API (AvatarController, OutfitsController):
		user(userId) -> User?                       name lookup (cached)
		look(userId) -> Look?                       cached
		description(userId) -> HumanoidDescription? for the outfit page preview
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")

local Bolt = require(ReplicatedStorage.Bolt)
local AvatarService = require(script.Parent.AvatarService)
local AvatarModel = require(ServerScriptService.models.user.AvatarModel)

local RobloxAvatarLookupService = {}

export type User = { userId: number, username: string, displayName: string }
export type Look = User & { inServer: boolean, items: { any } }

local CACHE_SECONDS = 600
local BUDGET = { requests = 20, seconds = 30 }
local MAX_NAME = 20 -- Roblox usernames are 3-20 characters
local MAX_INFOS = 50

local users: { [number]: User } = {}
local names: { [string]: { userId: number?, at: number } } = {} -- lowercased name -> id (nil = not found)
local avatars: { [number]: { description: HumanoidDescription?, items: { any }, at: number } } = {}
local recentCalls: { [Player]: { number } } = {}

local function fresh(at: number): boolean
	return os.clock() - at < CACHE_SECONDS
end

local function allowed(player: Player): boolean
	local now = os.clock()
	local times = recentCalls[player] or {}
	recentCalls[player] = times
	while times[1] and now - times[1] > BUDGET.seconds do
		table.remove(times, 1)
	end
	if #times >= BUDGET.requests then
		return false
	end
	table.insert(times, now)
	return true
end

local function userInfo(userId: number): User?
	local known = users[userId]
	if known then
		return known
	end
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		local user = { userId = userId, username = inServer.Name, displayName = inServer.DisplayName }
		users[userId] = user
		return user
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync({ userId })
	end)
	if ok and infos and infos[1] then
		local user = { userId = userId, username = infos[1].Username, displayName = infos[1].DisplayName }
		users[userId] = user
		return user
	end
	-- Some accounts (old or restricted ones, e.g. "mouse") get nothing back
	-- from GetUserInfosByUserIdsAsync though their name and avatar resolve.
	local named, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if not named or type(name) ~= "string" then
		return nil
	end
	local user = { userId = userId, username = name, displayName = name }
	users[userId] = user
	return user
end

-- A player in this server: their look here (worn items, owned flags dropped).
local function serverLook(player: Player): { any }?
	local model = AvatarModel.get(tostring(player.UserId))
	if not model then
		return nil
	end
	local items = {}
	for _, item in model.worn do
		table.insert(items, { targetId = item.targetId, kind = item.kind, typeName = item.typeName, name = item.name })
	end
	return items
end

local function roblox(userId: number): { description: HumanoidDescription?, items: { any }, at: number }?
	local cached = avatars[userId]
	if cached and fresh(cached.at) then
		return cached
	end
	local description, items = AvatarService.userAvatar(userId)
	if not description then
		return nil
	end
	local entry = { description = description, items = items, at = os.clock() }
	avatars[userId] = entry
	return entry
end

function RobloxAvatarLookupService.user(userId: number): User?
	return userInfo(userId)
end

function RobloxAvatarLookupService.look(userId: number): Look?
	local user = userInfo(userId)
	if not user then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local items = serverLook(player)
		if items then
			return { userId = userId, username = user.username, displayName = user.displayName, inServer = true, items = items }
		end
	end
	local entry = roblox(userId)
	if not entry then
		return nil
	end
	return { userId = userId, username = user.username, displayName = user.displayName, inServer = false, items = entry.items }
end

function RobloxAvatarLookupService.description(userId: number): HumanoidDescription?
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local items = serverLook(player)
		if items then
			local ok, description = pcall(AvatarService.describeLook, player, items)
			return if ok then description else nil
		end
	end
	local entry = roblox(userId)
	return if entry and entry.description then entry.description:Clone() else nil
end

local function findUser(player: Player, name: any): any
	if type(name) ~= "string" then
		return { ok = false, error = "notfound" }
	end
	name = string.match(name, "^%s*@?(.-)%s*$") or ""
	if #name < 3 or #name > MAX_NAME or not string.match(name, "^[%w_]+$") then
		return { ok = false, error = "notfound" }
	end
	local key = string.lower(name)
	local cached = names[key]
	if not cached or not fresh(cached.at) then
		if not allowed(player) then
			return { ok = false, error = "busy" }
		end
		local ok, result = pcall(function()
			return Players:GetUserIdFromNameAsync(name)
		end)
		if not ok then
			if string.find(tostring(result), "Unknown user") then
				names[key] = { userId = nil, at = os.clock() }
				return { ok = false, error = "notfound" }
			end
			return { ok = false, error = "failed" }
		end
		cached = { userId = result, at = os.clock() }
		names[key] = cached
	end
	local userId = cached.userId
	if not userId then
		return { ok = false, error = "notfound" }
	end
	local user = userInfo(userId)
	if not user then
		return { ok = false, error = "failed" }
	end
	return { ok = true, user = user }
end

local function userLook(player: Player, userId: any): any
	if type(userId) ~= "number" or userId ~= userId or userId <= 0 or userId % 1 ~= 0 then
		return { ok = false, error = "notfound" }
	end
	local cached = avatars[userId]
	local cheap = Players:GetPlayerByUserId(userId) ~= nil or (cached and fresh(cached.at) and users[userId] ~= nil)
	if not cheap and not allowed(player) then
		return { ok = false, error = "busy" }
	end
	local look = RobloxAvatarLookupService.look(userId)
	if not look then
		return { ok = false, error = "failed" }
	end
	return { ok = true, look = look }
end

local function userInfos(_player: Player, ids: any): { User }
	local result: { User } = {}
	if type(ids) ~= "table" then
		return result
	end
	local missing = {}
	for index, id in ids do
		if type(index) == "number" and index <= MAX_INFOS and type(id) == "number" and id > 0 and id % 1 == 0 then
			if users[id] then
				table.insert(result, users[id])
			else
				table.insert(missing, id)
			end
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(missing)
		end)
		if ok and infos then
			for _, info in infos do
				local user = { userId = info.Id, username = info.Username, displayName = info.DisplayName }
				users[info.Id] = user
				table.insert(result, user)
			end
		end
		-- Any the batch skipped: one at a time (see userInfo).
		for _, id in missing do
			if not users[id] then
				local user = userInfo(id)
				if user then
					table.insert(result, user)
				end
			end
		end
	end
	return result
end

function RobloxAvatarLookupService.init()
	Bolt.RemoteFunction("FindRobloxUser").OnServerInvoke = findUser
	Bolt.RemoteFunction("RobloxUserLook").OnServerInvoke = userLook
	Bolt.RemoteFunction("RobloxUserInfos").OnServerInvoke = userInfos
	Players.PlayerRemoving:Connect(function(player: Player)
		recentCalls[player] = nil
	end)
end

return RobloxAvatarLookupService
