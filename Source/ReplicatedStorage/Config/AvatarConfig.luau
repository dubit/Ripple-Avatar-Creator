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
		DynamicHead = "Head",
		DynamicHeadAvatar = "Head",
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
}

return config
