--!strict
-- REFERENCE COPY. The live module is Studio-authored at
-- ReplicatedStorage.Config.StoresConfig (configs aren't Rojo-synced in
-- this template — see docs/CONFIG_GUIDE.md). Keep the two in step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigTypes = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ConfigTypes")
local StoresConfigTypes = require(ConfigTypes:WaitForChild("StoresConfigTypes"))

type StoresConfig = StoresConfigTypes.StoresConfig

local config: StoresConfig = {
	maxStores = 3,
	minItems = 4,
	maxItems = 100,
	maxOutfits = 20,
	nameLength = { min = 3, max = 30 },
	featured = 4,
	sectionSize = 10,
	collections = {
		{ name = "Free", maxPrice = 0 },
		{ name = "Under 50", minPrice = 1, maxPrice = 49 },
		{ name = "Accessories", category = "Accessories" },
		{ name = "Clothing", category = "Clothing" },
		{ name = "Hair", assetTypes = { "HairAccessory" } },
		{ name = "Animations", category = "Animations" },
	},
	maxCollections = 3,
	collectionMinItems = 2,
}

return config
