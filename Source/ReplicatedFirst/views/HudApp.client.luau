--!strict

--[[
	HudApp

	Entry point for the react-luau HUD: mounts views/Hud into its OWN
	ScreenGui. Never createRoot(PlayerGui) — React clears its container's
	existing children on first render, which deletes any other ScreenGui
	already there.

	Also starts background preloads of the UI sounds, icons and world textures
	(floor patterns, flat skies), so their first use isn't delayed by
	downloading the asset, and holds phones and tablets in landscape (the
	HUD isn't laid out for portrait).
]]

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local Hud = require(script.Parent:WaitForChild("Hud"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local SkinAssets = require(script.Parent:WaitForChild("SkinAssets"))

Sounds.preload()
task.spawn(function()
	local images = {}
	for _, name in SkinAssets.iconNames() do
		table.insert(images, SkinAssets.iconImage(name) :: string)
	end
	for _, group in { SkinAssets.floorTextures, SkinAssets.skyTextures } do
		for _, id in group do
			if id ~= 0 then
				table.insert(images, "rbxassetid://" .. id)
			end
		end
	end
	ContentProvider:PreloadAsync(images)
end)

-- Landscape only, either way up. The place's StarterGui says so too; this
-- keeps it so if that setting ever changes.
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HudApp"
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = ReactRoblox.createRoot(screenGui)
root:render(React.createElement(Hud))
