--!strict

--[[
	useTapAvatar

	Calls `onTap` when the player taps or clicks their own character in the
	world (it opens the recommendation ring). Taps are told apart from camera
	drags by useWorldTap; ignored while `enabled` is false (e.g. the panel
	is open). The hit test is a raycast from the camera through the press
	point that only considers the local character.
]]

local Players = game:GetService("Players")

local useWorldTap = require(script.Parent:WaitForChild("useWorldTap"))

local REACH = 500 -- studs

local function hitsOwnCharacter(screenPosition: Vector3): boolean
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	if not camera or not character then
		return false
	end
	-- Input positions exclude the top-bar inset, as ScreenPointToRay expects.
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { character }
	return workspace:Raycast(ray.Origin, ray.Direction * REACH, params) ~= nil
end

local function useTapAvatar(onTap: () -> (), enabled: boolean)
	useWorldTap(function(position: Vector3)
		if hitsOwnCharacter(position) then
			onTap()
		end
	end, enabled)
end

return useTapAvatar
