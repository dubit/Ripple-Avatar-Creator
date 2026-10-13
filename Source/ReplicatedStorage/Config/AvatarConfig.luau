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
		-- Single body parts (from someone's look or a Roblox outfit)
		Torso = "Torso",
		LeftArm = "LeftArm",
		RightArm = "RightArm",
		LeftLeg = "LeftLeg",
		RightLeg = "RightLeg",
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
		-- A full body brings its own head and every part.
		Body = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" },
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
	-- Skin tones offered under Catalogue › Body › Skin tone, after "your own"
	-- and before Custom: Roblox's avatar-editor palette (read from the mobile
	-- app; colours that are BrickColors use the exact BrickColor value, the
	-- rest are sampled from a screenshot, within a level or two).
	skinTones = {
		{ name = "Dark brown", hex = "#3D2C22" },
		{ name = "Deep brown", hex = "#4B372E" },
		{ name = "Medium brown", hex = "#564236" },
		{ name = "Dark taupe", hex = "#5A4C42" },
		{ name = "Bronze", hex = "#8A6E49" },
		{ name = "Tan", hex = "#AB8B64" },
		{ name = "Linen", hex = "#AF9483" },
		{ name = "Sand", hex = "#D4A684" },
		{ name = "Light orange", hex = "#EAB892" },
		{ name = "Pastel Blue", hex = "#80BBDB" },
		{ name = "Grey", hex = "#BCBCBC" },
		{ name = "Red", hex = "#B53A35" },
		{ name = "Rust", hex = "#A45918" },
		{ name = "Bright orange", hex = "#DA8541" },
		{ name = "Pale yellow", hex = "#FBE27D" },
		{ name = "Olive", hex = "#B4BF45" },
		{ name = "Bright green", hex = "#4B974B" },
		{ name = "Dark green", hex = "#287F47" },
		{ name = "Cyan", hex = "#04AFEC" },
		{ name = "Toothpaste", hex = "#00FFFF" },
		{ name = "Blue", hex = "#3779B3" },
		{ name = "Carnation pink", hex = "#FF98DC" },
		{ name = "Alder", hex = "#B480FF" },
		{ name = "Purple", hex = "#835196" },
		{ name = "Magenta", hex = "#D415B0" },
	},
}

return config
