--!strict

--[[
	useGlassBlur

	Client-only scene blur behind a full-screen glass panel. Roblox UI can't
	blur what's behind a single frame (no backdrop-filter), so this blurs the
	whole 3D view while `active` — right for the full-screen panel, wrong for
	the World options side panel, where the player needs to see the world
	change live.

	The BlurEffect lives in Lighting on this client only (never replicated) and
	is destroyed on unmount. Size springs in and out.

	Usage:
		useGlassBlur(isPanelOpen and skin.glass == "blur")
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local Tokens = require(script.Parent.Parent:WaitForChild("Tokens"))
local useSpringNumber = require(script.Parent:WaitForChild("useSpringNumber"))

local function useGlassBlur(active: boolean, size: number?)
	local target = if active then size or Tokens.glass.blurSize else 0
	local current = useSpringNumber(target, if active then Tokens.spring.panelIn else Tokens.spring.panelOut)
	local blurRef = React.useRef(nil :: BlurEffect?)

	React.useEffect(function()
		local blur = Instance.new("BlurEffect")
		blur.Name = "SkinGlassBlur"
		blur.Size = 0
		blur.Parent = Lighting
		blurRef.current = blur
		return function()
			blur:Destroy()
			blurRef.current = nil
		end
	end, {})

	React.useEffect(function()
		local blur = blurRef.current
		if blur then
			blur.Size = current
			blur.Enabled = current > 0
		end
	end, { current })
end

return useGlassBlur
