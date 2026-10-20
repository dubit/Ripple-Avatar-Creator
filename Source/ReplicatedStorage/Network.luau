--!strict

--[[
	Network - Central networking module using Bolt

	This module provides:
	- Auto-generation of Bolt ReliableEvents for controller intents
	- Auto-generation of Bolt RemoteProperties for model state
	- Type-safe action constants and state types
	- Single source of truth for all networking (replaces IntentActions + StateEvents)

	To add new controllers or models, simply add them to NetworkConfig below.

	Usage in Controllers:
		local Network = require(ReplicatedStorage.Network)
		self.intentEvent = Network.registerIntent("Basket")

	Usage in Models:
		local Network = require(ReplicatedStorage.Network)
		self._stateProperty = Network.registerState("Basket", defaultState)

	Usage in Views:
		local Network = require(ReplicatedStorage.Network)
		local basketIntent = Network.Intent.Basket
		basketIntent:FireServer(Network.Actions.Basket.Add, { targetId = 123, kind = "Asset" })

		local basketState = Network.State.Basket
		basketState:Observe(function(data) ... end)
]]

-- WaitForChild, not direct indexing: Network is required very early from
-- ReplicatedFirst (HudApp), before ReplicatedStorage is guaranteed to have
-- replicated its siblings to the client. Direct indexing raised an intermittent
-- "Bolt is not a valid member of ReplicatedStorage" on startup.
local Bolt = require(script.Parent:WaitForChild("Bolt"))
local NetworkBuilder = require(script.Parent:WaitForChild("NetworkBuilder"))

-- ============================================================================
-- GAME CONFIGURATION: Add new controllers and models here
-- ============================================================================

-- Network Configuration: Single source of truth for all controllers and state
local NetworkConfig = {
	Controllers = {
		Avatar = { "TryOn", "TakeOff", "TakeOffMany", "WearMany", "TakeOffAll", "Undo", "Reset", "WearRobloxOutfit", "WearUserLook", "SetSkin", "RefreshOwn", "SetScale", "MoveLayer" },
		Basket = { "Add", "Remove", "AddMany", "RemoveMany", "Clear" },
		Community = { "Favourite", "Report", "Open", "Moderate" },
		Favourites = { "Toggle" },
		Navigation = { "View" },
		Outfits = { "Save", "Overwrite", "Rename", "Delete", "WearAll", "WearSelected", "Follow", "Share", "ShareCreation", "WearShared" },
		Purchase = { "Buy", "Finished", "Check" },
		Stores = { "Create", "Rename", "AddItem", "RemoveItem", "AddOutfit", "RemoveOutfit", "SetRowItems", "AddRow", "EditRow", "SetRowSearch", "RenameRow", "RemoveRow", "MoveRow", "Publish", "Unpublish", "Delete", "Favourite", "Report", "Open", "Share", "Moderate" },
		SlashCommand = {},  -- No actions, just the intent
		WorldOptions = { "Set", "Reset" },
	},

	States = {
		-- What the player is wearing (persisted; AvatarModel). `worn` is a list
		-- of { targetId, kind, typeName, name } in the order put on.
		Avatar = {
			ownerId = "",
			worn = {},
			skin = {},
			ownSkin = {},
			scale = {},
			ownScale = {},
			seeded = false,
			own = {},
			canUndo = false,
		},
		-- What the player means to buy (persisted; BasketModel): a list of
		-- { targetId, kind, typeName, name }, oldest first.
		Basket = {
			ownerId = "",
			items = {},
		},
		-- The player's favourite catalogue items (persisted; FavouritesModel),
		-- as "Asset:123" / "Bundle:45" keys, most recent last.
		Favourites = {
			ownerId = "",
			items = {},
		},
		-- The player's saved outfits (persisted; OutfitsModel), oldest first:
		-- { id, name, items = { { targetId, kind, typeName, name } } }.
		Outfits = {
			ownerId = "",
			outfits = {},
			nextId = 1,
			following = {},
			creationCodes = {},
			published = {},
			communityFavourites = {},
			communityRecent = {},
		},
		-- What the player owns, as far as we've checked, and their latest
		-- purchase (session only; OwnershipModel). `owned` holds "Asset:123" /
		-- "Bundle:45" keys; `purchase.id` echoes the client's request id.
		Ownership = {
			ownerId = "",
			owned = {},
			purchase = { id = 0, state = "idle", reason = "", bought = {} },
		},
		SlashCommand = {
			ownerId = "",
			message = "",
		},
		-- The player's side of stores (persisted; StoresModel): codes of the
		-- stores they own and have starred (newest first), and the day they
		-- last visited each store.
		Stores = {
			ownerId = "",
			mine = {},
			favourites = {},
			visited = {},
		},
		-- Defaults mirror WorldOptionsConfig.defaults (the model loads them).
		WorldOptions = {
			ownerId = "",
			time = 14.5,
			sky = "Clear",
			floor = "#cc5f00",
			floorLightness = 100,
			pattern = "Grid",
			patternColor = "#ffffff",
			patternLightness = 0,
			patternStrength = 20,
			brightness = 100,
			shadows = true,
		},
	},
}

-- ============================================================================
-- BUILD NETWORK MODULE (Engine code - do not modify)
-- ============================================================================

local Network = NetworkBuilder.build(NetworkConfig, Bolt)

-- ============================================================================
-- TYPE EXPORTS: Add type definitions for new actions and states
-- ============================================================================

-- Action Type Exports (manually defined for type safety)
export type AvatarAction = "TryOn" | "TakeOff" | "TakeOffMany" | "WearMany" | "TakeOffAll" | "Undo" | "Reset" | "WearRobloxOutfit" | "WearUserLook" | "SetSkin" | "RefreshOwn" | "SetScale" | "MoveLayer"
export type BasketAction = "Add" | "Remove" | "AddMany" | "RemoveMany" | "Clear"
export type CommunityAction = "Favourite" | "Report" | "Open" | "Moderate"
export type FavouritesAction = "Toggle"
export type NavigationAction = "View"
export type PurchaseAction = "Buy" | "Finished" | "Check"
export type OutfitsAction = "Save" | "Overwrite" | "Rename" | "Delete" | "WearAll" | "WearSelected" | "Follow" | "Share" | "ShareCreation" | "WearShared"
export type StoresAction = "Create" | "Rename" | "AddItem" | "RemoveItem" | "AddOutfit" | "RemoveOutfit" | "SetRowItems" | "AddRow" | "EditRow" | "SetRowSearch" | "RenameRow" | "RemoveRow" | "MoveRow" | "Publish" | "Unpublish" | "Delete" | "Favourite" | "Report" | "Open" | "Share" | "Moderate"
export type WorldOptionsAction = "Set" | "Reset"

-- State Type Exports (manually defined for type safety)
export type WornItem = {
	targetId: number, -- the catalogue asset / bundle id
	kind: "Asset" | "Bundle",
	typeName: string, -- AvatarAssetType / BundleType name
	name: string,
	owned: boolean?, -- known owned (it came from the player's own avatar)
}

export type AvatarState = {
	ownerId: string,
	worn: { WornItem }, -- in the order put on
	seeded: boolean, -- filled from the player's own avatar on first join
	own: { WornItem }, -- the player's own Roblox avatar's items (refreshed every join)
	skin: { [string]: string }, -- skin colours by body part ("#RRGGBB"); a part left out is the player's own
	ownSkin: { [string]: string }, -- the player's own avatar's colours, all six parts
	scale: { [string]: number }, -- body scale (BodyScale keys); one left out is the player's own
	ownScale: { [string]: number }, -- the player's own avatar's scale
	canUndo: boolean,
}

export type BasketState = {
	ownerId: string,
	items: { WornItem }, -- oldest first (`owned` is never set)
}

export type FavouritesState = {
	ownerId: string,
	items: { string }, -- "Asset:123" / "Bundle:45", most recent last
}

export type Outfit = {
	id: number,
	name: string, -- text-filtered
	items: { WornItem }, -- what was worn, in the order put on (`owned` unset)
	skin: any?, -- skin colours worn with it (by body part; SkinColours.normalise)
	scale: any?, -- body scale worn with it (BodyScale.normalise)
	code: string?, -- its share code ("7KQ2XM") while unedited since sharing
}

export type OutfitsState = {
	ownerId: string,
	outfits: { Outfit }, -- oldest first
	nextId: number,
	following: { number }, -- user ids followed here (Outfits › Following), newest first
	creationCodes: { [string]: string }, -- share codes for Roblox-saved outfits, by outfit id
	published: { string }, -- codes shared, so on Community (Mine), newest first
	communityFavourites: { string }, -- Community codes starred, newest first
	communityRecent: { string }, -- Community codes opened lately, newest first
}

export type PurchaseResult = {
	id: number, -- the client's request id
	state: "idle" | "waiting" | "done" | "cancelled" | "failed",
	reason: string, -- why nothing (or not everything) was bought
	bought: { string }, -- keys bought by this purchase
}

export type OwnershipState = {
	ownerId: string,
	owned: { string }, -- "Asset:123" / "Bundle:45", known owned
	purchase: PurchaseResult,
}

export type StoresState = {
	ownerId: string,
	mine: { string }, -- codes of the player's own stores (drafts too), newest first
	favourites: { string }, -- codes of stores starred, newest first
	visited: { [string]: number }, -- code -> day (days since 1970) last visited
}

export type WorldOptionsState = {
	ownerId: string,
	time: number, -- ClockTime, 0..24
	sky: string, -- WorldOptionsConfig.skies
	floor: string, -- hex, one of WorldOptionsConfig.floorColors
	floorLightness: number, -- percent multiplier on the floor colour
	pattern: string, -- WorldOptionsConfig.patterns
	patternColor: string, -- hex, one of WorldOptionsConfig.patternColors
	patternLightness: number, -- percent multiplier on the pattern colour
	patternStrength: number, -- percent opacity of the pattern
	brightness: number, -- percent
	shadows: boolean,
}

-- ============================================================================

return Network
