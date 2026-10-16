# Model Development Guide

This guide explains how to create Models in this Roblox MVC project.

## What is a Model?

Models represent the authoritative game state and live exclusively on the server. They are the single source of truth for all game data in your application.

## Architecture Overview

All models in this project follow an inheritance pattern based on `AbstractModel`:

- **AbstractModel**: Base class providing common functionality for all models
- **Concrete Models** (e.g., BasketModel): Extend AbstractModel and add specific game logic

## Model Scopes

Models can have different scopes that determine their lifecycle and ownership:

### User-Scoped Models (`models/user/`)

User-scoped models are **per-player** and **persistent** (saved to DataStore):

- **Lifecycle**: Created when player joins, destroyed when player leaves
- **Persistence**: Automatically saved to DataStore
- **Owner ID**: Player's UserId (e.g., "123456789")
- **Use Cases**: Saved lists, player settings, progress
- **Examples**: `BasketModel` (the items the player means to buy), `AvatarModel`, `OutfitsModel`, `StoresModel`, `FavouritesModel`, `WorldOptionsModel`

### Server-Scoped Models (`models/server/`)

Server-scoped models are **per-server instance** and **ephemeral** (not saved):

- **Lifecycle**: Created once when server starts, persists until server shutdown
- **Persistence**: None - data resets when server restarts
- **Owner ID**: Fixed string "SERVER"
- **Use Cases**: Match state, server events, shared game state
- **Example** (illustrative): an `EventModel` holding a server-wide live event's countdown — no module in this repo uses this scope yet

### UserSession-Scoped Models (`models/userSession/`)

UserSession-scoped models are **per-player** and **ephemeral** (never saved to DataStore):

- **Lifecycle**: Created when player joins, destroyed when player leaves (resets every session)
- **Persistence**: None — data is never saved to DataStore
- **Sync**: Owner player only (for UI like mana bars, ammo counters, cooldown timers)
- **Owner ID**: Player's UserId (e.g., "123456789")
- **Use Cases**: Mana, ammo, cooldowns, combo counters, session-only buffs, temporary UI state
- **Example**: `OwnershipModel` - what the player owns and how their latest purchase went; checked afresh each session because ownership can change outside the game

### UserEntity-Scoped Models (`models/userEntities/`)

UserEntity-scoped models are **per-player instances** and **persistent** (saved to DataStore):

- **Lifecycle**: Multiple instances per player, created on-demand, destroyed when player leaves
- **Persistence**: Automatically saved to DataStore with composite keys (ModelName_UserId_ModelId)
- **Owner ID**: Composite key of UserId + ModelId (e.g., "123456789_pet1")
- **Use Cases**: Pets, player-owned bases, character slots, equipment slots, squadmates
- **Example** (illustrative): a `PetsModel` - each player can have multiple pets (pet1, pet2, pet3, etc.); no module in this repo uses this scope yet
- **ID Strategy**: Application-specific - sequential numbers, UUIDs, or semantic identifiers

### ServerEntity-Scoped Models (`models/serverEntities/`)

ServerEntity-scoped models are **per-server instances** and **ephemeral** (not saved). There are two variants:

**Predefined** — entity IDs are known at server start:
- **Lifecycle**: Created once in `initAllServerEntities()` at server start, persist until shutdown
- **Persistence**: None - data resets when server restarts
- **Owner ID**: Fixed string "SERVER" with unique entityId (e.g., "SERVER_main_gate")
- **Use Cases**: Drawbridges, gates, doors, world objects with fixed IDs
- **Example** (illustrative): a `DrawbridgeModel` — entities like "main_gate", "north_drawbridge" defined upfront
- **ID Strategy**: Semantic strings (e.g., "main_gate", "north_drawbridge")

**Dynamic** — entities created at runtime by game logic:
- **Lifecycle**: `initAllServerEntities()` is a no-op; entities created via a static `create()` factory method
- **Persistence**: None - all instances lost on server restart
- **Owner ID**: Fixed string "SERVER" with a runtime-generated entityId (e.g., a UUID)
- **Use Cases**: Player-placed objects, spawned world items, runtime-created instances
- **Example** (illustrative): a `PickupsModel` — items dropped into the world during a session
- **ID Strategy**: UUIDs or other runtime-generated unique IDs

No module in this repo uses either ServerEntity variant yet.

### Choosing a Scope

| Scope | Location | Persistent | Per-Player | Multiple Instances | Sync Target | Use For |
|-------|----------|------------|------------|-------------------|-------------|---------|
| **User** | `models/user/` | ✅ Yes | ✅ Yes | ❌ One per player | Owner | Basket, outfits, avatar, settings |
| **UserSession** | `models/userSession/` | ❌ No | ✅ Yes | ❌ One per player | Owner | Ownership checks, purchase in progress, cooldowns |
| **Server** | `models/server/` | ❌ No | ❌ No | ❌ One for server | All | Match scores, timers, shared game state |
| **UserEntity** | `models/userEntities/` | ✅ Yes | ✅ Yes | ✅ Many per player | Owner | Pets, bases, character slots, equipment |
| **ServerEntity (predefined)** | `models/serverEntities/` | ❌ No | ❌ No | ✅ Many for server | All | Drawbridges, gates, doors — fixed IDs at startup |
| **ServerEntity (dynamic)** | `models/serverEntities/` | ❌ No | ❌ No | ✅ Many for server | All | Player-placed objects, spawned items — runtime IDs |

## Creating a New Model

### Step 1: Understand AbstractModel

All models inherit from `AbstractModel.luau` which provides:

- **`new(modelName: string, ownerId: string, scope: ModelScope)`**: Constructor for creating new instances with model name, owner identifier, and scope
- **`getOrCreate(modelName, ownerId, constructorFn)`**: Centralized registry management - gets existing instance or creates new one. Never yields. Used by ModelRunner and non-User scopes.
- **`getOrWait(modelName, ownerId, constructorFn) -> T?`**: Like `getOrCreate` but yields until ModelRunner calls `markLoaded` for this model+owner. Returns `nil` if the player leaves before data is loaded. **Used exclusively by User-scoped `.get()` methods.**
- **`markLoaded(modelName, ownerId)`**: Called by ModelRunner after a User-scoped model's DataStore data is applied. Resumes any threads parked in `getOrWait`.
- **`removeInstance(modelName: string, ownerId: string)`**: Centralized instance removal for cleanup
- **`syncState(skipPersistence: boolean?)`**: Syncs model state to clients via Bolt RemoteProperty and triggers DataStore persistence (User-scoped only). Automatically detects scope for filtering.
- **`ownerId: string`**: Property storing the unique identifier for the model owner
- **`_stateProperty: RemoteProperty`**: Bolt RemoteProperty for state synchronization (registered via Network.registerState())

### Step 2: Determine Model Scope

#### Decision Tree: Choosing the Right Model Scope

Use this decision tree to determine which scope your model needs:

**Question 1: Does each player need multiple instances of this data?**
- **Yes** → **UserEntity-scoped** (place in `models/userEntities/`)
  - Player has multiple pets: UserEntityModel
  - Player has multiple bases: UserEntityModel
  - Player has multiple character slots: UserEntityModel
- **No** → Continue to Question 2

**Question 2: Does each player have their own separate copy of this data?**
- **Yes** → User-scoped (continue to Question 3)
- **No** → Go to Question 4

**Question 3: Should this data persist across server restarts and player sessions?**
- **Yes** → **User-scoped** (place in `models/user/`)
- **No** → **UserSession-scoped** (place in `models/userSession/`)

**Question 4: Is this data shared across all players in the server?**
- **Yes** → Continue to Question 5
- **No** → Reconsider Question 2 - data might be per-player after all

**Question 5: Do you need multiple instances of this shared data?**
- **Yes** → **ServerEntity-scoped** (place in `models/serverEntities/`)
  - Multiple drawbridges: ServerEntity
  - Multiple gates: ServerEntity
  - Multiple world objects: ServerEntity
- **No** → **Server-scoped** (place in `models/server/`)

**Examples:**

✅ **User-scoped** (per-player, persistent):
- The basket (`BasketModel`) and saved outfits (`OutfitsModel`)
- What the player is wearing (`AvatarModel`)
- Favourite items (`FavouritesModel`) and the player's own stores (`StoresModel`)
- Player settings and preferences (`WorldOptionsModel`)
- Quest progress and achievements

✅ **UserSession-scoped** (per-player, ephemeral, resets on rejoin):
- What the player owns, as checked this session (`OwnershipModel`)
- The purchase in progress (`OwnershipModel`)
- Active cooldown timers
- Combo counters
- Session-only buffs or status effects

✅ **Server-scoped** (shared, ephemeral, single instance):
- Match timer for all players
- Current round number
- Server-wide events
- Leaderboard for current session

✅ **ServerEntity-scoped, predefined** (shared, ephemeral, fixed set of instances):
- Drawbridges ("main_gate", "north_drawbridge")
- Gates and doors with open/closed state
- World objects with known IDs at server start

✅ **ServerEntity-scoped, dynamic** (shared, ephemeral, runtime-created instances):
- Player-placed objects or dropped pickups
- Spawned world items with session lifetimes
- Any shared object whose ID is only known at runtime

❌ **Common mistakes:**
- Making the basket Server-scoped (each player needs their own!)
- Making match timer User-scoped (all players should see the same timer!)
- Expecting Server-scoped data to persist (it won't - that's by design!)

#### Scope Selection Guidelines

Before creating your model, decide which scope it needs:

- **User-Scoped**: Place in `Source/ServerScriptService/models/user/YourModel.luau` and pass `"User"` to AbstractModel
- **UserSession-Scoped**: Place in `Source/ServerScriptService/models/userSession/YourModel.luau` and pass `"UserSession"` to AbstractModel
- **Server-Scoped**: Place in `Source/ServerScriptService/models/server/YourModel.luau` and pass `"Server"` to AbstractModel
- **UserEntity-Scoped**: Place in `Source/ServerScriptService/models/userEntities/YourModel.luau` and pass `"UserEntity"` to AbstractModel
- **ServerEntity-Scoped**: Place in `Source/ServerScriptService/models/serverEntities/YourModel.luau` and pass `"ServerEntity"` to AbstractModel

### Step 3: Create Your Model File

#### For User-Scoped Models (`models/user/YourModel.luau`):

> **Note**: User-scoped `.get()` uses `getOrWait` and returns `YourModel?`. It yields until
> ModelRunner finishes loading DataStore data for this player, then returns the populated instance.
> It returns `nil` if the player leaves before loading completes. All callers must nil-check.

```lua
--!strict

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local YourModel = {}
YourModel.__index = YourModel
setmetatable(YourModel, AbstractModel)

export type YourModel = typeof(setmetatable({} :: {
	-- Define your model's properties here
	propertyName: propertyType,
}, YourModel)) & AbstractModel.AbstractModel

function YourModel.new(ownerId: string): YourModel
	local self = AbstractModel.new("YourModel", ownerId, "User") :: any
	setmetatable(self, YourModel)

	-- Initialize your properties
	self.propertyName = defaultValue

	return self :: YourModel
end

-- Returns nil if the player leaves before DataStore data is loaded.
-- Always nil-check the result at the call site.
function YourModel.get(ownerId: string): YourModel?
	return AbstractModel.getOrWait("YourModel", ownerId, function()
		return YourModel.new(ownerId)
	end) :: YourModel?
end

function YourModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("YourModel", ownerId)
end

-- Add your model's methods here
function YourModel:yourMethod(): ()
	-- Implementation
	self:syncState() -- User-scoped models automatically sync to owner
end

return YourModel
```

#### For Server-Scoped Models (`models/server/YourModel.luau`):

```lua
--!strict

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local YourModel = {}
YourModel.__index = YourModel
setmetatable(YourModel, AbstractModel)

export type YourModel = typeof(setmetatable({} :: {
	-- Define your model's properties here
	propertyName: propertyType,
}, YourModel)) & AbstractModel.AbstractModel

function YourModel.new(ownerId: string): YourModel
	local self = AbstractModel.new("YourModel", ownerId, "Server") :: any
	setmetatable(self, YourModel)

	-- Initialize your properties
	self.propertyName = defaultValue

	return self :: YourModel
end

function YourModel.get(ownerId: string): YourModel
	return AbstractModel.getOrCreate("YourModel", ownerId, function()
		return YourModel.new(ownerId)
	end) :: YourModel
end

function YourModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("YourModel", ownerId)
end

-- Add your model's methods here
function YourModel:yourMethod(): ()
	-- Implementation
	self:syncState() -- Server-scoped models automatically sync to all
end

return YourModel
```

#### For UserSession-Scoped Models (`models/userSession/YourModel.luau`):

```lua
--!strict

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local YourModel = {}
YourModel.__index = YourModel
setmetatable(YourModel, AbstractModel)

export type YourModel = typeof(setmetatable({} :: {
	-- Define your model's properties here
	propertyName: propertyType,
}, YourModel)) & AbstractModel.AbstractModel

function YourModel.new(ownerId: string): YourModel
	local self = AbstractModel.new("YourModel", ownerId, "UserSession") :: any
	setmetatable(self, YourModel)

	-- Initialize your properties
	self.propertyName = defaultValue

	return self :: YourModel
end

function YourModel.get(ownerId: string): YourModel
	return AbstractModel.getOrCreate("YourModel", ownerId, function()
		return YourModel.new(ownerId)
	end) :: YourModel
end

function YourModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("YourModel", ownerId)
end

-- Add your model's methods here
function YourModel:yourMethod(): ()
	-- Implementation
	self:syncState() -- Syncs to owner player only; never touches DataStore
end

return YourModel
```

#### For UserEntity-Scoped Models (`models/userEntities/YourModel.luau`):

```lua
--!strict

local AbstractModel = require(script.Parent.Parent.AbstractModel)
local PersistenceService = require(script.Parent.Parent.Parent.services.PersistenceService)

local YourModel = {}
YourModel.__index = YourModel
setmetatable(YourModel, AbstractModel)

export type YourModel = typeof(setmetatable({} :: {
	-- Define your model's properties here
	propertyName: propertyType,
}, YourModel)) & AbstractModel.AbstractModel

function YourModel.new(ownerId: string, modelId: string): YourModel
	-- UserEntity models require both ownerId and modelId
	-- Optional: Pass "all" as 5th parameter for broadcast sync instead of owner-only
	local self = AbstractModel.new("YourModel", ownerId, "UserEntity", modelId) :: any
	setmetatable(self, YourModel)

	-- Initialize your properties
	self.propertyName = defaultValue

	return self :: YourModel
end

function YourModel.get(ownerId: string, modelId: string): YourModel
	return AbstractModel.getOrCreate("YourModel", ownerId, function()
		return YourModel.new(ownerId, modelId)
	end, modelId) :: YourModel
end

function YourModel.remove(ownerId: string, modelId: string): ()
	AbstractModel.removeInstance("YourModel", ownerId, modelId)
end

-- REQUIRED: Static method to load all entities for a player
-- Called by ModelRunner when player joins
function YourModel.loadAllForOwner(ownerId: string): boolean
	-- Get entity IDs for this player from somewhere (e.g., UserModel, external list, etc.)
	-- For example: local entityIds = UserModel.get(ownerId).yourModelIds
	local entityIds = {"1", "2", "3"} -- Example: sequential IDs

	-- Load each entity from DataStore
	for _, entityId in entityIds do
		local success, loadedData = PersistenceService:loadModel("YourModel", ownerId, entityId)

		if not success then
			return false -- Loading failed, player will be kicked
		end

		-- Create instance
		local entity = YourModel.get(ownerId, entityId)

		-- Apply loaded data if it exists
		if loadedData then
			entity:_applyLoadedData(loadedData)
		end

		-- Sync initial state (skip persistence since we just loaded)
		entity:syncState(true)
	end

	return true
end

-- REQUIRED: Static method to remove all entities for a player
-- Called by ModelRunner when player leaves
function YourModel.removeAllEntitiesForOwner(ownerId: string): ()
	AbstractModel.removeAllEntitiesForOwner("YourModel", ownerId)
end

-- Add your model's methods here
function YourModel:yourMethod(): ()
	-- Implementation
	self:syncState() -- UserEntity models default to owner-only sync
end

-- Example: Method that broadcasts to all players (requires "all" syncScope in constructor)
-- NOTE: For User-scoped models with syncScope="all", syncState() aggregates ALL users'
-- states into { [ownerId]: State } before broadcasting. Clients receive the full
-- dictionary and must index by the local player's UserId to get their own state.
function YourModel:broadcastMethod(): ()
	-- Only works if you passed "all" as syncScope to AbstractModel.new()
	self:syncState() -- Will broadcast aggregated { [ownerId]: State } to all players
end

return YourModel
```

#### For ServerEntity-Scoped Models (`models/serverEntities/YourModel.luau`):

```lua
--!strict

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local YourModel = {}
YourModel.__index = YourModel
setmetatable(YourModel, AbstractModel)

export type YourModel = typeof(setmetatable({} :: {
	-- Define your model's properties here
	propertyName: propertyType,
}, YourModel)) & AbstractModel.AbstractModel

function YourModel.new(entityId: string): YourModel
	-- ServerEntity models always use "SERVER" as ownerId
	local self = AbstractModel.new("YourModel", "SERVER", "ServerEntity", entityId) :: any
	setmetatable(self, YourModel)

	-- Initialize your properties
	self.propertyName = defaultValue

	return self :: YourModel
end

function YourModel.get(entityId: string): YourModel
	return AbstractModel.getOrCreate("YourModel", "SERVER", function()
		return YourModel.new(entityId)
	end, entityId) :: YourModel
end

function YourModel.remove(entityId: string): ()
	AbstractModel.removeServerEntity("YourModel", entityId)
end

-- REQUIRED: Static method to initialize all server entities
-- Called by ModelRunner when server starts
function YourModel.initAllServerEntities(): ()
	-- Define all entity IDs that should exist in the world
	local entityIds = {"main_gate", "north_drawbridge", "south_door"}

	for _, entityId in entityIds do
		local entity = YourModel.get(entityId)
		entity:syncState() -- Sync initial state to all players
	end
end

-- Add your model's methods here
function YourModel:yourMethod(): ()
	-- Implementation
	self:syncState() -- ServerEntity models automatically sync to all players
end

return YourModel
```

#### For Dynamic ServerEntity-Scoped Models (`models/serverEntities/YourModel.luau`):

Use this when entity IDs are not known at server start — they are created at runtime by game logic.

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local YourModel = {}
YourModel.__index = YourModel
setmetatable(YourModel, AbstractModel)

export type YourModel = typeof(setmetatable({} :: {
	-- Define your model's properties here
	propertyName: propertyType,
}, YourModel)) & AbstractModel.AbstractModel

function YourModel.new(entityId: string): YourModel
	local self = AbstractModel.new("YourModel", "SERVER", "ServerEntity", entityId) :: any
	setmetatable(self, YourModel)

	-- Initialize your properties
	self.propertyName = defaultValue

	return self :: YourModel
end

function YourModel.get(entityId: string): YourModel
	return AbstractModel.getOrCreate("YourModel", "SERVER", function()
		return YourModel.new(entityId)
	end, entityId) :: YourModel
end

function YourModel.remove(entityId: string): ()
	AbstractModel.removeServerEntity("YourModel", entityId)
end

-- Static factory: create a fully-initialized entity and sync to all clients
function YourModel.create(entityId: string, propertyName: propertyType): YourModel
	local entity = YourModel.get(entityId)
	entity.propertyName = propertyName
	entity:syncState()
	return entity
end

-- Get all active instances
function YourModel.getAll(): { [string]: YourModel }
	return AbstractModel.getAllServerEntities("YourModel") :: any
end

-- Sync all instances to clients. Handles the empty-collection edge case:
-- when the last entity is removed, no instance exists to call syncState() on,
-- so we broadcast {} directly via Network.
function YourModel.syncAll(): ()
	local all = YourModel.getAll()
	local anyEntity = next(all)
	if anyEntity then
		all[anyEntity]:syncState()
	else
		local Network = require(ReplicatedStorage.Network)
		Network.State.Your:Set({})
	end
end

-- REQUIRED: no-op for dynamic entities — nothing to initialize at server start
function YourModel.initAllServerEntities(): ()
end

-- Add your model's methods here
function YourModel:yourMethod(): ()
	-- Implementation
	self:syncState()
end

return YourModel
```

**Key Differences:**
- Require path: `script.Parent.Parent.AbstractModel` (up two levels from `user/`, `userSession/`, `server/`, `userEntities/`, or `serverEntities/`)
- Scope parameter: `"User"`, `"UserSession"`, `"Server"`, `"UserEntity"`, or `"ServerEntity"`
- UserSession models are identical in structure to User models but never touch DataStore and reset on rejoin
- UserEntity models require `modelId` parameter in constructor and all static methods
- UserEntity models must implement `loadAllForOwner()` and `removeAllEntitiesForOwner()` static methods
- ServerEntity models always use "SERVER" as ownerId with unique entityId
- ServerEntity models must implement `initAllServerEntities()` static method (no-op for dynamic variants)
- **Predefined** ServerEntity: `initAllServerEntities()` creates all instances upfront; entity IDs are semantic strings
- **Dynamic** ServerEntity: entities created at runtime via a `create()` factory; add `syncAll()` to handle empty-collection broadcasts; entity IDs are typically UUIDs
- Access pattern: User/UserSession use player UserId, Server uses `"SERVER"`, UserEntity uses composite `ownerId_modelId`, ServerEntity uses `"SERVER"` + `entityId`
- Default sync: UserEntity models default to owner-only (like User/UserSession), can override to "all" with 5th parameter to `new()`
- ServerEntity models always sync to all players (no persistence)

### Step 3b: UserEntity ID Management Strategies

For UserEntity-scoped models, choosing an appropriate ID strategy is important. The framework doesn't prescribe a specific approach - select based on your application's needs:

#### Sequential Numeric IDs
**Pattern**: "1", "2", "3", "4", ...

**Advantages:**
- Simple and intuitive
- Natural ordering for display
- Short DataStore keys (reduces storage)
- Easy to debug

**Disadvantages:**
- Requires tracking highest ID per player
- Reusing IDs after deletion can cause confusion
- Not globally unique

**Best for:** Pets, equipment slots, save slots, bases

**Example:** `OutfitsModel` hands out outfit ids this way (inside one User-scoped model), so an outfit keeps its id when others are deleted:
```lua
-- OutfitsModel:add
local outfit = {
	id = self.nextId,
	name = name,
	items = keep(items),
	-- ...
}
self.nextId += 1
table.insert(self.outfits, outfit)
self:syncState()
```

For UserEntity IDs, keep the same counter (plus the list of live IDs) on a User-scoped model, which `loadAllForOwner()` then reads. Creating a new pet (illustrative names):
```lua
local roster = PetRosterModel.get(ownerId) -- hypothetical User-scoped model
if not roster then return end
local petId = tostring(roster.nextPetId)
roster.nextPetId += 1
table.insert(roster.petIds, petId)
roster:syncState()

local pet = PetsModel.get(ownerId, petId)
```

#### UUID/GUID Strategy
**Pattern**: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

**Advantages:**
- Guaranteed globally unique
- No collision concerns
- Can be generated client-side or server-side
- No need to track counters

**Disadvantages:**
- Long DataStore keys (36+ characters)
- Not human-readable
- No natural ordering

**Best for:** Player-created items, user-generated content, items that can be traded

**Example:**
```lua
local HttpService = game:GetService("HttpService")

-- In controller when creating new item
local itemId = HttpService:GenerateGUID(false) -- false = no curly braces
local item = ItemModel.get(ownerId, itemId)
```

#### Semantic IDs
**Pattern**: "slot1", "slot2", "main_base", "secondary_base"

**Advantages:**
- Self-documenting
- Easy to understand in logs
- Can encode meaning (e.g., "equipped_helmet")
- Good for fixed-size collections

**Disadvantages:**
- Requires predefined naming scheme
- Can become complex with dynamic content
- Length varies

**Best for:** Fixed equipment slots, preset loadouts, specific roles

**Example:**
```lua
-- Fixed equipment slots
local slots = {"helmet", "chest", "legs", "weapon"}
for _, slotName in slots do
	local equipment = EquipmentModel.get(ownerId, slotName)
end
```

#### Hybrid Approach
**Pattern**: Combine strategies (e.g., "pet_1", "pet_2" or "2024-12-09_1")

**Advantages:**
- Balances readability and uniqueness
- Can include metadata in ID
- Flexible for different use cases

**Example:**
```lua
local timestamp = os.time()
local entityId = string.format("base_%d_%d", timestamp, counter)
```

### Step 4: Key Pattern Requirements

#### Inheritance Setup

```lua
setmetatable(YourModel, AbstractModel)
```

This line establishes the inheritance chain so your model inherits from AbstractModel.

#### Type Definition

```lua
export type YourModel = typeof(setmetatable({} :: {
	-- Your properties
}, YourModel)) & AbstractModel.AbstractModel
```

The `& AbstractModel.AbstractModel` ensures proper type inheritance and eliminates type warnings.

#### Constructor Pattern

```lua
function YourModel.new(ownerId: string): YourModel
	local self = AbstractModel.new("YourModel", ownerId, "User") :: any
	setmetatable(self, YourModel)

	-- Initialize properties

	return self :: YourModel
end
```

**Important**:
- Pass the model name (e.g., `"YourModel"`) as the first parameter to `AbstractModel.new()`
- This retrieves a Bolt RemoteProperty via `Network.registerState()` for state synchronization
- **Prerequisite:** Add an entry to NetworkConfig.States in Network.luau first (NetworkBuilder auto-generates the RemoteProperty)
- State properties are accessed as `Network.State.Your` (model name without "Model" suffix)
- Pass `ownerId` as the second parameter
- Pass the scope (`"User"`, `"UserSession"`, `"Server"`, `"UserEntity"` or `"ServerEntity"`) as the third parameter
- Cast `AbstractModel.new()` to `any` to allow metatable manipulation without type errors

**Type Safety Tip:**
Define your model's state data type in Network.luau for type-safe observers:

```lua
-- In Network.luau NetworkConfig
States = {
    Your = {
        ownerId = "",
        property1 = 0,
        property2 = "",
    },
},

-- Add exported type
export type YourModelData = {
    ownerId: string,
    property1: number,
    property2: string,
}

-- Views can then use:
Network.State.Your:Observe(function(data: Network.YourModelData)
    -- Type-safe handling
end)
```

### Step 4: Implement Per-Owner Registry Pattern

All models should use the per-owner registry pattern for proper instance management:

```lua
-- Registry to store instances per owner
local instances: { [string]: YourModel } = {}

function YourModel.get(ownerId: string): YourModel
	if instances[ownerId] == nil then
		instances[ownerId] = YourModel.new(ownerId)
	end
	return instances[ownerId]
end

function YourModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("YourModel", ownerId)
end

-- Usage from a controller (User-scoped):
local playerModel = YourModel.get(tostring(player.UserId))

-- Usage from a controller (Server-scoped):
local sharedModel = YourModel.get("SERVER")
```

**Benefits:**
- Each owner (player, team, etc.) gets their own model instance
- Lazy initialization - instances created only when needed
- Proper cleanup via `remove()` prevents memory leaks
- Universal pattern works for players and other game entities

### Step 5: Syncing State Changes to Clients

Models automatically sync their state to clients using the `syncState()` method. Every model method that changes state should call `syncState()`:

```lua
function YourModel:updateProperty(newValue): ()
	self.propertyName = newValue
	self:syncState()  -- Sync to clients (scope auto-detected from model type)
end

function YourModel:updateWithoutPersistence(newValue): ()
	self.propertyName = newValue
	self:syncState(true)  -- Skip DataStore persistence (still syncs state)
end
```

#### Automatic Scope Detection

The `syncState()` method **automatically detects the appropriate broadcast scope** based on the model's scope type:

- **User-scoped models**: Automatically sync only to the owning player via `RemoteProperty:SetFor(player, state)`
  - Use for private data: basket, outfits, personal settings
  - Most common for player-specific models
  - Triggers DataStore persistence

- **Server-scoped models**: Automatically sync to all connected players via `RemoteProperty:Set(state)`
  - Use for shared data: match scores, server events, shared game state
  - Data visible to all players
  - Does not trigger persistence (Server-scoped models are ephemeral)

**Advantages of automatic scope detection:**
- ✅ No need to specify "owner" or "all" - determined by model type
- ✅ Fewer errors - can't accidentally broadcast private data to all players
- ✅ Cleaner code - single `syncState()` call for all models

#### Example: User vs Server Scoped

```lua
-- User-scoped model (BasketModel.luau): only the player sees their basket
function BasketModel:clear(): ()
	if #self.items > 0 then
		self.items = {}
		self:syncState()  -- Automatically sends only to owner + persists to DataStore
	end
end

-- Server-scoped model (illustrative EventModel): everyone sees the same countdown
function EventModel:start(endsAt: number): ()
	self.endsAt = endsAt
	self:syncState()  -- Automatically broadcasts to all players
end
```

#### How It Works

1. When `syncState()` is called, AbstractModel syncs the **entire model state** to clients via Bolt RemoteProperty
2. Bolt RemoteProperty registered via `Network.registerState()` in AbstractModel.new()
3. Client-side Views use `Network.State.ModelName:Observe()` to receive state updates
4. For User-scoped models, Bolt handles per-player filtering automatically via `SetFor(player, state)`
5. For Server-scoped models, Bolt broadcasts to all players via `Set(state)`
6. User-scoped models also trigger DataStore persistence via PersistenceService

## Examples

### Example 1: BasketModel (User-Scoped)

`Source/ServerScriptService/models/user/BasketModel.luau` is the simplest real model: the items the player means to buy, oldest first, saved across sessions.

### Features:
- One property: `items: { BasketItem }` (each `{ targetId, kind, typeName, name }`)
- `get(ownerId)` uses `getOrWait` and returns `BasketModel?` — callers nil-check
- Methods: `indexOf(targetId, kind)`, `add(items)` (skips duplicates, drops the oldest past `AvatarConfig.basketLimit`), `take(refs)`, `clear()`
- Each mutating method calls `syncState()` only when something actually changed
- Synced as `Network.State.Basket` (entry `Basket = { ownerId = "", items = {} }` in Network.luau)

```lua
-- Add the items not already in the basket. Returns the ones added.
function BasketModel:add(items: { BasketItem }): { BasketItem }
	local added = {}
	for _, item in items do
		if not self:indexOf(item.targetId, item.kind) then
			table.insert(self.items, {
				targetId = item.targetId,
				kind = item.kind,
				typeName = item.typeName,
				name = item.name,
			})
			table.insert(added, item)
		end
	end
	if #added > 0 then
		while #self.items > AvatarConfig.basketLimit do
			table.remove(self.items, 1)
		end
		self:syncState()
	end
	return added
end
```

### Usage in Production:
- `ModelRunner.server.luau` loads each player's saved data on join, applies it, syncs, then calls `markLoaded`
- `BasketController` resolves and validates items, then calls `BasketModel.get(tostring(player.UserId))` and `:add(...)`
- Views observe `Network.State.Basket`
- Cleanup happens automatically on PlayerRemoving (after pending writes are flushed)

The other User-scoped models follow the same shape with more state: `AvatarModel` (what's worn), `OutfitsModel` (saved outfits, `nextId`), `StoresModel` (codes of stores owned and starred), `FavouritesModel`, `WorldOptionsModel`.

### Example 2: OwnershipModel (UserSession-Scoped)

`Source/ServerScriptService/models/userSession/OwnershipModel.luau` holds what the player owns (as checked this session) and their latest purchase. Never saved: ownership can change outside the game, so each session checks afresh.

### Features:
- Synced: `owned: { string }` ("Asset:123" / "Bundle:45" keys), `purchase: Purchase`
- Private (underscore-prefixed, never sent): `_checked` (every key looked up, owned or not), `_pending` (the purchase in progress)
- `get(ownerId)` uses `getOrCreate`, **not** `getOrWait` — only persisted models are marked loaded, so `getOrWait` would wait forever
- Methods: `owns(key)`, `knows(key)`, `record(results)`, `startPurchase(id, items)`, `finishPurchase(id, state, reason, bought)`

```lua
-- Session models have nothing to load, so no waiting (getOrWait would wait
-- forever: only persisted models are marked loaded).
function OwnershipModel.get(ownerId: string): OwnershipModel?
	return AbstractModel.getOrCreate("OwnershipModel", ownerId, function()
		return OwnershipModel.new(ownerId)
	end) :: OwnershipModel?
end
```

### Example 3: Server-Scoped (illustrative)

> Illustrative — no module in this repo uses this scope yet (`models/server/` exists, empty, with a `.gitkeep`).

A Server-scoped model is a single instance with ownerId `"SERVER"`, created by ModelRunner at startup and broadcast to everyone:

```lua
-- models/server/EventModel.luau (hypothetical)
function EventModel.new(ownerId: string): EventModel
	local self = AbstractModel.new("EventModel", ownerId, "Server") :: any
	setmetatable(self, EventModel)
	self.endsAt = 0
	return self :: EventModel
end

-- From a controller or service: EventModel.get("SERVER"):start(os.time() + 300)
```

- Ephemeral: resets when the server restarts; no cleanup on player leave
- Needs a `States` entry in Network.luau like any other model (`Event = { ownerId = "", endsAt = 0 }`)

### Example 4: DrawbridgeModel (ServerEntity-Scoped, predefined — illustrative)

> Illustrative — no module in this repo uses this scope yet (`models/serverEntities/` exists, empty, with a `.gitkeep`).

ServerEntity-scoped models are like Server-scoped but allow multiple instances:
- `ModelRunner.server.luau` calls `initAllServerEntities()` on startup
- Each entity ID (e.g., "main_gate", "north_drawbridge") gets its own instance: `DrawbridgeModel.get("main_gate")`
- State syncs to all clients as an aggregated `{entityId -> state}` dictionary
- No cleanup on player leave (persists for server lifetime)

```lua
-- models/serverEntities/DrawbridgeModel.luau (hypothetical)
function DrawbridgeModel.new(entityId: string): DrawbridgeModel
	local self = AbstractModel.new("DrawbridgeModel", "SERVER", "ServerEntity", entityId) :: any
	setmetatable(self, DrawbridgeModel)
	self.isOpen = false
	return self :: DrawbridgeModel
end

function DrawbridgeModel.get(entityId: string): DrawbridgeModel
	return AbstractModel.getOrCreate("DrawbridgeModel", "SERVER", function()
		return DrawbridgeModel.new(entityId)
	end, entityId) :: DrawbridgeModel
end

function DrawbridgeModel.initAllServerEntities(): ()
	local entityIds = {"main_gate", "north_drawbridge", "south_door"}
	for _, entityId in entityIds do
		DrawbridgeModel.get(entityId):syncState()
	end
end

function DrawbridgeModel:toggle(): ()
	self.isOpen = not self.isOpen
	self:syncState() -- Broadcasts to all players
end
```

### Example 5: PickupsModel (ServerEntity-Scoped, dynamic — illustrative)

> Illustrative — no module in this repo uses this scope yet.

The **dynamic** variant, where entities are created at runtime rather than predefined at startup:
- `initAllServerEntities()` is a **no-op** — no entities exist at server start
- A static `create()` factory initializes all properties and syncs in one call
- `syncAll()` handles the **empty-collection edge case**: when the last entity is removed, no instance remains to call `syncState()` on, so it broadcasts `{}` directly via Network
- Entity IDs are generated at runtime (e.g., `HttpService:GenerateGUID(false)`)
- Removal: `PickupsModel.remove(entityId)` then `PickupsModel.syncAll()`; an expiry loop for this belongs in a game service (see [SERVICES_GUIDE.md](SERVICES_GUIDE.md))

```lua
-- models/serverEntities/PickupsModel.luau (hypothetical)
function PickupsModel.create(entityId: string, kind: string, position: Vector3): PickupsModel
	local pickup = PickupsModel.get(entityId)
	pickup.kind = kind
	pickup.positionX, pickup.positionY, pickup.positionZ = position.X, position.Y, position.Z
	pickup.createdTime = os.time()
	pickup:syncState()
	return pickup
end

function PickupsModel.syncAll(): ()
	local all = PickupsModel.getAll()
	local anyPickup = next(all)
	if anyPickup then
		all[anyPickup]:syncState() -- triggers aggregated broadcast for all entities
	else
		-- No pickups remain — broadcast empty state directly
		local Network = require(game:GetService("ReplicatedStorage"):WaitForChild("Network"))
		Network.State.Pickups:Set({})
	end
end

-- No-op: pickups are created dynamically, not at server start
function PickupsModel.initAllServerEntities(): ()
end
```

## File Locations

All under `Source/ServerScriptService/models/`:

- **AbstractModel**: `AbstractModel.luau`
- **ModelRunner**: `ModelRunner.server.luau`
- **User-Scoped Models**: `user/` (BasketModel, AvatarModel, OutfitsModel, StoresModel, FavouritesModel, WorldOptionsModel)
- **UserSession-Scoped Models**: `userSession/` (OwnershipModel)
- **Server-Scoped Models**: `server/` (empty, `.gitkeep`)
- **UserEntity-Scoped Models**: `userEntities/` (empty, `.gitkeep`)
- **ServerEntity-Scoped Models**: `serverEntities/` (empty, `.gitkeep`)
- **State entries**: `Source/ReplicatedStorage/Network.luau` (`NetworkConfig.States`)
- **Testing**: see Testing Your Model below

## Testing Your Model

Test in a Studio Play session, after stopping and restarting Play so it runs the latest synced source:

- **Through the game:** do the thing that changes the model (or call one of its methods with a slash command, e.g. `/basketmodel clear`; see `docs/SLASH_COMMANDS.md`), then read the replicated state on the client with `Network.State.<Name>:Get()`.
- **Persistence:** leave and rejoin, and check the Output for PersistenceService's `Loaded` / `Successfully wrote` lines for your model.
- **Pure logic:** keep list-editing helpers free of the model instance where you can, so a Server command-bar script can require and call them.

Don't call a User-scoped model's `.get()` from the command bar: it waits for that player's model to load (`getOrWait`), and the command bar's copy of the model registry never gets one.

## Best Practices

1. **Always use `--!strict`** for type safety
2. **Include the `& AbstractModel.AbstractModel`** in your type definition to avoid warnings
3. **Pass model name first** to `AbstractModel.new("YourModel", ownerId)` - this creates the RemoteEvent
4. **Cast `AbstractModel.new()` to `any`** in your constructor
5. **Use per-owner registry pattern** for player-specific or entity-specific state
6. **Use player.UserId as owner ID** for player-owned models: `tostring(player.UserId)`
7. **Implement cleanup** in player lifecycle events (PlayerRemoving)
8. **Always call `syncState()` after state changes** - scope is automatically detected from model type
9. **Think about data visibility** - User-scoped models sync only to owner, Server-scoped sync to all
10. **Use `syncState()` for debugging** during development to inspect model state
11. **Define clear types** for all properties and method parameters

## Common Patterns

### Per-Player Model with Registry

```lua
local PlayerInventory = {}
local instances: { [string]: PlayerInventory } = {}

function PlayerInventory.new(ownerId: string): PlayerInventory
	local self = AbstractModel.new("PlayerInventory", ownerId) :: any
	setmetatable(self, PlayerInventory)

	self.items = {}

	return self :: PlayerInventory
end

function PlayerInventory.get(ownerId: string): PlayerInventory
	if instances[ownerId] == nil then
		instances[ownerId] = PlayerInventory.new(ownerId)
	end
	return instances[ownerId]
end

function PlayerInventory.remove(ownerId: string): ()
	instances[ownerId] = nil
end

-- Usage in controller:
local inventory = PlayerInventory.get(tostring(player.UserId))
```

### Player Lifecycle Management

Player lifecycle is automatically handled by `ModelRunner.server.luau` in the `models/` folder. The ModelRunner:

- **Auto-discovers** all models in `models/user/`, `models/userSession/`, `models/server/`, `models/userEntities/`, and `models/serverEntities/` folders (empty folders simply contribute nothing)
- **Server-scoped models**: Initialized once on server startup with ownerId "SERVER"
- **ServerEntity-scoped models**: Initialized once on server startup via `initAllServerEntities()` method
- **User-scoped models**: Initialized when players join (PlayerAdded event)
- **UserEntity-scoped models**: Initialized when players join via `loadAllForOwner()` method
- **Loads** saved data from DataStore via PersistenceService (User-scoped and UserEntity-scoped only; kicks player if load fails)
- **Applies** loaded data to model instances (or uses defaults for new players)
- **Cleans up** User-scoped and UserEntity-scoped model instances when players leave (PlayerRemoving event)
- **Server-scoped and ServerEntity-scoped models**: Persist for server lifetime (no per-player cleanup)

```lua
--!strict

local Players = game:GetService("Players")

-- Initialize PersistenceService before any models are used
local PersistenceService = require(script.Parent.Parent.services.PersistenceService)
PersistenceService.init()

-- Auto-discover and require all models (skip Abstract)
local modelsFolder = script.Parent
local models = {}

type ModelClass = {
	get: (ownerId: string) -> any,
	remove: (ownerId: string) -> (),
}

type ModelScope = "User" | "Server" | "UserEntity" | "ServerEntity"

type ModelInfo = {
	class: ModelClass,
	name: string,
	scope: ModelScope,
}

local modelInfos: { ModelInfo } = {}

-- Helper function to discover models in a folder with a specific scope
local function discoverModelsInFolder(folder: Instance, scope: ModelScope)
	for _, moduleScript in folder:GetChildren() do
		if moduleScript:IsA("ModuleScript") and not moduleScript.Name:find("^Abstract") then
			local model = require(moduleScript) :: ModelClass
			table.insert(models, model)
			table.insert(modelInfos, {
				class = model,
				name = moduleScript.Name,
				scope = scope,
			})
			print("ModelRunner: Discovered " .. scope .. "-scoped model - " .. moduleScript.Name)
		end
	end
end

-- Discover User-scoped models
local userFolder = modelsFolder:FindFirstChild("user")
if userFolder then
	discoverModelsInFolder(userFolder, "User")
end

-- Discover Server-scoped models
local serverFolder = modelsFolder:FindFirstChild("server")
if serverFolder then
	discoverModelsInFolder(serverFolder, "Server")
end

-- Initialize Server-scoped models once (ephemeral, shared by all players)
print("ModelRunner: Initializing Server-scoped models")
for _, modelInfo in modelInfos do
	if modelInfo.scope == "Server" then
		local instance = modelInfo.class.get("SERVER")
		print("ModelRunner: Initialized Server-scoped model - " .. modelInfo.name)
	end
end

-- Handle player initialization
Players.PlayerAdded:Connect(function(player: Player)
	local ownerId = tostring(player.UserId)
	print("ModelRunner: Initializing models for player " .. player.Name)

	for _, modelInfo in modelInfos do
		-- Only initialize User-scoped models per player
		if modelInfo.scope == "User" then
			-- Load data from DataStore for this model
			local success, loadedData = PersistenceService:loadModel(modelInfo.name, ownerId)

			-- If load failed, kick the player to prevent data loss
			if not success then
				player:Kick("Roblox servers are busy right now. Please rejoin to try again. Your progress is safe!")
				return -- Stop processing this player
			end

			-- Get or create model instance for this player (with defaults)
			local instance = modelInfo.class.get(ownerId)

			-- Apply loaded data if it exists (overwrites defaults)
			if loadedData then
				instance:_applyLoadedData(loadedData)
			end

			-- Don't fire initial state here - client will request when ready
			-- This prevents race condition where RemoteEvent hasn't replicated yet
		end
	end
end)

-- Handle player cleanup
Players.PlayerRemoving:Connect(function(player: Player)
	local ownerId = tostring(player.UserId)
	print("ModelRunner: Cleaning up models for player " .. player.Name)

	-- Only remove User-scoped models (Server-scoped persist for server lifetime)
	for _, modelInfo in modelInfos do
		if modelInfo.scope == "User" then
			modelInfo.class.remove(ownerId)
		end
	end
end)
```

**Important**: You don't need to manually add your model to ModelRunner. Simply create it in the `models/user/`, `models/userSession/`, `models/server/`, `models/userEntities/`, or `models/serverEntities/` folder and it will be automatically discovered and managed.

## Working with Network State Entries

Every model needs a matching entry in `NetworkConfig.States` in `Source/ReplicatedStorage/Network.luau`. `AbstractModel.new("BasketModel", ...)` strips the `Model` suffix and calls `Network.registerState("Basket")`, which returns the Bolt RemoteProperty NetworkBuilder built from the `Basket` entry; views read it as `Network.State.Basket`. (Network.luau replaces the template's old `StateEvents` module.)

**1. Add the default state** (always include `ownerId`):

```lua
-- Network.luau, NetworkConfig.States
-- What the player means to buy (persisted; BasketModel): a list of
-- { targetId, kind, typeName, name }, oldest first.
Basket = {
	ownerId = "",
	items = {},
},
```

**2. Export a state type** for views:

```lua
export type BasketState = {
	ownerId: string,
	items: { WornItem }, -- oldest first (`owned` is never set)
}
```

**3. Observe it in a view** with `useBoltState` (Bolt's `:Observe()` fires immediately with the current value, then on every update):

```lua
local basket = useBoltState(Network.State.Basket, {
	ownerId = "",
	items = {},
})
```

### State Data Guidelines

**Include** what views display and what changes over time (`items`, `worn`, `purchase`). **Don't include** internal state clients never see — keep it on underscore-prefixed fields, like OwnershipModel's `_checked` and `_pending` — or sensitive data.

### Troubleshooting

**Problem:** Views not receiving state updates
- Check: Does the `States` key match the model name minus `Model`? (`BasketModel` → `Basket`)
- Check: Is the view observing `Network.State.<Key>` with that same key?

**Problem:** Wrong players receiving state
- Check: Is your model scope correct in `AbstractModel.new()`?
- User/UserSession/UserEntity sync only to the owner by default; Server/ServerEntity sync to everyone — this is expected

## Exercising Models from Chat

Every public model method is automatically available as an in-game slash command for staff (rank 200+ in the owning group; for a non-group game, Studio sessions or the creator) — no registration or descriptor tables needed. Name methods clearly and they show up as commands. See [SLASH_COMMANDS.md](SLASH_COMMANDS.md) for syntax, permissions and argument parsing.

## Next Steps

After creating your model:

1. **Add its state entry** to `NetworkConfig.States` in `Source/ReplicatedStorage/Network.luau` (see above)
2. **Create a Controller** (`Source/ServerScriptService/controllers/`) to handle user intents and update your model
3. **Create a View** (`Source/ReplicatedFirst/views/`) to display model state to players

See the main [README.md](../README.md) for the complete MVC architecture overview.
