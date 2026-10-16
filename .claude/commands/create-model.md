---
description: Create a new Roblox model with AbstractModel pattern
allowed-tools: Bash(find, cat, grep), Read, Write, Edit, Glob
---

I'll guide you through creating a new Roblox model that follows this project's AbstractModel architecture.

## Project Model Architecture

- **All models extend AbstractModel**
- **Five scopes**:
  - `User`: Per-player, persistent (saved to DataStore). One instance per player. Example: BasketModel (a simple list — start here), also AvatarModel, OutfitsModel, StoresModel
  - `UserSession`: Per-player, ephemeral (never saved). One instance per player, resets each session. Example: OwnershipModel
  - `Server`: Shared, ephemeral (resets on restart). One instance for all players. No in-repo example yet (hypothetical: LeaderboardModel)
  - `UserEntity`: Per-player, persistent (saved to DataStore). Multiple instances per player. No in-repo example yet (hypothetical: PetModel)
  - `ServerEntity`: Shared, ephemeral, multiple instances. No in-repo example yet. Two variants:
    - **Predefined**: Entity IDs known at startup (hypothetical: DrawbridgeModel — gates, doors, world objects)
    - **Dynamic**: Entities created at runtime (hypothetical: AuctionLotsModel — player-created listings, spawned instances)
- **File locations**:
  - User models → `Source/ServerScriptService/models/user/`
  - UserSession models → `Source/ServerScriptService/models/userSession/`
  - Server models → `Source/ServerScriptService/models/server/`
  - UserEntity models → `Source/ServerScriptService/models/userEntities/`
  - ServerEntity models → `Source/ServerScriptService/models/serverEntities/`
- **Auto-discovery**: ModelRunner automatically discovers and initializes models (no manual registration needed)

## Reference Files

Before generating code, I will read these stable reference files to ensure accuracy:
- `Source/ServerScriptService/models/AbstractModel.luau` - Base class pattern and required methods
- `Source/ReplicatedStorage/Network.luau` - Network state structure and type exports
- `docs/MODEL_GUIDE.md` - Complete model documentation with examples and patterns

These core files contain the exact patterns, type definitions, and conventions to follow.

## Interactive Model Creation Wizard

Let's begin creating your model step by step!

### Step 1: Model Name

What should your model be named?

**Requirements**:
- Must end with "Model" (e.g., BasketModel, OutfitsModel)
- Must use PascalCase (e.g., QuestProgressModel)
- No underscores or special characters

### Step 2: Model Scope

Does this model need to be **User-scoped**, **UserSession-scoped**, **Server-scoped**, **UserEntity-scoped**, or **ServerEntity-scoped**?

- **User scope**: Per-player data that persists - one instance per player (like the basket, saved outfits, owned stores)
- **UserSession scope**: Per-player data that doesn't persist - resets each session (like ownership checks and in-flight purchases — see OwnershipModel)
- **Server scope**: Shared data that all players see - one instance for server (like leaderboards, world state)
- **UserEntity scope**: Per-player data that persists - multiple instances per player (like pets, bases, character slots)
- **ServerEntity scope**: Shared, ephemeral, multiple instances. Ask whether entities are:
  - **Predefined** — IDs known at server start (gates, drawbridges, world objects with fixed IDs)
  - **Dynamic** — created at runtime by game logic (player-created listings, spawned objects, session instances)

### Step 3: Properties

What properties does this model need?

For each property, I'll ask for:
1. **Property name** (camelCase, e.g., items, budgetLeft)
2. **Property type** (number, string, boolean, or a list/table — e.g. BasketModel's `items: { BasketItem }`)
3. **Default value** (initial value when model is created)

**Reserved names** (cannot use): ownerId, _modelName, _scope, _stateProperty

**Note for UserEntity models**: UserEntity-scoped models automatically include a `modelId` property (managed by AbstractModel). You only need to define your custom properties here.

### Step 4: Method Design

Based on the properties you've defined, I'll:
1. Suggest common methods for each property type:
   - **number**: add, spend, set operations
   - **string**: set, update operations
   - **boolean**: set, toggle operations
   - **list**: add, remove/take, clear (see BasketModel)
2. Ask if any operations need to modify multiple properties together
3. Discuss invariant validation (constraints that should always be true)

**Important**: Only model-level invariants belong here (e.g., "basket holds at most AvatarConfig.basketLimit items"). Business logic validation (e.g., "is this a real catalogue item") belongs in controllers.

### Step 5: Generation

I will:
1. ✅ Read reference files to understand the exact pattern
2. ✅ Generate complete model file following the pattern exactly
3. ✅ Read Network.luau to understand state structure
4. ✅ Add Network state definition in alphabetical order
5. ✅ Add type export after existing state types
6. ✅ Provide testing instructions

---

## Implementation Details (Internal)

When generating the model, I will:

1. **Read reference files**:
   - Use Read tool on `Source/ServerScriptService/models/AbstractModel.luau` to understand the base class API
   - Read `docs/MODEL_GUIDE.md` for complete pattern examples and conventions
   - Read `Source/ReplicatedStorage/Network.luau` to understand state structure
   - Understand: inheritance setup, type definitions, .new()/.get()/.remove() pattern
   - Note the syncState() calls in all state-modifying methods

2. **Generate model file** at correct location:
   - User scope: `Source/ServerScriptService/models/user/{ModelName}.luau`
   - UserSession scope: `Source/ServerScriptService/models/userSession/{ModelName}.luau`
   - Server scope: `Source/ServerScriptService/models/server/{ModelName}.luau`
   - UserEntity scope: `Source/ServerScriptService/models/userEntities/{ModelName}.luau`
   - ServerEntity scope: `Source/ServerScriptService/models/serverEntities/{ModelName}.luau`

2a. **For User-scoped models specifically**:
   - `.get()` must use `AbstractModel.getOrWait` (not `getOrCreate`) and return `{ModelName}?` (nullable)
   - This yields until ModelRunner finishes loading DataStore data, then returns the real instance
   - Returns `nil` if the player leaves before data loads — all callers must nil-check the result
   - Template:
     ```lua
     function {ModelName}.get(ownerId: string): {ModelName}?
         return AbstractModel.getOrWait("{ModelName}", ownerId, function()
             return {ModelName}.new(ownerId)
         end) :: {ModelName}?
     end
     ```
   - Do NOT use `getOrWait` for UserSession, Server, UserEntity, or ServerEntity scopes — those use `getOrCreate` and return non-nullable

2b. **For UserSession models specifically**:
   - Constructor takes only `ownerId: string` (no modelId)
   - Register Network state the same way as User models (model syncs to client)
   - No `loadAllForOwner` or `removeAllEntitiesForOwner` required
   - Methods call `syncState()` — syncs to owner player but skips DataStore
   - See docs/MODEL_GUIDE.md UserSession template for complete pattern

2c. **For ServerEntity models specifically**:
   - Constructor takes `entityId: string`, always passes `"SERVER"` as ownerId
   - `get(entityId)` and `remove(entityId)` use entityId (not ownerId)
   - Must implement `initAllServerEntities()` static method (required by ModelRunner)
   - **Predefined variant**: `initAllServerEntities()` creates all known entities upfront and calls `syncState()` on each
   - **Dynamic variant**: `initAllServerEntities()` is a no-op; add a `create(entityId, ...)` static factory that sets properties and calls `syncState()`; add a `syncAll()` that handles the empty-collection edge case by broadcasting `{}` via Network directly when no entities remain
   - See docs/MODEL_GUIDE.md ServerEntity templates for both patterns

3. **For UserEntity models specifically**:
   - Constructor requires `modelId` parameter: `function Model.new(ownerId: string, modelId: string)`
   - get() method requires `modelId`: `function Model.get(ownerId: string, modelId: string)`
   - remove() method requires `modelId`: `function Model.remove(ownerId: string, modelId: string)`
   - Must implement `loadAllForOwner(ownerId)` static method
   - Must implement `removeAllEntitiesForOwner(ownerId)` static method
   - See docs/MODEL_GUIDE.md UserEntity template for complete pattern

4. **Edit Network.luau**:
   - Read current file first
   - Insert state definition in States object (alphabetically)
   - Insert type export in type exports section (alphabetically)
   - Use model name without "Model" suffix for state name (e.g., BasketModel → Basket)

4. **Validation during generation**:
   - Ensure all properties initialized in .new()
   - All state-modifying methods call self:syncState()
   - Type definitions include & AbstractModel.AbstractModel
   - Proper --!strict pragma at top

---

## Let's Start!

Please provide the following information to begin:

**1. Model Name** (must end with "Model"):
