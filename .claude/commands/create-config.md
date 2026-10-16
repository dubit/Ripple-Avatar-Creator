---
description: Create a new Roblox config with type definitions
allowed-tools: Bash(find, cat, grep, ls), Read, Write, Edit, Glob
---

I'll guide you through creating a new Roblox config that follows this project's config pattern with type-safe definitions.

## Project Config Architecture

- **Two-part pattern**:
  - **Types file**: Synced via Rojo, defines config structure
  - **Config module**: Created in Studio, contains actual data values
- **Type definitions location**: `Source/ReplicatedStorage/Config/ConfigTypes/{Name}ConfigTypes.luau`
- **Config modules location**: Created manually in Studio under `ReplicatedStorage.Config`
- **Why this split**: Config data (prices, rates, thresholds) is often adjusted in Studio during playtesting

## Reference Files

Before generating code, I will read these stable reference files to ensure accuracy:
- `docs/CONFIG_GUIDE.md` - Complete config documentation with patterns and examples
- `Source/ReplicatedStorage/Config/ConfigTypes/StoresConfigTypes.luau` - Example types file (small; `AvatarConfigTypes` / `WorldOptionsConfigTypes` show nested tables)
- `Source/ReplicatedStorage/Config/StoresConfig.luau` - Reference copy of the matching Studio-authored module (repo convention: keep a `-- REFERENCE COPY` next to the types so the values are reviewable; keep the two in step)

These core files contain the exact patterns, type definitions, and conventions to follow.

## Interactive Config Creation Wizard

Let's begin creating your config step by step!

### Step 1: Config Name

What should your config be named?

**Requirements**:
- Must end with "Config" (e.g., StoresConfig, AuctionConfig, PointsConfig)
- Must use PascalCase (e.g., RecommendationsConfig)
- No underscores or special characters

**Examples**:
- StoresConfig - Limits on player stores and their rows (real)
- WorldOptionsConfig - World options defaults, flight and sprint tuning (real)
- AuctionConfig - Bid increments and auction durations (hypothetical)
- PointsConfig - Points awarded per action (hypothetical)

**Config Name**:

### Step 2: Description

What does this config contain? (Brief description for the file header)

**Examples**:
- "player stores: limits on stores and their rows"
- "UGC auction bid increments and durations"
- "points awarded per action"

**Description**:

### Step 3: Properties

What properties does this config need?

For each property, I'll ask for:
1. **Property name** (camelCase, e.g., maxStores, pointsPerAction)
2. **Property type**:
   - `table` - A lookup table with string keys (most common for configs)
   - `number` - A single numeric value
   - `string` - A single string value
   - `boolean` - A true/false flag
3. **Table value type** (if property is a table): number, string, boolean, or nested object
4. **Purpose** (brief description for documentation)

**How many properties?** (1-10):

[For each property, ask: name, type, value type if table, purpose]

### Step 4: Example Data

For each table property, provide 3-5 example entries that demonstrate the expected data format.

**Example format for a points table:**
```
Share = 10
Publish = 25
Favourite = 2
```

This helps generate a useful "stub plus" config module that you can expand in Studio.

### Step 5: Review & Confirm

I'll display a summary showing:
- Config name and types file location
- All properties with their types
- Example data for tables
- Config module output location (Studio)

**Proceed with generation?** (Yes/No/Edit)

### Step 6: Generation

I will:
1. Read docs/CONFIG_GUIDE.md to understand the exact pattern
2. Read existing ConfigTypes for reference
3. Create types file at `Source/ReplicatedStorage/Config/ConfigTypes/{Name}ConfigTypes.luau`
4. Output config module code to the conversation for you to paste into Studio

---

## Implementation Details (Internal)

When generating the config, I will:

### 1. Read Reference Files

Use Read tool on:
- **docs/CONFIG_GUIDE.md** to understand patterns and conventions
- **StoresConfigTypes.luau** (and its reference copy `Config/StoresConfig.luau`) to see exact type definition syntax

### 2. Generate Types File

**Location**: `Source/ReplicatedStorage/Config/ConfigTypes/{Name}ConfigTypes.luau`

**Structure**:

```lua
--!strict
--[[
    {Name}ConfigTypes
    Type definitions for {description}
]]

{For each table property:}
export type {PropertyName}Table = {
    [string]: {valueType},
}

export type {Name}Config = {
    {For each property:}
    {propertyName}: {propertyType},
}

return nil
```

### 3. Output Config Module (For Studio)

Output to conversation (user pastes into Studio):

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigTypes = ReplicatedStorage:WaitForChild("Config"):WaitForChild("ConfigTypes")
local {Name}ConfigTypes = require(ConfigTypes:WaitForChild("{Name}ConfigTypes"))

type {Name}Config = {Name}ConfigTypes.{Name}Config

local config: {Name}Config = {
    {For each property:}
    {propertyName} = {exampleData or defaultValue},
}

return config
```

### 4. Validation During Generation

Before finalizing:
- Ensure --!strict pragma at top of types file
- All table types properly exported
- Main config type includes all properties
- Config module matches type structure exactly
- Example data uses correct types

### 5. Output Instructions

After generation, provide:

```
Config Generation Complete!

Created Files:
  Source/ReplicatedStorage/Config/ConfigTypes/{Name}ConfigTypes.luau

Studio Setup Required:

1. Open Roblox Studio
2. Navigate to ReplicatedStorage > Config
3. Right-click Config folder > Insert Object > ModuleScript
4. Name it "{Name}Config" (exactly this name)
5. Paste the config module code below
6. Save the place

Config Module Code (copy and paste into Studio):
[CONFIG CODE HERE]

Testing:
1. Open the Command Bar in Studio (View > Command Bar)
2. Run: local config = require(game.ReplicatedStorage.Config.{Name}Config); print(config)
3. Verify the config loads without errors

Usage in Code:
  local {Name}Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("{Name}Config"))
  local value = {Name}Config.{exampleProperty}

Documentation:
  See docs/CONFIG_GUIDE.md for complete config patterns and best practices
```

---

## Type Patterns

### Simple Table (String -> Number)

```lua
export type PricesTable = {
    [string]: number,
}
```

### Simple Table (String -> String)

```lua
export type DescriptionsTable = {
    [string]: string,
}
```

### Simple Table (String -> Boolean)

```lua
export type EnabledFeaturesTable = {
    [string]: boolean,
}
```

### Nested Object Table

```lua
export type AuctionTiersTable = {
    [string]: {
        startingBid: number,
        bidIncrement: number,
        durationMinutes: number,
    },
}
```

### Mixed Properties

```lua
export type AuctionConfig = {
    tiers: AuctionTiersTable,
    maxBidsPerMinute: number,
    houseName: string,
    isEnabled: boolean,
}
```

---

## Let's Start!

Please provide the following information to begin:

**1. Config Name** (must end with "Config"):
