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
	maxRows = 12,
	rowNameLength = { min = 1, max = 24 },
	rowLimit = { default = 20, max = 60 },
}

return config
