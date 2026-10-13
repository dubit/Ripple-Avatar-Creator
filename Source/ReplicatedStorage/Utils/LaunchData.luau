--!strict

--[[
	LaunchData

	The one string an experience link can carry ("launchData", up to 200
	bytes), read on join from player:GetJoinData().LaunchData. Two kinds of
	link use it:

	  · ad / campaign links: a plain tag ("wknd-adA"), recorded by
	    AnalyticsService as the `launch_data` acquisition property;
	  · share links: "s:<code>" (a share code, SharedContentService), from
	    the share dialog's QR. Fields are "key:value" joined by "|", so a
	    link can carry more later ("s:7KQ2XM|c:wknd-adA").

	A plain tag has no ":", so the two never collide.

	API:
		read(player) -> string        the join's launch data, "" if none
		                              (server; in Studio, falls back to a
		                              Workspace `TestLaunchData` attribute
		                              or StringValue)
		parse(text) -> { [string]: string }   its "key:value" fields
		shareCode(text) -> string?    the "s" field, upper-cased
		shareLink(code) -> string     the link that opens a code in this
		                              experience (what the QR holds)
]]

local RunService = game:GetService("RunService")

local LaunchData = {}

function LaunchData.read(player: Player): string
	local launchData = ""
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(joinData) == "table" and type(joinData.LaunchData) == "string" then
		launchData = joinData.LaunchData
	end
	-- Studio playtests can't supply real launch data: set a `TestLaunchData`
	-- attribute or StringValue on Workspace (e.g. "wknd-adA" or "s:7KQ2XM").
	-- Gated on IsStudio, so live joins are never affected.
	if launchData == "" and RunService:IsStudio() then
		local testValue = workspace:GetAttribute("TestLaunchData")
		if type(testValue) ~= "string" or testValue == "" then
			local value = workspace:FindFirstChild("TestLaunchData")
			testValue = if value and value:IsA("StringValue") then value.Value else nil
		end
		if type(testValue) == "string" then
			launchData = testValue
		end
	end
	return launchData
end

function LaunchData.parse(text: string): { [string]: string }
	local fields: { [string]: string } = {}
	for _, pair in string.split(text, "|") do
		local key, value = string.match(pair, "^%s*([%w_]+):(.*)$")
		if key and value then
			fields[key] = value
		end
	end
	return fields
end

function LaunchData.shareCode(text: string): string?
	local code = LaunchData.parse(text).s
	return if code and code ~= "" then string.upper(code) else nil
end

function LaunchData.shareLink(code: string): string
	return "https://www.roblox.com/games/start?placeId=" .. game.PlaceId .. "&launchData=s:" .. code
end

return LaunchData
