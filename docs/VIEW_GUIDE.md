# View Development Guide

This guide explains how to create Views in this Roblox MVC project.

## What is a View?

Views are client-side scripts that handle visual feedback, audio, and user interactions. There are two types:

- **HUD views** (ScreenGui/UI): React-luau components that render 2D interface elements. Built as ModuleScripts (`.luau`) and composed under the root component `Hud.luau`, which `HudApp.client.luau` mounts into its own ScreenGui via ReactRoblox.
- **Client scripts / workspace views**: Imperative LocalScripts (`.client.luau`) for things outside the React tree — Roblox callbacks and the player's own character (`PurchaseView`, `FlightView`, `SprintView`). A workspace view of this kind uses CollectionService to find tagged instances in the 3D world and wire up interactions, tweens, and particle effects (the planned diegetic "monoliths", see `docs/PROJECT_BRIEF.md`; no view in the repo does this yet).

Both types observe game state and provide immediate user feedback while the server remains the authority for state changes.

## Architecture Overview

### HUD Views (React-Luau)

HUD views are React function components. A single entry point (`HudApp.client.luau`) creates its own `HudApp` ScreenGui in PlayerGui and mounts the root component `Hud.luau` into it. All HUD state flows through React:

- **State**: `useBoltState` hook bridges Bolt RemoteProperty into React state
- **Data flow**: Props flow down from `Hud` to `WorldHud`, `panel/FullPanel` and the screens
- **Navigation**: `hooks/useNavigation` in `Hud` decides whether the world HUD or the full-screen panel is shown, and which screen the panel displays (one panel, a breadcrumb stack of screens — no modals)
- **View-to-view communication**: React props and callbacks (no BindableEvents)

### Client Scripts and Workspace Views (Imperative)

These are standalone LocalScripts. A workspace view uses CollectionService to find tagged 3D instances and set up interactions directly:

- **State**: `Network.State.*:Observe()` callbacks update local variables
- **Interactions**: ProximityPrompts, tweens, particle emitters
- **Data flow**: Each script manages its own state and connections

## View Patterns

Views follow one of three patterns (or a combination). The decision tree applies to both HUD and workspace views.

### Pattern A: Pure Client-Side Feedback
- No server communication
- Immediate visual/audio response only
- Example: Particle effects, sound effects, camera shake, tween animations
- In repo: FlightView and SprintView (client scripts moving the player's own character, which replicates on its own)

### Pattern B: Intent-Based with Server Validation
- Send intent to Controller via Bolt ReliableEvent (`Network.Intent.*`)
- Provide immediate feedback (particles, sounds)
- Wait for server confirmation before showing final state
- Examples:
  - **Client script**: PurchaseView (hears `MarketplaceService.PromptBulkPurchaseFinished` and passes the outcome to PurchaseController's `Finished` intent)

### Pattern C: State Observation and UI Updates
- Observe Model state changes via Bolt RemoteProperty (`Network.State.*:Observe()`)
- Update display based on authoritative server state
- `Observe()` fires immediately with current state, then on every update
- Bolt handles per-player filtering automatically for User-scoped models
- Examples:
  - **HUD**: WorldHud (renders the Basket button's Robux badge from the `look` prop that `Hud` owns — placeholder state today, a `useBoltState` subscription in `Hud` once the server models land)
  - **HUD**: the full-panel screens (`screens/*`) receive `nav` and `look` as props from `FullPanel`, never subscribing themselves
  - **World**: WorldRenderer (a React component that renders nothing: it applies the World options state to Lighting and to the parts tagged `WorldFloor`)

### Pattern B + C: Combination
- User actions (Pattern B) plus state observation (Pattern C) in the same feature
- Examples:
  - **HUD**: `hooks/useWorldOptions` + WorldOptionsView (observes `Network.State.WorldOptions`, sends `Set` / `Reset` intents)
  - **HUD**: `screens/usePlaceholderLook` (observes Basket / Favourites / Ownership state, sends Basket, Favourites and Purchase intents)

### Decision Tree

```
Does view need server communication?
+-- No --> Pattern A (Pure Client)
+-- Yes --> Does view send user actions?
    +-- No --> Pattern C (State Observation)
    +-- Yes --> Does view also observe state?
        +-- No --> Pattern B (Intent-Based)
        +-- Yes --> Pattern B + C (Combination)
```

### Common Mistakes

- **Using Pattern A for game state changes** -- Do not update UI based on client predictions alone. Always wait for server confirmation for authoritative state.
- **Using Pattern B without considering state updates** -- If your view displays changing data, you likely need Pattern C too. Separate concerns: interaction (B) + display (C).
- **Not filtering ownerId for "all" scope broadcasts** -- Server-scoped models broadcast to all players. Views must filter to show only relevant data when needed.

## React-Luau HUD Architecture

### File Structure

```
Source/ReplicatedFirst/views/
+-- HudApp.client.luau           -- Entry point: creates its own "HudApp" ScreenGui, mounts Hud into it
+-- Hud.luau                     -- Root component: SkinRoot, navigation, look state; WorldHud or FullPanel
+-- WorldHud.luau                -- HUD over the world: tab bar, Basket (+ Robux badge), Create / Save / Reset, World options toggle
+-- WorldOptionsView.luau        -- World options side panel
+-- WorldRenderer.luau           -- Applies World options to Lighting + "WorldFloor"-tagged parts (renders nothing)
+-- panel/
|   +-- FullPanel.luau           -- The one full-screen panel: tabs, close, left column, content area, screen routing
|   +-- Breadcrumbs.luau         -- Back button + crumb row for the navigation stack
+-- screens/                     -- What the panel shows (placeholder data for now)
|   +-- CatalogueScreen.luau     -- Catalogue tab root
|   +-- ItemScreen.luau          -- Item page
|   +-- StoresScreen.luau        -- { Root, Store }
|   +-- OutfitsScreen.luau       -- { Root, Outfit }
|   +-- ListScreens.luau         -- { Basket, Wearing }
|   +-- Parts.luau               -- Shared parts: Thumb, PriceTag, ItemCard, ListRow, CardGrid, Heading
|   +-- PlaceholderData.luau     -- Placeholder catalogue/stores/outfits
|   +-- usePlaceholderLook.luau  -- Placeholder worn/basket state until the server models land
+-- components/                  -- Skin kit components (see "Skin kit" below)
+-- hooks/
    +-- useBoltState.luau        -- Bolt RemoteProperty --> React state bridge
    +-- useNavigation.luau       -- Full-panel root + breadcrumb stack
    +-- useLocalSize.luau        -- Measure a GuiObject in local/design units (AbsoluteSize ÷ canvas scale)
    +-- useSpring / useTransition / ... -- Animation hooks (see "Animation")
```

The non-React client scripts (`PurchaseView`, `FlightView`, `SprintView` `.client.luau`) live in the same folder and are unaffected by the HUD structure.

### Skin kit (Ripple Avatar Creator)

The project's visual language lives in a small kit, built in Task 1 of
`features/cac-adaptation/PLAN.md` from the Claude Design mock in
`features/cac-adaptation/design/`. New HUD work should compose these rather than
restyling from scratch:

```
Source/ReplicatedFirst/views/
+-- Tokens.luau                  -- every colour, gradient, radius, size, type style, spring preset
+-- SkinAssets.luau              -- the one module holding image asset IDs (icons)
+-- SkinContext.luau             -- sizing mode, glass mode, scale (provided by SkinRoot)
+-- components/
|   +-- SkinRoot.luau            -- viewport root; owns the sizing decision; provides SkinContext
|   +-- PillButton.luau          -- glossy round/pill button: hover glow, 0.94 press, active orange
|   +-- PillTabs.luau            -- segmented top tab bar
|   +-- GlossFace.luau           -- the black/orange split-gradient fill both of the above use
|   +-- GlassPanel.luau          -- dark / bar / light glass surfaces
|   +-- Badge.luau               -- count badge (Robux) and marker badges (wearing / in basket)
|   +-- TextTab.luau             -- underlined text tab
|   +-- Chip.luau                -- outlined filter chip
|   +-- Icon.luau                -- Material Symbols Rounded glyph (one image per icon)
|   +-- ShadowText.luau          -- single-line label sized from useTextWidth, optional text-shadow
+-- hooks/
|   +-- useSkin.luau             -- px / stroke / textPx / fromScreen for the current sizing mode
|   +-- useInteraction.luau      -- hover + press state (touch-safe)
|   +-- useGlassBlur.luau        -- client-only scene blur behind full-screen panels
|   +-- useSystemBarInset.luau   -- real-pixel area of Roblox's top-bar buttons
|   +-- useTextWidth.luau        -- measured text width (TextService, cached) for explicit text sizing
```

- **Design pixels everywhere.** Components take the design's own px values
  (1180×820 canvas) and convert through `useSkin().px`, so the
  relative-vs-canvas sizing decision lives only in `SkinRoot`.
- **Fonts:** Nunito ships with Roblox: `Tokens.font(weight)` maps design weights
  600/700/800/900 to `Enum.FontWeight` SemiBold/Bold/ExtraBold/Heavy.
- **Icons:** one white 128px PNG per Material Symbols Rounded glyph
  (`assets/ui/icons/`, rebuilt by `tools/build_icons.py`), tinted with
  `ImageColor3`. Image asset IDs live in `SkinAssets`; an icon with no ID draws
  a deliberate placeholder.
- **No `AutomaticSize` for text under a `SkinRoot` canvas.** Under an ancestor
  `UIScale`, Roblox auto-sizes text from its on-screen bounds, so anything that
  auto-sizes after the scale is applied comes out scale× too wide (it shifted
  the tab labels in a freshly opened panel). Size text explicitly with
  `hooks/useTextWidth` — `ShadowText`, `TextTab`, `Chip` and `Badge` already do.
- **Gradients:** always on a white `BackgroundColor3` (pitfall 1). Gradient
  colours can't be sprung, so "active" crossfades a second face's
  transparency.
- **Roblox's top bar** is fixed-size in real pixels: lay out against
  `useSystemBarInset()` converted with `useSkin().fromScreen`, never a scaled
  design-px guess.

### HudApp.client.luau -- Entry Point

HudApp is the single LocalScript that mounts the entire HUD. It creates its **own** ScreenGui and renders `Hud` into it:

```lua
local Hud = require(script.Parent:WaitForChild("Hud"))

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HudApp"
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local root = ReactRoblox.createRoot(screenGui)
root:render(React.createElement(Hud))
```

**Never `createRoot(PlayerGui)`.** React clears its container's existing children on first render, so mounting straight into PlayerGui deletes every other ScreenGui already there.

### Hud.luau -- Root Component

`Hud` is the root of the React tree. It:

1. Wraps everything in `SkinRoot` with the project's sizing decision (`sizing = "fill"`, `axis = "height"`, `glass = "blur"`)
2. Owns navigation state (`hooks/useNavigation`) and, until the server models land, the placeholder look (`screens/usePlaceholderLook`: what's worn / in the basket)
3. Renders `WorldHud` while the panel is closed and `panel/FullPanel` while it is open
4. Drives the scene blur behind the panel through a small `BlurDriver` that calls `hooks/useGlassBlur`

```lua
local function BlurDriver(props: { active: boolean })
	local skin = useSkin()
	useGlassBlur(props.active and skin.glass == "blur")
	return nil
end

local function Hud()
	local nav = useNavigation()
	local look = usePlaceholderLook()

	return e(SkinRoot, {
		sizing = "fill",
		axis = "height",
		glass = "blur",
	}, {
		Blur = e(BlurDriver, { active = nav.isOpen }),
		World = if nav.isOpen then nil else e(WorldHud, { nav = nav, look = look, tabs = TABS }),
		Panel = if nav.isOpen then e(FullPanel, { nav = nav, look = look, tabs = TABS }) else nil,
	})
end
```

When real server state arrives, `Hud` is where the `useBoltState` subscriptions go; the values are passed down as props like `look` is today.

### useBoltState Hook

`useBoltState` bridges Bolt RemoteProperty into React. It calls `Observe()`, which fires immediately with the current value and then on every update. The hook returns the current state value and triggers a React re-render on changes.

```lua
-- API: useBoltState(remoteProperty, initialValue) -> currentValue
-- From screens/usePlaceholderLook.luau (called by Hud; the values go down as the `look` prop):
local DEFAULT_BASKET = { items = {} }
local basketState = useBoltState(Network.State.Basket, DEFAULT_BASKET :: any)

-- From hooks/useWorldOptions.luau:
local saved = useBoltState(Network.State.WorldOptions, DEFAULT)
```

Implementation (`Source/ReplicatedFirst/views/hooks/useBoltState.luau`):

```lua
local function useBoltState<T>(remoteProperty: any, initialValue: T): T
    local state, setState = React.useState(initialValue)

    React.useEffect(function()
        local unsubscribe = remoteProperty:Observe(function(newValue: T)
            setState(newValue)
        end)

        return function()
            if type(unsubscribe) == "function" then
                unsubscribe()
            end
        end
    end, {})

    return state
end
```

Key points:
- Pass the Bolt `RemoteProperty` and a default value matching the state shape
- Returns the latest state value; React re-renders the component when it changes
- The `useEffect` cleanup function unsubscribes when the component unmounts
- No manual initial state request needed -- `Observe()` fires immediately

### Props Pattern

`Hud` owns the state and passes it down as props. `WorldHud`, `FullPanel` and every screen are pure renderers that receive `nav` (the `useNavigation` result) and `look` (worn / basket state) through props:

```lua
-- Hud passes navigation + look down
World = if nav.isOpen then nil else e(WorldHud, { nav = nav, look = look, tabs = TABS }),

-- WorldHud declares its props type
export type Props = {
	nav: any,
	look: any,
	tabs: { any },
}
```

### Full Panel and Navigation

There are no modals. Everything beyond the world HUD opens in **one** full-screen panel, `panel/FullPanel.luau`: tab bar and close button, a left column (avatar preview card with the Wearing bar, Basket card), and a content area showing breadcrumbs (`panel/Breadcrumbs.luau`) and then the current screen.

What the panel shows is driven by `hooks/useNavigation.luau`, held in `Hud`:

- `root` -- `"Catalogue" | "Stores" | "Outfits" | "Basket" | "Wearing"`, or `nil` when the panel is closed (`isOpen = root ~= nil`)
- `stack` -- deeper pages for the breadcrumbs; each entry is `{ kind, id, label }` and carries its own crumb label
- `toggleTab(tab)` -- open a tab with an empty stack; tapping the tab that's already open closes the panel
- `openRoot(root)` -- open Basket / Wearing (no toggle)
- `push(entry)`, `replaceTop(entry)`, `popTo(depth)`, `back()`, `close()`

**Adding a screen:**

1. Create the component in `views/screens/` taking `{ nav, look, ... }` props. Build it from the skin kit and `screens/Parts` (size text with `ShadowText` / `useTextWidth`, design px through `useSkin().px`).
2. Route it in `currentScreen` in `panel/FullPanel.luau` -- either a new `nav.root` value or a new stack-entry `kind`:

```lua
local function currentScreen(nav: any, look: any)
	local top = nav.top
	if top then
		if top.kind == "item" then
			return e(ItemScreen, { nav = nav, look = look, itemId = top.id })
		elseif top.kind == "store" then
			return e(StoresScreen.Store, { nav = nav, look = look, storeId = top.id })
		-- ... add your kind here
		end
	end
	if nav.root == "Catalogue" then
		return e(CatalogueScreen, { nav = nav, look = look })
	-- ... roots
	end
	return nil
end
```

3. Navigate to it with `useNavigation`: `nav.push({ kind = "store", id = store.id, label = store.name })` from another screen, or `nav.toggleTab` / `nav.openRoot` for a root.

`FullPanel` keys the screen by root + stack depth + top label, so per-screen state (category, sort, scroll) resets when you navigate. Panel open/close motion arrives in a later task via the existing `useTransition` / `useSpring` hooks.

## Animation

The project includes a spring physics animation system built on React bindings. Animations run on `RenderStepped` and update Instance properties directly — no re-renders during motion.

### Spring Physics Config (SpringSolver.luau)

SpringSolver is a pure math module (no React dependency) implementing a damped harmonic oscillator. It decomposes complex types (UDim2, Color3, Vector2) into number arrays, solves component-wise, then recomposes.

Config parameters:
- `force` — stiffness; how aggressively the spring moves toward the target
- `dampening` — friction; how quickly oscillation settles
- `mass` — inertia; higher values make the spring feel heavier

Default config: `{ force = 180, dampening = 20, mass = 1 }`

**Presets:**

| Use case | force | dampening | mass | Character |
|----------|-------|-----------|------|-----------|
| Modal open/close | 200 | 14 | 1 | Bouncy entrance |
| Modal leave | 300 | 30 | 1 | Fast overdamped exit |
| Tile stagger | 220 | 22 | 1 | Quick pop-in |
| Number tick | 120 | 24 | 1 | Smooth counting, no overshoot |
| Drag spring-back | 300 | 25 | 1 | Stiff physical return |

### useSpring (useSpring.luau)

Binding-based property animation. Animates a dictionary of properties toward target values. Returns React bindings that update Instance properties directly — zero re-renders during animation.

```lua
local springProps = useSpring({
    Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundTransparency = 0,
}, { force = 200, dampening = 20 })
-- springProps.Position and springProps.BackgroundTransparency are bindings
```

Pass `immediate = true` in the config to snap to target without animating.

### useSpringNumber (useSpringNumber.luau)

Animates a single number using spring physics. Returns a rounded integer via `useState` — re-renders only when the displayed digit changes. Used for currency displays and counters.

```lua
local displayAmount = useSpringNumber(props.amount, { force = 120, dampening = 24 })
```

### useTransition (useTransition.luau)

Enter/leave transitions with stagger. Manages delayed unmount so leaving elements animate out before removal.

**Boolean mode** (single item show/hide — panels):

```lua
local transitions = useTransition(isVisible, {
    from = { BackgroundTransparency = 1, WindowYOffset = -50 },
    enter = { BackgroundTransparency = 0, WindowYOffset = 0 },
    leave = { BackgroundTransparency = 1, WindowYOffset = -50 },
    config = { force = 200, dampening = 14 },
    leaveConfig = { force = 300, dampening = 30 },
})
```

**List mode** (multiple items with stagger — grids):

```lua
local transitions = useTransition(items, {
    from = { BackgroundTransparency = 1 },
    enter = { BackgroundTransparency = 0 },
    leave = { BackgroundTransparency = 1 },
    trail = 40, -- ms between items
    keys = function(item) return item.id end,
    config = { force = 220, dampening = 22 },
})
```

Returns an array of `{ item, key, springProps, phase }`. Each `springProps` table contains bindings. `phase` is `"entering"`, `"entered"`, or `"leaving"`.

Separate `leaveConfig` allows fast overdamped exits while keeping bouncy entrances. Use `useTransition` directly in the component that shows/hides (boolean mode keeps it mounted through the `"leaving"` phase); the full panel's open/close motion will be built this way.

### useDrag (useDrag.luau)

Drag with momentum and spring-back. Tracks release velocity from a circular buffer of position samples and feeds it into the spring as initial velocity.

```lua
local dragBind, dragOffset = useDrag({ springBack = true, config = { force = 300, dampening = 25 } })
-- Bind: [React.Event.InputBegan] = dragBind.onInputBegan
-- Position: dragOffset:map(function(offset) return UDim2.new(0.5, offset.X, 0.5, offset.Y) end)
```

### CanvasGroup Pattern

Use `CanvasGroup` instead of `Frame` when you need `GroupTransparency` for uniform fade (e.g., fading an entire modal including all children).

Gotcha: `UIStroke` on a `CanvasGroup` does NOT fade with `GroupTransparency`. Put the stroke on a child `Frame` inside the `CanvasGroup` instead.

### File Locations

```
views/hooks/
  SpringSolver.luau      — Pure math, no React dependency
  useSpring.luau          — Binding-based property springs
  useSpringNumber.luau    — Number springs for text displays
  useTransition.luau      — Enter/leave/stagger transitions
  useDrag.luau            — Drag with momentum + spring-back
  useViewportScale.luau   — Viewport-height scale factor for residual pixels
```

## Responsive Scaling

Roblox games render on every aspect ratio from phone portrait to ultrawide PC. HUD views must **scale relatively**, not to fixed pixels. The mental model: an energy bar is "40% of the screen width" (`UDim2.fromScale(0.4, ...)`) at every resolution — never "268 px wide", which is huge on a phone and tiny on a 4K monitor.

**Default to `UDim2.fromScale`.** Size and position elements as fractions of their parent. Reserve `UDim2.fromOffset` (fixed pixels) for genuinely fixed things (a 1 px divider, an icon that must not scale) — and even then, prefer scaling the pixel value (see `useViewportScale` below).

**Fixed pixels everywhere is a code smell.** If a design hands you `width: 268px; top: 30px; font-size: 38px` with no `vh`/`vw`/`aspect-ratio`, that layout will break for most players. Convert it to relative sizing rather than translating `px` 1:1 to `fromOffset`. (The `/html-to-react-luau` skill's Phase 2a walks through exactly this.)

**Lock shapes with `UIAspectRatioConstraint`.** When an element must keep its proportions (a square avatar, a hex badge), give it a positive `Size` on both axes and add a `UIAspectRatioConstraint`. Note the trap: `Size = UDim2.fromScale(0, 1)` collapses to nothing — both axes need positive Scale (see the skill's pitfall #10).

**Residual pixels → `useViewportScale`.** A few things can't be a Scale UDim — `UIStroke.Thickness`, small `UICorner` radii, and `TextSize` derived from a `vh` design value. `useViewportScale()` returns `viewport.Y / 1080`; multiply your design-pixel value by it so those pixels stay proportional to the rest of the layout:

```lua
local useViewportScale = require(script.Parent:WaitForChild("hooks"):WaitForChild("useViewportScale"))

local function Badge()
    local scale = useViewportScale()
    return e("Frame", {
        Size = UDim2.fromScale(0.2, 0.1),
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, {
        Corner = e("UICorner", { CornerRadius = UDim.new(0, math.floor(12 * scale + 0.5)) }),
        Stroke = e("UIStroke", { Thickness = math.max(1, math.floor(3 * scale + 0.5)) }),
        Label = e("TextLabel", {
            -- CSS `font-size: 4vh` → 4% of a 1080 design height, scaled to viewport
            TextSize = math.max(10, math.floor(0.04 * 1080 * scale + 0.5)),
        }),
    })
end
```

**Caveat — `useViewportScale` is height-axis only.** It tracks viewport *height*, so it stays proportional only for elements that also scale with height (e.g. corner-pinned pieces in a viewport-filling root). It is **wrong** for pixels inside an aspect-locked, width-dominant container (a centred modal with `UIAspectRatioConstraint` + `DominantAxis.Width`) — there, drive scale off the container's own measured `AbsoluteSize`. The `/html-to-react-luau` skill (pitfalls #12–13) has the full treatment, including the "Canvas + `UIScale`" pattern for fixed-pixel modals.

**Prefer computed `TextSize` over `TextScaled` for `vh`-based fonts.** `TextScaled` fills the label's container (layout-dependent); a `vh` font size is a literal viewport fraction. Compute `TextSize` from `useViewportScale` as above. Use `TextScaled` only when text lives inside a uniformly scaled fixed-pixel canvas.

> **Ripple Avatar Creator sizing decision: `fill`, scaled by height.** HUD content is authored in design pixels on the 1180×820 canvas inside `SkinRoot`, which applies one `UIScale` (viewport height ÷ 820) to a canvas stretched to the screen's aspect, so corner-pinned pieces reach the real edges. Chosen over `relative` (per-element pixels) and `fit` (letterboxed) after testing in Task 1. Under this mode: don't use `AutomaticSize` for text (see Skin kit), and convert real-pixel measurements (Roblox's top bar) with `useSkin().fromScreen`. Glass decision: scene blur behind full-screen panels.

> **Starting from a design?** Run `/html-to-react-luau` to translate an HTML/CSS/JSX mockup (or screenshot) into a react-luau component that follows these rules, then wire its state with `/create-view`.

## Creating a HUD View

Decide where it lives first:

- **A page the player navigates to** (a list, a detail page, a store) → a **screen** in `views/screens/`, shown inside the full panel. This is the usual case.
- **Something over the world** (a button, an indicator, a side panel like World options) → a component rendered by `WorldHud.luau`.

### Step 1: Create the Component

Create a ModuleScript, e.g. `Source/ReplicatedFirst/views/screens/YourScreen.luau`. Compose the skin kit: design px go through `useSkin().px`, text is sized with `ShadowText` / `useTextWidth` (no `AutomaticSize` under the canvas), measured layout uses `useLocalSize`:

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local hooks = views:WaitForChild("hooks")
local components = views:WaitForChild("components")
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local ShadowText = require(components:WaitForChild("ShadowText"))

local e = React.createElement

local function YourScreen(props: { nav: any, look: any })
	local skin = useSkin()
	return e("Frame", {
		Name = "YourScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Title = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(24)),
			BackgroundTransparency = 1,
		}, {
			Text = e(ShadowText, { text = "Your screen", style = Tokens.type.cardTitle }),
		}),
	})
end

return YourScreen
```

### Step 2: Route and Navigate to It

For a screen, add a branch to `currentScreen` in `panel/FullPanel.luau` (a new stack-entry `kind`, or a new root) and navigate with `useNavigation` from wherever the player opens it -- `nav.push({ kind = "yours", id = someId, label = "Your screen" })`. See "Full Panel and Navigation" above.

For a world-HUD element, render it from `WorldHud.luau` and pass what it needs from `WorldHud`'s `nav` / `look` props.

### Step 3: Add State (if needed)

If your view needs server state, add a `useBoltState` call in `Hud.luau` and pass the data down as props (through `WorldHud` / `FullPanel` to the screen):

```lua
-- Illustrative: Network.State.YourModel is hypothetical
local yourData = useBoltState(Network.State.YourModel, { defaultField = "" })

Panel = if nav.isOpen then e(FullPanel, { nav = nav, look = look, yourData = yourData, tabs = TABS }) else nil,
```

## Creating a Workspace View

A workspace view wires up CollectionService-tagged interactables in the world — the planned diegetic "monoliths" (`docs/PROJECT_BRIEF.md`). **Illustrative — no view in this repo uses this pattern yet**; the `Monolith` tag and `Network.Intent.YourFeature` below are hypothetical.

### Step 1: Create the LocalScript

Create a new LocalScript in `Source/ReplicatedFirst/views/YourView.client.luau`:

```lua
--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Network"))

local MONOLITH_TAG = "Monolith"

local function setupMonolith(monolith: Instance)
    -- WaitForChild: Studio-authored children may not have replicated yet
    local base = monolith:WaitForChild("Base")
    local proximityPrompt = base:WaitForChild("ProximityPrompt") :: ProximityPrompt
    local sound = base:WaitForChild("Sound") :: Sound

    proximityPrompt.Triggered:Connect(function(player: Player)
        -- Immediate feedback
        sound:Play()

        -- Send intent to server
        Network.Intent.YourFeature:FireServer(Network.Actions.YourFeature.Action, data)
    end)
end

-- Handle existing tagged instances
for _, monolith in CollectionService:GetTagged(MONOLITH_TAG) do
    task.spawn(setupMonolith, monolith)
end

-- Handle instances added (or streamed in) later
CollectionService:GetInstanceAddedSignal(MONOLITH_TAG):Connect(function(monolith: Instance)
    task.spawn(setupMonolith, monolith)
end)
```

### Step 2: Tag Instances in Studio

Add the tag to your 3D instances in Roblox Studio using the Tag Editor (View > Tags or Alt+T).

### Step 3: Add State Observation (if needed)

For Pattern C or B+C, add an Observe call inside the setup function:

```lua
Network.State.YourModel:Observe(function(data: Network.YourModelState)
    -- Update visual state based on server data
    updateVisuals(data)
end)
```

### Real tagged-instance code: WorldRenderer

The closest real example is `WorldRenderer.luau`, which recolours every part tagged `WorldFloor` and catches floor parts that stream in later (trimmed):

```lua
local FLOOR_TAG = "WorldFloor"

-- applyFloor:
for _, part in CollectionService:GetTagged(FLOOR_TAG) do
	if part:IsA("BasePart") then
		part.Color = colour
		-- ... top-face Texture for the pattern
	end
end

-- In the component's effect, once the game has loaded:
local added = CollectionService:GetInstanceAddedSignal(FLOOR_TAG):Connect(function()
	applyFloor(latest.current.options, latest.current.config, original.current :: Snapshot)
end)
return function()
	added:Disconnect()
end
```

## Example: PurchaseView (Client Script, Pattern B)

`Source/ReplicatedFirst/views/PurchaseView.client.luau` -- Roblox tells only the client how a bulk purchase prompt ended, so this passes the outcome on to PurchaseController (trimmed):

```lua
--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Network"))

MarketplaceService.PromptBulkPurchaseFinished:Connect(function(...: any)
	-- (player, status, results); tolerate the player being left off.
	local status, results = ...
	if typeof(status) == "Instance" then
		status, results = select(2, ...)
	end
	local items = {}
	local robuxSpent = nil
	-- ... copy each result's id / type / status into items
	Network.Intent.Purchase:FireServer(Network.Actions.Purchase.Finished, {
		status = nameOf(status),
		robuxSpent = robuxSpent,
		items = items,
	})
end)
```

Key points:
- `WaitForChild("Network")`: ReplicatedFirst scripts run before ReplicatedStorage is guaranteed to have replicated
- Sends intent to server via Bolt ReliableEvent
- The server doesn't take the client's word: PurchaseController re-checks ownership with Roblox, and the statuses only pick the wording of the result (which arrives back through `Network.State.Ownership`)

## Example: WorldHud Basket Badge (HUD, Pattern C)

`Source/ReplicatedFirst/views/WorldHud.luau` -- the Basket button and its Robux badge, rendered purely from props (trimmed):

```lua
export type Props = {
	nav: any,
	look: any,
	tabs: { any },
}

local function WorldHud(props: Props)
	local skin = useSkin()
	local basket = Tokens.size.basket
	local total = props.look.basketTotal

	-- ... inside the bottom-left button row:
	Basket = e(PillButton, {
		variant = "round",
		size = basket.size,
		icon = "shopping_basket",
		iconSize = basket.icon,
		glowRadius = basket.glow,
		layoutOrder = 1,
		zIndex = 2,
		onActivated = function()
			props.nav.openRoot("Basket")
		end,
		-- Design: badge sits top -8px, right -18px of the 84 button.
		badge = if total > 0
			then e(Badge, {
				kind = "count",
				tone = "orange",
				icon = "toll",
				text = tostring(total),
				anchorPoint = Vector2.new(1, 0),
				position = UDim2.fromOffset(skin.px(18), -skin.px(8)),
				zIndex = 6,
			})
			else nil,
	}),
```

Key points:
- Pure function component -- receives all data via props, no direct state subscriptions
- `look.basketTotal` comes from `Hud`; today that's `usePlaceholderLook`, later a `useBoltState` subscription in `Hud` -- `WorldHud` doesn't change
- Navigation is a callback on the `nav` prop (`openRoot("Basket")` opens the full panel on the Basket list) -- no BindableEvents
- Sizes come from `Tokens` in design px and go through `skin.px`; the button and badge are skin-kit components (`PillButton`, `Badge`)

## Model Scopes and State Formats

The state format you receive in `Observe()` depends on the model's scope. Entity-scoped models send aggregated dictionaries, not single objects. Only User and UserSession models exist in the repo today; the other samples are illustrative.

### User Scope (e.g., BasketModel)

One instance per player. Default (`syncScope = "owner"`): state sent only to the owner as a single object. UserSession models (OwnershipModel: per player, not saved) arrive the same way.

```lua
-- Direct Observe (in a client script):
Network.State.Basket:Observe(function(data: Network.BasketState)
    -- data is a single object: { ownerId, items = { { targetId, kind, typeName, name } } }
    updateCount(#data.items)
end)

-- In the HUD (screens/usePlaceholderLook.luau, called by Hud):
local basketState = useBoltState(Network.State.Basket, DEFAULT_BASKET :: any)
-- basketState.items available as React state
```

Broadcast variant (`syncScope = "all"`): all users' states aggregated into a dictionary keyed by `ownerId` (illustrative — `PowerUp` is hypothetical):

```lua
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

type PowerUpStateDictionary = { [string]: Network.PowerUpState }

powerUpState:Observe(function(allPowerUps: PowerUpStateDictionary)
    -- allPowerUps is { [ownerId] = { ownerId, power, ... } }
    local myState = allPowerUps[tostring(localPlayer.UserId)]
    if myState then
        updatePowerUpDisplay(myState.power)
    end
end)
```

### Server Scope (illustrative)

One instance for the entire server. State broadcast to all players as a single object (`Leaderboard` is hypothetical):

```lua
leaderboardState:Observe(function(data: Network.LeaderboardState)
    -- data is a single object: { ownerId = "SERVER", entries, ... }
    updateBoard(data.entries)
end)
```

### UserEntity Scope (illustrative)

Multiple instances per player (one per entity). State sent only to the owner as a dictionary keyed by entityId (`Pets` is hypothetical):

```lua
type PetsStateDictionary = { [string]: Network.PetsState }

-- Direct Observe:
petsState:Observe(function(allPets: PetsStateDictionary)
    clearList()
    for entityId, pet in allPets do
        addToList(entityId, pet.name)
    end
end)

-- In the HUD (useBoltState, from the hook Hud calls):
local petsDict = useBoltState(Network.State.Pets, {} :: PetsStateDictionary)
-- petsDict is the full dictionary, passed down as props to the screen that lists it
```

### ServerEntity Scope (illustrative)

Multiple instances shared across all players (one per entity). State broadcast to all players as a dictionary keyed by entityId. A view rendering them into the world must handle both spawning new entities and removing entities no longer in state. **Illustrative — no view in this repo uses this pattern yet** (`Drop` is a hypothetical timed world object):

```lua
type DropsStateDictionary = { [string]: Network.DropState }

local spawned: { [string]: Model } = {}

dropsState:Observe(function(allDrops: DropsStateDictionary)
    -- Spawn new entities
    for entityId, drop in allDrops do
        if not spawned[entityId] then
            spawned[entityId] = spawnDrop(entityId, drop)
        end
    end

    -- Remove entities no longer in state
    for entityId, model in spawned do
        if not allDrops[entityId] then
            model:Destroy()
            spawned[entityId] = nil
        end
    end
end)
```

### Quick Reference Table

| Scope | syncScope | Recipients | State Format | Example |
|-------|-----------|-----------|--------------|---------|
| User | `"owner"` (default) | Owner only | Single object | BasketModel |
| UserSession | `"owner"` (default) | Owner only | Single object | OwnershipModel |
| User | `"all"` (override) | All players | `{ [ownerId]: State }` | (hypothetical PowerUpModel) |
| Server | `"all"` (default) | All players | Single object | (hypothetical LeaderboardModel) |
| UserEntity | `"owner"` (default) | Owner only | `{ [entityId]: State }` | (hypothetical PetsModel) |
| ServerEntity | `"all"` (default) | All players | `{ [entityId]: State }` | (hypothetical DropsModel) |

**Common Mistakes with Entity-Scoped Models**:

1. **Treating entity-scoped state as a single object** -- If your Observe callback receives data but nothing happens, check if the model is entity-scoped and iterate the dictionary.

2. **Only handling additions, not removals** -- When entities can be removed (like timed world objects expiring), your view must compare the incoming state with tracked entities and remove any that are no longer present. Either:
   - Clear and rebuild: `clearList()` then iterate (simple but may cause flicker)
   - Diff and update: Spawn new, remove missing (smoother for visual objects)

3. **Treating User + `syncScope="all"` state as a single object** -- If a User-scoped model uses `syncScope = "all"`, its property holds `{ [ownerId]: State }` -- a dictionary keyed by ownerId, broadcast to all players. Index by the local player's UserId to get your own state.

## File Locations

- **HUD entry point**: `Source/ReplicatedFirst/views/HudApp.client.luau`
- **HUD root**: `Source/ReplicatedFirst/views/Hud.luau` (world HUD: `WorldHud.luau`, `WorldOptionsView.luau`)
- **Full panel**: `Source/ReplicatedFirst/views/panel/` (`FullPanel.luau`, `Breadcrumbs.luau`)
- **Panel screens + shared parts**: `Source/ReplicatedFirst/views/screens/`
- **Skin kit**: `Source/ReplicatedFirst/views/Tokens.luau`, `SkinAssets.luau`, `SkinContext.luau`
- **Shared UI components**: `Source/ReplicatedFirst/views/components/`
- **React hooks**: `Source/ReplicatedFirst/views/hooks/`
- **Client scripts**: `Source/ReplicatedFirst/views/*.client.luau` (PurchaseView, FlightView, SprintView; workspace views go here too)
- **Network module**: `ReplicatedStorage/Network.luau`

The naming convention distinguishes the two types:
- `.client.luau` -- LocalScript (client script / workspace view, or the HudApp entry point)
- `.luau` -- ModuleScript (React component or hook)

## Best Practices

### 1. Keep Components Small

Split HUD views into focused components. Use the `components/` folder for shared skin-kit building blocks (PillButton, GlassPanel, Badge, ShadowText, ...) and `screens/Parts.luau` for pieces shared between screens (ItemCard, ListRow, CardGrid, ...). Each component should do one thing.

### 2. Use Hooks for State

Use `useBoltState` to subscribe to server state in `Hud` (the root component). Do not call `Observe()` directly inside React components -- let `Hud` manage subscriptions and pass data down as props.

### 3. Props for Data Flow

Pass data and callbacks as props from `Hud` to child components. This keeps components pure and testable:

```lua
-- Good: component receives data as props
local function BasketCount(props: { look: any })
    return e(ShadowText, { text = #props.look.basket .. " items", style = Tokens.type.small })
end

-- Bad: component subscribes to state directly (illustrative: Network.State.Basket is hypothetical)
local function BasketCount()
    local basket = useBoltState(Network.State.Basket, default)
    return e(ShadowText, { text = #basket.items .. " items", style = Tokens.type.small })
end
```

Centralizing subscriptions in `Hud` avoids duplicate Observe subscriptions and makes state flow easy to trace.

### 4. Use WaitForChild in Workspace Views

Always wait for children to exist in workspace views, as they may not be ready immediately:

```lua
local button = instance:WaitForChild("Button")
local sound = button:WaitForChild("Sound")
```

### 5. Type Safety

Use `--!strict` and type your variables:

```lua
local proximityPrompt = base:WaitForChild("ProximityPrompt") :: ProximityPrompt
local sound = base:WaitForChild("Sound") :: Sound
```

For React components, export a `Props` type:

```lua
export type Props = {
    nav: useNavigation.Navigation,
    look: usePlaceholderLook.Look,
    onClose: () -> (),
}
```

### 6. Immediate Feedback

Provide instant visual feedback before server confirmation (applies to both view types):

```lua
-- Workspace view: particles and sound
proximityPrompt.Triggered:Connect(function(player: Player)
    particleEmitter:Emit(particleEmitter.Rate)
    sound:Play()
    intent:FireServer(Network.Actions.Feature.Action, data)
end)
```

### 7. Handle CollectionService Correctly in Workspace Views

Always handle both existing and dynamically added tagged instances:

```lua
for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
    task.spawn(function()
        setupInstance(instance)
    end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance: Instance)
    task.spawn(function()
        setupInstance(instance)
    end)
end)
```

Use `task.spawn` to avoid one failing setup blocking the rest.

## Relationship to Models and Controllers

### Views --> Controllers
- Views send intents to controllers via Bolt ReliableEvents (`Network.Intent.*:FireServer()`)
- Views never directly modify Models

### Views <-- Models
- Views observe state changes broadcast by Models via Bolt RemoteProperty (`Network.State.*:Observe()`)
- HUD views receive this data as React props (`Hud` calls `useBoltState`, passes data down)
- Workspace views call `Observe()` directly in their setup functions

### Complete Flow Example

```
1. User clicks button (View provides immediate feedback)
2. View fires intent: Network.Intent.Basket:FireServer(Network.Actions.Basket.Add, { targetId = 123, kind = "Asset" })
3. Controller validates and updates Model
4. Model broadcasts state change to clients via Bolt RemoteProperty
5. HUD: useBoltState triggers React re-render with new state
   Client script: Observe() callback fires with new state
6. View updates display with authoritative server state
```

## Next Steps

After creating your view:

1. **Create a Controller** (`Source/ServerScriptService/controllers/`) if server validation is needed
2. **Create a Model** (`Source/ServerScriptService/models/`) to store authoritative state
3. **Test the flow** end-to-end with user interactions

See the main [README.md](../README.md) for the complete MVC architecture overview.
