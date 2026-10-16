# Services Guide

Services are server-side modules that run automatically to handle background tasks, scheduled operations, and system-wide functionality. Unlike controllers (which respond to user intents), services operate independently to maintain game state.

## What Are Services?

Services are "controllers that run automatically" - they don't wait for user input but instead:
- Run background loops to check/update state periodically
- Listen to system events (player join/leave, game lifecycle)
- Provide shared utilities for other server components

## Services vs Controllers

| Aspect | Services | Controllers |
|--------|----------|-------------|
| **Trigger** | Automatic (loops, events) | User intent (Bolt ReliableEvent) |
| **Purpose** | Background tasks, system operations | Handle user actions |
| **Initialization** | Auto-discovered by ServiceRunner (game/) or explicit (framework/) | Auto-discovered by ControllerRunner |
| **Player-specific** | Usually system-wide | Usually per-player |
| **Examples** | PersistenceService, CommunityService | BasketController, StoresController |

## Service Categories

Services are organized into two folders based on initialization requirements:

### Framework Services (`services/framework/`)
Services that require explicit ordering or are dependencies for other systems:
- **PersistenceService** - Must initialize before any model is used
- **AnalyticsService** - GA4 event tracking and batching (initializes after PersistenceService)
- **SlashCommandService** - Must initialize after models are discovered

Framework services are initialized explicitly by ServiceRunner in a specific order.

### Game Services (`services/game/`)
Services that just need to run after models are ready:
- **HeatmapService** - Tracks player positions on a 2D grid for spatial analytics
- **CommunityService** / **StoresService** - Shared outfits and stores; flush counted wears/visits/favourites on a timer
- **SharedContentService** - Share-code records in a global DataStore, called on demand by controllers and other services
- **AnalyticsDimensions** - Registers the per-player count dimensions stamped on analytics events
- *Your new services go here!*

Game services are **auto-discovered** - just drop a `.luau` file with an `init()` function and it runs automatically. (ServiceRunner requires every ModuleScript in `game/` and calls `init()` only where it exists, so a helper with no `init()`, like `RankedPages`, can live there too.)

## Service Patterns

### Pattern 1: Loop-Based Services

Loop-based services run periodic tasks using `task.spawn()` with a `while true do` loop.

**When to use:**
- Periodic cleanup (expired items, stale data)
- Scheduled updates (leaderboards, timers)
- Resource management (token regeneration)

**Examples:** PersistenceService (queue processing), HeatmapService (position sampling), CommunityService / StoresService (batched count flushes)

**Template:**
```lua
--!strict

local MyService = {}

local CHECK_INTERVAL_SECONDS = 1
local isRunning = false

local function doPeriodicWork(): ()
    -- Your periodic logic here
end

local function startLoop()
    if isRunning then return end
    isRunning = true

    task.spawn(function()
        while true do
            doPeriodicWork()
            task.wait(CHECK_INTERVAL_SECONDS)
        end
    end)
end

function MyService.init()
    print("[MyService] Initializing...")
    startLoop()
end

return MyService
```

### Pattern 2: Event-Driven Services

Event-driven services respond to system events without continuous polling.

**When to use:**
- Player lifecycle handling (join/leave)
- Game state transitions (round start/end)
- One-time setup or registration

**Examples:** SlashCommandService (chat commands), DeepLinkService (share links read on join), AvatarService (re-applies worn items on respawn)

**Template:**
```lua
--!strict

local Players = game:GetService("Players")

local MyService = {}

local function onPlayerAdded(player: Player)
    -- Handle player join
end

local function onPlayerRemoving(player: Player)
    -- Handle player leave
end

function MyService.init()
    print("[MyService] Initializing...")

    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    -- Handle players already in game
    for _, player in Players:GetPlayers() do
        onPlayerAdded(player)
    end
end

return MyService
```

## Decision Tree: Choosing a Pattern

```
Do you need to run code periodically on a timer?
├── YES → Use Loop-Based Pattern
│         Examples: cleanup tasks, scheduled updates, resource regeneration
│
└── NO → Do you respond to specific events?
         ├── YES → Use Event-Driven Pattern
         │         Examples: player join/leave, chat commands, game lifecycle
         │
         └── NO → Consider if you need a service at all
                  (Maybe a utility module or model method is better)
```

## Example: CommunityService (Loop-Based)

CommunityService counts wears and favourites of Community outfits in memory and writes them to the DataStore in one batch every `FLUSH_SECONDS`, rather than on every click. Excerpt from `services/game/CommunityService.luau`:

```lua
local FLUSH_SECONDS = 60

local pending: { [string]: { wears: number, favourites: number } } = {}

function CommunityService.countWear(code: string)
	local entry = pending[code] or { wears = 0, favourites = 0 }
	entry.wears += 1
	pending[code] = entry
end

function CommunityService.init()
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			CommunityService.flush()
		end
	end)
	game:BindToClose(CommunityService.flush)
	Players.PlayerRemoving:Connect(function()
		if #Players:GetPlayers() <= 1 then
			task.spawn(CommunityService.flush)
		end
	end)
end
```

**Key design decisions:**
- **60-second interval**: Keeps DataStore requests low; the counts feed rankings, not anything a player waits on
- **Batching**: `flush()` swaps `pending` for a fresh table first, then writes each code once with its summed deltas
- **Shutdown safety**: `BindToClose` and the last-player-leaving check flush whatever is still pending
- StoresService uses the same shape for store visits and favourites; HeatmapService is a fuller loop (samples every `sampleIntervalSeconds`, flushes every `flushIntervalSeconds`, both from `AnalyticsConfig.heatmap`)

### Pattern: Expiring Server Entities (illustrative)

> Illustrative — no module in this repo uses this pattern yet (`models/serverEntities/` is empty).

A loop-based service is the natural home for despawning dynamic ServerEntity models (see [MODEL_GUIDE.md](MODEL_GUIDE.md)). Collect first, remove, then sync once — `syncAll()` covers the case where the last entity was just removed:

```lua
-- services/game/PickupsService.luau (hypothetical)
local function removeExpired(): ()
	local now = os.time()
	local expired: { string } = {}
	for entityId, pickup in PickupsModel.getAll() do
		if now - pickup.createdTime >= PickupsConfig.lifetimeSeconds then
			table.insert(expired, entityId)
		end
	end
	for _, entityId in expired do
		PickupsModel.remove(entityId)
	end
	if #expired > 0 then
		PickupsModel.syncAll() -- one broadcast, even when the collection is now empty
	end
end
```

## Step-by-Step: Creating a New Service

### Step 1: Choose Your Pattern

Ask yourself:
- Need periodic checks? → Loop-based
- Respond to events? → Event-driven
- Both? → Combine patterns in one service

### Step 2: Create the Service File

Create your service in `Source/ServerScriptService/services/game/`:

```lua
--!strict

local MyService = {}

function MyService.init()
    print("[MyService] Initializing...")
    -- Your initialization logic
end

return MyService
```

**That's it!** ServiceRunner auto-discovers and initializes any ModuleScript in `services/game/` that has an `init()` function.

### Step 3: Test

1. Start Play mode in Studio
2. Check Output window for `[MyService] Initializing...`
3. Verify your service behavior

## Best Practices

### DO:
- Use descriptive print statements for debugging (prefix with `[ServiceName]`)
- Initialize services after models they depend on
- Use `task.spawn()` for loops to avoid blocking
- Batch operations when possible (sync once after multiple changes)
- Use module-level `isRunning` flag to prevent duplicate loops

### DON'T:
- Block the main thread with infinite loops (always use `task.spawn()`)
- Start multiple instances of the same loop
- Call `syncState()` for every individual change in a batch operation
- Forget to handle edge cases (empty collections, missing data)

## Service File Locations

```
Source/ServerScriptService/
├── services/
│   ├── ServiceRunner.luau         -- Orchestrates service initialization
│   ├── framework/                 -- Explicit initialization order
│   │   ├── PersistenceService.luau    -- DataStore write queue (loop-based)
│   │   ├── AnalyticsService.luau      -- GA4 event batching (loop-based)
│   │   └── SlashCommandService.luau   -- Chat commands (event-driven)
│   └── game/                      -- Auto-discovered services
│       ├── AnalyticsDimensions.luau   -- Per-player analytics dimensions
│       ├── CommunityService.luau      -- Community outfits, count flushes (loop-based)
│       ├── HeatmapService.luau        -- Player position tracking (loop-based)
│       ├── SharedContentService.luau  -- Share-code records (on demand)
│       ├── StoresService.luau         -- Player stores, count flushes (loop-based)
│       └── ...                        -- AvatarService, DeepLinkService, OwnershipService, etc.
├── models/
│   └── ModelRunner.server.luau    -- Calls ServiceRunner for service init
└── controllers/
    └── ...
```

### Adding a New Game Service

Simply create a new `.luau` file in `services/game/` with an `init()` function:

```lua
-- services/game/MyNewService.luau
local MyNewService = {}

function MyNewService.init()
    print("[MyNewService] Initializing...")
end

return MyNewService
```

ServiceRunner will automatically discover and initialize it. You'll see in the Output:
```
[ServiceRunner] Initialized: MyNewService
```

## Tracking Custom Analytics Events

If AnalyticsService is enabled, your game services can send custom GA4 events:

```lua
local ServiceRunner = require(script.Parent.Parent.ServiceRunner)

function MyService.init()
    local AnalyticsService = ServiceRunner.getAnalyticsService()

    -- Track a custom event (player, event name, params)
    if AnalyticsService and AnalyticsService.isEnabled then
        AnalyticsService:trackEvent(player, "quest_completed", {
            quest_name = "Dragon Slayer",
            time_taken = 120,
        })
    end
end
```

Events are automatically batched, enriched with session/user data, and sent to GA4. See AnalyticsConfig for setup.

## Existing Services Reference

| Service | Location | Pattern | Purpose |
|---------|----------|---------|---------|
| PersistenceService | framework/ | Loop-based | Processes DataStore write queue with rate limiting |
| AnalyticsService | framework/ | Loop-based | Batches and sends GA4 events via Measurement Protocol |
| SlashCommandService | framework/ | Event-driven | Registers and handles chat slash commands |
| HeatmapService | game/ | Loop-based | Tracks player positions on a 2D grid for spatial analytics |
| CommunityService | game/ | Loop-based | Community outfits; flushes wear/favourite counts every 60s |
| StoresService | game/ | Loop-based | Player stores; flushes visit/favourite counts every 60s |
| SharedContentService | game/ | On demand | Claims and looks up share codes in a global DataStore |
| AvatarService | game/ | Event-driven | Applies worn items to the character after changes and respawns |
| DeepLinkService | game/ | Event-driven | Reads share-link launch data on join |
| AnalyticsDimensions | game/ | Setup only | Registers `basket_count`, `worn_count`, `outfits_count`, `stores_count` |

### When to Use Framework vs Game

| Put in `framework/` if... | Put in `game/` if... |
|---------------------------|----------------------|
| Other services depend on it | It just needs models to be ready |
| Initialization order matters | Order doesn't matter |
| It's a core system service | It's game-specific logic |
| Example: PersistenceService | Example: CommunityService |
