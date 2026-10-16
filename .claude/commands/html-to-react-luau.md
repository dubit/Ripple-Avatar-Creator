---
description: Translate an HTML/CSS (or JSX) UI design into a Roblox react-luau view component
allowed-tools: Bash(ls, find, cat, grep), Read, Write, Edit, Glob, Grep
---

I'll translate an HTML/CSS UI design into a Roblox react-luau component that fits this template's view architecture, reusing existing components where possible and flagging anything that needs a new asset.

## What this skill does — and what `/create-view` does

These two are complementary; use them together:

- **`/html-to-react-luau` (this skill)** — turns a *visual design* (HTML/CSS/JSX/screenshot) into the component's **structure and styling**: the React element tree, layout, sizing, colours, fonts, and which existing components to reuse.
- **`/create-view`** — wires a view to the game's **state and intents** (Network patterns A/B/C, panel screen vs world HUD, FullPanel routing / WorldHud wiring) and validates against `Network.luau`.

Typical flow: run this skill first to get a faithful component skeleton, then run `/create-view` (or follow `docs/VIEW_GUIDE.md`) to bind it to `useBoltState` / `Network.Intent` and mount it in `HudApp.client.luau`. I'll emit static, well-structured display markup and hand off the state wiring — I won't invent Network calls.

## This template's UI architecture (what I target)

HUD views in this template are **react-luau components** (ModuleScripts, `.luau`) under `Source/ReplicatedFirst/views/`. `HudApp.client.luau` mounts the root `Hud.luau` into its own ScreenGui; `Hud` renders `WorldHud` (over the world) or `panel/FullPanel` (one full-screen panel whose content is a screen from `views/screens/`). Reusable pieces live in `Source/ReplicatedFirst/views/components/` and hooks in `Source/ReplicatedFirst/views/hooks/`.

There is **no primitives library** (`branded/`/`universal/`), and **no design-system asset pipeline** — so I never assume those exist. The brand system is the skin kit (`views/Tokens.luau` + the components in `views/components/`, see "Design references" below); I reuse what's actually there and in `views/screens/Parts.luau`, and otherwise emit self-contained chrome, flagging repeated patterns as candidates for a shared component.

## How to invoke me

- `/html-to-react-luau path/to/design.html`
- `/html-to-react-luau` (then paste the HTML/JSX, or attach a screenshot, when prompted)

## Preferred input formats (best → worst)

1. **JSX with semantic component tags + inline styles + comments** — fastest path: custom tags (`<Panel>`, `<Button>`) signal intent and map onto reusable components; prop names and comments make the author's intent explicit. If a `.jsx` sits next to an `.html`, I read both — JSX for structure/intent, the HTML render for visual truth.
2. **JSX without a component library** — still useful (semantic names + inline styles) but I do more mapping work.
3. **Static HTML/CSS** — works; I infer structure from the markup and computed styles.
4. **Screenshot / Figma image only** — last resort. Everything is inferred from the picture; expect more back-and-forth.

## My workflow — six phases

I **always start with the visual**. Reading HTML/CSS alone misses styling nuance.

### Phase 1 — Visual understanding

This template has no HTML-render pipeline, so I get the visual from you: **attach a screenshot / PNG of the design**, or open the HTML in a browser and paste a screenshot. I look at that first, before reading the markup, so my mental model is shaped by the picture rather than the code. If no image is available I proceed from the HTML alone and say so — the port is lower-confidence.

### Phase 2 — Capability audit

#### 2a. Input fidelity check (treat fixed-pixel as a code smell)

Before mapping anything, look at the CSS. Roblox games render on every aspect ratio from phone portrait to ultrawide PC, so UI here should use **relative** scaling — `vh`/`vw`/`aspect-ratio` in CSS, or `UDim2.fromScale` + `UIAspectRatioConstraint` in Roblox. If the input uses **fixed pixels everywhere** (`width: 268px`, `top: 30px`, `font-size: 38px`, no `vh`/`vw`/`aspect-ratio`/`transform: scale(...)`) or **anchors everything to the top-left** (every element has `left:`/`top:` but no `right:`/`bottom:`/`left: 50%`), treat it as a code smell.

Sometimes it's intentional — a one-off Studio mockup that'll only ever render at 1920×1080, or a deliberately fixed splash screen. But it's easily missed: the design author may have defaulted to fixed pixels without thinking about responsive behaviour, and the resulting Roblox UI will overflow on phones and look tiny on ultrawides.

**Always raise this with you before proceeding.** Two paths:

1. **"Convert the HTML first"** — I help draft a prompt for your design tool asking it to re-author the input in `vh`/`vw`/`aspect-ratio`. The known-working instruction stack: (1) every dimension in `vh`/`vw` not `px`, (2) `aspect-ratio` on elements that must keep their shape, (3) the stage element fills the body with no aspect lock, (4) no JS resize listeners. Round-trip revised HTML back before the Roblox port.
2. **"Convert as we skin"** — translate to relative scaling anyway, inferring anchoring from position and function. A button at `left: 29px, top: 30px` near the top-left probably pins top-left (`AnchorPoint = Vector2.new(0, 0)` + `Position = UDim2.fromScale(0.015, 0.028)`). One at `right: 28px, bottom: 27px` pins bottom-right. A `left: 50%` element stays centred. I flag every guess in the end-of-run summary.

The wrong move is to silently translate `px` 1:1 to `UDim2.fromOffset`. That LOOKS right on Studio's default viewport and breaks for half the player base. If the input is fixed-pixel, I confirm intent before emitting.

#### 2b. DOM walk and translation table

I walk the DOM from the HTML/JSX and classify each element:

| HTML / CSS | Roblox |
|---|---|
| `<div>` | `Frame` |
| `<button>` | `TextButton` |
| `<img>` | `ImageLabel` |
| `<p>`, `<span>`, `<h1>`–`<h6>` | `TextLabel` |
| `border-radius: <r>` (single value) | `UICorner` with `CornerRadius = UDim.new(0, r)` |
| `border-radius: <tl> <tr> <br> <bl>` (asymmetric) | **UICorner is uniform across all four corners — cannot do this.** See "Asymmetric border-radius" below. |
| `border: <w>px <color>` | `UIStroke` (Color3, Thickness, `ApplyStrokeMode = Border`) |
| `box-shadow` | `UIStroke` low-alpha black approximation |
| `display: flex; flex-direction: row` | `UIListLayout` Horizontal |
| `display: flex; flex-direction: column` | `UIListLayout` Vertical |
| `display: grid` | `UIGridLayout` |
| `gap: <g>` | `UIListLayout.Padding = UDim.new(0, g)` |
| `padding` | `UIPadding` |
| `position: absolute; left/top` (in px) | `Position = UDim2.fromOffset(x, y)` + `AnchorPoint` — see 2a; usually a code smell |
| `position: absolute; left: <N>vw; top: <N>vh` | `Position = UDim2.fromScale(N/100, N/100)` + `AnchorPoint` |
| `width: <N>vw` / `height: <N>vh` (direct child of viewport-fill root) | `Size.X.Scale = N/100` / `Size.Y.Scale = N/100` |
| `width: <N>vw` / `height: <N>vh` (nested element) | `Size = UDim2.fromOffset(N/100 × DESIGN_H × useViewportScale())` — see Phase 5a |
| `aspect-ratio: <W>/<H>` | `UIAspectRatioConstraint { AspectRatio = W/H, AspectType = FitWithinMaxSize }` — Size MUST be positive on both axes (pitfall 10) |
| `font-size: <N>px` | `TextSize = N` |
| `font-size: <N>vh` | `TextSize = math.floor(N/100 × DESIGN_H × useViewportScale() + 0.5)` — NOT `TextScaled` (Phase 5b) |
| `z-index` | `ZIndex` (explicit — Roblox doesn't inherit like CSS) |
| `overflow: hidden` | `ClipsDescendants = true` |
| `background: <color>` | `BackgroundColor3` |
| `background: linear-gradient(...)` | `UIGradient` (see pitfall 1 — parent BG must be white) |
| `color: <c>` | `TextColor3` |
| `font-family: <F>` | `Font = Enum.Font.<Match>` (or `FontFace`) — pick the closest shipped font |
| `text-align: center` | `TextXAlignment = Enum.TextXAlignment.Center` |
| `opacity: <o>` | `BackgroundTransparency = 1 - o` (or `TextTransparency`) |
| `transform: rotate(N)` (on a rectangle) | `Rotation = N` |
| `transform: scale(s)` on a fixed-pixel canvas | `UIScale` on an inner Canvas frame (pitfall 12 / Pattern 2) |

Elements I flag as **needs a PNG asset** (Roblox can't draw natively):

- `clip-path: polygon(...)` on a `<div>` — any non-rectangle polygon
- `clip-path: <shape>` — anything but `inset()` (which maps to a rect + UICorner)
- SVG `<polygon>`, `<path>`, `<circle>` (when not just a rect)
- Conic / radial gradients on irregular shapes
- Multi-fill complex backgrounds (gradient + shape mask)
- Any `data-roblox-hex` / `data-roblox-asset=<key>` attribute (explicit hint from the author)

Elements I flag as **unsupported in Roblox UI** — must redesign or accept a compromise:

- `filter: blur(...)` — no Roblox UI equivalent
- `mix-blend-mode` / `background-blend-mode`
- Custom mask compositing beyond cutout-image patterns
- 3D transforms (`rotateX`, `rotateY`, perspective)

**Asymmetric border-radius** (`border-radius: 0 24px 24px 0`): `UICorner` applies one radius to all four corners. When per-corner radii differ, render a 9-slice template PNG (e.g. a 100×100 silhouette with the corner pattern baked in) and use `ImageLabel` with `ScaleType = Enum.ScaleType.Slice` + `SliceCenter = Rect.new(24, 24, 76, 76)` to preserve corners at any stretched size. White-fill the template so it tints at runtime via `ImageColor3`. **Don't fake asymmetry with a uniform UICorner + overlapping Frames** — the overlap math is fragile and strokes won't reconcile.

**Read the source SVG, not just the rendered HTML**: every PNG-bound element usually has a source `.svg`. Open it for hints the CSS omits:
- `preserveAspectRatio="none"` → designed to stretch. Use `ScaleType.Stretch`, not `Fit` (Fit letterboxes against aspect mismatch).
- `fill="currentColor"` → colour comes from CSS `color:`; renders BLACK if converted as-is. For runtime tinting via `ImageColor3`, export a copy with `fill="#FFFFFF"`.
- `<path>` with separate `fill` and `stroke` → multi-tone. If both need independent runtime tints, export fill and stroke as separate white-fill layers; otherwise keep colours as-is in one render.

### Phase 3 — Asset reconciliation

**Roblox Studio's Asset Manager doesn't accept SVGs — every SVG must be exported to PNG and uploaded before its asset ID can be wired in.** Never ask the user to upload SVGs directly.

This template ships no asset-generation pipeline, so for each "needs PNG" element I:

1. Describe exactly what PNG is needed (dimensions, whether it should be white-fill for runtime tinting, 9-slice insets if any).
2. Ask you to export it from your design tool (or generate it) and upload it via Studio's Asset Manager.
3. Wire the returned asset ID into the component (inline as a constant, or into your project's asset/token store if one exists).

#### Phase 3a — Upload checklist (deliver at end-of-run)

**I can't see your Studio Asset Manager.** For every PNG the component needs, I list:

- **NEW** — no asset exists yet: "export, upload, paste the ID back."
- **MAY UPDATE** — an asset for a related name may already exist and could be visually stale: "eyeball the existing one against the new design; re-upload only if it's iterated."
- Always include what the PNG should look like and which constant/field the ID wires to.

### Phase 4 — Component discovery (reuse is the default; a new component is debt)

Before writing anything new, I run a live discovery pass (grep/ls, not a hand-maintained list that drifts):

```sh
# 1. Skin kit components (the project's visual language)
ls Source/ReplicatedFirst/views/components/
#    e.g. SkinRoot, PillButton, PillTabs, GlossFace, GlassPanel, Badge,
#         TextTab, Chip, Icon, ShadowText

# 2. Shared screen parts for the full panel
grep -n "^function Parts\." Source/ReplicatedFirst/views/screens/Parts.luau
#    Thumb, PriceTag, ItemCard, ListRow, CardGrid, Heading

# 3. Hooks (state, skin, navigation, animation, scaling)
ls Source/ReplicatedFirst/views/hooks/
#    e.g. useSkin, useInteraction, useTextWidth, useLocalSize, useGlassBlur,
#         useSystemBarInset, useNavigation, useBoltState, useSpring,
#         useSpringNumber, useTransition, useDrag, useViewportScale

# 4. Existing views/screens to copy idioms from
ls Source/ReplicatedFirst/views/ Source/ReplicatedFirst/views/screens/ Source/ReplicatedFirst/views/panel/
#    Hud, WorldHud, WorldOptionsView, panel/FullPanel, screens/*Screen

# 5. Shared utilities
ls Source/ReplicatedStorage/ 2>/dev/null

# 6. Targeted name search when I have a concept in mind
grep -rln "ConceptKeyword" Source/ReplicatedFirst/views/
```

**Mapping rule:** if the JSX uses `<Foo>` and a matching component exists in `views/components/` (or a part in `screens/Parts.luau`), I use it — don't reinvent. A new page in the full panel becomes a screen in `views/screens/`, routed in `currentScreen` in `panel/FullPanel.luau` (see "Full Panel and Navigation" in `docs/VIEW_GUIDE.md`). If it doesn't exist, see "When you need a new component" below.

**Content-population step (don't skip):** if the design shows an in-game asset inside a UI slot (a pet, character portrait, 3D model), the game may already have a renderer for it. Before emitting an empty placeholder Frame, grep for a `ViewportFrame` / preview helper and reuse the technique.

**Data-type verification (don't skip):** for every field the component will read from state (`data.items`, `state.purchase.state`), grep the type in `Network.luau` to confirm the field exists with that name and type:

```sh
grep -nE "export type (TypeName)" Source/ReplicatedStorage/Network.luau
```

Don't infer field names from the JSX's prop names — the JSX models data in HTML's vocabulary, the Roblox side in `Network.luau`'s, and they diverge silently. A missing field returns `nil` with no error; the symptom is invisible content, not a crash. (State wiring itself is `/create-view`'s job — here I just make sure the field names I reference are real.)

### Phase 5 — Layout extraction

I translate each element's geometry:

- bounding box → `Size` (`UDim2.fromScale` or `fromOffset`) + `Position` + `AnchorPoint`
- flex/grid → `UIListLayout` / `UIGridLayout` with extracted `Padding` / alignment
- padding → `UIPadding`
- z-stacking → explicit `ZIndex`

**Per-element margin/padding reads (don't skip):** a container's flex/grid handles spacing *between* children, but each child often carries its own `marginTop`/`marginLeft` in its inline style. Read every styled element individually — a `marginTop: 36` on one child shifts only that child; missing it makes that one label sit "too high" while the row reads correctly.

**Grid width math (one-off check):** for any `UIGridLayout` in a `ScrollingFrame`, verify columns fit before shipping:

```
cols × cellWidth + (cols-1) × gap + 2 × padding ≤ containerWidth − scrollbarThickness
```

Off-by-one here silently wraps to fewer columns.

#### Phase 5a — vh/vw translation rules

CSS `vh`/`vw` are viewport-relative; `UDim2.fromScale` is parent-relative. They're equivalent ONLY when the parent fills the viewport (the HUD root, a ScreenGui-filling Frame). For nested elements they diverge:

- **Direct child of a viewport-filling root**: `vh → Scale.Y`, `vw → Scale.X` (`UDim2.fromScale(vw/100, vh/100)`).
- **Nested element**: use `Offset = math.floor(N/100 × DESIGN_H × useViewportScale() + 0.5)`, keeping the dimension at the literal % of viewport regardless of intermediate parent sizes.

`useViewportScale` (`views/hooks/useViewportScale.luau`) returns `viewport.Y / 1080`. It's the small concession to "rolling our own" — Roblox doesn't natively express "% of viewport" as a number.

**Caveat — it's height-axis only.** `useViewportScale` tracks viewport *height*. Correct for residual pixels on elements that scale with viewport height (corner-pinned pieces in a viewport-filling root). **Wrong** for pixels inside an aspect-locked / width-dominant container (a centred modal with `UIAspectRatioConstraint` + `DominantAxis.Width`) — there, drive scale off the container's measured `AbsoluteSize` along its dominant axis. See pitfall #13.

#### Phase 5b — Direct TextSize > TextScaled when input is in vh

For `font-size: 4.63vh`, the target is "text = 4.63% of viewport height". `TextScaled` doesn't match — it fills the label's container, which depends on layout. Use a computed `TextSize`:

```lua
TextSize = math.max(N_MIN, math.floor(designPx * useViewportScale() + 0.5))
-- where designPx = N/100 * DESIGN_H
```

The min clamp keeps text readable on tiny viewports. `TextScaled` IS right when the design is *fixed-pixel inside a scaled wrapper* (Pattern 2) — the text just fills a container being scaled as one unit.

### Phase 6 — Emit react-luau

I write the component to `Source/ReplicatedFirst/views/<Name>.luau` (a ModuleScript — NOT `.client.luau`), or to `views/components/<Name>.luau` if it's a reusable piece.

The component:
- uses `--!strict`
- has a top docstring: what it is + a reference to the HTML source
- uses `local e = React.createElement`
- imports existing components/hooks first, new ones second
- comments any decision that's *inferred* rather than *literal* (e.g. "interpreting `box-shadow: 0 0 6px rgba(0,0,0,0.2)` as UIStroke @ 0.8 transparency, 6px thickness")
- exports its `Props` type

Skeleton (state wiring is added later via `/create-view`):

```lua
--!strict

--[[
	<Name>

	Ported from <source.html>. Static display component — state wiring
	(useBoltState / Network.Intent) added separately via /create-view.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local e = React.createElement

export type Props = {
	-- data this component displays, passed in by its parent
}

local function <Name>(props: Props)
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- children
	})
end

return <Name>
```

At end-of-run I tell you:
- the file path of the generated component
- any new PNGs to upload (with a description of each + the constant/field the ID wires to)
- assumptions to sanity-check (especially any anchoring guesses from Phase 2a)
- anything from the HTML that doesn't translate (animations, state, behaviour to wire manually)
- **any visual divergences from the design** — listed explicitly, with the asset/rework needed to close each

**No silent visual compromises.** If the design needs a shape Roblox can't draw natively, EITHER deliver it via a PNG asset OR list the divergence in the summary. Substituting silently (pill for hex, rectangle for polygon, uniform radius for asymmetric) ships a visual lie you have to catch in review. Naming it is the contract.

**Refactor preserves children.** When collapsing a one-shot composite into a reusable component, every visible child in the original must remain reachable via a prop. Audit the JSX's children, map each to a prop, and verify the call site re-supplies them. Symptom: "it looked right yesterday and is missing its icon today."

**LayoutOrder discipline.** For siblings under a `UIListLayout`/`UIGridLayout` that need a specific order, set explicit `LayoutOrder = N` on each. React's key iteration order is undefined — without it, "Price above Name" can flip between renders.

## Roblox layout pitfalls (learned the painful way)

Engine-level gotchas. Most are independent of any component library — they're just how Roblox UI behaves. Where a reusable component would encapsulate the fix, I note it, but the *rule* stands on its own.

1. **`UIGradient` multiplicative trap.** Each pixel renders as `parent.BackgroundColor3 × gradient_stop / 255`, so a dark parent BG crushes the gradient to black. **Always set `BackgroundColor3 = white` on the Frame carrying a `UIGradient`** (and drive visible colour through the gradient stops). Never put a UIGradient on a Frame with a non-white BG.

2. **`ScaleType.Slice` misrenders when the slice-center exceeds the target.** A `SliceCenter` whose Y range covers the full source height (zero-height caps) renders only the top portion at smaller targets — a downward-widening trapezoid. Validate slice insets against the source image; if unsure, fall back to `Stretch`. Pure `Stretch` (no slice) is always safe.

3. **Flex containers shrink-wrap; Roblox Frames don't.** A JSX flexbox sizes to its content. A Roblox Frame is whatever `Size` you give it. When porting a `display: flex` container, decide explicitly whether it fills its parent (`Size = UDim2.fromScale(1, ...)`) or hugs content (`AutomaticSize`).

4. **`AutomaticSize.Y` parents need `AutomaticSize.Y`-compatible children.** A child with `Size.Y.Scale = 1` contributes 0 to the parent's auto-size and collapses it to 0 height. When a parent auto-sizes Y, give every direct child `Size = UDim2.new(1, 0, 0, 0)` + `AutomaticSize.Y` so the cascade propagates.

5. **Roblox has no CSS-style flex centering.** A child in an empty Frame lands at top-left `(0, 0)`. To centre content, add a `UIListLayout` with `HorizontalAlignment`/`VerticalAlignment = Center` (or anchor the child at `0.5, 0.5`).

6. **Don't position siblings to an auto-sized element with guessed pixel offsets.** A close button at `(0.5, +PANEL_WIDTH/2, 0.5, -240+32)` breaks when the panel auto-sizes. Parent the affordance *to* the auto-sized element and use corner-relative anchoring: `AnchorPoint = Vector2.new(1, 0)` + `Position = UDim2.new(1, -inset, 0, inset)`.

7. **Decorator wrappers intercept layout props — Roblox has no `display: contents`.** Every Frame is a layout participant. When you wrap element X in a decorator (animation wrapper, conditional fade), the grandparent's `UIListLayout` sees the wrapper's `LayoutOrder`/`AnchorPoint`/`AutomaticSize`, not X's. **Forward every layout-affecting prop to the wrapper.** Symptom: "I wrapped X for animation and now it's in the wrong place."

8. **`CanvasGroup` clips compositing to its own `AbsoluteSize`, regardless of `ClipsDescendants`.** It composites descendants to an offscreen surface sized to its own bounds — anything rendered outside (via `UIScale` overflow, negative offsets) is dropped. If you wrap hover/press-scaling content in a CanvasGroup (e.g. for fade), add render margin: a `UIPadding` inside the CanvasGroup pushes children inward and auto-sizes the group outward, giving overflow room. Symptom: "the button's edges get clipped on hover."

9. **`AutomaticSize` ignores Scale-based child contributions.** A parent computes its auto-size from the OFFSET components of children; Scale contributions count as zero. So `AutomaticSize.X` + children using `Size.X.Scale = 1` → parent X = 0 → everything renders 0×0. If a child uses Scale-based size on an axis, that axis of the parent must have an explicit (non-zero) Size, not AutomaticSize. Symptom: "the container is invisible / the buttons are gone."

10. **`UIAspectRatioConstraint` with `FitWithinMaxSize` collapses both axes when either Size axis is 0.** The naive "height-driven aspect, so `Size = UDim2.fromScale(0, 1)`" does NOT work — you need positive Scale on BOTH axes; the constraint then trims one to keep the ratio. Symptom: "the slot isn't rendering." Check neither Scale is 0.

    **Sub-rule — `AspectType.ScaleWithParentSize` is NOT a generic "scale with parent" switch.** It fills the parent on the dominant axis and derives the other from the ratio — the Size's Scale values are ignored entirely. Default to `FitWithinMaxSize` for anything with explicit `fromScale` bounds. Symptom: "the modal overflows top/bottom on wide screens."

11. **Direct `TextSize` from `useViewportScale` is the faithful translation of `font-size: <N>vh`; `TextScaled` is not.** `TextScaled` fills the label's container (layout-dependent); `vh` is a literal viewport fraction. Compute `TextSize = math.floor(designPx × useViewportScale() + 0.5)` and skip `TextScaled`. Use `TextScaled` only for a fixed-pixel canvas inside a transform-scaled wrapper. Symptom: "text only fills 70–80% of the vertical space."

12. **`UIScale` scales its PARENT, not its descendants — the opposite of what the name suggests.** Putting `UIScale` directly under a Frame scales that Frame's own rendered size. If you then drive `Scale` off that same Frame's `AbsoluteSize` (via `GetPropertyChangedSignal("AbsoluteSize")`), you get a runaway feedback loop shrinking to zero. **For the "fixed-pixel + scale" pattern (Pattern 2), wrap design-pixel content in an inner Canvas Frame and parent `UIScale` to *that*.** The outer Frame holds the aspect constraint and the observable AbsoluteSize; it stays at natural size. Symptom: "modal renders briefly then collapses, and click-off stops working."

13. **`useViewportScale` is height-axis only — it desyncs from anything sized on a different axis.** It returns `viewport.Y / 1080`, so the pixels it scales stay proportional only when their element also scales with viewport height. An element inside an aspect-locked container with `DominantAxis.Width` scales with WIDTH — narrow the window (change aspect, not just size) and the container shrinks while `useViewportScale` holds steady, leaving corners/badges oversized. **Residual pixels inside an aspect-locked container must be driven off the container's own `AbsoluteSize`** (subscribe to `GetPropertyChangedSignal("AbsoluteSize")`, compute `scale = AbsoluteSize.<dominantAxis> / DESIGN_<dominantAxis>`). Reserve `useViewportScale` for corner-pinned pieces in a genuinely viewport-filling root. Symptom: "corners/badges look fine when I shrink proportionally but wrong when I make it narrower."

14. **Hooks must run unconditionally — never `return nil` above your hook calls.** React's hook bookkeeping is positional: hook N's state lives at slot N. If one render calls zero hooks and the next calls five, the slots misalign and state silently corrupts. **Call EVERY hook unconditionally on every render; put guards (`if not props.visible then return nil`) BELOW the hook block.** Symptom: a state value that's the right type on first render and nil/zero on later renders without any explicit reset.

## Animation

This template ships spring-physics hooks in `views/hooks/` — prefer them over hand-rolled `TweenService`.

- **`useSpring`** — animate a dictionary of properties (Position, Size, Transparency) toward targets with spring physics; returns React bindings that update instances directly (no re-render thrash). Config: `{ force, dampening, mass, immediate }`. Use for panel slide-in, element entrance, anything that might retarget mid-animation.
  ```lua
  local springProps = useSpring({ Position = UDim2.fromScale(0.5, 0.5) }, { force = 200, dampening = 20 })
  -- e("Frame", { Position = springProps.Position })
  ```
- **`useSpringNumber`** — animate a numeric display (Robux total, count, score) so it rolls to a new value; re-renders only when the displayed digit changes.
- **`useTransition`** — mount/unmount lifecycle: keeps a component mounted through its exit animation before unmount (Roblox's `AnimatePresence`). Supports staggering via a `trail`.
- **`useDrag`** — draggable element with momentum and spring-back.

For enter/exit animation, use `useTransition` (boolean mode for a single element, list mode with `trail` for grids) and `useSpring` directly in the component that shows/hides. Spring presets live in `Tokens.spring`. Full-panel open/close motion belongs to the panel, not to individual screens.

CSS `@keyframes` / `transition` don't translate automatically — I flag them for manual wiring (Out of scope, below).

## Interaction states

For interactive elements:

- **Reuse `views/components/PillButton.luau`** for buttons (round or pill; hover glow, 0.94 press, active orange) — and `PillTabs` / `TextTab` / `Chip` for tabs and filters — rather than re-implementing button behaviour.
- For a custom control the kit doesn't cover, use a real `TextButton` with `React.Event.Activated` (not `.Activated:Connect`) and `AutoButtonColor = false`, and get hover/press state from `hooks/useInteraction` (touch-safe) — wire its `onEnter` / `onLeave` to `MouseEnter` / `MouseLeave`, as `screens/Parts.ItemCard` and `panel/FullPanel`'s cards do. Take hover/press values from `Tokens.hover` / `Tokens.press`.
- If you find yourself writing the same interaction handling a third time, that's the signal to extract a shared component.

## When you need a new component

1. **Reusable across screens?** → `views/components/`. Keep it self-contained, expose a clean `Props` type, and reuse existing hooks (don't reinvent animation/input).
2. **Screen-specific?** → keep it next to the view file (or inline). Don't promote to `components/` until a second screen actually needs it. A new shared component is debt; earn it with a second consumer.

## Design references (the skin kit)

**`views/Tokens.luau` is the brand system.** Every colour, gradient, radius, size, type style, glass/glow/hover/press value and spring preset lives there; image asset IDs live in `views/SkinAssets.luau`. Compose the skin components (`SkinRoot`, `PillButton`, `PillTabs`, `GlossFace`, `GlassPanel`, `Badge`, `TextTab`, `Chip`, `Icon`, `ShadowText`) and `screens/Parts` rather than restyling. See "Skin kit" in `docs/VIEW_GUIDE.md`.

- **Map design values to Tokens, don't copy them.** A colour, radius or font size in the HTML should resolve to an existing `Tokens` entry. If it genuinely isn't there and is used more than once, add it to `Tokens` — never scatter magic `Color3`s or sizes across components.
- **Design pixels through `useSkin()`.** The HUD renders under `SkinRoot` (`fill` sizing, scaled by height, 1180×820 design canvas). Write the design's own px and convert with `skin.px` / `skin.stroke` / `skin.textPx`; real screen pixels (Roblox's top bar, `useSystemBarInset`) convert with `skin.fromScreen`.
- **Fonts:** Nunito via `Tokens.font(weight)` (600/700/800/900 → SemiBold/Bold/ExtraBold/Heavy) and the `Tokens.type` styles.
- **Text sizing:** `ShadowText` / `hooks/useTextWidth` — never `AutomaticSize` (or `AutomaticCanvasSize`) under the canvas `UIScale`; measure containers with `hooks/useLocalSize`.
- **Drop shadow**: a black `UIStroke` halo (`ApplyStrokeMode = Border`), not a separate Frame — but keep it **thin and faint**: the kit uses `Tokens.stroke.shadowThickness` (3, through `skin.px`) at `Tokens.stroke.shadowTransparency` (0.82). `UIStroke` can't feather, so thick halos (6–10px at 0.7–0.8) read as hard rings.
- **Multi-tone assets** (e.g. an orange-filled + yellow-bordered star): one white-fill PNG per tone, layered at runtime as stacked `ImageLabel`s each with its own `ImageColor3`. Never flatten a 2-colour SVG to a single silhouette — the colour distinction is lost forever and you can only restore one tone at runtime.
- **Spacing**: if the design implies a grid (multiples of 4 or 8), keep to it; otherwise take spacing from the design's own values.

## Translating responsive HTML — pick ONE pattern per ScreenGui root

CSS authors express "scale with viewport" three ways. Identify which the input uses (Phase 2a) and pick the matching Roblox strategy:

1. **Fixed pixels everywhere, no scaling logic.** Authored at one canvas size, hardcoded `px`, no `vh`/`vw`/`aspect-ratio`/transform. Looks right only at exactly the design size.
   → **`UDim2.fromOffset` design pixels, no scaling.** Acceptable for a one-off Studio mockup; **not shippable** to a game where players have any resolution. **Code smell — see Phase 2a.**

2. **Fixed pixels inside a `transform: scale(s)` wrapper.** A wrapper scales the whole fixed-pixel canvas uniformly to fit (`transform: scale(min(100vw/W, 100vh/H))`).
   → **Two nested Frames + a `UIScale` on the inner one.**
       Outer: `Size = UDim2.fromScale(canvasW/designW, canvasH/designH)` of the viewport-fill root, with `UIAspectRatioConstraint(canvasW/canvasH, FitWithinMaxSize)`. Transparent; holds the observable `AbsoluteSize`.
       Inner ("Canvas"): `Size = UDim2.fromOffset(designW, designH)`, centred (`AnchorPoint = 0.5,0.5` + `Position = fromScale(0.5, 0.5)`). Carries all chrome and design-pixel content.
       `UIScale` parented to the **inner Canvas** with `Scale = outerRef.AbsoluteSize.X / designW`, computed via a `GetPropertyChangedSignal("AbsoluteSize")` subscriber in a `useEffect`. Mirrors the CSS transform exactly; letterboxes on aspect mismatch. Good for self-contained modals.
       **DO NOT** parent the `UIScale` to the outer aspect-constrained Frame — that's pitfall #12's runaway loop.

3. **`vh`/`vw`/`aspect-ratio` natively, no canvas wrapper.** Every dimension viewport-relative; elements pinned to different corners; `aspect-ratio` locks shapes.
   → **Per-element `UDim2.fromScale` for direct children of the viewport-fill root + `useViewportScale × px` for nested pixel values + `UIAspectRatioConstraint` for shape locks.** Maximum flexibility; faithful to the CSS intent. **Preferred for game HUDs and overlays.**

Recognise the pattern from the CSS:
- `px` everywhere, no transform, no `vh`/`vw` → Pattern 1 (warn per Phase 2a)
- `transform: scale(...)` + a fixed `width/height` canvas → Pattern 2
- `vh`/`vw`/`aspect-ratio` throughout, no transform-scale wrapper → Pattern 3

The techniques don't mix cleanly within one ScreenGui-mounted React root — pick one per root. You CAN mix across roots (a modal in Pattern 2 in its own ScreenGui, the HUD in Pattern 3 in its own), just keep each root internally consistent.

## Out of scope (v1)

- **Animations** (`@keyframes`, `transition`) — I emit static structure and flag animations for wiring via the template's spring hooks / `TweenService`.
- **State and event handlers** (`onclick`, `onchange`) — I emit static display markup; state and intents are wired via `/create-view`. I honour `data-action="..."` hints if present.
- **CSS media queries / per-breakpoint variants** — Roblox UI has no media-query equivalent; rely on uniform scaling (Patterns 2/3). Breakpoint-specific layouts are a separate design conversation.
- **Asset auto-upload** — new PNGs are uploaded manually via Studio's Asset Manager.

## Ready

Show me the HTML/JSX file path or paste it here — and attach a screenshot of the design if you can (Phase 1).
