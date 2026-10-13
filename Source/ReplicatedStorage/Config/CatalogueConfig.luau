--!strict
-- REFERENCE COPY. The live module is Studio-authored at
-- ReplicatedStorage.Config.CatalogueConfig (configs aren't Rojo-synced in
-- this template — see docs/CONFIG_GUIDE.md). Keep the two in step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigTypes = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ConfigTypes")
local CatalogueConfigTypes = require(ConfigTypes:WaitForChild("CatalogueConfigTypes"))

type CatalogueConfig = CatalogueConfigTypes.CatalogueConfig

-- Categories follow the Roblox marketplace menu
-- (catalog.roblox.com/v1/search/navigation-menu-items), with Classic split
-- out of Clothing. Bodysuits is left out: the API has no type for it.
local config: CatalogueConfig = {
	categories = {
		{
			name = "Body",
			chips = {
				{ name = "Full Bodies", bundleTypes = { "BodyParts" } },
				{ name = "Hair", assetTypes = { "HairAccessory" } },
				{ name = "Heads", bundleTypes = { "DynamicHead" } },
				{ name = "Skin tone", special = "skinTone" },
			},
		},
		{
			name = "Clothing",
			chips = {
				{ name = "Layering", special = "layering" }, -- the order your layered clothing goes on
				{ name = "Shirts", assetTypes = { "ShirtAccessory" } },
				{ name = "T-Shirts", assetTypes = { "TShirtAccessory" } },
				{ name = "Sweaters", assetTypes = { "SweaterAccessory" } },
				{ name = "Jackets", assetTypes = { "JacketAccessory" } },
				{ name = "Pants", assetTypes = { "PantsAccessory" } },
				{ name = "Dresses & Skirts", assetTypes = { "DressSkirtAccessory" } },
				{ name = "Shorts", assetTypes = { "ShortsAccessory" } },
				{ name = "Shoes", bundleTypes = { "Shoes" } },
			},
		},
		{
			name = "Classic",
			chips = {
				{ name = "Shirts", assetTypes = { "Shirt" } },
				{ name = "T-Shirts", assetTypes = { "TShirt" } },
				{ name = "Pants", assetTypes = { "Pants" } },
			},
		},
		{
			name = "Accessories",
			chips = {
				{ name = "Head", assetTypes = { "Hat" } },
				{ name = "Face", assetTypes = { "FaceAccessory" } },
				{ name = "Neck", assetTypes = { "NeckAccessory" } },
				{ name = "Shoulder", assetTypes = { "ShoulderAccessory" } },
				{ name = "Front", assetTypes = { "FrontAccessory" } },
				{ name = "Back", assetTypes = { "BackAccessory" } },
				{ name = "Waist", assetTypes = { "WaistAccessory" } },
				{ name = "Gear", assetTypes = { "Gear" } },
			},
		},
		{
			name = "Backgrounds",
			chips = {
				{ name = "Backgrounds", assetTypes = { "AvatarBackground" } },
			},
		},
		{
			name = "Animations",
			chips = {
				{ name = "Bundles", bundleTypes = { "Animations" } },
				{ name = "Emotes", assetTypes = { "EmoteAnimation" } },
			},
		},
		{
			name = "Makeup",
			chips = {
				{ name = "Eyes", assetTypes = { "EyeMakeup" } },
				{ name = "Lips", assetTypes = { "LipMakeup" } },
				{ name = "Face", assetTypes = { "FaceMakeup" } },
				{ name = "Eyelashes", assetTypes = { "EyelashAccessory" } },
				{ name = "Eyebrows", assetTypes = { "EyebrowAccessory" } },
			},
		},
		{
			name = "Scale", -- body scale sliders (Roblox's avatar editor "Scale")
			special = "scale",
			chips = {},
		},
	},
	pageSize = 60,
	sort = "Relevance",
	sortAggregation = "AllTime",
	sorts = {
		{ label = "Relevance", sortType = "Relevance", windowed = false },
		{ label = "Most Favourited", sortType = "MostFavorited", windowed = true },
		{ label = "Bestselling", sortType = "Bestselling", windowed = true },
		{ label = "Recently Created", sortType = "RecentlyCreated", windowed = false },
		{ label = "Price: Low to High", sortType = "PriceLowToHigh", windowed = false },
		{ label = "Price: High to Low", sortType = "PriceHighToLow", windowed = false },
	},
	sortWindows = {
		{ label = "All time", aggregation = "AllTime" },
		{ label = "Past month", aggregation = "PastMonth" },
		{ label = "Past week", aggregation = "PastWeek" },
		{ label = "Past day", aggregation = "PastDay" },
	},
	priceMax = 400,
	priceStep = 5,
	pricePresets = {
		{ label = "Free", min = 0, max = 0 },
		{ label = "Under 50", max = 49 },
		{ label = "50–100", min = 50, max = 100 },
		{ label = "100+", min = 100 },
	},
	salesTypes = {
		{ label = "All", filter = "All" },
		{ label = "Limited", filter = "Collectibles" },
		{ label = "Timed", filter = "TimedOptions" },
	},
	colours = { "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Brown", "Black", "Grey", "White" },
	colourTarget = 30,
	colourMaxPages = 5,
	includeOffSale = false,
	cacheSeconds = 300,
	searchDebounce = 0.4,
	backoffSeconds = 30,
	thumbnailSize = 150,
}

return config
