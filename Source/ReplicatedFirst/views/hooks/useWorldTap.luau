--!strict

--[[
	useWorldTap

	Calls `onTap(position)` when the player taps or clicks the 3D world
	(`position`: the press point, as ScreenPointToRay expects it). The
	caller decides what was hit (useTapAvatar: your own character;
	OthersRings: an item in another player's ring).

	  · mouse: on left-button press, like the HUD's buttons
	  · touch: on release, and only if the finger barely moved and wasn't
	    held long, so dragging to turn the camera never counts as a tap

	Presses that Roblox or the HUD already used (gameProcessed) are ignored,
	and so is everything while `enabled` is false (e.g. the panel is open).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local TOUCH_SLOP = 12 -- pixels a tap may drift
local TOUCH_TIME = 0.35 -- seconds a tap may last

local function useWorldTap(onTap: (position: Vector3) -> (), enabled: boolean)
	local latest = React.useRef({ onTap = onTap, enabled = enabled })
	latest.current = { onTap = onTap, enabled = enabled }

	React.useEffect(function()
		local touches: { [InputObject]: { position: Vector3, at: number } } = {}
		local began = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or not latest.current.enabled then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				latest.current.onTap(input.Position)
			elseif input.UserInputType == Enum.UserInputType.Touch then
				touches[input] = { position = input.Position, at = os.clock() }
			end
		end)
		local ended = UserInputService.InputEnded:Connect(function(input: InputObject)
			local start = touches[input]
			if not start then
				return
			end
			touches[input] = nil
			local quick = os.clock() - start.at <= TOUCH_TIME
			local still = (input.Position - start.position).Magnitude <= TOUCH_SLOP
			if quick and still and latest.current.enabled then
				latest.current.onTap(input.Position)
			end
		end)
		return function()
			began:Disconnect()
			ended:Disconnect()
		end
	end, {})
end

return useWorldTap
