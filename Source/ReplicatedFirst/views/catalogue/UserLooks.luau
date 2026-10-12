--!strict

--[[
	UserLooks (client)

	Other people's looks for Outfits › Roblox, from RobloxAvatarLookupService
	(server; Bolt remote functions). Roblox only exposes another user's
	current avatar, not their saved outfits; a player in this server shows
	what they're wearing here.

	API (all yield except where noted):
		find(name) -> (User?, error?)   a username (or @username) -> user;
		                                error "notfound" | "busy" | "failed"
		look(userId) -> (Look?, error?) their look, items as CatalogueClient
		                                item ids (cached briefly)
		info(userIds) -> { [userId]: User }   names for ids (cached)
		friends() -> { User }           your Roblox friends (no yield: loads
		                                in the background, fires `changed`)
		prefetch(userIds)               fetch names for ids (no yield; fires
		                                `changed`)
		known(userId) -> User?          no yield
		changed                         signal: friends / names arrived
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bolt = require(ReplicatedStorage:WaitForChild("Bolt"))
local CatalogueClient = require(script.Parent:WaitForChild("CatalogueClient"))

local UserLooks = {}

export type User = { userId: number, username: string, displayName: string }
export type Look = User & { inServer: boolean, items: { number } }

local findRemote = Bolt.RemoteFunction("FindRobloxUser")
local lookRemote = Bolt.RemoteFunction("RobloxUserLook")
local infoRemote = Bolt.RemoteFunction("RobloxUserInfos")

local LOOK_SECONDS = 20 -- in-server looks change as people try things on
local MAX_FRIENDS = 50

local users: { [number]: User } = {}
local found: { [string]: { user: User?, error: string? } } = {}
local looks: { [number]: { look: Look, at: number } } = {}
local friendList: { User } = {}
local friendsLoading = false

local changedEvent = Instance.new("BindableEvent")
UserLooks.changed = changedEvent.Event

local function remember(user: any): User?
	if type(user) ~= "table" or type(user.userId) ~= "number" then
		return nil
	end
	local entry = { userId = user.userId, username = tostring(user.username), displayName = tostring(user.displayName) }
	users[entry.userId] = entry
	return entry
end

function UserLooks.known(userId: number): User?
	return users[userId]
end

function UserLooks.find(name: string): (User?, string?)
	local key = string.lower(name)
	local cached = found[key]
	if cached then
		return cached.user, cached.error
	end
	local ok, result = pcall(function()
		return findRemote:InvokeServer(name)
	end)
	if not ok or type(result) ~= "table" then
		return nil, "failed"
	end
	if result.ok then
		local user = remember(result.user)
		found[key] = { user = user }
		return user, nil
	end
	-- Only "not found" is worth remembering; busy / failed may pass.
	if result.error == "notfound" then
		found[key] = { error = "notfound" }
	end
	return nil, result.error or "failed"
end

function UserLooks.look(userId: number): (Look?, string?)
	local cached = looks[userId]
	if cached and os.clock() - cached.at < LOOK_SECONDS then
		return cached.look, nil
	end
	local ok, result = pcall(function()
		return lookRemote:InvokeServer(userId)
	end)
	if not ok or type(result) ~= "table" then
		return nil, "failed"
	end
	if not result.ok or type(result.look) ~= "table" then
		return nil, result.error or "failed"
	end
	local raw = result.look
	local items = {}
	for _, entry in raw.items or {} do
		table.insert(items, CatalogueClient.remember(entry).id)
	end
	local look: Look = {
		userId = raw.userId,
		username = tostring(raw.username),
		displayName = tostring(raw.displayName),
		inServer = raw.inServer == true,
		items = items,
	}
	remember(look)
	looks[userId] = { look = look, at = os.clock() }
	return look, nil
end

function UserLooks.info(userIds: { number }): { [number]: User }
	local result: { [number]: User } = {}
	local missing = {}
	for _, id in userIds do
		if users[id] then
			result[id] = users[id]
		else
			table.insert(missing, id)
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(function()
			return infoRemote:InvokeServer(missing)
		end)
		if ok and type(infos) == "table" then
			for _, info in infos do
				local user = remember(info)
				if user then
					result[user.userId] = user
				end
			end
		end
	end
	return result
end

function UserLooks.friends(): { User }
	if not friendsLoading then
		friendsLoading = true
		task.spawn(function()
			local ok, pages = pcall(function()
				return Players:GetFriendsAsync(Players.LocalPlayer.UserId)
			end)
			if not ok or not pages then
				return
			end
			local list = {}
			while #list < MAX_FRIENDS do
				for _, friend in pages:GetCurrentPage() do
					if #list >= MAX_FRIENDS then
						break
					end
					local user = remember({ userId = friend.Id, username = friend.Username, displayName = friend.DisplayName })
					if user then
						table.insert(list, user)
					end
				end
				if pages.IsFinished then
					break
				end
				if not pcall(function()
					pages:AdvanceToNextPageAsync()
				end) then
					break
				end
			end
			friendList = list
			changedEvent:Fire()
		end)
	end
	return friendList
end

-- Names for ids we were handed without them (recent lookups); fires changed.
-- Each id is asked about once.
local asked: { [number]: boolean } = {}
function UserLooks.prefetch(userIds: { number })
	local missing = {}
	for _, id in userIds do
		if not users[id] and not asked[id] then
			asked[id] = true
			table.insert(missing, id)
		end
	end
	if #missing > 0 then
		task.spawn(function()
			UserLooks.info(missing)
			changedEvent:Fire()
		end)
	end
end

return UserLooks
