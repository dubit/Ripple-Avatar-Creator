# Controller Development Guide

This guide explains how to create Controllers in this Roblox MVC project.

## What is a Controller?

Controllers handle user intents from the client, validate them, and update Models accordingly. They live exclusively on the server and act as the gatekeeper between client requests and authoritative game state.

## Architecture Overview

All controllers in this project follow an inheritance pattern based on `AbstractController`:

- **AbstractController**: Base class that registers Bolt ReliableEvents via Network module and provides inheritance infrastructure
- **Concrete Controllers** (e.g., BasketController): Extend AbstractController and implement specific business logic

## Data Flow

```
Client (View) → Bolt ReliableEvent (Intent) → Controller (Validation) → Model (State Update)
```

Controllers are responsible for:
- **Receiving** client intents via Bolt ReliableEvents
- **Validating** requests (anti-cheat, permissions, game rules)
- **Updating** models with validated data
- **Never** directly manipulating Views or client state

## Creating a New Controller

### Step 1: Understand AbstractController

All controllers inherit from `AbstractController.luau` which provides:

- **`new(controllerName: string)`**: Constructor that creates the controller and gets its Bolt ReliableEvent from Network module
- **`intentEvent: ReliableEvent`**: Bolt ReliableEvent obtained via Network.registerIntent() for client-server communication
- **`dispatchAction(actionsTable, action, player, ...)`**: Validates and executes actions from an ACTIONS table, with automatic error handling
- **Automatic analytics**: Every dispatched action is tracked as a `controller_action` GA4 event (if AnalyticsService is enabled)

**Automatic Bolt Event Registration:**
- All controller intents are eagerly registered in Network.luau at module load
- AbstractController.new() gets the pre-existing event via Network.registerIntent()
- Takes the controller name (e.g., "BasketController")
- Removes "Controller" suffix
- Returns the Bolt ReliableEvent from Network.Intent.[Name]
- Example: `BasketController` → `Network.Intent.Basket`

### Step 2: Create Your Controller File

Create a new ModuleScript in `Source/ServerScriptService/controllers/YourController.luau`:

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractController = require(script.Parent.AbstractController)
local YourModel = require(script.Parent.Parent.models.user.YourModel) -- or .server.YourModel
local Network = require(ReplicatedStorage.Network)

local YourController = {}
YourController.__index = YourController
setmetatable(YourController, AbstractController)

export type YourController = typeof(setmetatable({}, YourController)) & AbstractController.AbstractController

function YourController.new(): YourController
	local self = AbstractController.new("YourController") :: any
	setmetatable(self, YourController)

	-- Set up event listener with strongly-typed action parameter
	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: string, ...)
		-- Check permissions/anti-cheat
		if not canPlayerDoThis(player) then
			warn("Unauthorized action attempt from " .. player.Name)
			return
		end

		-- Get the model
		-- For User-scoped models: yields until DataStore data is loaded, returns nil if player left
		local model = YourModel.get(tostring(player.UserId))
		if not model then return end  -- player left before data loaded
		-- For Server-scoped models: get shared instance (non-nullable)
		-- local model = YourModel.get("SERVER")
		-- For UserEntity-scoped models: get/create per-entity instance (non-nullable)
		-- IMPORTANT: Always use .get(), never .new() - .get() ensures registry registration
		-- local entity = YourEntityModel.get(tostring(player.UserId), entityId)

		-- Use Network.Actions constants instead of magic strings
		if action == Network.Actions.YourFeature.SomeAction then
			model:performAction(...)
		elseif action == Network.Actions.YourFeature.AnotherAction then
			model:performOtherAction(...)
		end
	end)

	-- Note: AbstractController.new() automatically prints initialization message

	return self :: YourController
end

return YourController
```

### Step 3: Key Pattern Requirements

#### Inheritance Setup

```lua
setmetatable(YourController, AbstractController)
```

This establishes the inheritance chain so your controller inherits from AbstractController.

#### Type Definition

```lua
export type YourController = typeof(setmetatable({}, YourController)) & AbstractController.AbstractController
```

The `& AbstractController.AbstractController` ensures proper type inheritance and eliminates type warnings.

#### Constructor Pattern

```lua
function YourController.new(): YourController
	local self = AbstractController.new("YourController") :: any
	setmetatable(self, YourController)

	-- Set up your event listeners here

	return self :: YourController
end
```

**Important**:
- Pass your controller's name to `AbstractController.new()`
- Cast to `any` to allow metatable manipulation
- Set up event listeners using `self.intentEvent` (Bolt ReliableEvent from Network module)
- The Network.Intent.[YourController] event is already registered eagerly at module load

### Step 4: Initialize Your Controller

Controllers are automatically initialized by `ControllerRunner.server.luau` in the `controllers/` folder. The ControllerRunner uses auto-discovery to find and initialize all controllers:

```lua
--!strict

-- Auto-discover and initialize all controllers (skip Abstract)
local controllersFolder = script.Parent
local controllers = {}

for _, moduleScript in controllersFolder:GetChildren() do
	if moduleScript:IsA("ModuleScript") and not moduleScript.Name:find("^Abstract") then
		local Controller = require(moduleScript)
		Controller.new()
		table.insert(controllers, Controller)
		print("ControllerRunner: Initialized controller - " .. moduleScript.Name)
	end
end

print("ControllerRunner: All " .. #controllers .. " controller(s) initialized")
```

**Important**: You don't need to manually add your controller to ControllerRunner. Simply create it in the `controllers/` folder and it will be automatically discovered and initialized.

## Example: BasketController

`Source/ServerScriptService/controllers/BasketController.luau` is a small, complete controller:

### Features:
- Extends AbstractController
- Handles five actions through an ACTIONS table: `Add`, `Remove`, `AddMany`, `RemoveMany`, `Clear`
- Shape-checks every item the client sends (`refOf`: a positive integer `targetId`, `kind` of `"Asset"` or `"Bundle"`), then looks it up server-side (`AvatarService.resolve`) so a client can't put made-up items or names in the basket
- Caps list sizes (`AvatarConfig.maxWearMany`) and rate-limits each player (`AvatarConfig.basketBudget` requests per window; over budget, requests are dropped)
- Updates BasketModel (User scope) with the validated items

Other real controllers worth reading: `StoresController` (budgeted edits, and a Bolt RemoteFunction that answers `{ ok, error }` so the UI can say why a request failed), `PurchaseController` (MarketplaceService bulk purchases, one at a time per player), `WorldOptionsController` (clamping and snapping numeric settings to config).

### Bolt ReliableEvent Used:
- Name: `Network.Intent.Basket`
- Registered eagerly in Network.luau at module load
- Accessed via `Network.registerIntent()` in AbstractController

### Event Signature:
```lua
Network.Intent.Basket:FireServer(action: Network.BasketAction, raw: any)
-- e.g. Network.Intent.Basket:FireServer(Network.Actions.Basket.Add, { targetId = 123, kind = "Asset" })
```

### Testing:
Client-side code can immediately use the Bolt event:
- Network.Intent.Basket is available as soon as Network module loads
- No need to wait for event creation - it's eagerly registered
- Fire requests with proper parameters
- Test different actions

## File Locations

- **AbstractController**: `Source/ServerScriptService/controllers/AbstractController.luau`
- **Your Controllers**: `Source/ServerScriptService/controllers/YourController.luau`
- **Controller Initialization**: `Source/ServerScriptService/controllers/ControllerRunner.server.luau`
- **Network Module**: `Source/ReplicatedStorage/Network.luau` (Bolt events eagerly registered here)

## Client-Side Usage

From a LocalScript (View), fire intents to your controller using Network module:

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Import Network module (contains all Bolt events)
local Network = require(ReplicatedStorage:WaitForChild("Network"))

-- Use the pre-registered Bolt ReliableEvent
-- No need to wait - it's already available!
Network.Intent.YourController:FireServer(Network.Actions.YourFeature.ActionName, arg1, arg2)
```

## Best Practices

### 1. Intent-Based Naming

Use intent-based names that describe what the player is **trying** to do, not commands:

✅ **Good**: `RequestPurchase`, `AttemptEquip`, `TryCollect`
❌ **Bad**: `SetBasketItems`, `UpdatePoints`, `ChangeWeapon`

### 2. Always Validate

**NEVER** trust the client. Always validate:

```lua
-- Validate action (use Network.Actions constants)
if action ~= Network.Actions.YourFeature.ValidAction1 and action ~= Network.Actions.YourFeature.ValidAction2 then
	warn("Invalid action: " .. tostring(action))
	return
end

-- Validate parameters
if type(amount) ~= "number" or amount <= 0 then
	warn("Invalid amount: " .. tostring(amount))
	return
end

-- Validate permissions
if not canPlayerAfford(player, cost) then
	warn("Player cannot afford this")
	return
end
```

### 3. Server Authority

Controllers enforce server authority:

```lua
-- ❌ DON'T: Save what the client sent (it could carry any name, type or price)
model:add({ raw })

-- ✅ DO: Shape-check it, then build the record from server-side data
-- (BasketController's add: refOf checks the shape, resolveAll looks each
-- item up with AvatarService.resolve and keeps only real catalogue items)
local ref = refOf(raw)
if ref then
	model:add(resolveAll(model, { ref }))
end
```

### 4. Error Handling Philosophy

Follow the "fail fast" philosophy:

**Use `error()`** for configuration issues:
```lua
if not self.intentEvent then
	error("Bolt ReliableEvent not registered for " .. controllerName)
end
```

**Use `warn()` and `return`** for runtime validation failures:
```lua
if not isValid then
	warn("Invalid request from " .. player.Name)
	return
end
```

### 5. Type Safety

Always use `--!strict` and type all parameters with the most specific types available:

```lua
-- Type the action parameter (Network.Actions provides constants)
self.intentEvent.OnServerEvent:Connect(function(player: Player, action: string, amount: number)
	-- Use Network.Actions constants for validation
	-- Runtime validation via ACTIONS table ensures security
end)
```

### 6. Action Patterns

Use action-based patterns for multiple operations with Network.Actions constants:

```lua
-- Use Network.Actions constants instead of magic strings
-- (illustrative if/else form; WorldOptionsController does this via an ACTIONS table)
if action == Network.Actions.WorldOptions.Set then
	model:apply(validate(raw))
elseif action == Network.Actions.WorldOptions.Reset then
	model:reset()
else
	warn("Unknown action: " .. tostring(action))
end
```

## CRITICAL: Parameter Order and Alignment

### Parameter Order Rule

**Action handlers receive exactly the arguments that follow the first `player` in the `dispatchAction` call.** AbstractController.dispatchAction is:

```lua
function AbstractController:dispatchAction(actionsTable, action, player, ...)
    local actionFunc = actionsTable[action]
    -- (warns and returns if action isn't a key)
    actionFunc(...)  -- passes everything AFTER player
end
```

The repo's convention is **player first, then the model, then the client's payload**. BasketController:

```lua
local function add(player: Player, model: any, raw: any) ... end
local function clear(player: Player, model: any, _raw: any) ... end

self:dispatchAction(ACTIONS, action, player, player, model, raw)
                                     ^       ^^^^^^^^^^^^^^^^^^
                                     |        These become ...
                                 For validation   Passed to action handler
                                 and analytics
```

The variadic `...` is `player, model, raw` - so every handler receives these in that order. A controller whose handlers don't need the player can leave it out of `...` (WorldOptionsController: `set(model, raw)`, dispatched with `self:dispatchAction(ACTIONS, action, player, model, raw)`).

### Parameter Alignment Rule

**ALL action handlers in a controller MUST accept the SAME parameters in the SAME positions.** One `dispatchAction` call serves every action, so a handler can't get a different argument list from its neighbours.

Extra trailing arguments are harmless in Luau (a handler that declares fewer parameters just ignores them), so the union of everything any action needs goes on the end. AvatarController passes an `extra` that only some actions use:

```lua
local function tryOn(player: Player, model: any, raw: any) ... end                    -- ignores extra
local function moveLayer(player: Player, model: any, raw: any, direction: any) ... end -- uses it

self:dispatchAction(ACTIONS, action, player, player, model, raw, extra)
```

❌ **WRONG** (a handler with its parameters in a different order):
```lua
-- Every other handler is (player, model, raw); this one isn't
local function clear(model: any, player: Player)
    model:clear()  -- model is actually the Player here: runtime error
end

self:dispatchAction(ACTIONS, action, player, player, model, raw)
```

✅ **CORRECT** (same positions; unused ones are prefixed `_`):
```lua
local function clear(player: Player, model: any, _raw: any)
    trackAll(player, "basket_remove", model.items)
    model:clear()
end
```

### Quick Reference

**Action Handler Signature Pattern:**
```lua
local function actionName(
    player: Player,   -- first (the repo's convention)
    model: any,       -- the model(s) the controller fetched
    raw: any,         -- the client's payload (validate it!)
    extra: any        -- optional trailing args only some actions use
)
```

**dispatchAction Call Pattern:**
```lua
self:dispatchAction(
    ACTIONS,          -- Action lookup table
    action,           -- Action string (from Network.Actions)
    player,           -- For validation warnings + analytics in dispatchAction
    player,           -- Handler args start here
    model,
    raw,
    extra
)
```

**Remember:**
1. Handlers receive everything after the first `player`
2. All action handlers take the SAME parameters in the SAME positions
3. Player usually appears TWICE in the dispatchAction call (once for dispatch, once for handlers)
4. Unused parameters are okay (prefix them `_`) - alignment is critical

### The `executeAction` method

Every controller in the repo puts its per-request work (rate limit, fetch the model, dispatch) in a `Controller:executeAction(player, action, ...)` method, and `OnServerEvent` just calls it. `SlashCommandService` calls the same method for slash commands, so keep that shape:

```lua
function BasketController:executeAction(player: Player, action: Network.BasketAction, raw: any)
	if not allowed(player) then
		return
	end
	local model = BasketModel.get(tostring(player.UserId))
	if not model then
		return
	end
	self:dispatchAction(ACTIONS, action, player, player, model, raw)
end
```

## Common Patterns

### Decision Tree: Choosing Controller Action Pattern

Use this decision tree to determine which pattern to use for your controller:

**Question: How many distinct actions will this controller handle?**

- **1 action** → **Single Action Controller** (no action parameter needed)
- **2-3 actions** → **Either pattern works** (if/else is simpler for small numbers)
- **4+ actions** → **Lookup Table pattern** (more maintainable, easier to extend)

**Benefits of each approach:**

✅ **Single Action Controller** (no action parameter):
- Simplest pattern for controllers with one responsibility
- No action validation needed
- Clear and straightforward

✅ **if/else pattern** (2-3 actions):
- Simple to understand and write
- Good for small number of related actions
- Linear control flow is easy to follow

✅ **Lookup Table pattern** (4+ actions, RECOMMENDED):
- More scalable - easy to add new actions
- Better separation of concerns (functions are modular)
- Consistent organization across controllers
- AbstractController's `dispatchAction` handles validation
- Easier to test individual actions
- Better for code reviews

**Examples (real controllers in this repo):**

**Single action:**
- FavouritesController → `Toggle` only (still dispatched through a one-entry ACTIONS table, so it gets validation and analytics for free)

**2-3 actions:**
- WorldOptionsController → `Set`, `Reset` (2 actions)
- PurchaseController → `Buy`, `Finished`, `Check` (3 actions)

**4+ actions (use lookup table):**
- BasketController → `Add`, `Remove`, `AddMany`, `RemoveMany`, `Clear` (5 actions)
- AvatarController (13 actions), StoresController (21 actions)

Every controller in the repo uses the lookup table pattern, whatever its size; the other two patterns below are illustrative.

### Single Action Controller

For controllers with one primary action (illustrative — `YourModel` and `performAction` are hypothetical):

```lua
function YourController.new(): YourController
	local self = AbstractController.new("YourController") :: any
	setmetatable(self, YourController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, raw: any)
		-- Validate raw, then process
		local model = YourModel.get(tostring(player.UserId))
		if not model then return end
		model:performAction(raw)
	end)

	return self :: YourController
end
```

### Multi-Action Controller (if/else pattern)

For controllers handling a few related actions (illustrative — `EquipmentController` and its model are hypothetical):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage.Network)

function EquipmentController.new(): EquipmentController
	local self = AbstractController.new("EquipmentController") :: any
	setmetatable(self, EquipmentController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: string, raw: any)
		local equipment = EquipmentModel.get(tostring(player.UserId))
		if not equipment then return end

		-- Use Network.Actions constants
		if action == Network.Actions.Equipment.Equip then
			equipment:equip(raw)
		elseif action == Network.Actions.Equipment.Unequip then
			equipment:unequip(raw)
		else
			warn("Unknown action: " .. tostring(action))
		end
	end)

	return self :: EquipmentController
end
```

### Multi-Action Controller (lookup table pattern - RECOMMENDED)

For better scalability and maintainability, use named functions with a lookup table and Network.Actions constants. From `BasketController.luau` (trimmed — the full file adds the `refOf` / `resolveAll` validation helpers, the `allowed` rate limit and analytics):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbstractController = require(script.Parent.AbstractController)
local BasketModel = require(script.Parent.Parent.models.user.BasketModel)
local Network = require(ReplicatedStorage.Network)

-- Define action functions at module level: (player, model, raw)
local function add(player: Player, model: any, raw: any)
	local ref = refOf(raw)
	if ref then
		trackAll(player, "basket_add", model:add(resolveAll(model, { ref })))
	end
end

local function clear(player: Player, model: any, _raw: any)
	trackAll(player, "basket_remove", model.items)
	model:clear()
end

-- Map Network.Actions constants to functions
local ACTIONS = {
	[Network.Actions.Basket.Add] = add,
	[Network.Actions.Basket.Remove] = remove,
	[Network.Actions.Basket.AddMany] = addMany,
	[Network.Actions.Basket.RemoveMany] = removeMany,
	[Network.Actions.Basket.Clear] = clear,
}

function BasketController:executeAction(player: Player, action: Network.BasketAction, raw: any)
	if not allowed(player) then
		return
	end
	local model = BasketModel.get(tostring(player.UserId))
	if not model then
		return
	end
	-- Dispatch action (AbstractController handles validation and execution)
	self:dispatchAction(ACTIONS, action, player, player, model, raw)
end

function BasketController.new(): BasketController
	local self = AbstractController.new("BasketController") :: any
	setmetatable(self, BasketController)

	self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.BasketAction, raw: any)
		self:executeAction(player, action, raw)
	end)

	return self :: BasketController
end
```

**Benefits of named function + lookup table + Network.Actions pattern:**
- Easy to add new actions - define the function and add it to the table
- Each action is a named, reusable function (better for testing and debugging)
- Clean separation between validation and business logic
- Very readable event handler
- Consistent code organization across controllers
- AbstractController's `dispatchAction` method handles action validation automatically
- **Type-safe action strings** - no magic strings, prevents typos
- **Single source of truth** - all actions defined in Network module

### Anti-Cheat Integration

Add anti-cheat checks in your validation:

```lua
self.intentEvent.OnServerEvent:Connect(function(player: Player, action: string, targetPosition: Vector3)
	-- Distance check
	local character = player.Character
	if not character then return end

	local distance = (character.HumanoidRootPart.Position - targetPosition).Magnitude
	if distance > MAX_INTERACTION_DISTANCE then
		warn("Player too far from target: " .. player.Name)
		return
	end

	-- Rate limiting
	local lastAction = lastActionTime[player.UserId] or 0
	if tick() - lastAction < COOLDOWN_TIME then
		warn("Action cooldown active for: " .. player.Name)
		return
	end
	lastActionTime[player.UserId] = tick()

	-- Process valid action
	local model = YourModel.get(tostring(player.UserId))
	model:performAction(player, targetPosition)
end)
```

## Testing Your Controller

Test in a Studio Play session (stop and start Play after each edit, since Play runs the source synced when it started):

- **Drive it for real:** use the UI that sends the intent, or a slash command (`/basketcontroller Clear`; see `docs/SLASH_COMMANDS.md`), then read the model's state from the client with `Network.State.<Name>:Get()`.
- **Test pure logic on the server:** keep validation and list-editing in plain functions (as `StoresService.setRowItems` and `BasketController`'s `refOf` are) so a Server-side command-bar script can `require` the module and call them with made-up input.
- **Watch the Output** for the controller's warnings and the `controller_action` analytics events (with `AnalyticsConfig.debug = true`).

Firing an intent from the command bar doesn't reach the real controller: command-bar `require`s get their own copies of `Network` and Bolt.

## Adding New Controllers

1. **Create** `YourController.luau` in `Source/ServerScriptService/controllers/`
2. **Extend** AbstractController using the pattern above
3. **That's it!** ControllerRunner will automatically discover and initialize your controller
4. **Test** it in Play (see Testing Your Controller)

**Note**: Controllers are auto-discovered by ControllerRunner. Any ModuleScript in the `controllers/` folder (except those starting with "Abstract") will be automatically required and initialized.

## Relationship to Models and Views

### Controllers → Models
- Controllers **update** models
- Controllers may **read** a model to validate (e.g. `BasketController` checks `model:indexOf`), but only the model changes its own state
- Models handle their own state and broadcasting

### Model Scopes

Controllers interact with these model scopes (see AbstractModel's `ModelScope`). Only User and UserSession models exist in the repo today; the Server and UserEntity samples below are illustrative.

**1. User-Scoped Models** (`models/user/`)
- One instance per player (e.g., BasketModel, AvatarModel, OutfitsModel, StoresModel)
- Identified by `ownerId` (player.UserId as string)
- Data persists per player
- `.get()` returns `T?` (nullable) — yields until DataStore data is loaded, returns `nil` if player leaves first

```lua
-- Always nil-check: returns nil if player left before their data finished loading
local model = BasketModel.get(tostring(player.UserId))
if not model then
	return
end
```

**2. UserSession-Scoped Models** (`models/userSession/`)
- One instance per player, **not** saved (e.g., OwnershipModel: what the player owns and their latest purchase, checked afresh each session)
- Fetched the same way: `OwnershipModel.get(tostring(player.UserId))` (PurchaseController nil-checks it too)

**3. Server-Scoped Models** (`models/server/`)
- Single shared instance for all players (none in the repo yet; e.g. a hypothetical LeaderboardModel)
- Identified by `"SERVER"` constant
- Data shared across all players

```lua
-- Illustrative: LeaderboardModel is hypothetical
local leaderboard = LeaderboardModel.get("SERVER")
```

**4. UserEntity-Scoped Models** (`models/userEntities/`)
- Multiple instances per player (none in the repo yet; e.g. a hypothetical PetsModel)
- Identified by BOTH `ownerId` AND `modelId`
- Used for collections of player-owned entities

```lua
-- Illustrative: PetsModel is hypothetical
-- IMPORTANT: Always use .get(), never .new()
-- .get() ensures registry registration for proper state sync
local pet = PetsModel.get(tostring(player.UserId), petId)
```

**⚠️ Critical: UserEntity `.get()` vs `.new()`**

When creating new UserEntity instances, **always use `.get()`**:
- `.get()` registers the instance in AbstractModel's registry
- `.new()` creates an orphan instance not tracked by the registry
- State sync (`syncState()`) only finds registered instances
- Using `.new()` will cause state to not sync to clients

```lua
-- ❌ WRONG: Creates orphan instance, won't sync
local pet = PetsModel.new(ownerId, petId)

-- ✅ CORRECT: Registers instance, syncs properly
local pet = PetsModel.get(ownerId, petId)
```

### Controllers ← Views
- Views **send intents** to controllers via RemoteEvents
- Views **never directly** call controller methods
- Communication is always through RemoteEvents

### Complete Flow Example

```
1. Player taps "Add to basket" on an item page (View)
2. View fires intent: Network.Intent.Basket:FireServer(Network.Actions.Basket.Add, { targetId = 123, kind = "Asset" })
3. BasketController checks the budget and the payload's shape, then looks the item up (AvatarService.resolve)
4. Controller updates BasketModel: model:add(items)
5. Model updates its state and syncs it to the owning client (Network.State.Basket)
6. Views receive the new state (useBoltState) and update UI
```

### Shared Constants (Network.Actions)

All intent action strings are centralized in `Network.luau`:

**In Views (Client):**
```lua
local Network = require(ReplicatedStorage:WaitForChild("Network"))
Network.Intent.Basket:FireServer(Network.Actions.Basket.Add, { targetId = 123, kind = "Asset" })
```

**In Controllers (Server):**
```lua
local Network = require(ReplicatedStorage.Network)

-- Use Network.Actions constants for validation
local ACTIONS = {
	[Network.Actions.Basket.Add] = add,
	[Network.Actions.Basket.Remove] = remove,
}

-- Type the action parameter
self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.BasketAction, raw: any)
	-- Runtime validation via ACTIONS table ensures security
end)
```

**Action Constants:**
Network.Actions provides constants for each feature (generated from `NetworkConfig.Controllers`):
```lua
Network.Actions.Basket.Add = "Add"
Network.Actions.Basket.Clear = "Clear"
Network.Actions.Purchase.Buy = "Buy"
Network.Actions.WorldOptions.Reset = "Reset"
```

**Benefits:**
- **No magic strings** - centralized constants prevent typos
- **Runtime security** - ACTIONS table lookup validates client input
- **Easy refactoring** - change in one place, affects both views and controllers
- **Self-documenting code** - developers can see valid actions from constants
- **Single source of truth** - all networking in Network module
- **Type-safe at runtime** - invalid actions rejected by dispatch logic

## Working with Network.Actions

When creating a new controller, you need to add action constants to the Network module for consistent communication between views and controllers.

### What is Network.Actions?

Network.Actions is part of the centralized Network module (`Source/ReplicatedStorage/Network.luau`) that provides:
- **Action constants** - Single source of truth for all user intent strings
- **Intent events** - Bolt ReliableEvents for client-server communication
- **State synchronization** - Bolt RemoteProperties for model state
- **Complete networking** - All game networking in one module
- **NetworkBuilder** - Engine module that auto-generates networking infrastructure from NetworkConfig

### When to Add New Actions

Add new actions to Network.Actions when:
- ✅ You create a new controller that handles user intents
- ✅ You're adding new functionality to an existing controller
- ✅ A view needs to send a new type of user intent to the server

### Step-by-Step: Adding New Actions

**1. Open `Source/ReplicatedStorage/Network.luau`**

**2. Add entry to NetworkConfig.Controllers:**

NetworkBuilder will automatically generate the Intent event and Actions table:

```lua
-- In the NetworkConfig table
local NetworkConfig = {
    Controllers = {
        YourFeature = { "ActionName", "AnotherAction" },
        -- ... other controllers
    },
}
```

**3. Add exported action type (optional, for type safety):**

```lua
export type YourFeatureAction = "ActionName" | "AnotherAction"
```

**4. That's it!**

NetworkBuilder automatically generates:
- `Network.Intent.YourFeature` - Bolt ReliableEvent for client-server communication
- `Network.Actions.YourFeature` - Action constants table for type-safe validation

Both are immediately available throughout your codebase.

### Action Naming Conventions

Actions should describe **what the user wants to do** (their intent), not what will happen (commands).

✅ **Good action names** (intent-focused, verb-based):
- `PurchaseWeapon` - User wants to buy a weapon
- `EquipItem` - User wants to equip an item
- `TryOn` - User wants to try an item on (Avatar)
- `Buy` - User wants to buy what's in their basket (Purchase)
- `Follow` - User wants to follow a creator's outfits (Outfits)
- `Publish` - User wants to publish their store (Stores)

❌ **Bad action names** (command-like or too vague):
- `SetBasketItems` - Sounds like a command, not an intent
- `Update` - Too vague, update what?
- `Click` - Describes UI interaction, not intent
- `Execute` - Generic and unclear
- `Process` - Implementation detail, not user intent
- `Handle` - Developer jargon, not user-facing

### Example: The Basket Actions

**In `Network.luau`** (NetworkConfig entry plus the exported type):

```lua
local NetworkConfig = {
	Controllers = {
		Basket = { "Add", "Remove", "AddMany", "RemoveMany", "Clear" },
		-- ... other controllers ...
	},
}

export type BasketAction = "Add" | "Remove" | "AddMany" | "RemoveMany" | "Clear"
```

**In the Controller** (`BasketController.luau`):

```lua
local Network = require(ReplicatedStorage.Network)

-- Map Network.Actions constants to handler functions
local ACTIONS = {
	[Network.Actions.Basket.Add] = add,
	[Network.Actions.Basket.Remove] = remove,
	[Network.Actions.Basket.AddMany] = addMany,
	[Network.Actions.Basket.RemoveMany] = removeMany,
	[Network.Actions.Basket.Clear] = clear,
}

-- Use typed action parameter
self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.BasketAction, raw: any)
	self:executeAction(player, action, raw) -- validates, then dispatchAction
end)
```

**In the View** (`screens/usePlaceholderLook.luau`):

```lua
local Network = require(ReplicatedStorage:WaitForChild("Network"))

Network.Intent.Basket:FireServer(Network.Actions.Basket.Clear)
```

### Multiple Actions in One Feature

Group related actions under one feature, one controller. StoresController handles 21 (`Create`, `Rename`, `AddItem`, ..., `Moderate`) through one ACTIONS table, and wraps the ones that write to DataStores in a shared budget:

```lua
local ACTIONS: { [string]: (Player, any, any, ...any) -> Result } = {
	[Network.Actions.Stores.Create] = budgeted(create),
	[Network.Actions.Stores.Rename] = budgeted(rename),
	-- ...
	[Network.Actions.Stores.Favourite] = favourite,
	[Network.Actions.Stores.Report] = report,
}
```

### Single Action Feature

For controllers with only one action, you still benefit from the pattern:

```lua
-- Network.luau
Favourites = { "Toggle" },

export type FavouritesAction = "Toggle"
```

This provides:
- Consistent pattern across all controllers
- Easy to add more actions later
- Type safety even for single actions
- Self-documenting code

### Updating Existing Actions

**Adding a new action to existing feature:**

```lua
-- Before
WorldOptions = { "Set", "Reset" },
export type WorldOptionsAction = "Set" | "Reset"

-- After (adding a hypothetical Randomise)
WorldOptions = { "Set", "Reset", "Randomise" },
export type WorldOptionsAction = "Set" | "Reset" | "Randomise"  -- Update type
```

**Then update controller:**

1. Add handler function
2. Add to ACTIONS table
3. Update OnServerEvent type annotation (already covered by union type)

### Type Safety Benefits

The `export type` unions give you checking wherever you annotate with them:

```lua
-- ✓ Correct
local action: Network.BasketAction = "Add"

-- ✗ Type error - "Hack" is not a BasketAction
local action: Network.BasketAction = "Hack"
```

`Network.Actions.*` itself is generated at runtime by NetworkBuilder, so a typo like `Network.Actions.Basket.Ad` is **not** caught by the type checker — it evaluates to `nil`, and the server's ACTIONS lookup rejects it with an "Invalid action" warning. Copy constants carefully, and keep the exported type in step with NetworkConfig.

**Refactoring safety:**
```lua
-- Rename an action in NetworkConfig and its exported type;
-- code annotated with the type shows errors where the old string is used
```

### Troubleshooting

**Problem:** Type errors in controller OnServerEvent
- Check: Did you export the type from Network.luau?
- Fix: Add `export type YourFeatureAction = "Action1" | "Action2"`

**Problem:** Action not in ACTIONS table at runtime ("Invalid action received from ...")
- Check: Did you map the Network.Actions constant to a function?
- Fix: `[Network.Actions.Feature.Action] = handlerFunction`

**Problem:** View sending wrong action string
- Check: Are you using Network.Actions constants, not magic strings?
- Fix: Use `Network.Actions.Feature.Action` instead of `"Action"`

**Problem:** New action is `nil` on the client
- Check: Did you add it to `NetworkConfig.Controllers` (not just the exported type)?
- Fix: Update both `YourFeature = { ..., "NewAction" }` AND `export type YourFeatureAction = "..." | "NewAction"`

### Benefits Summary

✅ **Type Safety** - Typed `action` parameters catch mismatches at compile-time
✅ **Single Source of Truth** - Action strings defined once in NetworkConfig, used everywhere
✅ **Refactoring Safety** - Change once, type errors guide you to annotated usages
✅ **Self-Documenting** - Types show valid actions at a glance
✅ **Consistent Pattern** - All controllers use the same approach

### Understanding Type Safety: Compile-Time vs Runtime

It's important to understand the distinction between compile-time type checking and runtime behavior.

#### What Happens at Compile-Time

When you write code with type annotations:

```lua
self.intentEvent.OnServerEvent:Connect(function(player: Player, action: Network.BasketAction, raw: any)
    -- Luau's type checker validates your code
end)
```

**Compile-time benefits:**
- Luau validates that `action` is used consistently with the `BasketAction` type
- Type errors are caught during development, not in production

**What types DON'T do:**
- They don't prevent clients from sending arbitrary data
- They don't exist at runtime (type erasure)
- They don't validate network input

#### What Happens at Runtime

When a client fires an intent:

```lua
-- Client sends:
Network.Intent.Basket:FireServer("Add", { targetId = 123, kind = "Asset" })

-- Server receives:
function(player, action, raw)
    -- action is just a string, raw is any value - could be anything!
end
```

**Runtime reality:**
- All type annotations are erased - `action: Network.BasketAction` becomes just `action`
- A malicious client could send `"HackAction"`, or a `raw` that isn't a table at all
- **No automatic validation happens from the type system**

#### Where Real Validation Happens

The ACTIONS table pattern validates the action:

```lua
-- In AbstractController.dispatchAction:
local actionFunc = actionsTable[action]
if not actionFunc then
    warn("Invalid action received from " .. player.Name .. ": " .. tostring(action))
    return
end
```

**This table lookup is your actual security for the action:**
- If `action` isn't a key in the table, `actionFunc` is `nil`
- Only actions you explicitly defined in ACTIONS can execute

The payload needs its own checks in each handler (BasketController's `refOf`: is `raw` a table, is `targetId` a positive integer, is `kind` `"Asset"` or `"Bundle"`).

#### Two-Layer Defense Strategy

**Layer 1: Compile-Time Types (Developer Safety)**
- Catches mistakes during development
- Prevents internal bugs in your own code
- Makes refactoring safer

**Layer 2: Runtime Validation (Security)**
- ACTIONS table lookup rejects invalid actions
- Payload validation (shape checks, server-side lookups, size caps, rate limits)
- Protects against malicious clients

#### Key Takeaway

**Types guide honest developers to write correct code. Runtime validation protects against malicious actors.**

Don't rely on types alone for security - always validate untrusted input at runtime.

## Automatic Analytics Tracking

When AnalyticsService is enabled, **every controller action is automatically tracked** in GA4. No code needed — AbstractController calls `AnalyticsService:trackControllerAction()` after each successful `dispatchAction()`.

Each action generates a `controller_action` event with:
- `controller_name` — e.g., "BasketController"
- `action_name` — e.g., "Add"

This means every new controller you create automatically gets analytics coverage. You can see action frequency, popular features, and per-user behaviour in GA4 reports.

For custom analytics beyond action tracking, call `AnalyticsService:trackEvent()` directly in your action handlers.

## Next Steps

After creating your controller:

1. **Create a Model** (`Source/ServerScriptService/models/`) to store the game state your controller modifies
2. **Create a View** (`Source/ReplicatedFirst/views/`) to display state and send intents to your controller
3. **Test the flow** end-to-end with both server and client scripts

See the main [README.md](../README.md) for the complete MVC architecture overview.
