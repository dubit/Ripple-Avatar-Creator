--!strict
-- REFERENCE COPY. The live module is Studio-authored at
-- ReplicatedStorage.Config.AvatarConfig (configs aren't Rojo-synced in
-- this template — see docs/CONFIG_GUIDE.md). Keep the two in step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigTypes = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ConfigTypes")
local AvatarConfigTypes = require(ConfigTypes:WaitForChild("AvatarConfigTypes"))

type AvatarConfig = AvatarConfigTypes.AvatarConfig

local config: AvatarConfig = {
	slots = {
		-- Body
		HairAccessory = "Hair", -- one hair, as in the design
		BodyParts = "Body",
		DynamicHead = "Head", -- a dynamic head (bundle or asset)
		DynamicHeadAvatar = "Head",
		Head = "Head", -- a classic head mesh
		Face = "Face", -- a classic face
		-- Layered clothing
		ShirtAccessory = "Shirt",
		TShirtAccessory = "TShirt",
		SweaterAccessory = "Sweater",
		JacketAccessory = "Jacket",
		PantsAccessory = "Pants",
		ShortsAccessory = "Shorts",
		DressSkirtAccessory = "DressSkirt",
		Shoes = "Shoes",
		LeftShoeAccessory = "LeftShoe", -- single shoes, from a player's own avatar
		RightShoeAccessory = "RightShoe",
		-- Classic clothing
		Shirt = "ClassicShirt",
		Pants = "ClassicPants",
		TShirt = "ClassicTShirt",
		-- Animations, gear, backgrounds
		Animations = "Animations",
		Gear = "Gear",
		AvatarBackground = "Background",
		-- Makeup and face details
		FaceMakeup = "FaceMakeup",
		LipMakeup = "LipMakeup",
		EyeMakeup = "EyeMakeup",
		EyebrowAccessory = "Eyebrows",
		EyelashAccessory = "Eyelashes",
	},
	alsoReplaces = {
		Body = { "Head" }, -- a full body brings its own head
	},
	groups = {
		Hat = "Accessories",
		FaceAccessory = "Accessories",
		NeckAccessory = "Accessories",
		ShoulderAccessory = "Accessories",
		FrontAccessory = "Accessories",
		BackAccessory = "Accessories",
		WaistAccessory = "Accessories",
		EmoteAnimation = "Emotes",
	},
	groupLimits = {
		Accessories = 10,
		Emotes = 8, -- the emote wheel's slots
	},
	tryOnCooldown = 0.2,
	undoDepth = 20,
	maxWearMany = 20,
	basketLimit = 100,
	basketBudget = { requests = 10, seconds = 2 },
	outfits = {
		maxOutfits = 50,
		maxItems = 40,
		nameLength = 30,
		cooldown = 0.3,
	},
	-- Skin tones offered under Catalogue › Body › Skin tone (Roblox's
	-- classic body colours), after "your own".
	skinTones = {
		{ name = "Pastel brown", hex = "#FFCC99" },
		{ name = "Light orange", hex = "#EAB892" },
		{ name = "Nougat", hex = "#CC8E69" },
		{ name = "Brick yellow", hex = "#D7C59A" },
		{ name = "Dark orange", hex = "#A05F35" },
		{ name = "Burnt sienna", hex = "#8F4C2A" },
		{ name = "Brown", hex = "#7C5C46" },
		{ name = "Reddish brown", hex = "#694028" },
		{ name = "Dark taupe", hex = "#5A4C42" },
		{ name = "Sand red", hex = "#957977" },
		{ name = "Bright yellow", hex = "#F5CD30" },
		{ name = "White", hex = "#F2F3F3" },
		{ name = "Medium stone grey", hex = "#A3A2A5" },
		{ name = "Black", hex = "#1B2A35" },
		{ name = "Bright red", hex = "#C4281C" },
		{ name = "Bright blue", hex = "#0D69AC" },
		{ name = "Bright green", hex = "#4B974B" },
		{ name = "Lavender", hex = "#8C5B9F" },
	},
}

return config
