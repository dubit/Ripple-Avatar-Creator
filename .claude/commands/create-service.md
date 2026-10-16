---
description: Create a new Roblox service with automatic pattern detection
allowed-tools: Bash(find, cat, grep), Read, Write, Edit, Glob
---

I'll guide you through creating a new Roblox service. Services are server-side modules that run automatically to handle background tasks and system events.

## Reference Files

Before generating code, I will read:
- `docs/SERVICES_GUIDE.md` - Complete patterns, templates, and best practices

## Interactive Service Creation Wizard

### Step 1: Service Name

What should your service be named?

**Requirements**:
- Must end with "Service" (e.g., AuctionService, RecommendationService)
- Must use PascalCase
- Should describe its responsibility

### Step 2: Service Pattern

Which pattern does this service follow?

**Loop-Based** (periodic tasks):
- Runs on a timer interval
- Use for: cleanup, scheduled updates, regeneration
- Examples: HeatmapService samples player positions every `sampleIntervalSeconds`; CommunityService flushes wear/favourite counts to DataStores every `FLUSH_SECONDS`

**Event-Driven** (responds to events):
- Reacts to system events
- Use for: player join/leave, game lifecycle, chat commands
- Examples: DeepLinkService handles launch data on PlayerAdded; SlashCommandService (framework) listens for PlayerAdded

See docs/SERVICES_GUIDE.md "Decision Tree" for pattern selection guidance.

### Step 3: Pattern-Specific Details

**If Loop-Based**:
- What task runs periodically?
- What interval in seconds? (default: 1)

**If Event-Driven**:
- What events? (PlayerAdded, PlayerRemoving, other?)
- What happens on each event?

### Step 4: Dependencies

What models/configs does this service need?

For each dependency:
- Module name (e.g., StoresModel, StoresConfig, SharedContentService)
- Location hint (models/user/, Config/, services/game/, etc.)

### Step 5: Generation

I will:
1. Read docs/SERVICES_GUIDE.md for the exact template
2. Generate service file in `Source/ServerScriptService/services/game/`
3. Provide testing instructions

---

## Implementation Details (Internal)

### File Location
All game services go in: `Source/ServerScriptService/services/game/{ServiceName}.luau`

Services here are auto-discovered by ServiceRunner - no registration needed.

### Templates

Use the templates from docs/SERVICES_GUIDE.md:
- Loop-based: Pattern 1 template with `task.spawn()` and `while true do`
- Event-driven: Pattern 2 template with event connections

### Key Requirements
- `--!strict` pragma at top
- Module-level `isRunning` flag for loop-based services
- `init()` function is required for auto-discovery
- Use `print("[ServiceName] Initializing...")` for debugging

### Require Paths
```lua
-- Models (server-side)
local MyModel = require(ServerScriptService.models.server.MyModel)
local MyEntityModel = require(ServerScriptService.models.serverEntities.MyEntityModel)

-- Config (replicated)
local MyConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("MyConfig"))
```

### Testing
After generation:
1. Start Play mode in Studio
2. Check Output for `[ServiceRunner] Initialized: {ServiceName}`
3. Verify service behavior

---

## Let's Start!

**1. Service Name** (must end with "Service"):
