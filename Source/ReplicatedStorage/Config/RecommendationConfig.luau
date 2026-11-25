--!strict
-- REFERENCE COPY. The live module is Studio-authored at
-- ReplicatedStorage.Config.RecommendationConfig (configs aren't Rojo-synced in
-- this template — see docs/CONFIG_GUIDE.md). Keep the two in step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigTypes = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ConfigTypes")
local RecommendationConfigTypes = require(ConfigTypes:WaitForChild("RecommendationConfigTypes"))

type RecommendationConfig = RecommendationConfigTypes.RecommendationConfig

local config: RecommendationConfig = {
	recipe = { "creator", "complete", "style", "creator", "complete", "wildcard", "style" },
	areas = {
		{ name = "Hair", weight = 3, category = "Body", chips = { "Hair" }, covers = { "HairAccessory" } },
		{ name = "Hat", weight = 2, category = "Accessories", chips = { "Head" }, covers = { "Hat" } },
		{ name = "Face", weight = 1.5, category = "Accessories", chips = { "Face" }, covers = { "FaceAccessory" } },
		{ name = "Neck", category = "Accessories", chips = { "Neck" }, covers = { "NeckAccessory" } },
		{ name = "Shoulder", category = "Accessories", chips = { "Shoulder" }, covers = { "ShoulderAccessory" } },
		{ name = "Front", category = "Accessories", chips = { "Front" }, covers = { "FrontAccessory" } },
		{ name = "Back", weight = 1.5, category = "Accessories", chips = { "Back" }, covers = { "BackAccessory" } },
		{ name = "Waist", category = "Accessories", chips = { "Waist" }, covers = { "WaistAccessory" } },
		{
			name = "Top",
			weight = 3,
			category = "Clothing",
			chips = { "Shirts", "T-Shirts", "Sweaters" },
			covers = { "ShirtAccessory", "TShirtAccessory", "SweaterAccessory", "Shirt", "TShirt", "DressSkirtAccessory" },
		},
		{ name = "Jacket", weight = 2, category = "Clothing", chips = { "Jackets" }, covers = { "JacketAccessory" } },
		{
			name = "Legs",
			weight = 3,
			category = "Clothing",
			chips = { "Pants", "Shorts", "Dresses & Skirts" },
			covers = { "PantsAccessory", "ShortsAccessory", "DressSkirtAccessory", "Pants" },
		},
		{ name = "Shoes", weight = 3, category = "Clothing", chips = { "Shoes" }, covers = { "Shoes", "LeftShoeAccessory", "RightShoeAccessory" } },
	},
	styleWords = {
		"goth", "gothic", "emo", "punk", "grunge", "y2k", "cyber", "cyberpunk", "kawaii", "cute", "preppy",
		"fairy", "angel", "angelic", "demon", "devil", "vampire", "cowboy", "cowgirl", "pirate", "ninja", "knight",
		"princess", "prince", "royal", "crown", "street", "streetwear", "skater", "sporty", "vintage", "retro",
		"cottagecore", "baddie", "anime", "cat", "bunny", "bear", "fox", "wolf", "dragon", "witch", "wizard",
		"star", "stars", "heart", "hearts", "flower", "floral", "butterfly", "cherry", "strawberry", "camo",
		"plaid", "denim", "leather", "school", "uniform", "business", "beach", "summer", "winter", "christmas",
		"halloween", "spooky", "skull", "chain", "chains", "bow", "ribbon", "lace", "frilly", "fluffy",
		"military", "robot", "mecha", "alien", "galaxy", "space", "glitch", "rainbow", "pastel", "neon",
	},
	colourWords = {
		"black", "white", "red", "blue", "pink", "purple", "green", "yellow", "orange", "brown", "grey",
		"gray", "gold", "golden", "silver", "teal", "cyan", "navy", "beige", "cream", "lavender", "lilac",
	},
	ignoreCreators = { "Roblox" },
	-- Types never shown in a ring: classic clothing, gear, backgrounds,
	-- emotes (user, 2026-11-24).
	skipTypes = { "Shirt", "Pants", "TShirt", "Gear", "AvatarBackground", "EmoteAnimation" },
	-- Types never sent to the engine (basis / worn). Classic clothing is
	-- sent: it says something about the outfit, it just isn't recommended
	-- (user, 2026-11-25).
	unsentTypes = { "Gear", "AvatarBackground", "EmoteAnimation" },
	-- Ripple (Tomorrow's Players) items: one further down the engine's list
	-- takes the place of a non-Ripple item in the ring if its score is at
	-- least rippleWithin x that item's (user, 2026-11-24).
	rippleGroupId = 15288940,
	rippleWithin = 0.7,
	pickFrom = 12,
	maxSearches = 6,
	creatorSort = "Bestselling",
	styleSort = "MostFavorited",
	wildcardSort = "MostFavorited",
	wildcardWindow = "PastMonth",
	ring = {
		count = 7,
		radius = 10,
		padSize = 5,
		cardSize = 4,
		cardHeight = 5,
		cardMaxDistance = 120,
		walkAway = 14,
		maxStep = 4,
		groundSearch = 30,
		modelSize = 3,
		modelHeight = 2.6,
		spinSpeed = 0.8,
		bobHeight = 0.25,
		bobSpeed = 1.8,
		dwell = 0.25,
	},
}

return config
