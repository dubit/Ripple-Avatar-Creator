--!strict

--[[
	DeepLinkService (event-driven)

	Share links: a player who joins through one (the share dialog's QR,
	launchData "s:<code>", see LaunchData) lands on what the code opens.

	On join the code is read and kept for the player; the client takes it
	once the HUD is up over the "TakeJoinLink" remote function (Bolt) ->
	{ code, kind } or nil, and opens it (an outfit: its page under Outfits).
	The kind comes from the code's record, so the client can skip kinds it
	doesn't know yet (stores, users). A link opened while already playing
	starts a fresh join (Roblox has no hand-off into a running session), so
	this only ever runs at join; in-game, codes go in the Outfits search.

	Analytics: share_join { code, kind, owner_id, own } once per join with a
	code (`own` when it's the sharer's own code). AnalyticsService records
	such joins as launch_data "share".

	Studio: set Workspace's `TestLaunchData` attribute to "s:<code>" before
	Play.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bolt = require(ReplicatedStorage.Bolt)
local LaunchData = require(ReplicatedStorage.Utils.LaunchData)
local SharedContentService = require(script.Parent.SharedContentService)

local DeepLinkService = {}

type Link = { code: string, record: any?, ready: boolean }

local links: { [Player]: Link } = {}

-- Lazy, like AbstractController (avoids a load-order dependency).
local analytics: any = nil
local function track(player: Player, eventName: string, params: { [string]: any })
	if analytics == nil then
		local ok, service = pcall(function()
			return require(script.Parent.Parent.framework.AnalyticsService)
		end)
		analytics = if ok then service else false
	end
	if analytics and analytics.isEnabled then
		analytics:trackEvent(player, eventName, params)
	end
end

local function onPlayerAdded(player: Player)
	local code = SharedContentService.normalise(LaunchData.shareCode(LaunchData.read(player)))
	if not code then
		return
	end
	local link: Link = { code = code, record = nil, ready = false }
	links[player] = link
	local record = SharedContentService.lookup(code)
	link.record = if type(record) == "table" then record else nil
	link.ready = true
	local ownerId = if link.record and type(link.record.ownerId) == "number" then link.record.ownerId else 0
	track(player, "share_join", {
		code = code,
		kind = if link.record then tostring(link.record.kind) else "unknown",
		owner_id = ownerId,
		own = ownerId == player.UserId,
	})
end

function DeepLinkService.init()
	Bolt.RemoteFunction("TakeJoinLink").OnServerInvoke = function(player: Player)
		local link = links[player]
		if not link then
			return nil
		end
		local waited = 0
		while not link.ready and waited < 10 do
			waited += task.wait(0.1)
		end
		links[player] = nil
		if not link.record then
			return nil
		end
		return { code = link.code, kind = link.record.kind }
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		links[player] = nil
	end)
end

return DeepLinkService
