---
description: Create a new Roblox view with automatic pattern detection
allowed-tools: Bash(find, cat, grep, ls), Read, Write, Edit, Glob
---

I'll guide you through creating a new Roblox view with automatic pattern detection (A, B, C, or B+C). This project has two distinct view types that follow different architectures.

> **Starting from a visual design?** If you have an HTML/CSS/JSX mockup or a screenshot to translate, run `/html-to-react-luau` **first** — it produces the component's structure, layout, and responsive scaling. Then come back here to wire it to Network state (patterns A/B/C) and into the HUD (a screen routed by `panel/FullPanel`, or an element in `WorldHud`). This skill owns the state wiring; `/html-to-react-luau` owns the visual translation. See also `docs/VIEW_GUIDE.md` → "Responsive Scaling".

## Project View Architecture

This project has **two types of views**:

### HUD Views (ScreenGui/UI) — react-luau components
- **File type**: ModuleScript (`.luau`) in `Source/ReplicatedFirst/views/`
- **Architecture**: `HudApp.client.luau` creates its own `HudApp` ScreenGui and mounts the root component `Hud.luau`, which renders either `WorldHud.luau` (the HUD over the world) or `panel/FullPanel.luau` (the one full-screen panel)
- **State observation**: `useBoltState` hook bridges Bolt RemoteProperty into React state (called in `Hud`, passed down as props)
- **Navigation**: `hooks/useNavigation` in `Hud` — root (Catalogue/Stores/Outfits/Basket/Wearing) + breadcrumb stack. No modals: a new page is a **screen** in `views/screens/`, routed in `currentScreen` in `panel/FullPanel.luau`
- **Look**: composed from the skin kit (`Tokens.luau`, `components/` PillButton/GlassPanel/Badge/ShadowText/..., `hooks/useSkin`) and `screens/Parts.luau` (ItemCard, ListRow, CardGrid, ...)
- **Interactions**: `PillButton` (or `React.Event.Activated` + `hooks/useInteraction` for custom controls)
- **Examples**: WorldHud, screens/StoresScreen, screens/ListScreens

### Workspace Views (3D parts/models) — imperative LocalScripts
- **File type**: LocalScript (`.client.luau`) in `Source/ReplicatedFirst/views/`
- **Architecture**: Imperative scripts using CollectionService to find tagged instances
- **State observation**: `Network.State.{Model}:Observe()` directly (no React)
- **Interactions**: ProximityPrompt.Triggered, ClickDetector, etc.
- **In-repo non-React views**: `PurchaseView.client.luau` (Pattern B — relays `PromptBulkPurchaseFinished` to PurchaseController), `FlightView.client.luau` / `SprintView.client.luau` (Pattern A — character movement, no server). None targets a tagged Workspace interactable yet; the nearest tag consumer is `WorldRenderer.luau`, a render-nothing React component that recolours every part tagged `"WorldFloor"`. The tagged-interactable examples below use a hypothetical `MonolithView` / tag `"Monolith"` for illustration (e.g. a diegetic monolith the player walks up to)

### Three interaction patterns (apply to both types):
- **Pattern A**: Pure client-side feedback (particles, sounds, animations) — no server communication
- **Pattern B**: Intent-based with server validation (send actions to controllers via Network.Intent)
- **Pattern C**: State observation (observe model state changes via Network.State)
- **Pattern B+C**: Combination (send intents AND observe state)

## Reference Files

Before generating code, I will read these stable reference files to ensure accuracy:
- `Source/ReplicatedStorage/Network.luau` — Network configuration to validate controllers and states
- `Source/ReplicatedFirst/views/Hud.luau` — HUD root (navigation, state, WorldHud vs FullPanel)
- `Source/ReplicatedFirst/views/panel/FullPanel.luau` — full panel; `currentScreen` is where new screens are routed
- `Source/ReplicatedFirst/views/hooks/useNavigation.luau` — navigation API (push / toggleTab / openRoot / back / close)
- `Source/ReplicatedFirst/views/screens/Parts.luau` — shared screen parts (ItemCard, ListRow, CardGrid, Heading, ...)
- `Source/ReplicatedFirst/views/hooks/useBoltState.luau` — Custom hook for state in React views

## Interactive View Creation Wizard

Let's begin creating your view step by step!

### Step 1: View Name

What should your view be named?

**Requirements**:
- Must end with "View" (e.g., MonolithView, WorldOptionsView) — or "Screen" for a full-panel screen (e.g., StoresScreen)
- Must use PascalCase (e.g., AuctionLotView)
- No underscores or special characters

**Examples**:
- StoresScreen — The Stores panel pages (root list + a store)
- FlightView — Double-jump flight (client only)
- MonolithView — Handles a tagged in-world monolith (illustrative)

### Step 1.5: View Type

**Is this a HUD/UI view or a Workspace/3D view?**

| HUD View | Workspace View |
|---|---|
| ScreenGui elements (buttons, labels, frames) | 3D parts, models, ProximityPrompts |
| Rendered in PlayerGui overlay | Exists in Workspace |
| React component (ModuleScript `.luau`) | Imperative LocalScript (`.client.luau`) |
| Rendered under Hud.luau (FullPanel screen or WorldHud element) | Runs standalone via CollectionService |
| Examples: WorldHud, screens/StoresScreen, screens/ListScreens | Examples: PurchaseView, FlightView, SprintView (untagged); illustrative MonolithView |

**View type** (HUD / Workspace):

---

## HUD View Path

*Only shown if view type is HUD*

### Step 2H: Panel Screen or World HUD?

Is this a **panel screen** (a page shown inside the full-screen panel, reached through tabs / breadcrumbs) or a **world-HUD element** (always over the world, like the Basket button or the World options panel)?

**Panel screen examples**: CatalogueScreen, StoresScreen (Root + Store), ListScreens (Basket + Wearing), ItemScreen
**World-HUD examples**: WorldHud's Basket button + Robux badge, WorldOptionsView

**Panel screen or world HUD?**:

### Step 3H: User Actions (Pattern B Detection)

Does this view need to send user actions to the server?

**Examples that send actions**:
- Item page with a Buy button — Sends "Buy" to PurchaseController
- Item card's basket toggle — Sends "Add" / "Remove" to BasketController

**Examples that DON'T send actions**:
- Basket badge showing the Robux total — Read-only display
- A list screen that only displays data

**Send user actions to server?** (Yes/No):

**If Yes**:

Which controller will handle these actions?

I will read Network.luau to validate this controller exists and show you available options.

**Controller name** (without "Controller" suffix):

**Action details**:

For each action this view will send:
1. **Action name** (e.g., "Purchase", "Equip", "Donate")
2. **What triggers it?** (button click, toggle, etc.)
3. **Parameters** (if any — name and type for each)

How many actions will this view send? (1-5):

[For each action, ask: Action name, trigger, parameters]

### Step 4H: State Observation (Pattern C Detection)

Does this view need to display or react to server state changes?

**Examples that observe state**:
- Basket badge — total from state that `Hud` observes, passed down as a prop
- A list screen — a UserEntity dictionary observed in `Hud`, passed down to the screen

**Examples that DON'T observe state**:
- Pure cosmetic animation panel — No server data

**Observe server state?** (Yes/No):

**If Yes**:

Which model's state will this view observe?

I will read Network.luau to validate this state exists and show you available options.

**State name** (without "State" suffix):

**What is the model's scope?**

**IMPORTANT**: The state format depends on the model scope AND its syncScope:
- **User / UserSession, syncScope="owner"** (default, e.g., BasketModel, OwnershipModel) — Single state object, sent to owner only
- **User, syncScope="all"** (none in-repo; hypothetical PowerUpModel) — Dictionary `{ [ownerId]: State }`, broadcast to all players. Index by `tostring(localPlayer.UserId)` to get the local player's state.
- **Server** (none in-repo; hypothetical LeaderboardModel) — Single state object, broadcast to all
- **UserEntity** (none in-repo; hypothetical PetsModel) — Dictionary `{ [entityId]: State }`, sent to owner only
- **ServerEntity** (none in-repo; hypothetical AuctionLotsModel) — Dictionary `{ [entityId]: State }`, broadcast to all

**Model scope** (User/Server/UserEntity/ServerEntity):

**If User scope: Does it use syncScope="all"?** (Yes/No):

**Which properties from this state will you use?**

I will show you the available properties from Network.luau.

**Properties** (comma-separated):

### Step 4.5H: Animation Needs

Does this view need animation? (spring transitions, drag, number springs)

**Examples that use animation**:
- Currency display that rolls up/down — useSpringNumber
- Panel that slides in — useSpring on Position
- Element with enter/exit animation — useTransition (boolean mode keeps it mounted while it leaves)
- Draggable sticker or item — useDrag

**Needs animation?** (Yes/No):

**If Yes**:

Which animation hooks does this view need?

| Hook | Use case |
|---|---|
| `useSpring` | Animate properties (Position, Size, Transparency) toward targets with spring physics |
| `useSpringNumber` | Animate numeric displays (Robux total, counts, score) — re-renders only when displayed digit changes |
| `useTransition` | Enter/exit animations for items appearing/disappearing, supports stagger via `trail` |
| `useDrag` | Make an element draggable with momentum and spring-back |

**Selected hooks** (comma-separated):

**Note**: For enter/exit animation, call `useTransition` directly in the component that shows/hides the element. Full-panel open/close motion is owned by the panel (a later task, also built on `useTransition` / `useSpring`) — screens don't animate their own mount.

### Step 5H: Props Definition

Based on the patterns detected, what props will this component receive?

If this is a **panel screen**, `FullPanel`'s `currentScreen` renders it inside the content area (below the breadcrumbs) and passes `{ nav, look, ... }` — plus any id from the stack entry (e.g. `storeId = top.id`). The panel chrome (tabs, close, left column) is already there; the screen only draws its content.

If this is a **world-HUD element**, `WorldHud` renders it and passes what it needs from its own `nav` / `look` props.

Server state is observed with `useBoltState` in `Hud.luau` and passed down — not subscribed in the screen.

### Step 6H: Review & Confirm

I'll display a comprehensive summary showing:
- View name and file location
- **View type**: HUD (react-luau component)
- **Panel screen / world-HUD** placement
- **Detected Pattern**: A, B, C, or B+C with explanation
- Actions to send (if Pattern B)
- States to observe (if Pattern C) with model scope and state format
- Props definition
- Routing / wiring instructions (FullPanel `currentScreen` + navigation, or WorldHud)

**Proceed with generation?** (Yes/No/Edit)

---

## Workspace View Path

*Only shown if view type is Workspace*

### Step 2W: CollectionService Tag

What CollectionService tag will this view target?

**Important**: This tag will be applied to instances in Roblox Studio. Tags are **case-sensitive**!

**Examples**:
- MonolithView — Tag: "Monolith" (illustrative)
- WorldRenderer — Tag: "WorldFloor" (real; the floor parts it recolours)

**Tag name**:

### Step 3W: Target Instance Type

What type of instance will be tagged?

**Common types**:
- **Part** — Single 3D part
- **Model** — Group of parts
- **Other** — Specify custom type

**Instance type**:

### Step 4W: User Actions (Pattern B Detection)

Does this view need to send user actions to the server?

**Examples that send actions**:
- Monolith with proximity prompt (illustrative) — Sends "AddMany" to BasketController with the monolith's featured items
- PurchaseView (real, untagged) — Sends "Finished" to PurchaseController when the purchase prompt closes

**Examples that DON'T send actions**:
- FlightView / SprintView — Client-only movement
- WorldRenderer — Only applies state to tagged floor parts

**Send user actions to server?** (Yes/No):

**If Yes**:

Which controller will handle these actions?

I will read Network.luau to validate this controller exists and show you available options.

**Controller name** (without "Controller" suffix):

**Action details**:

For each action this view will send:
1. **Action name** (e.g., "Purchase", "Donate", "Interact")
2. **What triggers it?** (ProximityPrompt, ClickDetector, touch, etc.)
3. **Parameters** (if any — name and type for each)

How many actions will this view send? (1-5):

[For each action, ask: Action name, trigger, parameters]

### Step 5W: State Observation (Pattern C Detection)

Does this view need to display or react to server state changes?

**Examples that observe state**:
- Monolith (illustrative) — Observes Basket to hide its prompt once its items are in
- WorldRenderer (real) — Applies WorldOptions state to every `"WorldFloor"` part
- Auction plinth (illustrative) — Observes a ServerEntity lots dictionary to spawn/remove display models

**Examples that DON'T observe state**:
- One-shot particle effect — Just plays particles, no state to track

**Observe server state?** (Yes/No):

**If Yes**:

Which model's state will this view observe?

I will read Network.luau to validate this state exists and show you available options.

**State name** (without "State" suffix):

**What is the model's scope?**

**IMPORTANT**: The state format depends on the model scope AND its syncScope:
- **User / UserSession, syncScope="owner"** (default, e.g., BasketModel, OwnershipModel) — Single state object, sent to owner only
- **User, syncScope="all"** (none in-repo; hypothetical PowerUpModel) — Dictionary `{ [ownerId]: State }`, broadcast to all
- **Server** (none in-repo; hypothetical LeaderboardModel) — Single state object, broadcast to all
- **UserEntity** (none in-repo; hypothetical PetsModel) — Dictionary `{ [entityId]: State }`, sent to owner only
- **ServerEntity** (none in-repo; hypothetical AuctionLotsModel) — Dictionary `{ [entityId]: State }`, broadcast to all

**Model scope** (User/Server/UserEntity/ServerEntity):

**If User scope: Does it use syncScope="all"?** (Yes/No):

**Which properties from this state will you use?**

**Properties** (comma-separated):

### Step 6W: Immediate Feedback (Pattern A Detection)

Does this view need immediate visual or audio feedback (particles, sounds, animations)?

**Examples**:
- Particle burst when clicking a button
- Sound effect on proximity prompt trigger
- Tween animation on a monolith's SurfaceGui

**Immediate feedback?** (Yes/No):

**If Yes**:
- **Feedback types**: particles, sound, tween, other (comma-separated)
- **When triggered**: (e.g., "on proximity prompt", "when state changes")

### Step 7W: Expected Children

What child instances does this view expect to find under the tagged instance?

**Important**:
- The ROOT instance gets the CollectionService tag
- Children are accessed by name using WaitForChild()
- Names must match EXACTLY (case-sensitive)

For each child:
1. **Child name** (exact name as it will appear in Studio)
2. **Child type** (ProximityPrompt, Sound, ParticleEmitter, Part, etc.)

**How many children?** (0-10):

[For each child, ask: name and type]

### Step 8W: Review & Confirm

I'll display a comprehensive summary showing:
- View name and file location
- **View type**: Workspace (imperative LocalScript)
- CollectionService tag and instance type
- **Detected Pattern**: A, B, C, or B+C with explanation
- Actions to send (if Pattern B)
- States to observe (if Pattern C) with model scope and state format
- Immediate feedback (if Pattern A)
- Expected hierarchy with children
- Studio setup requirements

**Proceed with generation?** (Yes/No/Edit)

---

## Implementation Details (Internal)

When generating the view, I will:

### 1. Read Reference Files

Use Read tool on:
- **Network.luau** to:
  - Validate controller exists in NetworkConfig.Controllers
  - Validate state exists in NetworkConfig.States
  - Extract available actions for the controller
  - Extract available properties for the state
  - Generate type-safe Network.Actions and Network.State references
- **Hud.luau**, **panel/FullPanel.luau** and **WorldHud.luau** (HUD path only) to:
  - Understand current wiring (navigation, props, `currentScreen` routing)
  - Determine where to add the new screen's route, or the new world-HUD element
- **screens/Parts.luau** and the skin kit components (HUD path only) to reuse existing parts rather than restyle

### 2. Pattern Detection

Determine pattern based on user responses:

```lua
if (sendsActions AND observesState):
    pattern = "B+C" -- Combination
    description = "Sends intents to controller AND observes model state"
elif (sendsActions):
    pattern = "B" -- Intent-Based
    description = "Sends intents to controller for server validation"
elif (observesState):
    pattern = "C" -- State Observation
    description = "Observes model state changes and updates UI"
else:
    pattern = "A" -- Pure Client-Side
    description = "Pure client-side feedback with no server communication"
```

### 3. Generate View File

#### HUD View — React Component

**Location** (ModuleScript, NOT `.client.luau`):
- Panel screen: `Source/ReplicatedFirst/views/screens/{ViewName}.luau`
- World-HUD element: `Source/ReplicatedFirst/views/{ViewName}.luau`

**Skin rules** (the HUD renders under `SkinRoot`'s canvas `UIScale`):
- Author in design px (1180×820 canvas) and convert through `useSkin().px` / `skin.textPx`; take sizes, colours and type styles from `Tokens`
- Size text explicitly with `ShadowText` (or `hooks/useTextWidth`) — no `AutomaticSize` / `AutomaticCanvasSize` under the canvas (they come out scale× wrong); measure containers with `hooks/useLocalSize`
- Reuse skin-kit components (`PillButton`, `GlassPanel`, `Badge`, `TextTab`, `Chip`, `Icon`) and `screens/Parts` before writing new ones

**Template**:

```lua
--!strict

--[[
    {ViewName}

    Pattern: {DetectedPattern}
    Purpose: {HighLevelDescription}

    Props:
        {propName}: {propType}
        ...
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

-- Panel screen: views = script.Parent.Parent; world-HUD element: views = script.Parent
local views = script.Parent.Parent
local hooks = views:WaitForChild("hooks")
local components = views:WaitForChild("components")
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local ShadowText = require(components:WaitForChild("ShadowText"))

local e = React.createElement

{If Pattern C and state is consumed directly in this component (not passed as props from Hud):}
local useBoltState = require(hooks:WaitForChild("useBoltState"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

{If Pattern B:}
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local {controller}Intent = Network.Intent.{Controller}

export type Props = {
    {propName}: {propType},
    ...
}

local function {ViewName}(props: Props)
    local skin = useSkin()

    {If Pattern C with useBoltState:}
    local stateData = useBoltState(Network.State.{Model}, {defaultValue})

    {If Pattern B - button handler:}
    local function on{Action}()
        {controller}Intent:FireServer(Network.Actions.{Controller}.{Action}{, params})
    end

    return e("Frame", {
        Name = "{ViewName}",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, {
        Title = e("Frame", {
            Size = UDim2.new(1, 0, 0, skin.px(24)),
            BackgroundTransparency = 1,
        }, {
            Text = e(ShadowText, { text = "{Title}", style = Tokens.type.cardTitle }),
        }),
        {-- child elements: PillButton, GlassPanel, Parts.CardGrid / Parts.ItemCard / Parts.ListRow, ...}
    })
end

return {ViewName}
```

**If animation hooks are needed**, add the relevant imports and usage:

```lua
{If useSpring:}
local useSpring = require(hooks:WaitForChild("useSpring"))

-- In the component body:
local springProps = useSpring({
    Position = if isOpen then UDim2.new(0.5, 0, 0.5, 0) else UDim2.new(0.5, 0, 1.5, 0),
    BackgroundTransparency = if isOpen then 0 else 1,
}, {
    force = 200,
    dampening = 20,
})

-- Bind spring values directly to element properties:
return e("Frame", {
    Position = springProps.Position,
    BackgroundTransparency = springProps.BackgroundTransparency,
})

{If useSpringNumber — for currency/number displays:}
local useSpringNumber = require(hooks:WaitForChild("useSpringNumber"))

-- In the component body:
local displayTotal = useSpringNumber(props.robuxTotal, {
    force = 120,
    dampening = 14,
})

return e("TextLabel", {
    Text = `{displayTotal} Robux`,
})
```

**Note**: Elements that need enter/exit animation use `useTransition` directly (boolean mode keeps the element mounted through its `"leaving"` phase). Don't add mount animation to panel screens — the panel owns its own open/close motion.

**After generating the component**, provide wiring instructions:

**If panel screen**:
1. Add `local {ViewName} = require(screens:WaitForChild("{ViewName}"))` to `panel/FullPanel.luau`
2. Route it in `currentScreen`: a new stack-entry kind (`elseif top.kind == "{kind}" then return e({ViewName}, { nav = nav, look = look, {id} = top.id })`) or, for a new root, a `nav.root == ...` branch (and a `Root` value in `hooks/useNavigation`)
3. Navigate to it with `useNavigation` from wherever the player opens it: `props.nav.push({ kind = "{kind}", id = {id}, label = "{CrumbLabel}" })`, or `nav.toggleTab` / `nav.openRoot` for a root
4. If it needs server state, add the `useBoltState` call in `Hud.luau` and pass it through `FullPanel` to the screen

**If world-HUD element**:
1. Add `local {ViewName} = require(views:WaitForChild("{ViewName}"))` to `WorldHud.luau`
2. Render `{ViewName} = e({ViewName}, { ... })` in WorldHud's tree, positioned in design px via `skin.px` (keep the top-left clear for Roblox's top bar — see `useSystemBarInset`)
3. Pass what it needs from WorldHud's `nav` / `look` props (or add a prop from `Hud`)

#### Workspace View — Imperative LocalScript

**Location**: `Source/ReplicatedFirst/views/{ViewName}.client.luau` (LocalScript)

**Template**:

```lua
--!strict

--[[
    {ViewName}

    Pattern: {DetectedPattern}
    Purpose: {HighLevelDescription}

    {If Pattern B:}
    Sends Intents:
      - Network.Intent.{Controller}:FireServer(Network.Actions.{Controller}.{Action}, params...)

    {If Pattern C:}
    Observes State:
      - Network.State.{Model}:Observe() - Updates when {properties} change

    Expected Hierarchy:
    {RootInstanceType} [{RootInstanceName}] (Tagged: "{TagName}")
    {For each child:}
    +-- {ChildName} ({ChildType})
    {End for}

    Studio Setup:
    1. Create {RootInstanceType} in Workspace
    2. Add children: {ChildNames}
    3. Apply CollectionService tag "{TagName}" to ROOT instance only
    4. Names must match exactly (case-sensitive)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
{If B:}local Players = game:GetService("Players")

{If B or C:}local Network = require(ReplicatedStorage:WaitForChild("Network"))

{If B:}local localPlayer = Players.LocalPlayer
{If B:}local {controller}Intent = Network.Intent.{Controller}
{If C:}local {model}State = Network.State.{Model}

local TAG = "{TagValue}"

{If A with constants:}local {CONSTANT_NAME} = {value}

local function setup{InstanceType}(instance: Instance)
    {For each child:}
    local {childName} = instance:WaitForChild("{ChildName}") :: {ChildType}

    {If B - connect interactions:}
    {trigger}.{Event}:Connect(function({eventParams})
        {If localPlayer check needed:}
        if {param} ~= localPlayer then
            return
        end

        {If A - immediate feedback:}
        -- Immediate visual/audio feedback
        {feedbackCode}

        -- Send intent to server
        {controller}Intent:FireServer(
            Network.Actions.{Controller}.{Action}{, params}
        )
    end)

    {If C - observe state:}
    {model}State:Observe(function(data: Network.{Model}State)
        -- Update visuals with state
        {updateCode}
    end)
end

for _, instance in CollectionService:GetTagged(TAG) do
    task.spawn(setupInstance, instance)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
    task.spawn(setupInstance, instance)
end)
```

### 4. Pattern-Specific Code Examples

**HUD Pattern A — Pure Client Feedback:**
```lua
local function EffectView(props: Props)
    return e("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
    }, {
        -- Animation or visual-only elements
    })
end
```

**HUD Pattern B — Intent-Based:**
```lua
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local basketIntent = Network.Intent.Basket

local function AddToBasketButton(props: Props)
    local function onAdd()
        basketIntent:FireServer(Network.Actions.Basket.Add, { targetId = props.targetId, kind = props.kind })
    end

    return e("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
    }, {
        AddButton = e("TextButton", {
            Text = "Add to basket",
            [React.Event.Activated] = onAdd,
        }),
    })
end
```

**HUD Pattern C — State Observation:**
```lua
local useBoltState = require(script.Parent:WaitForChild("hooks"):WaitForChild("useBoltState"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local function BasketCount(props: Props)
    local basket = useBoltState(Network.State.Basket, { ownerId = "", items = {} })

    return e("TextLabel", {
        Text = `{#basket.items} in basket`,
    })
end
```

**HUD Pattern B+C — Combination:**
```lua
local useBoltState = require(script.Parent:WaitForChild("hooks"):WaitForChild("useBoltState"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local basketIntent = Network.Intent.Basket

local function BasketBar(props: Props)
    local basket = useBoltState(Network.State.Basket, { ownerId = "", items = {} })

    local function onClear()
        basketIntent:FireServer(Network.Actions.Basket.Clear)
    end

    return e("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
    }, {
        CountLabel = e("TextLabel", {
            Text = `{#basket.items} in basket`,
        }),
        ClearButton = e("TextButton", {
            Text = "Clear",
            [React.Event.Activated] = onClear,
        }),
    })
end
```

**HUD Pattern C — Screen built from the skin kit (dictionary state):**
```lua
-- Illustrative: Hud calls useBoltState at top level and passes the dictionary
-- down through FullPanel. Built like StoresScreen's store page: Parts.CardGrid
-- sizes its cells and scroll extent from measured width (no AutomaticSize).
local Parts = require(script.Parent:WaitForChild("Parts"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))

export type Props = {
    nav: any,
    look: any,
    itemsData: { [string]: PlaceholderData.Item }, -- keyed by entityId
}

local function YourItemsScreen(props: Props)
    local cards: { [string]: any } = {}
    local count = 0
    for entityId, item in props.itemsData do
        count += 1
        cards["Item" .. entityId] = e(Parts.ItemCard, {
            item = item,
            wearing = props.look.isWorn(item.id),
            inBasket = props.look.inBasket(item.id),
            layoutOrder = item.id, -- dictionaries are unordered: sort by something stable
            onActivated = function()
                props.nav.push({ kind = "item", id = item.id, label = item.name })
            end,
        })
    end

    return e(Parts.CardGrid, {
        columns = 6,
        extraHeight = 40, -- design px below each square cell for name + price
        count = count,
    }, cards)
end
```

**Workspace Pattern A — Pure Client Feedback:**
```lua
local function setupPart(part: Instance)
    local proximityPrompt = part:WaitForChild("ProximityPrompt") :: ProximityPrompt
    local particleEmitter = part:WaitForChild("ParticleEmitter") :: ParticleEmitter
    local sound = part:WaitForChild("Sound") :: Sound

    proximityPrompt.Triggered:Connect(function(player: Player)
        if player ~= localPlayer then
            return
        end
        particleEmitter:Emit(20)
        sound:Play()
    end)
end
```

**Workspace Pattern B — Intent-Based:**
```lua
-- Illustrative: a "Monolith"-tagged model; featuredItemsOf reads its { targetId, kind } list
local function setupMonolith(monolith: Instance)
    local prompt = monolith:WaitForChild("ProximityPrompt") :: ProximityPrompt

    prompt.Triggered:Connect(function(player: Player)
        if player ~= localPlayer then
            return
        end
        basketIntent:FireServer(Network.Actions.Basket.AddMany, featuredItemsOf(monolith))
    end)
end
```

**Workspace Pattern C — State Observation (ServerEntity Spawner; illustrative — no ServerEntity model in-repo yet):**
```lua
local lotsState = Network.State.AuctionLots
local lotTemplate = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("AuctionLot")
local spawnedLots: { [string]: Model } = {}

type AuctionLotsStateDictionary = { [string]: Network.AuctionLotsState }

local function spawnLot(entityId: string, data: Network.AuctionLotsState)
    if spawnedLots[entityId] then
        return
    end
    local lot = lotTemplate:Clone() :: Model
    lot:PivotTo(CFrame.new(data.positionX, data.positionY, data.positionZ))
    lot.Parent = Workspace
    spawnedLots[entityId] = lot
end

lotsState:Observe(function(allLots: AuctionLotsStateDictionary)
    for entityId, lotData in allLots do
        spawnLot(entityId, lotData)
    end
    for entityId, _ in spawnedLots do
        if not allLots[entityId] then
            spawnedLots[entityId]:Destroy()
            spawnedLots[entityId] = nil
        end
    end
end)
```

**Workspace Pattern B+C — Combination:**
```lua
-- Illustrative: the Pattern B monolith, hiding its prompt once its items are in the basket
local function setupMonolith(monolith: Instance)
    local base = monolith:WaitForChild("Base")
    local proximityPrompt = base:WaitForChild("ProximityPrompt") :: ProximityPrompt
    local sound = base:WaitForChild("Sound") :: Sound
    local featured = featuredItemsOf(monolith) -- { { targetId: number, kind: "Asset" | "Bundle" } }

    proximityPrompt.Triggered:Connect(function(player: Player)
        if player ~= localPlayer then
            return
        end
        sound:Play()
        basketIntent:FireServer(Network.Actions.Basket.AddMany, featured)
    end)

    basketState:Observe(function(data: Network.BasketState)
        local inBasket = {}
        for _, item in data.items do
            inBasket[item.kind .. ":" .. item.targetId] = true
        end
        local missing = false
        for _, ref in featured do
            if not inBasket[ref.kind .. ":" .. ref.targetId] then
                missing = true
            end
        end
        proximityPrompt.Enabled = missing
    end)
end
```

### 5. Validation During Generation

Before finalizing:
- **Both types**: --!strict pragma at top of file
- **Both types**: Pattern matches user's stated needs
- **Both types**: Controllers and states validated against Network.luau
- **Both types**: Network.Actions constants used for type-safe action dispatch
- **Both types**: Type annotations include Network exported types
- **HUD**: Component is a function returning React elements
- **HUD**: Props type is exported
- **HUD**: useBoltState used correctly (not raw :Observe())
- **HUD**: React.Event used for button interactions (not .Activated:Connect)
- **HUD**: Routing / wiring instructions are complete and correct (FullPanel `currentScreen` + navigation, or WorldHud)
- **HUD**: Design px go through `useSkin().px`; text is sized with `ShadowText` / `useTextWidth` (no `AutomaticSize` / `AutomaticCanvasSize`)
- **HUD**: Existing skin-kit components and `screens/Parts` are reused where they fit
- **HUD (animated)**: Verify animations play on state changes (spring targets update when observed state changes)
- **HUD (animated)**: Verify spring settles (no infinite oscillation — dampening must be > 0)
- **HUD (animated, drag)**: Verify `React.Event.InputBegan` fires on the drag target (bind `dragBind.onInputBegan`)
- **Workspace**: CollectionService used directly (NOT AbstractView)
- **Workspace**: GetTagged + GetInstanceAddedSignal pattern used
- **Workspace**: task.spawn wraps setup calls
- **Workspace**: All children accessed via WaitForChild with type annotations

### 6. Testing Instructions

After generation, provide:

#### HUD View Completion Output

```
View Generation Complete!

Created Files:
  Source/ReplicatedFirst/views/{screens/ if panel screen}{ViewName}.luau

View Type: HUD (react-luau component)
Pattern Detected: {Pattern} ({PatternDescription})
Placement: {Panel screen / World HUD}

{If Pattern B:}
Network Integration:
  Network.Intent.{Controller} — Bolt ReliableEvent for sending intents
  Network.Actions.{Controller}.{Action} — Type-safe action constants

{If Pattern C:}
Network Integration:
  Network.State.{Model} — Bolt RemoteProperty for state observation
  Network.{Model}State — Type definition for state data
  Observed via: useBoltState hook

Wiring Required:

  {If panel screen:}
  1. Add require to panel/FullPanel.luau:
     local {ViewName} = require(screens:WaitForChild("{ViewName}"))

  2. Route it in currentScreen:
     elseif top.kind == "{kind}" then
         return e({ViewName}, { nav = nav, look = look, {id} = top.id })

  3. Navigate to it (useNavigation):
     props.nav.push({ kind = "{kind}", id = {id}, label = "{CrumbLabel}" })

  4. (If server state) useBoltState in Hud.luau, pass down through FullPanel

  {If world HUD:}
  1. Add require to WorldHud.luau:
     local {ViewName} = require(views:WaitForChild("{ViewName}"))

  2. Render it in WorldHud's tree:
     {ViewName} = e({ViewName}, { ... }),

  3. Pass required props from WorldHud's nav / look (or a new prop from Hud)

Testing:
  1. Start Play mode (F5)
  2. Check that the HUD renders without errors in Output
  {If panel screen:}
  3. Navigate to the screen; check the breadcrumbs show its label and Back returns
  4. Verify layout at a few window sizes (phone/landscape/ultrawide) — text not clipped or offset
  {If Pattern C:}
  3. Verify state updates render in the UI
  {If Pattern B:}
  3. Click action buttons and check server Output for controller processing

  {If animated:}
  3. Verify animations play on state changes (e.g., spring moves to new target)
  4. Verify spring settles — no infinite oscillation
  {If drag:}
  5. Verify InputBegan fires on the drag target (element should follow pointer)

Common Issues:

  "Component not rendering"
  - Check: Panel screen — is there a currentScreen branch in panel/FullPanel.luau for its kind/root?
  - Check: World HUD — is it rendered in WorldHud.luau's tree?
  - Check: Does the export type Props match what FullPanel / WorldHud passes?

  "useBoltState returns default value"
  - Check: Is the Network.State.{Model} key correct?
  - Check: Has the model synced state to this player?

  {If Pattern B:}
  "Intent not working"
  - Check: Is Network.Intent.{Controller} correct?
  - Check: Are you using Network.Actions.{Controller}.{Action} constant?

  {If panel screen:}
  "Screen not opening"
  - Check: Does the nav.push entry's kind match the currentScreen branch exactly?
  - Check: Is the panel open (nav.root set)? push only adds to an open panel's stack

  "Text too wide / shifted"
  - Check: No AutomaticSize on text under the canvas — use ShadowText / useTextWidth
```

#### Workspace View Completion Output

```
View Generation Complete!

Created Files:
  Source/ReplicatedFirst/views/{ViewName}.client.luau

View Type: Workspace (imperative LocalScript)
Pattern Detected: {Pattern} ({PatternDescription})

{If Pattern B:}
Network Integration:
  Network.Intent.{Controller} — Bolt ReliableEvent for sending intents
  Network.Actions.{Controller}.{Action} — Type-safe action constants

  Actions this view sends:
    {For each action:}
    - {ActionName}({parameters})

{If Pattern C:}
Network Integration:
  Network.State.{Model} — Bolt RemoteProperty for state observation
  Network.{Model}State — Type definition for state data

  Properties observed: {propertyList}

Studio Setup Requirements:

  IMPORTANT: Follow these steps EXACTLY in Roblox Studio

  1. Create the root instance
     - Type: {RootInstanceType}
     - Location: Workspace
     - Name: {SuggestedName} (or any name you prefer)

  2. Add required children

     Expected hierarchy:
     {RootInstanceType} [{ExampleName}]
     {For each child:}
     +-- {ChildName} ({ChildType})
     {End for}

     Child names must match EXACTLY (case-sensitive!)

  3. Apply CollectionService tag
     - Open Tags window: View > Tags (or press Alt+T)
     - Select the ROOT instance only ({RootInstanceType})
     - Add tag: "{TagName}"
     - Tag is case-sensitive! Must be exactly "{TagName}"
     - DO NOT tag the children, only the root instance

  4. Save and test
     - Save the place
     - Start Play mode (F5)
     - Check Output window for:
       "{ViewName}: Initialized"

Testing:
  1. Verify the view initializes (check Output for print message)
  2. Verify tagged instances are found

  {If Pattern B:}
  3. Trigger the action (proximity prompt, click, etc.)
  4. Check server Output for controller processing

  {If Pattern C:}
  3. Change the model state from server
  4. Verify visuals update automatically

  {If Pattern A:}
  3. Trigger the feedback (click, proximity, etc.)
  4. Verify particles, sounds, or animations play

Common Issues:

  "View not initializing"
  - Check: Is the tag spelled exactly "{TagName}"? (case-sensitive)
  - Check: Is the tag on the ROOT instance, not children?
  - Check: Did you save the place after adding the tag?

  "WaitForChild timeout error"
  - This is INTENTIONAL — it means hierarchy is incorrect
  - Check: Do child names match exactly? (case-sensitive)
  - Check: Are children actually present under the tagged instance?

  {If Pattern B:}
  "Intent not working"
  - Check: Is the controller initialized? (check server Output)
  - Check: Are you using Network.Actions.{Controller}.{Action} constant?

  {If Pattern C:}
  "State not updating"
  - Check: Is the model initialized? (check server Output)
  - Check: Is the model calling syncState() after changes?
  - Check: Is Network.State.{Model} available? (check client Output)

  "Observe fires but nothing happens" (Entity-scoped models)
  - Check: Is this a UserEntity or ServerEntity scoped model?
  - Fix: Entity-scoped models send { [entityId]: State } dictionary, not single object
  - Fix: Iterate the dictionary: for entityId, data in allEntities do ... end

  "Observe fires but shows wrong player's data" (User + syncScope="all" models)
  - Fix: User+all models send { [ownerId]: State } dictionary to ALL players
  - Fix: Index by local player: local myState = data[tostring(localPlayer.UserId)]
```

---

## Important Reminders

- Views run on CLIENT — display and feedback only
- NEVER trust client data — server always validates
- Use Network.Actions constants, not magic strings
- **HUD views**: React components (.luau ModuleScripts) under Hud.luau — panel screens in views/screens/ routed by FullPanel, or world-HUD elements in WorldHud
- **Workspace views**: Imperative LocalScripts (.client.luau), use CollectionService directly
- AbstractView has been removed — do NOT reference it
- There are no modals: the full panel + useNavigation handle what's on screen (React state in Hud, not tags)

---

## Let's Start!

Please provide the following information to begin:

**1. View Name** (must end with "View"):

**1.5. View Type** (HUD or Workspace):
