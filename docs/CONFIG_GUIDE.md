# Config Development Guide

This guide explains how to create and use Configs in this Roblox MVC project.

## What is a Config?

Configs are static game data modules that hold values like item prices, spawn rates, level thresholds, and other tunable constants. They are separate from code and designed to be easily adjusted without modifying game logic.

## Architecture Overview

Configs in this project follow a two-part pattern:

1. **Type definitions** (synced via Rojo): Define the structure of your config data
2. **Config modules** (created in Studio): Contain the actual data values

This separation allows:
- Type safety for config data throughout your codebase
- Easy adjustment of values directly in Roblox Studio
- Version control for types without cluttering git with data changes

## File Locations

There are two config locations: **shared configs** (ReplicatedStorage) and **server-side configs** (ServerScriptService). Use server-side configs for anything containing secrets or data that only the server needs and views never use.

### Shared Configs (ReplicatedStorage)

#### Types (Version Controlled)

```
Source/ReplicatedStorage/Config/ConfigTypes/{Name}ConfigTypes.luau
```

Type definition files are synced via Rojo and should be in version control. They define the structure that config modules must follow.

#### Config Modules (Studio Only)

```
ReplicatedStorage.Config.{Name}Config (ModuleScript in Studio)
```

Config modules are created directly in Roblox Studio under ReplicatedStorage > Config. They are NOT synced via Rojo because:
- Config data often needs adjustment during playtesting
- Values like prices, rates, and thresholds change frequently
- Rojo's `$ignoreUnknownInstances: true` on the Config folder protects these from deletion

### Server-Side Configs (ServerScriptService)

Use server-side configs when the config contains secrets (API keys, tokens) or when only server code needs the values and clients should never see them.

#### Types (Version Controlled)

```
Source/ServerScriptService/Config/ConfigTypes/{Name}ConfigTypes.luau
```

Same pattern as shared config types — synced via Rojo, version controlled.

#### Config Modules (Studio Only)

```
ServerScriptService.Config.{Name}Config (ModuleScript in Studio)
```

Created in Studio under ServerScriptService > Config. Protected from Rojo deletion by `$ignoreUnknownInstances: true` on the Config folder in `default.project.json`.

#### Example: AnalyticsConfig

The AnalyticsConfig is a server-side config because it contains a GA4 API secret. It also includes heatmap tracking settings. Create it in Studio at `ServerScriptService > Config > AnalyticsConfig`:

```lua
--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ConfigTypes = ServerScriptService:WaitForChild("Config"):WaitForChild("ConfigTypes")
local AnalyticsConfigTypes = require(ConfigTypes:WaitForChild("AnalyticsConfigTypes"))

type AnalyticsConfig = AnalyticsConfigTypes.AnalyticsConfig

local config: AnalyticsConfig = {
    enabled = true,
    measurementId = "G-XXXXXXXXXX",
    apiSecret = "your-api-secret",
    hashSalt = "change-me-to-something-unique",  -- set once, NEVER change post-launch (rehashes all UserIds)
    flushIntervalSeconds = 15,
    maxBatchSize = 25,
    debug = false,  -- true routes events to GA4 DebugView and OUT of standard reports; false for live

    -- Controller action names to skip in auto-tracking (noise reduction). Optional.
    excludedActions = {},

    -- Absolute model values stamped as params onto (almost) every event, so any
    -- metric can be segmented by player progression in BigQuery. Each key needs a
    -- resolver registered in services/game/AnalyticsDimensions (ships with "gold").
    globalParams = { "gold" },

    heatmap = {
        enabled = false,
        trackingMode = "summary",
        boundsMin = { -100, -100 },
        boundsMax = { 100, 100 },
        cellSize = 10,
        sampleIntervalSeconds = 1,
        flushIntervalSeconds = 120,
        heartbeatIntervalSeconds = 60,
        -- version = "arena-v1",  -- optional friendly label stamped as `heatmap_gen`;
                                  -- omit to auto-derive from cellSize + bounds (any grid
                                  -- change then yields a new generation automatically)
    },
}

return config
```

**Note:** HttpService must be enabled in Game Settings > Security for analytics to work.

**Acquisition attribution** is automatic — no config needed. `AnalyticsService` reads `player:GetJoinData().LaunchData` on join and stores it as the `launch_data` user property, so events can be segmented by ad campaign. Tag each campaign link with a distinct LaunchData; untagged joins record as `"organic"`. Campaign tags must not contain `:`, which marks `key:value` fields (`Utils/LaunchData`). Share links (`s:<code>`, from the share dialog's QR) record as `"share"`, or as their `c:` field if they carry one. `DeepLinkService` sends a `share_join` event saying which code brought the player in. To test in Studio, set a `TestLaunchData` attribute/StringValue on Workspace (e.g. `wknd-adA`, or `s:<code>` to test a share link).

#### Accessing Server-Side Configs

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local config = require(ServerScriptService:WaitForChild("Config"):WaitForChild("AnalyticsConfig"))
```

## Config Pattern

### Types File (Source/ReplicatedStorage/Config/ConfigTypes/{Name}ConfigTypes.luau)

```lua
--!strict
--[[
    {Name}ConfigTypes
    Type definitions for {description}
]]

-- Define table types for structured data
export type ItemPricesTable = {
    [string]: number,
}

-- Define the main config type
export type {Name}Config = {
    itemPrices: ItemPricesTable,
    baseMultiplier: number,
}

return nil
```

**Key points:**
- Use `--!strict` for type safety
- Export all types that consumers need
- Return `nil` - this is a types-only module
- Use descriptive names for table types

### Config Module (Created in Studio)

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigTypes = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ConfigTypes")
local {Name}ConfigTypes = require(ConfigTypes:WaitForChild("{Name}ConfigTypes"))

type {Name}Config = {Name}ConfigTypes.{Name}Config

local config: {Name}Config = {
    itemPrices = {
        Sword = 100,
        Shield = 75,
        Potion = 25,
    },
    baseMultiplier = 1.5,
}

return config
```

**Key points:**
- Use `--!strict` for type safety
- Import types from ConfigTypes folder
- Create a local type alias for cleaner code
- Annotate the config variable with the type
- Return the config table

## Decision Tree: When to Use Configs

**Question 1: Is this data that might need adjustment during development or playtesting?**
- **Yes** → Use a Config
- **No** → Continue to Question 2

**Question 2: Is this a constant that affects game balance (prices, rates, thresholds)?**
- **Yes** → Use a Config
- **No** → Continue to Question 3

**Question 3: Is this data that designers (non-programmers) might need to modify?**
- **Yes** → Use a Config
- **No** → Consider a constant in the relevant module

### Examples

**Use shared configs (ReplicatedStorage) for:**
- Item prices and costs
- Experience point thresholds
- Spawn rates and probabilities
- Cooldown durations
- Damage/health values
- Level requirements
- Drop tables
- Quest rewards

**Use server-side configs (ServerScriptService) for:**
- API keys and secrets (e.g., analytics, external services)
- Server-only tuning values that clients don't need
- Any data containing credentials or tokens

**Use Models instead when:**
- Data changes at runtime (player inventory, health)
- Data is per-player (user preferences, progress)
- Data needs server authority (game state)

**Use constants in code when:**
- Value never changes (math constants, fixed strings)
- Value is implementation detail (buffer sizes, internal IDs)
- Value is only used in one module

## Example: FavoursConfig

### Types File (FavoursConfigTypes.luau)

```lua
--!strict
--[[
    FavoursConfigTypes
    Type definitions for divine favours configuration
]]

export type FavoursTable = {
    [string]: number,
}

export type FavoursConfig = {
    favours: FavoursTable,
}

return nil
```

### Config Module (Created in Studio)

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigTypes = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ConfigTypes")
local FavoursConfigTypes = require(ConfigTypes:WaitForChild("FavoursConfigTypes"))

type FavoursConfig = FavoursConfigTypes.FavoursConfig

local config: FavoursConfig = {
    favours = {
        Blessing = 100,
        Fortune = 250,
        Miracle = 500,
        Divinity = 1000,
    },
}

return config
```

## Using Configs in Code

### In Controllers/Models (Server)

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FavoursConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FavoursConfig"))

-- Access config values
local blessingCost = FavoursConfig.favours.Blessing

-- Iterate over config data
for favourName, cost in FavoursConfig.favours do
    print(favourName, cost)
end
```

### In Views (Client)

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FavoursConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FavoursConfig"))

-- Display config values in UI
for favourName, cost in FavoursConfig.favours do
    createFavourButton(favourName, cost)
end
```

## Best Practices

### 1. Use Descriptive Type Names

```lua
-- Good: Clear what the table contains
export type ItemPricesTable = {
    [string]: number,
}

-- Avoid: Generic names
export type Table = {
    [string]: number,
}
```

### 2. Group Related Data

```lua
-- Good: Related data in one config
export type ShopConfig = {
    prices: PricesTable,
    discountRates: DiscountTable,
    maxPurchasePerDay: number,
}

-- Avoid: Scattered across multiple configs
```

### 3. Use Consistent Naming

- Config types: `{Name}Config`
- Table types: `{Purpose}Table`
- Files: `{Name}ConfigTypes.luau` (types), `{Name}Config` (module in Studio)

### 4. Document Config Purpose

```lua
--[[
    ShopConfigTypes
    Type definitions for shop pricing and purchase limits

    Used by: ShopController, ShopView
    Updated: When adding new items or adjusting economy
]]
```

### 5. Keep Types and Data Separate

Types in ConfigTypes folder (version controlled):
- Define structure
- Document expected format
- Provide type safety

Config modules in Studio:
- Contain actual values
- Easy to adjust during playtesting
- Not in version control

## Common Patterns

### Tiered Values

```lua
export type TierTable = {
    [string]: number,
}

export type RewardsConfig = {
    tiers: TierTable,
}

-- Usage:
local config: RewardsConfig = {
    tiers = {
        Bronze = 10,
        Silver = 25,
        Gold = 50,
        Platinum = 100,
    },
}
```

### Lookup Tables

```lua
export type ItemStatsTable = {
    [string]: {
        damage: number,
        speed: number,
        range: number,
    },
}

export type WeaponsConfig = {
    weapons: ItemStatsTable,
}
```

### Probability Tables

```lua
export type DropRatesTable = {
    [string]: number, -- 0.0 to 1.0
}

export type LootConfig = {
    dropRates: DropRatesTable,
}
```

## Studio Setup

### Creating a New Config Module

**Shared config (ReplicatedStorage):**
1. Open Roblox Studio
2. Navigate to ReplicatedStorage > Config
3. Right-click Config folder > Insert Object > ModuleScript
4. Name it `{Name}Config` (e.g., `FavoursConfig`)
5. Paste the config module template
6. Fill in your data values
7. Test by requiring it in the command bar:
   ```lua
   local config = require(game.ReplicatedStorage.Config.YourConfig)
   print(config)
   ```

**Server-side config (ServerScriptService):**
1. Open Roblox Studio
2. Navigate to ServerScriptService > Config
3. Right-click Config folder > Insert Object > ModuleScript
4. Name it `{Name}Config` (e.g., `AnalyticsConfig`)
5. Paste the config module template (use ServerScriptService path for types)
6. Fill in your data values
7. Test by requiring it in the command bar:
   ```lua
   local config = require(game.ServerScriptService.Config.YourConfig)
   print(config)
   ```

### Verifying Config Structure

After creating a config, verify it matches the types:

1. Require the config in a script
2. If types don't match, you'll get Luau type errors
3. Fix any mismatches between your data and the type definitions

## Troubleshooting

### "Cannot find ConfigTypes"

- Ensure Rojo is running and synced
- Check the file exists in `Source/ReplicatedStorage/Config/ConfigTypes/`
- Verify the filename matches what you're requiring

### "Type mismatch" errors

- Check that your config data matches the exported types
- Ensure all required fields are present
- Verify table key/value types match

### Config not updating in Studio

- Rojo only syncs ConfigTypes, not config modules
- Edit config modules directly in Studio
- Config modules are NOT in version control

## Next Steps

After creating your config:

1. **Use in Controllers** - Access config values for game logic validation
2. **Use in Views** - Display config data in UI elements
3. **Test in Studio** - Verify values work correctly in gameplay
4. **Adjust as needed** - Tune values based on playtesting feedback
