# Phase 1 — Catalog Avatar Creator adaptation — Implementation Plan

## Build order

**Approach:** feel-first, top-down (custom). Get the skin, motion and sound right before the heavy technical lifts. The first task is the first-playable slice (HUD shell in the final skin, full panel with tabs/breadcrumbs on placeholder content, buy-prompt frame, springs/tweens and UI sounds, and the relative-vs-absolute sizing decision). Then the layers in the SPEC's order: World options, Catalogue, Avatar core, Basket and buying, Outfits, Sharing, Community outfits, Stores. Large layers are split into several tasks. Tasks keep their numbers but run in document order: after Task 4 the catalogue (7, 8) was moved ahead of try-on (5, 6), so there are things to put on the avatar before dealing with what's on it.

**Rationale:** the design is settled and the riskiest things to get wrong late are look, feel and sizing across iPad/desktop/phone. Proving those first means every later layer (data, APIs, cross-server storage) plugs into a UI that already feels right, and the unresolved technical risks (catalogue limits, cross-server data, deep links, store model) each get an explicit investigation sub-task at the top of the task that depends on them rather than being assumed.

**Cross-cutting rules applied to every task**
- Template architecture only: Models / Controllers / Views / Services / Configs per `docs/*_GUIDE.md`. New intents/states are added to `Source/ReplicatedStorage/Network.luau` (NetworkConfig plus type exports) before the controller/model/view that use them. No new pattern where an existing one fits.
- HUD state flows through `HudApp` (`useBoltState` subscriptions, props/callbacks down, no BindableEvents). Navigation/UI-only state (open panel, tab, breadcrumb stack, buy prompt) is React state in `HudApp`, the same way `activeModal` is today.
- **No toasts, anywhere.** Feedback lives where the player is looking: the control or item changes state, the avatar changes, a count rolls, and a sound plays. Errors, not-found and empty states show inline where they happen. The design's toasts were built in Task 3 and removed (sidequest after Task 4); don't reintroduce them.
- HUD tasks translate the design with `/html-to-react-luau` (structure and styling), then wire state with `/create-view`. Each HUD sub-task names the design frame it implements. Visual divergences from the design (for example glass blur, which Roblox UI cannot do) are listed explicitly, never silent.
- Slash commands are auto-discovered from model methods and controller actions, so testing hooks need no extra work beyond naming methods well.
- Config modules are Studio-created (types under `Source/ReplicatedStorage/Config/ConfigTypes/` via `/create-config`); each task that adds one includes the Studio step.
- Instances found with `WaitForChild` (CLAUDE.md convention); `FindFirstChild` only for genuinely optional ones.
- Controller handlers validate everything from the client (item ids against the catalogue, list sizes, rate limits) and follow the ACTIONS-table / `dispatchAction` shape of the existing controllers. Analytics for controller actions is automatic; custom events use `AnalyticsService:trackEvent` as each task lands.
- Each task ends with a Play-mode playtest on desktop and a touch device emulation (iPad and phone) before the next task starts.

---

## Tasks

### Task 1: Skin foundation and sizing decision
- **Status:** [DONE]
- **Why here:** The whole spec is judged on feel. Tokens, fonts, icons and the base component kit must exist before any screen is built, and the sizing decision (relative vs absolute) changes how every later component is authored, so it is made first, on real devices.
- **Depends on:** none
- **Refs:** Constraints (Template architecture, Devices); Build order (first-playable slice: final skin, "settles the sizing approach"); Risks (Sizing: relative vs absolute); Success criteria (It feels good)
- **Acceptance criteria:**
  - A throwaway component gallery in the final skin (glossy black/orange split-gradient pills, Nunito 600-900, icons, glass panels, hover glow, 0.94 press scale) renders correctly on desktop, iPad and phone emulation.
  - The sizing approach is decided and recorded (relative scale + `useViewportScale`, or authoring at 1180x820 under one UIScale), with evidence from all three device classes, including how Roblox-native fixed-size UI (top bar) coexists.
  - Fonts and icons render with no placeholder glyphs; any divergence from the design is listed.
- **Associated UI:** Design tokens and chrome across all frames (5a to 5h); pills (tabs, Basket, Create avatar, Save to Roblox, Reset), glass panels, badges.
- **Sub-tasks:**
  - [DONE] 1.1 Investigate and decide font and icon delivery. Nunito is available as a Roblox font family (evaluate `FontFace` weights 600-900); Material Symbols Rounded is not a Roblox font, so evaluate a white-fill PNG sprite sheet or per-icon images tinted with `ImageColor3` (per the skill's Phase 3 asset flow). Produce the upload checklist for the icons the design uses (apparel, storefront, checkroom, shopping cart variants, flight, restart_alt, cloud_upload, person_add, etc.). Record as an open question for sign-off.
  - [DONE] 1.2 Create a shared design-tokens module under `Source/ReplicatedFirst/views/` (colours incl. the BK and OR gradient stops, radii, strokes, type scale, spring presets, glow/press values) so no screen holds magic numbers. Follow the skill's guidance to centralise repeated values.
  - [DONE] 1.3 Build the base skin components in `Source/ReplicatedFirst/views/components/` with `/html-to-react-luau`, reusing the template hooks: glossy pill button (reshaping `HudButton`; black default, orange active, hover glow, 0.94 press scale via `useSpring`), icon component, glass panel (translucent fill + stroke), badge, text tab (underline active), chip. `UIGradient` on white-BG frames (skill pitfall 1).
  - [DONE] 1.4 Decide how "glass" is rendered, since UI blur is unsupported: translucent fill only, or evaluate a client-side Lighting `BlurEffect`/`DepthOfField` while the full panel is open. List the divergence either way (open question).
  - [DONE] 1.5 Sizing spike: author the gallery both ways (per-element `UDim2.fromScale` + `useViewportScale`; and a 1180x820 canvas under one `UIScale` per the skill's Pattern 2), test on desktop, iPad and phone emulation (including narrow-aspect and notch/safe-area cases), pick one per ScreenGui root, record the decision and reasons in the open questions section and in `docs/VIEW_GUIDE.md` "Responsive Scaling".
  - [DONE] 1.6 Reserve the top-left system-bar area per device (design shows a 160x36 placeholder) and verify nothing overlaps Roblox's native top bar on any device.
  - [DONE] 1.7 Playtest checkpoint: gallery open on three device classes; sign-off on look before the shell is built.
- **Outcome:**
  > Sizing: `fill` (design px under one UIScale, canvas stretched to the screen's aspect) scaled by viewport **height**. Glass: **blur** (scene blur behind full-screen panels, design alphas). Icons: one 128px white PNG per Material Symbols glyph (IDs in `SkinAssets`). Learned the hard way: React clears its container's children on first render (never `createRoot(PlayerGui)`); `AutomaticSize` text mis-sizes under the canvas UIScale (use `useTextWidth`); a text shadow must be a lower-ZIndex sibling, not a child; clamp spring alphas used for glow/hover (overshoot flashes). The gallery's control strip was dropped; `HudApp` now mounts the gallery HUD mock as the interim HUD (pulled forward from Task 2), and the template HUD is no longer mounted.

### Task 2: HUD shell and full-panel frame (placeholder content)
- **Status:** [DONE]
- **Why here:** First half of the first-playable slice. The shell and panel frame are the container every later screen lives in; building them on placeholder content proves tabs, breadcrumbs and open/close without any backend.
- **Depends on:** 1
- **Refs:** Scope > HUD (world view); Scope > Full panel (shared frame); Integration points (HudApp / HUD components replaced); Success criteria (fewer clicks, nothing hidden; state stays small)
- **Acceptance criteria:**
  - World HUD shows: three pill tabs top centre (Catalogue, Stores, Outfits); bottom-left a large Basket button with a Robux-total badge plus Create avatar, Save to Roblox, Reset; bottom-right World options toggle; reserved top-left space.
  - Each tab opens the full panel on that tab; switching tabs inside the panel works; close returns to the world.
  - Breadcrumbs and back appear once navigation goes deeper than a tab (for example Outfits > X > Y) and each crumb pops to that level.
  - The panel left column shows an avatar-preview placeholder with Undo, a "Wearing - N" bar (opens Wearing) and a Basket card with count and CTA; Basket and Wearing open as list screens.
  - Wearing and basket state appear as badges/counts only, no always-on panels.
  - The template StatusBar, Favours and Candles HUD are gone and `HudApp` no longer reads Inventory/Favours state.
- **Associated UI:** 5a HUD; full-panel frame of 5b, 5f, 5g (left column, tabs, breadcrumb bar); World options toggle (side panel opens in Task 4).
- **Replication:** UI-only state (open panel, tab, breadcrumb stack). No world entity. Client React state in `HudApp`; nothing replicated.
- **Sub-tasks:**
  - [DONE] 2.1 Rewrite `Source/ReplicatedFirst/views/HudApp.client.luau`: world HUD, full-panel host, navigation state (tab + breadcrumb stack, push/pop/popTo, close). Mount into its own ScreenGui inside a `SkinRoot` — NOT `createRoot(PlayerGui)`: React clears its container's children on first render, which deleted other ScreenGuis in Task 1. Consider a navigation hook in `views/hooks/`. Use `/create-view`.
  - [DONE] 2.2 World HUD view (`/html-to-react-luau`, frame 5a): tab pills, Basket button with badge, action pills, World options toggle, system-bar reservation. Placeholder badge value from local state until Task 10.
  - [DONE] 2.3 Full-panel frame component (`/html-to-react-luau`, frames 5b/5f/5g chrome): left column (preview placeholder, Undo, Wearing bar, Basket card), right content area, breadcrumb/back row, close. Reuse `useTransition`/`AnimatedModal` shape; reshape `ModalWindow` rather than adding a parallel frame.
  - [DONE] 2.4 Placeholder screens for Catalogue, Stores, Outfits, Basket, Wearing and one deeper level per tab to exercise breadcrumbs.
  - [DONE] 2.5 Remove the template HUD examples in this task: `StatusBarView.luau`, `FavoursView.luau`, `CandlesView.luau`, `components/FavourTile.luau`, `components/HudButton.luau` (superseded by `PillButton` in Task 1), the Task 1 `views/gallery/` folder, and `CurrencyChip.luau` unless reshaped into the Robux/count chip; strip the Favours/Candles configs from `AnimatedModal`. Update `docs/VIEW_GUIDE.md` (HUD file structure, Props/Modal examples, StatusBarView example), `README.md` (view examples), `.claude/commands/create-view.md` and `.claude/commands/html-to-react-luau.md` references to point at the new shell components.
  - [DONE] 2.6 Playtest checkpoint on desktop, iPad and phone emulation: every tab, breadcrumb depth, close, and no overlap with the Roblox top bar.
- **Outcome:**
  > Shell built: `Hud` (root: SkinRoot fill/height/blur, navigation, placeholder look) → `WorldHud` or `panel/FullPanel` (+ `Breadcrumbs`); `hooks/useNavigation` (roots Catalogue/Stores/Outfits/Basket/Wearing + crumb stack; tapping the open tab closes); placeholder screens in `views/screens/` (Catalogue, Item, Stores root/store, Outfits root/outfit, Basket, Wearing) on `PlaceholderData` + `usePlaceholderLook` (slot rules), shared `Parts` (Thumb, PriceTag, ItemCard, ListRow, CardGrid, Heading). World options panel moved to `WorldOptionsView` (static until Task 4). Deviation agreed: ModalWindow/AnimatedModal deleted rather than reshaped — FullPanel is the one panel frame. Template HUD views, HudButton, CurrencyChip, FavourTile and the gallery deleted; docs/commands updated. Lessons: ScrollingFrames clip strokes drawn outside cells — inset grids/lists ~3px; size grid cells/scroll extents from `useLocalSize`, not AutomaticCanvasSize; labelled buttons keep text out of the press UIScale (text snaps to whole pixels and jitters, and text/shadow snap apart); tapping an active filter chip clears it. Verified on desktop, iPad and phone emulation.

### Task 3: Motion, sound and buy-prompt frame
- **Status:** [DONE]
- **Why here:** Second half of the first-playable slice. Motion and sound are the product's differentiator and are tuned on placeholder content before real data makes iteration slower. Completes the slice, so this task ends with a feel review.
- **Depends on:** 2
- **Refs:** Scope > Buy prompt; Success criteria (It feels good, State stays small); Risks (Sound direction)
- **Acceptance criteria:**
  - Every open/close, tab change, breadcrumb pop, press and badge change has considered motion (springs/tweens via the template hooks) and, where it helps, a UI sound.
  - ~~Toasts appear, stack/replace sensibly and dismiss~~ (built, then removed: see the no-toasts rule above).
  - The buy-prompt frame (single item or bundle total, Free state) opens and closes with motion and has the Roblox hand-off slot, without faking a Roblox purchase UI.
  - Basket badge and count changes animate (number roll via `useSpringNumber`).
  - Motion never reads as clutter and holds frame rate on a phone emulation.
- **Associated UI:** buy prompt (`buyOpen` in 5b/5f/5d), panel/tab/badge transitions across 5a to 5h.
- **Replication:** UI-only; client sounds are local. No world entity.
- **Sub-tasks:**
  - [DONE] 3.1 Decide sound direction and asset source (open question): style, whether assets are authored, bought or generated, and licence. List the sound slots needed (tab, open, close, press, toast, add to basket, try on/take off, purchase success, error; toast was dropped). Studio step: create the Sound instances/assets under SoundService.
  - [DONE] 3.2 Add a small client UI-sound helper in `views/hooks/` (a `useSound`-style hook alongside the existing hooks) so components trigger sounds declaratively; honour volume/mute. Use `/create-view`.
  - [DONE] 3.3 ~~Toast host and queue component~~ (removed after Task 4; no toasts) (`/html-to-react-luau`), driven by `HudApp` React state, with a `showToast` callback passed down; spring in/out.
  - [DONE] 3.4 Buy-prompt frame component (`/html-to-react-luau`): title, text, price or Free, tint swatch, Cancel/Confirm, with the confirm callback left as a stub for Task 11.
  - [DONE] 3.5 Motion pass over the shell from Task 2 using `useSpring`, `useTransition`, `useSpringNumber`, `useDrag` where it fits; record the spring presets in the tokens module; add the press/hover states to every interactive component.
  - [DONE] 3.6 Feel review and playtest on three device classes. Tune; capture phone-tightness issues for later tasks.
- **Outcome:**
  > Sound: ObsydianX "Interface SFX Pack 1" (CC0), style-3 tones + two cursor tones picked by measurement (brightness/harshness) for a bright-soft arcade feel, trimmed from 6s padding to 0.2–1.5s; the pack has no swipes, so `switch` / `worldIn` / `worldOut` are synthesised by `tools/build_swipes.py`. Files + provenance in `assets/ui/sounds/`, IDs in `SkinAssets.sounds`, volumes in `Tokens.sound`, played by `views/Sounds` (local, throttled, preloaded at startup with icons — first play was slow from downloading). Toasts were built here, then removed after Task 4: a pop-up where you're looking is in the way, so feedback is in-place state change + sound. Panel open/close sounds come from Hud on state change; buttons that open/close it are silent to avoid doubles; switching tabs or Basket/Wearing inside the panel plays `switch`. Toasts: `views/Toast` (latest replaces current, ~1.8s, CanvasGroup fade). Buy prompt: `views/BuyPrompt` (dense glass, tap-outside cancels; confirm does a placeholder purchase until Task 11). Motion: panel fades + body drops (CanvasGroup with render margin), tab bar and close button vanish instantly on close, screens slide in on navigation (`useAppear`), world HUD rises back, World options slides, counts roll; presets in `Tokens.spring`/`Tokens.motion`. HUD actions reachable via `HudContext`. Lesson: a full-size invisible "swallow taps" button must sit at a lower ZIndex than the controls it guards.

### Task 4: World options (client rendering, persistence) and double-jump flight
- **Status:** [DONE]
- **Why here:** First layer in the SPEC order. It is the lowest-risk real feature: one persisted per-player model, purely client rendering, and it exercises the whole intent / model / state / view loop and the persistence round trip for the first time.
- **Depends on:** 2, 3
- **Refs:** Scope > World options (side panel); Replication strategy (World options; Flight); Integration points (persistent user state: World options preferences); Risks (Flight in a shared world)
- **Acceptance criteria:**
  - World options panel opens from the bottom-right toggle: time of day 0-24 h slider, sky preset (Clear / Clouds / Studio / Void), floor colour (5 swatches), floor pattern (Grid / Checker / Plain), brightness 50-150 %, shadows toggle, and the hint "Double-jump to fly. Use it to find a quiet spot."
  - Time of day drives sky colour, sun/moon position and stars; changes apply instantly while dragging.
  - Settings are private: another player in the same server does not see your sky, floor, brightness or shadows.
  - Settings persist per player and are restored on rejoin.
  - Double-jump makes the player's own character fly using normal Roblox client-owned movement.
- **Associated UI:** World options panel (frame 5a side panel / `worldOpen`); sky, floor, orb, stars and haze behaviour in `logic.js` `renderVals`.
- **Replication:**
  - World options: **cosmetic / not position-critical**. The `WorldOptionsModel` holds the saved preference (logical, persisted). Each client renders its own sky/lighting/floor locally (Lighting and local changes to a tagged floor part are not replicated, so they are private by construction). No server Workspace change.
  - Flight: **moving / position-critical**. It is the player's own character; physics stays client-owned (default network ownership of the player's character). The server holds no flight model and reconstructs nothing. Do not mirror flight state into a model.
- **Sub-tasks:**
  - [DONE] 4.1 Config: world options ranges, presets, floor swatches, pattern list, flight tuning (speed, double-jump window). Use `/create-config`, then create the Studio config module.
  - [DONE] 4.2 Network: add a `WorldOptions` controller (actions such as SetOptions/Reset, validated ranges and enums) and a `WorldOptions` state in `Network.luau`.
  - [DONE] 4.3 Model: `Source/ServerScriptService/models/user/WorldOptionsModel.luau` (User scope; persisted via `syncState`). Use `/create-model`. Note PersistenceService debounces writes, but the view should still commit on release, not per drag tick.
  - [DONE] 4.4 Controller: `Source/ServerScriptService/controllers/WorldOptionsController.luau` with validation and ACTIONS table. Use `/create-controller`.
  - [DONE] 4.5 View, panel: World options side panel (`/html-to-react-luau`) with sliders, swatches, segmented pills, switch; local draft state applies immediately, intent fires on release/selection; observes the saved state on join.
  - [DONE] 4.6 View, world renderer: a client renderer that applies the options to Lighting (ClockTime/brightness/shadows, sky objects and presets), sun/moon/stars equivalent, and the floor (colour and pattern). The floor is a Studio-authored, CollectionService-tagged part; per the skill, mount the renderer from `HudApp` as an effect on props (no BindableEvent bridge), or as a tagged-instance workspace view if no HUD coupling is needed. Studio step: tag the floor part, add Sky/atmosphere instances.
  - [DONE] 4.7 Flight: client double-jump flight view (`.client.luau`, `/create-view`, Pattern A) using Humanoid state/jump request; configurable via 4.1. No server component.
  - [DONE] 4.8 Open question handling: flight in a shared world (collisions, griefing, "quiet spots" depend on world layout, which is not designed). Implement flight with the simplest safe defaults (no player collision change, config switch to disable) and flag the layout dependency.
  - [TODO] 4.9 Analytics: world-options changes tracked via controller auto-instrumentation; confirm they show in GA4 debug.
  - [DONE] 4.10 Playtest: two clients, change settings on one, confirm the other is unaffected; rejoin to confirm persistence; fly on touch device.
- **Outcome:**
  > Server: `WorldOptionsModel` (User scope, persisted) + `WorldOptionsController` (Set/Reset; every field validated against `WorldOptionsConfig`, numbers clamped/snapped, colours must be in the palette). Config: Studio-authored `ReplicatedStorage.Config.WorldOptionsConfig` with a reference copy in `Source/ReplicatedStorage/Config/` (keep in step — edit both). Client: `hooks/useWorldOptions` (saved + live draft; change on drag, commit on release/tap; reset; normalises stale saves), `WorldRenderer` (client-only Lighting/sky/clouds/floor — private by construction; waits for game load; floor parts tagged `WorldFloor` in Studio), `WorldOptionsView` (fixed title with reset + close, scrolling body), `components/Slider` + `Toggle`, `FlightView.client` (double-tap jump; climb on hold; hover; lands on touch-down; 0.35s take-off grace). Final panel: Time; Sky (Clear/Clouds/Studio/Void — Studio/Void use flat skybox images); Floor (lightness slider + orange/yellow/green/teal/purple/white); Pattern colour (lightness + same palette); Pattern (strength + Grid/Studs/Checker preview tiles); Lighting 0–200% (exposure, clamped by Roblox to ±3 stops); Shadows. Defaults match the place in Edit mode (14:30, Baseplate #cc5f00, black grid = white at 0% lightness, 20% strength). Colours saved as hex, not list positions. Picking a colour resets its lightness to 100%. Lessons: UIStroke on a TextButton outlines its text unless ApplyStrokeMode = Border; LayoutOrder is an integer (fractions collapse); slider tracks must be inset by half a knob inside the hit area; a dense Atmosphere fogs the floor — use flat skybox images for solid skies; JumpRequest repeats every frame while held (press gap 0.06s); command-bar `require` gets a separate module copy (can't read live model registries). Not verified: two-client privacy test, GA4 events (4.9), flight on a touch device. Open: flight in a shared world awaits a world layout (4.8 — `flight.enabled` switch in config).

### Task 7: Catalogue data layer
- **Status:** [DONE]
- **Why here:** The browse UI depends on what Roblox's in-experience catalogue can actually provide. This is the largest unresolved technical risk in the spec, so it is investigated and the data path is built before the UI that consumes it.
- **Depends on:** 3 (reordered: runs before 5 and 6, so browsing has real items before try-on exists)
- **Refs:** Scope > Catalogue (categories, search, filters); Risks (Catalogue data source and rate limits); Integration points
- **Acceptance criteria:**
  - Open questions on catalogue data are answered with evidence and recorded: what search/category/price facets the API exposes, colour as a facet or not, rate limits, caching, and where Featured/Halloween/New/Trending come from.
  - The server can return a page of items (id, name, type/sub-type, price, creator, favourites count) for a category/sub-category/search/price/colour query, within agreed limits.
  - Results for a given player's query are delivered to that player only.
- **Associated UI:** none yet (data layer); shapes follow `logic.js` ITEMS (name, main category, sub-category, price, colour, creator, favourites, flags).
- **Replication:** **Cosmetic / not position-critical.** Catalogue results are logical per-player data, not world entities. Delivery follows the existing intent/state pattern (candidate: a per-player session model holding the latest result page) unless the investigation chooses client-direct calls (see Open questions).
- **Sub-tasks:**
  - [DONE] 7.1 Investigation spike: evaluate `AvatarEditorService` catalogue search and item-details calls, `MarketplaceService` product info, thumbnail services, and any other in-experience catalogue API for: query facets, page size, rate limits, caching windows, and availability from client vs server. Decide server-proxied vs client-direct, and how colour and price filters are applied (server facet vs client filter over fetched pages). Write findings into the open questions.
  - [DONE] 7.2 Investigation: curation source for Featured, seasonal (Halloween), New, Trending, and any items outside the live catalogue. Do not invent one; present options (config-curated lists, a catalogue query heuristic, an external list) for the user to choose. *(Replaced: Featured/Halloween/New/Trending dropped for the marketplace categories; see open question 11.)*
  - [DONE] 7.3 Config: `CatalogueConfig` (categories, sub-categories, price presets, colour swatches, page size, cache lifetimes, curated lists as decided). `/create-config` plus Studio module.
  - [DONE] 7.4 Service: `services/game/CatalogueService.luau` (event-driven with an in-memory cache; add a loop only if cache expiry demands it) wrapping the API with throttling and retry/backoff. `/create-service`. *(Superseded by client-direct: no server service; throttling/backoff/cache live in `views/catalogue/CatalogueClient.luau`.)*
  - [DONE] 7.5 Network/Model/Controller: `Catalogue` controller (Search, LoadMore, GetDetails) and a `CatalogueModel` (UserSession) that syncs the latest page to the owner. If 7.1 chooses client-direct, replace this with a client Pattern A module plus a server validation hook for try-on (Task 5 will validate ids). `/create-model`, `/create-controller`. *(Client-direct chosen: `CatalogueClient` + `hooks/useCatalogue`; the server validation hook moves to Task 5.)*
  - [DONE] 7.6 Slot/type mapping: map catalogue asset types to slot rules that Task 5.2 then uses so browse, wear and the Wearing screen share one definition. *(Type→category/chip placement is derived from `CatalogueConfig` in `CatalogueClient`; the slot rules themselves are Task 5.2.)*
  - [DONE] 7.7 Server-side playtest via slash commands: query each category, apply price/colour filters, observe cache hits and rate-limit behaviour. *(Done as client-side Studio probes and a play test rather than slash commands, since there is no server path.)*
- **Outcome:**
  > Client-direct catalogue (user call): `AvatarEditorService:SearchCatalog` has a per-caller budget (~36 searches/26s, then HTTP 429 for 30s+), and the client's budget is separate from the server's, so a server proxy would put every player on one budget. `views/catalogue/CatalogueClient.luau` searches, caches per query (5 min), pages, waits out a throttle and retries once, and remembers every item seen (`item(id)`, `similar(item, n)`); bundle ids are negated so they can't collide with asset ids. `hooks/useCatalogue.luau` debounces typing (0.4s), searches at once on tab/chip change, and drops stale results by generation. Tabs follow the marketplace menu (`catalog.roblox.com/v1/search/navigation-menu-items`): Body, Clothing, Classic (split out, user), Accessories (Gear kept, user), Backgrounds, Animations, Makeup; Bodysuits has no API type, so it's left out; every query pins asset/bundle types, as untyped ones return non-wearables. `CatalogueConfig` is Studio-authored (reference copy in the repo). Real items carry thumbnails (`rbxthumb://`), descriptions, creator, favourites; `PlaceholderData.item` falls back to them so Item/Basket/Wearing/Buy work for real items. Extras from review: item-page description (4 lines), card click sound, search clear button, placeholder hidden on focus, Backspace / mouse back to go back. **Lessons:** `UserInputService.InputBegan` never reports mouse-button KeyCodes; the Input Action System is the documented route, but in Studio the side buttons of the user's plug-and-play IntelliMouse didn't reach Roblox at all (kept the binding; check in the live client). The UI sometimes renders low-res just after start-up in every game: that's engine render resolution, with no script control. EditableImage *can* read catalogue thumbnails in Studio (0.41s per 58) despite the docs; live servers still need checking (Task 8).

### Task 8: Catalogue browsing UI
- **Status:** [DONE]
- **Why here:** First real content in the panel. With the data layer in place, build the screen that most of the experience is spent in.
- **Depends on:** 3, 7. Until Task 5 lands, Try/Take off drive the local stand-in look (badges and counts change; the character does not), and the preview feedback arrives with Task 6.
- **Refs:** Scope > Catalogue; Success criteria (fewer clicks for try on / take off / find an item; nothing hidden)
- **Acceptance criteria:**
  - Category tabs (Body, Clothing, Classic, Accessories, Backgrounds, Animations, Makeup, from CatalogueConfig; done in Task 7) with per-category chips; the grid updates live.
  - Search box (keyword search done in Task 7); paste an item link or ID resolves to that item; the grid updates live as filters change; empty state and match count.
  - Filters, matching the marketplace (user, 2026-10-08: "more filters than just price and colour"): **price** popover with two-handle min/max slider and presets (Free, Under 50, 50-100, 100+); **colour** (dominant colour from thumbnails, see open question 11); **creator** (All, Roblox, or a typed creator name); **sales type** (All, Limited/Collectibles, Timed Options); **availability** (include off-sale/unavailable items); and **sort order** (Relevance, Most Favourited, Bestselling, Recently Created, Price low-high, Price high-low, with the time window for Most Favourited and Bestselling). All map onto `CatalogSearchParams` except colour.
  - Load more as the grid scrolls to the end.
  - Item cards show an orange "wearing" badge, a white "in basket" badge, and price/Free/Owned.
  - Tapping a card opens the menu: Try / Take off, Add/Remove basket, Buy/Get, View.
  - Trying an item on and taking it off takes one tap from the menu, with in-place and preview feedback.
- **Associated UI:** 5b Catalogue (badges and price range); colour and price popovers; card menu.
- **Replication:** **Cosmetic.** Card images are client-rendered thumbnails or viewports, not world entities. Open question: thumbnails vs 3D viewports on cards (cost on phones).
- **Sub-tasks:**
  - [DONE] 8.1 Decide card imagery (open question): static thumbnail images vs ViewportFrame previews, with a phone performance check. *Decided (user, 2026-10-08): thumbnails on cards (`rbxthumb://`, already in from Task 7); a 3D preview is a stretch for the item page only (8.8).*
  - [DONE] 8.2 Catalogue screen (`/html-to-react-luau`, frame 5b): category tabs, sub-chips, search, colour and price popovers (two-handle slider component, new in `components/`, justified by reuse in Stores), grid with staggered entrance (`useTransition` list mode), empty state.
  - [DONE] 8.3 Item card component with badges and the tap menu; menu actions wired to the local stand-in look (swapped to Avatar intents in Task 5), basket callbacks (stubbed to local state until Task 10) and buy-prompt frame (Task 3, confirm stubbed until Task 11).
  - [DONE] 8.4 Paste link/ID: parse catalogue URLs and bare IDs client-side, resolve the item through the Task 7 path, open the item page (Task 9) or show not-found inline at the search field.
  - [DONE] 8.5 Wire `HudApp` subscription to `Catalogue` and `Avatar` states; debounce search; pagination/load more on scroll.
  - [DONE] 8.6 Analytics: search, filter and view events (item id, category) via the controller or `trackEvent`. *Closed as a duplicate (user, 2026-10-08): picked up by Task 21's analytics completeness.*
  - [DONE] 8.7 Playtest: find an item in fewer taps than CAC (record the count), filter combos, rapid try-on/take-off, phone layout. *Done (user, 2026-10-08).*
  - [DONE] 8.8 Stretch: consider a 3D preview (ViewportFrame) as an option on the item page, e.g. a toggle between the thumbnail and a rotatable model. Weigh phone cost; may fold into Task 6's preview rig. *Done: the item page's "3D" button swaps the thumbnail for a turnable model of the item alone (see outcome).*
- **Build in three hand-backs (agreed 2026-10-08):** (1) card menu, load more, paste link/ID in the design's bottom bar; (2) filter bar: Sort, Colour, Price, Filters (creator, sales type, availability) as upward popovers; (3) colour classification + live-server check. Analytics (8.6) last.
- **Outcome:**
  > Built in three hand-backs. (1) Card menu over the thumbnail (Try / basket / Buy / View, one open at a time), load more as the grid nears the end, paste a marketplace link or bare ID (`CatalogueClient.parseLink` / `lookup`; a bare ID tries asset then bundle) in the design's bottom bar. (2) Sort (six orders + time window), Price (new two-handle `RangeSlider`, presets; searches on release, since the rate limit can't take a search per pixel), Filters (creator: anyone / Roblox / typed; sales type; include off-sale) as upward popovers in `screens/CatalogueFilters.luau`; all map onto `CatalogSearchParams` and each combination caches separately. (3) Colour: `catalogue/ItemColour.luau` reads thumbnails with EditableImage (Allow Mesh & Image APIs on), buckets sampled pixels by HSV and keeps every colour with ≥22% share; `hooks/useColourFilter.luau` filters client-side and keeps loading until 30 match or 5 pages; a spinner card holds the next slot while it churns; cards tint to their detected colour. Tuned on real thumbnails: grey below s 0.2 (pale skin is low-saturation), skin tones weighted 0.15, very dark reds are brown. User: accurate enough, a little slow but passable, caching spot on. Live-server permission for reading thumbnails not separately confirmed (the filter shows a message if it's blocked).
  > Review extras that changed shared behaviour: **buttons fire on press** (`views/Press.luau`: mouse down, touch down, but touch inside a ScrollingFrame fires on release so scrolling doesn't trigger taps; gamepad via Activated); the **root screen stays mounted under pushed pages** (FullPanel), so back from an item returns to the same results and scroll; **back handlers stack** (overlays close before navigation); Limited items show their **lowest resale price** (a sold-out collectible reports Price 0); item page shows a selectable **ID** and "Limited"; text **shadow alignment** fixed (shadow was centred, text left-aligned).
  > 3D view (8.8, user-requested after close): `catalogue/ItemModel.luau` builds the item alone, since the client can't load assets (InsertService is server-only). It builds a throwaway avatar from a HumanoidDescription holding just the item (`Players:CreateHumanoidModelFromDescription`, ~0.3s; bundles via their UserOutfit) and lifts out accessory/layered/shoe parts or the head; classic clothing and bodies show on a plain body. Animations, emotes, backgrounds, gear and makeup get no 3D button. `screens/ItemViewer3D.luau`: ViewportFrame framed to the bounding sphere, auto-spin until touched, drag to turn, wheel to zoom, opaque card-coloured background (a transparent one fringes dark items).
  > **Lesson (3D):** a freshly built avatar's parts can sit at their authored mesh positions (even hundreds of studs away) and nothing simulates in a ViewportFrame, so the rig is solved by hand from the root at rest pose: attachment joints (AnimationConstraint / RigidConstraint, current rigs) first, enabled Motor6D/Weld as fallback, then accessories by matching attachment names (their welds carry stale offsets). Also: a play session runs the source synced at play start, so restart play after edits before testing.
  > **Lessons:** `React.createBinding` in a render body resets on every re-render (use `useBinding`); a Thumb child can't be named "Ring" (Thumb owns one); taps pass through non-button Frames to cards beneath, so popovers sit on a blank TextButton; screenshot coordinates are scaled, so click positions come from AbsolutePosition.


### Task 5: Avatar core, server-side try-on
- **Status:** [DONE]
- **Why here:** Everything after this (catalogue, basket, outfits) calls "try on". It must exist as a validated, server-authoritative service with slot rules and Undo before any UI browsing depends on it.
- **Depends on:** 3, 7, 8 (reordered after the catalogue; tapping Try in the Task 8 grid then changes the real character)
- **Refs:** Scope > Catalogue (wearing rules); Scope > Full panel (Undo); Scope > HUD (Reset); Replication strategy (Player avatar); Integration points (Avatar); Risks (Undo semantics)
- **Acceptance criteria:**
  - Try on and take off change the player's real character on the server, and other players in the server see it.
  - Same-slot items replace each other (one hair, one top and so on); accessories and emotes stack.
  - Undo reverses the last avatar change; Reset returns to the player's own avatar; Take everything off works.
  - Appearance survives character respawn.
  - Rapid or malformed requests are rejected (rate limit, id validation).
- **Associated UI:** Undo button and "Wearing - N" bar in the panel's left column (frame 5g); feedback is the avatar changing plus a sound (no toasts).
- **Replication:**
  - **Player avatar (try-on): server Workspace is the source of truth.** The server applies the change to the real character (HumanoidDescription application is a candidate API to evaluate) and Roblox replicates it to everyone. No client reconstruction of the character.
  - Logical worn list and undo history: a session model feeds the HUD badges/counts and the Wearing screen. It never carries position or appearance data.
- **Sub-tasks:**
  - [DONE] 5.1 Investigate and decide (open questions): which item types can be applied without owning them (accessories, classic clothing, bundles/hair combos, animation packs, emotes, faces/heads), failure behaviour for off-sale/unloadable items, how emotes (not appearance) are handled, and the scope of Undo (avatar changes only, or basket/outfit actions too). Document findings in the open questions section.
  - [DONE] 5.2 Config: slot rules (Hair; Clothing/sub-slot; Face; Head; Animation pack; stackable types), rate limit and undo depth. `/create-config` plus Studio module.
  - [DONE] 5.3 Network: `Avatar` controller actions (TryOn, TakeOff, TakeOffAll, Undo, Reset) and `Avatar` state.
  - [DONE] 5.4 Model: `models/userSession/AvatarModel.luau` (UserSession scope: resets each join; holds worn item ids, slot map, undo stack). Use `/create-model`. Open point: restore last look on rejoin is not in the spec; confirm before adding persistence. *Built as `models/user/AvatarModel.luau` (User scope, persisted, user call); undo history session-only in `_undo`.*
  - [DONE] 5.5 Service: a game service (`services/game/AvatarService.luau`, event-driven) that applies the worn list to the character on server, re-applies on `CharacterAdded`/respawn, and resolves "Reset" from the player's own saved description. Use `/create-service`.
  - [DONE] 5.6 Controller: `controllers/AvatarController.luau` with validation (asset id type/shape, catalogue type check, cooldown), slot-rule application via config. Use `/create-controller`.
  - [DONE] 5.7 Wire HUD: Undo, Reset, Take everything off, and the Wearing count badge to the new state/intents (preview and Wearing screen follow in Task 6). Feedback is in place plus sound (no toasts).
  - [DONE] 5.8 Analytics: custom `try_on`, `take_off`, `reset` events with item id/type (feeds phase 3 signals).
  - [TODO] 5.9 Playtest with two clients: try on from a debug trigger/slash command, verify the other client sees the change, slot replacement, undo, respawn. *Single-client checks done in Studio (try on, slot replacement, undo, respawn, reset, rejoin, gear); a two-client check is still open — Roblox replicates the server character, so it is expected to hold.*
- **Outcome:**
  > Ran after the catalogue (reordered), so Try works on real items from the grid, the card menu and the item page. Decisions (user): undo covers avatar changes only; **the look is saved** (`AvatarModel`, User scope) and on first join is seeded from the player's own Roblox avatar; gear is held but inert (scripts stripped). `AvatarConfig` holds the slot rules: one per slot (hair, body, head, each layered and classic garment, shoes, animation pack, gear, background, each makeup type, eyebrows, eyelashes); accessories stack to 10 and emotes to 8, the oldest dropping off. `AvatarService` dresses the real character on the server from the player's own avatar (body, head, skin, proportions, animations) plus `worn`, re-dresses on respawn and coalesces applies; bundles go through their UserOutfit (a full body brings parts, head + face + mood, colours, proportions and its bundled accessories, e.g. the Paladin's helmet). `AvatarController` resolves every item server-side (`AvatarEditorService:GetItemDetails`, cached) and accepts only types `AvatarConfig` knows, with a 0.2s cooldown; it tracks `try_on` / `take_off` / `reset` with item id/type. HUD: Wearing count, Undo (disabled when empty), Reset to your avatar (undoable), mock items refused with the error sound; the basket stays local until Task 10.
  > Review extras: the Catalogue keeps its tab / chip / search / filters / scroll across closing the panel (`hooks/useSessionState`, per-browse scroll in `CardGrid`); `/state` and `/commands` also print their full reply to the Output.
  > **Lessons:** makeup isn't an AccessoryType: it's a `MakeupDescription` child of the HumanoidDescription; a bundle's first UserOutfit item is the full look (later ones, e.g. "- Face", are partial); a body bundle's outfit carries accessories and a mood animation that matter to how it looks; `GetEquippedEmotes` returns `{ Name, Slot }` tables. Command-bar `require` gets separate module copies, so client tests that fire intents must go through the real UI.


### Task 6: Avatar preview, Wearing screen and tap-avatar-to-open-Wearing
- **Status:** [DONE]
- **Why here:** Gives the try-on state its UI (preview, Wearing list) so every try-on from the catalogue has a visible result in the panel.
- **Depends on:** 5
- **Refs:** Scope > Full panel (live avatar preview, Wearing bar); Scope > Wearing; Scope > HUD (tap avatar opens Wearing); Replication strategy (Avatar preview)
- **Acceptance criteria:**
  - The panel's left column shows a live preview of what the player is currently wearing and updates as items change.
  - Wearing screen lists worn items with owned or price per item; Take off per item; Add unowned items to basket; Save as outfit; Take everything off.
  - Tapping your own avatar in the world (mouse or touch) opens Wearing.
  - Preview never moves or alters the real character.
- **Associated UI:** 5g Wearing; panel left column in 5b/5f/5g; 5a ("Tap your avatar in the world").
- **Replication:** **Cosmetic / not position-critical.** The panel preview is a client-only cosmetic copy of the current look (clone/rig rendered in a ViewportFrame; evaluate cloning the character vs building a rig from the description). It is derived from the real character in server Workspace; the server never knows about it. The preview is not stored in any model.
- **Sub-tasks:**
  - [DONE] 6.1 Avatar preview component (`/html-to-react-luau` for the frame, `/create-view` for the rig logic): client-only rig in a ViewportFrame, rotates/spring-settles, updates on Avatar state changes. Studio-free.
  - [DONE] 6.2 Wearing screen (`/html-to-react-luau`, frame 5g): rows with owned/price, Take off, Add to basket, Save as outfit (stub until Task 12), Take everything off, empty state.
  - [DONE] 6.3 Tap-own-avatar hook in `views/hooks/` (input raycast against the local character, mouse and touch) calling `HudApp`'s open-Wearing callback, so no new cross-script bridge pattern is introduced.
  - [DONE] 6.4 Item data the screens need (name, price, owned) come from a small client lookup keyed by asset id; use the Task 7 item shape.
  - [TODO] 6.5 Playtest on touch: tapping the avatar while the camera moves and while the panel is open. *Desktop verified; touch not tested (tap logic: short, still taps only).*
- **Outcome:**
  > The preview is a client-only clone of the player's real, server-dressed character (`panel/AvatarPreview.luau`), posed at rest via `ItemModel.restPose`, facing the camera, rebuilt when the character's descendants settle (try-on, respawn); it fills the Wearing card edge to edge. `components/ModelViewer.luau` is the shared turnable viewport (item page 3D view too): models live in a WorldModel so they can animate and be raycast; drag to turn, wheel zooms towards the point under the cursor (raycast, then scale the camera towards it), middle-drag pans exactly with the cursor. Only the cards' orange "View N items · ₹X" buttons open Wearing / Basket, so turning the avatar never switches screens. Tap your own character in the world opens Wearing (`hooks/useTapAvatar`).
  > Animation bar (`panel/AnimationBar.luau`): Idle / Move / Air / Swim / Emotes, each a menu upward; animations come from the live Animate script (worn packs show), emotes from a server lookup (`AvatarEmoteAnimations` Bolt remote function: the server opens the emote asset to find its animation; budget 20 per 10s, client shares in-flight requests). Trying on an emote plays it at once; a pack switches to Walk. Only an open menu's button is highlighted; a press outside closes it, another bar button switches menus.
  > Review extras: Wearing ordered unowned paid → free → owned; own-avatar items marked owned (migrated on join); Buy / Get per row in Wearing and Basket; a full body also clears the Head slot (`AvatarConfig.alsoReplaces`); Robux shown as "₹12,499" everywhere (`Tokens.robux`); disabled buttons dimmed (Undo greys out); Roblox's emote menu opens with "." (not B); emotes work while flying (emote-friendly hover only when the emote menu is open and you're still; falling otherwise); hold Shift to run (28) and fly 1.75x faster, shift-lock moved to Ctrl; computers only (user call).
  > **Lessons:** an emote's catalogue id isn't loadable as an animation (zero-length track); `createBinding` in render resets each render (use `useBinding`); measured text widths round a hair short, so only truncate capped labels; a strict server cooldown swallowed the second of two quick, legitimate requests (use a budget + client in-flight sharing); Roblox's Animate refuses emotes in Freefall, and Running mid-air flails when moving.


### Task 9: Item page, favourites and More like this
- **Status:** [DONE]
- **Why here:** The first persisted per-user collection after World options; item pages are the destination of View from cards, Wearing, Basket, outfit rows and stores, so they come before those.
- **Depends on:** 8
- **Refs:** Scope > Item page; Integration points (persistent user state: favourite items); Out of scope (More like this is same-category rule only)
- **Acceptance criteria:**
  - Large preview; name, type, creator, colour, favourites count.
  - Try on / Take off, Add to basket, Buy / Get free; favourite toggle (persists across sessions); More like this row (same category, same sub-category first).
  - Breadcrumbs show the path and back works (for example Catalogue > Item).
- **Associated UI:** Item page (opened from 5b View; shown inside 5d/5c breadcrumbs).
- **Replication:** Large preview is **cosmetic**: client-only rig/viewport of the item on a copy of the current look, not a server object. Favourites are logical persisted state.
- **Sub-tasks:**
  - [DONE] 9.1 Model: `models/user/FavouritesModel.luau` (User scope) holding favourite item ids (and, later, favourite store ids for Task 18). `/create-model`; note index size limits.
  - [DONE] 9.2 Network/Controller: `Favourites` controller (ToggleItem), validated against catalogue ids, rate-limited. `/create-controller`.
  - [DONE] 9.3 Item page screen (`/html-to-react-luau`): preview (reuse Task 6 rig), details, action row, favourite toggle with count, More like this row (same-category rule as a client/server query over cached results).
  - [DONE] 9.4 Hook up breadcrumbs for deep pushes from any source (catalogue, basket, wearing, outfit rows, stores) via the navigation hook from Task 2.
  - [DONE] 9.5 Playtest persistence of favourites across rejoin and the More like this row.
- **Outcome:**
  > Favourites: `FavouritesModel` (User scope, persisted, "Asset:123" / "Bundle:45" keys, capped at 500, oldest drops) and `FavouritesController` (Toggle; validates via AvatarService's cached catalogue lookup; 0.25s cooldown; favourite / unfavourite analytics). Item page: star button (orange when yours) carrying the catalogue's Roblox-wide favourite count ("★ 2,757,860") instead of a separate meta line, which would overflow the info column; cards show a star badge. More like this is a real catalogue search: same chip, topped up from the category (`useCatalogue` skips an empty category, for mock items). User call: favourites list deferred to Outfits/Stores, which have favourites tabs. Our star is separate from Roblox favourites (AvatarEditorService:PromptSetFavorite exists but prompts every time). Breadcrumbs from every source were already working (root screens stay mounted under pushed pages).


### Task 10: Basket model and Basket screen
- **Status:** [DONE]
- **Why here:** Basket persistence and the screen are the first half of the "Basket and buying" layer; buying (Task 11) needs a real basket to buy from.
- **Depends on:** 9
- **Refs:** Scope > Basket; Scope > HUD (Basket button badge); Integration points (persistent: basket)
- **Acceptance criteria:**
  - Add/remove from basket works from the card menu, item page, Wearing and outfit screens (outfit sources follow in later tasks); the Basket button badge shows the Robux total of unowned basket items, and the panel Basket card shows count and CTA ("View N items · ₹X ›", as changed in Task 6).
  - Basket persists across sessions.
  - Basket screen: rows with Try on / Remove, summary (items, already owned, total), Try on everything, "pull in what you're wearing".
  - Counts and badges animate; no always-on basket panel.
- **Associated UI:** 5f Basket; basket button and card in 5a and the panel.
- **Replication:** logical persisted state (**cosmetic / not position-critical**): model plus client view, per the template pattern.
- **Sub-tasks:**
  - [DONE] 10.1 Config: `basketLimit` (100) and `basketBudget` (10 changes per 2 s) added to `AvatarConfig` rather than a new config.
  - [DONE] 10.2 Model: `models/user/BasketModel.luau` (User scope); entries are the worn-item record, prices aren't saved.
  - [DONE] 10.3 Network/Controller: `BasketController` (Add, Remove, AddMany, RemoveMany, Clear), items checked with `AvatarService.resolve`. "Try on everything" uses Avatar `WearMany` (slot rules already there), and "pull in what you're wearing" is a client-side `AddMany` of the unowned worn items, so no TryAll / AddWorn actions.
  - [DONE] 10.4 `usePlaceholderLook` reads `Network.State.Basket`; toggle / add / pretend-buy send Basket intents.
  - [DONE] 10.5 Basket screen: Add what I'm wearing button; Buy all / Try on everything / Add disabled when they'd do nothing.
  - [DONE] 10.6 Prices come from `CatalogueClient.remember` (filled in the background); "already owned" finalised in Task 11.
  - [DONE] 10.7 Analytics: `basket_add`, `basket_remove` events.
  - [DONE] 10.8 Playtest: add from every entry point, rejoin persistence, basket badge sums.
- **Outcome:** Basket is a persisted `BasketModel` (worn-item records, no saved prices, capped at `AvatarConfig.basketLimit` 100) changed through `BasketController` (Add, Remove, AddMany, RemoveMany, Clear; items checked with `AvatarService.resolve`; a budget of 10 changes per 2 s rather than a cooldown, so quick taps aren't swallowed). No TryAll / AddWorn actions: Try on everything reuses Avatar `WearMany`, and Add what I'm wearing is a client `AddMany`. The client updates optimistically: changes are held as pending over the server's list until the server agrees, or for 3 s, after which the server's list wins. The starter mock basket is gone. Verified: card-menu add/remove, rejoin persistence, rapid toggling staying in sync; the 3 s fallback path wasn't exercised (Studio latency is ~0).

### Task 11: Buying through Roblox prompts, ownership awareness, Save to Roblox, Create avatar
- **Status:** [DONE]
- **Why here:** Completes layer 4. Needs the basket and the buy-prompt frame, and finishes the "Owned" labels used by cards, Wearing, Basket and outfits.
- **Depends on:** 3, 10
- **Refs:** Scope > Buy prompt; Scope > Basket (Buy all); Scope > HUD (Create avatar, Save to Roblox); Constraints (Roblox-native surfaces stay native); Integration points (analytics: purchase)
- **Acceptance criteria:**
  - Buy / Get on an item, and Buy all on the basket, Wearing or outfit selection, go straight to Roblox's own purchase prompt (decided in testing: our confirmation frame was one step too many and was removed). We never fake the Roblox UI.
  - Ownership is known per item (cards, item page, Wearing, Basket, outfit rows show Owned; Buy is disabled/relabelled when owned; summaries exclude owned items from totals).
  - Purchased items leave the basket (not Wearing; there they become Owned) after confirmed purchase; cancel or failure leaves everything unchanged. Roblox's prompt shows the reason; we only play a sound.
  - Save to Roblox uses Roblox's own avatar-editor save prompt for the current look.
  - Create avatar does what is decided in the open question.
- **Associated UI:** Buy prompt frame (Task 3), 5f Basket (Buy all), Item page Buy, 5a action pills Create avatar and Save to Roblox.
- **Replication:** Purchases and avatar saves are Roblox-native and server-confirmed; ownership cache is logical (**cosmetic / not position-critical**), a session model.
- **Sub-tasks:**
  - [DONE] 11.1 Investigation (open questions): candidate APIs to evaluate for catalogue purchases (`MarketplaceService` single and bulk purchase prompts, purchase-finished signals), ownership checks (`MarketplaceService` ownership calls, `AvatarEditorService` inventory-access prompt), bundle vs asset handling, free-item "Get", and what confirms success. Also candidate for Save to Roblox: `AvatarEditorService` save-avatar prompt. Confirm bulk "Buy all" is possible or define a sequential fallback.
  - [DONE] 11.2 Decide Create avatar semantics (open question): its behaviour is not specified in the design (it only shows a toast, which we don't use). Options include start a blank avatar, open Roblox's avatar-creation prompt, or reset to a default. Await the user's choice before building.
  - [DONE] 11.3 Service/Model: `services/game/OwnershipService.luau` plus `models/userSession/OwnershipModel.luau` caching owned item ids per player with refresh after purchases. `/create-service`, `/create-model`.
  - [DONE] 11.4 Network/Controller: `Purchase` controller (RequestBuy for ids, RequestSaveToRoblox) validating ids, deduplicating owned items and enforcing size limits; handles purchase-finished results and updates Basket and Ownership models. `/create-controller`.
  - [DONE] 11.5 Wire the Task 3 buy-prompt frame to real confirm/cancel; wire Buy all, outfit-selection Buy, item Buy/Get to it; success/cancel/failure shown in the buy prompt and on the items themselves (no toasts); purchase sound.
  - [DONE] 11.6 Wire Save to Roblox and Create avatar pills.
  - [DONE] 11.7 Analytics: `purchase_prompted`, `purchase_completed`, `purchase_cancelled` with item ids and Robux total (phase 3 signal).
  - [DONE] 11.8 Playtest in a published test place with real (cheap/free) items; Studio purchase prompts are limited, so record anything that can only be verified live.
- **Outcome:** Findings (11.1): `MarketplaceService:PromptBulkPurchase` takes assets and bundles together (one prompt for Buy all, up to 20 items) but **can only be called on the server**, while `PromptBulkPurchaseFinished` **can only be heard on the client**. So `PurchaseController.Buy` resolves the items, drops owned ones and opens the prompt; `PurchaseView` reports the outcome (`Finished`); the server re-checks ownership itself (`PlayerOwnsAsset` / `PlayerOwnsBundle`, with one 2 s recheck for items Roblox said succeeded), removes bought items from the basket and records them in `OwnershipModel` (UserSession: `owned`, `purchase` {id, state, reason, bought}). Studio test purchases grant nothing, so in Studio only an item the client reports as bought counts as owned for the session. Ownership is checked once a session per item for worn, basket and item-page items (`Check`, budgeted). Create avatar (11.2, user) = `AvatarEditorService:PromptCreateOutfit` (save the look as a new Roblox outfit); Save to Roblox = `PromptSaveAvatar`; both client-side (`AccountPrompts`). UI decisions from testing: no confirmation dialog (`BuyPrompt` deleted); Buy buttons show a spinner (new `Spinner` component, `PillButton.loading`) until Roblox's prompt ends; Wearing gets an orange Buy all; Basket gets Remove all; Remove all / Take everything off need a second press within 3 s, the armed button wiggling for attention. Lesson: UserSession models' `.get()` must use `getOrCreate`; `getOrWait` (User scope only) never returns for them and stalled player setup. Live purchases still to verify in a published place.

### Task 12: Outfits, Mine and the outfit screen
- **Status:** [DONE]
- **Why here:** First layer-5 task. Saving a look and wearing it again is the most-used core job after try-on; the outfit screen (with partial wear) is shared by Mine, Community and Roblox sources, so it is built once here.
- **Depends on:** 9, 10, 11
- **Refs:** Scope > Outfits (Mine, outfit screen, ring highlight); Scope > Wearing (Save as outfit); Integration points (persistent: saved outfits)
- **Acceptance criteria:**
  - Outfits tab, source Mine: "New outfit" saves what you're wearing; outfits can be renamed and deleted; the outfit you are currently wearing is ring-highlighted.
  - Search filters outfits by name.
  - Outfit screen: large preview, Wear all, every item with checkboxes (Select all/none), Wear selected, Add to basket, Buy selected (cost label for unowned selection); tapping a row opens the item page; breadcrumb shows Outfits > Name > Item.
  - Save as outfit from the Wearing screen works and the new outfit visibly appears in Outfits (no toast).
  - Names are filtered through Roblox text filtering.
- **Associated UI:** 5d Outfit screen; Outfits root (source tabs Mine/Community/Roblox, cards, "New outfit" card); 5g Save as outfit.
- **Replication:** saved outfits are logical persisted data (**cosmetic / not position-critical**). Outfit preview is a client-only rig (reuse Task 6); "Wear all" goes through the server-applied Avatar path from Task 5.
- **Sub-tasks:**
  - [DONE] 12.1 Decide outfit data shape and limits (UserEntity per outfit, following the FavoursModel pattern with an index in a User model, vs a single User model list). Note DataStore key length for UserEntity keys (`ModelName_userId_modelId` under 50 chars) and the per-key size cap. Record the decision.
  - [DONE] 12.2 Config: outfit limit per player, name length. `/create-config`.
  - [DONE] 12.3 Model: `OutfitsModel` in the chosen scope (and its index model if UserEntity). `/create-model`.
  - [DONE] 12.4 Network/Controller: `Outfits` controller (Save, Rename, Delete, WearAll, WearSelected), text-filter names with a filtering API (candidate: `TextService:FilterStringAsync`) before storing. `/create-controller`.
  - [DONE] 12.5 Outfits screen root (`/html-to-react-luau`, frame 5d root state and `outfitCards`): source tabs (Mine active, Community and Roblox placeholders until Tasks 13 and 16), search, "New outfit" card, ring highlight when worn items equal the outfit.
  - [DONE] 12.6 Outfit screen (`/html-to-react-luau`, frame 5d): preview, checkbox rows, Wear all/selected, Add to basket, Buy selected via Task 11 flow.
  - [DONE] 12.7 Wire Save as outfit on Wearing (Task 6) and "New outfit".
  - [DONE] 12.8 Analytics: `outfit_save`, `outfit_wear`, `outfit_delete`.
  - [DONE] 12.9 Playtest: save, rejoin, wear partial selection, ring highlight, rename/delete.
- **Outcome:** 12.1 decided: one User-scoped `OutfitsModel` holding a list of { id, name, items } (items = worn-item records) with `nextId`; limits in `AvatarConfig.outfits` (50 outfits × 40 items, 30-char names), far under the DataStore per-key cap, so no UserEntity index. `OutfitsController` (Save, Overwrite, Rename, Delete, WearAll, WearSelected) takes outfit ids and item positions only; names are trimmed, capped and filtered with `TextService:FilterStringAsync` + `GetNonChatStringForBroadcastAsync`. Wear all items replaces the look (undoable). Added in testing (user): a 3D outfit preview (the server builds the look with `AvatarService.describeLook` and parents the HumanoidDescription into the player's PlayerGui via the "OutfitPreview" remote; the client builds the rig); Mine order Save card → Your avatar (own Roblox avatar, "Reset to this"; the HUD Reset button is gone and a Basket-sized Wearing button with round count callouts replaces it) → saved outfits → outfits saved on Roblox (`RobloxOutfits`: `GetOutfits` needs `PromptAllowInventoryReadAccess`, so a "Show my Roblox outfits" card asks; body parts are regrouped into their bundle via a catalogue search on the parts' shared name, or one entry; wearing one keeps the player's own body); card mosaics ordered body → heads → layered → accessories → classic → animations; Wearing offers Save as new / Save over existing (picker) and becomes Saved → Go to <outfit> while the look matches; outfit-page Buy / Add to basket need an unowned selection; names save from an orange pencil or Enter (new `edit` icon). `SearchBox` and `ConfirmButton` became shared components. Lessons: when Studio's scripts lag the repo, fix Rojo (restart Studio, accept the sync diff), never write Source by hand; UserSession models must use `getOrCreate`.

### Task 13: Outfits, Roblox username lookup
- **Status:** [DONE]
- **Why here:** Second source of the layer-5 Outfits tab, and it reuses the outfit screen built in Task 12. It has its own API risk, so it is isolated.
- **Depends on:** 12
- **Refs:** Scope > Outfits (Roblox source: search a username to load their saved outfits/current avatar)
- **Acceptance criteria:**
  - On the Roblox source, searching a username loads that user's available outfits (or at minimum their current avatar) into the same card/outfit-screen flow.
  - Not-found, private, banned and rate-limited users show a clear inline empty state.
  - Wear all and partial wear work on another user's outfit exactly as on Mine.
- **Associated UI:** 5d Outfit screen; Outfits root, Roblox source ("Search a username" placeholder).
- **Replication:** lookups are server-side requests (**cosmetic**); previews are client-only rigs.
- **Sub-tasks:**
  - [DONE] 13.1 Investigation (open question): what the platform exposes for another user's saved outfits vs only their current avatar (candidates: `Players` name/id and appearance lookup methods, `AvatarEditorService` outfit queries). If saved outfits of other users are not retrievable, present the fallback options to the user instead of deciding.
  - [DONE] 13.2 Service: `services/game/RobloxAvatarLookupService.luau` with caching and throttling. `/create-service`.
  - [DONE] 13.3 Network/Model/Controller: `Outfits` actions (LookupUser) and a session model holding the player's last lookup result. `/create-model`, `/create-controller`.
  - [DONE] 13.4 Roblox source tab UI and loading/empty/error states (`/html-to-react-luau`).
  - [DONE] 13.5 Playtest with real usernames including nonexistent and private cases.
- **Outcome:** 13.1 found: only another user's *current* avatar is readable in-game (`Players:GetUserIdFromNameAsync` / `GetHumanoidDescriptionFromUserId`, `UserService` names, falling back to `GetNameFromUserIdAsync` for accounts it skips, e.g. "mouse"); saved outfits of others, Roblox follows and fuzzy/display-name search aren't available (HttpService can't reach Roblox's web APIs). Built `RobloxAvatarLookupService` (cached, 20 lookups / 30 s, remote functions FindRobloxUser (name or id), RobloxUserLook, RobloxUserInfos) and client `UserLooks`. Decisions in testing (user): Outfits tabs by source — Current (your avatar, reset; refreshes from Roblox) · Wardrobe (default) · Creations (Roblox-saved outfits, `RobloxOutfits`) · Friends · Roblox · Community; the Roblox tab is our own private Follow (`OutfitsModel.following`): an Add a person card (username or id → shown, then confirm Follow), search filters follows, unfollow needs a second press; no auto-tracking of lookups; players-in-server cards dropped in favour of Task 22 (tap avatars). Added scope (user): faces, heads and single body parts are wearable items read from every look (body parts shown as one Body row; Creations regroup parts into their bundle via a catalogue search, else keep them); skin colour per body part (`Utils/SkinColours`; Catalogue › Body › Skin tone with a body-figure part selector, Roblox's 25-colour avatar-editor palette, Custom with hue/saturation/brightness colour sliders (gradient tracks, no fill) or hex; a Skin tone row on outfit pages opens a part-by-part detail page); body Scale (`Utils/BodyScale`; Catalogue › Scale: height, width (also depth), head, body type, proportions within Roblox's limits); Clothing › Layering reorders layered clothing (worn order = layer order). Skin and scale are part of the look: saved, undoable, stored in outfits, copied with Wear all / ticked rows. "Your own" re-reads the Roblox avatar (picker, Scale, Current, Reset). Lessons: Rojo only syncs named children of ReplicatedStorage (shared modules go in `Utils`); the compile check is syntax-only, so use-before-declare bugs only show in play; Studio skips the final save flush when Play stops.

### Task 14: Sharing, cross-server storage decision and outfit share codes
- **Status:** [DONE]
- **Why here:** Layer 6. Share codes need a lookup that works across servers, which is the first place we need storage beyond per-user DataStore. The decision made here is reused by community outfits (Task 16) and stores (Task 17), so it is made now, deliberately, before building on it.
- **Depends on:** 12
- **Refs:** Scope > Share (outfit or store); Risks (Cross-server data; moderation); Integration points (Shared/global state beyond one server)
- **Acceptance criteria:**
  - Share on an outfit screen > Reveal code produces a short, copyable 6-character code (decided in testing: no `OUT-` prefix); the code resolves to that outfit from any server.
  - Entering a code in the Outfits search opens that outfit.
  - Codes are stable per outfit, collision-safe, and revocable if the outfit is deleted.
  - The share dialog (code, copy, reveal-blur) has motion and sound.
  - User-supplied names that are shown to others pass through text filtering.
- **Associated UI:** 5e Share (Reveal code, copy, QR slot); Outfits search accepting codes.
- **Replication:** shared lookup data is logical, cross-server, not position-critical (**cosmetic**). No world entity.
- **Sub-tasks:**
  - [DONE] 14.1 Investigation and decision (open question): cross-server storage options for code lookup, community content and stores (candidates: a global DataStore, OrderedDataStore for rankings, MemoryStore for short-lived lookups, an external service via HttpService; consider `MessagingService` only for cache invalidation). Compare consistency, size limits, request budgets, cost, and moderation hooks. Do not pick on the user's behalf.
  - [DONE] 14.2 Decide code format and generation (6 characters of the design's alphabet, collision handling, deterministic vs random) and moderation/takedown approach.
  - [DONE] 14.3 Service: `services/framework` or `services/game` `SharedContentService` (decide placement: it is a dependency of several services, so framework placement may fit; justify) exposing publish/lookup/delete with throttling. `/create-service`.
  - [DONE] 14.4 Network/Controller: `Share` controller (RevealCode, ResolveCode) with validation and rate limits. `/create-controller`.
  - [DONE] 14.5 Share dialog (`/html-to-react-luau`, frame 5e): reveal with blur-to-clear on the code, copy-to-clipboard behaviour (evaluate what Roblox allows on a client), QR slot placeholder. Roblox's clipboard limitations mean the "Copy" affordance may need an alternative (select-and-show); record as a divergence if so.
  - [DONE] 14.6 Wire code entry in the Outfits search to resolve and push to the outfit screen.
  - [DONE] 14.7 Analytics: `share_reveal`, `share_copy`, `code_resolve`.
  - [DONE] 14.8 Playtest across two servers (Studio server test, then live) for code lookup.
- **Outcome:** Decided (user): Roblox DataStores for shared content (open question 16). `SharedContentService` keeps records in a global DataStore ("SharedContent") keyed by code; codes are 6 characters of the design's alphabet (no I/O/0/1, ~1e9), random and claimed atomically with UpdateAsync, one pool for every kind of shared thing (the record carries `kind`; user: a prefix was too much). A code opens the thing as it is now: rename / save-over republish, delete revokes; old `OUT-` codes are replaced on reveal. Wardrobe outfits keep `code`; Roblox-saved outfits (Creations) can be shared too, published from Roblox's own data, their codes in `OutfitsModel.creationCodes` (not the Wardrobe) and refreshed when the dialog opens. Share dialog (design 5e) at Hud level: reveal, the code in a selectable box (Roblox can't write the clipboard: a recorded divergence from the design's Copy), QR slot for Task 15; Back closes it first (Hud's own back handler: child handlers register before the parent's). Codes go in the Community tab's search (user: not the Roblox tab, which stays follows only); a code found from another tab switches there; a code-shaped name still searches normally. Shared outfit page: preview, rows, Wear all items (exact, with skin and scale), Wear selected, basket, buy. Share icon is Material `share`. Analytics: `outfit_share`, `share_resolve`. Not verified: a second account opening a code; live cross-server.

### Task 15: QR deep links
- **Status:** [DONE]
- **Why here:** Isolated because it depends on unresolved platform support (experience launch data/deep links) and on a QR encoder. Codes already work without it, so a failure here does not block Sharing's core value.
- **Depends on:** 14
- **Refs:** Scope > Share (QR deep-links back to that screen); Risks (Deep links from QR)
- **Acceptance criteria:**
  - The share dialog shows a real, scannable QR whose link lands a joining player on that specific outfit (and later store) screen.
  - A player already in the experience who opens the same link is taken to the same screen without disruption. *(Revised after 15.1: Roblox can't hand a link to a running session, because opening one always starts a fresh join. In-game, the code shown beside the QR goes in the Outfits › Community search instead.)*
  - Existing acquisition attribution through LaunchData in analytics is not corrupted.
- **Associated UI:** 5e Share (QR tile, blurred until revealed).
- **Replication:** logical data; no world entity.
- **Sub-tasks:**
  - [DONE] 15.1 Investigation (open question): what launch-data/deep-link route Roblox supports for landing a joiner in a specific experience with a payload (candidates: experience join URL with launch data, `Players:GetJoinData`, `TeleportService` and `MessagingService` for already-in-experience cases); what a QR scanned by a phone camera can open; size limits of the payload.
  - [DONE] 15.2 Integration risk: `AnalyticsService` stores `LaunchData` as the `launch_data` acquisition property and treats untagged joins as `organic`. Decide how deep-link payloads coexist (namespace the payload, or separate analytics handling); update `AnalyticsService` accordingly and note it in `docs/CONFIG_GUIDE.md`.
  - [DONE] 15.3 QR encoder: evaluate a Luau QR library already usable in the repo (check `Packages/`) vs adding one; render modules as a client component (pixels as frames or an image).
  - [DONE] 15.4 Join-time handler: a service (`services/game/DeepLinkService.luau`, event-driven on player join) that reads the launch data and tells the client which screen to open via a state/intent, honoured by `HudApp` navigation. `/create-service`.
  - [TODO] 15.5 Playtest on a phone scanning a QR shown on another device, in a live published place. *(Deferred: the experience is still private, so the link only opens for its owner. Test this once it's public and age-rated.)*
- **Findings (15.1–15.4):**
  - **The link.** `https://www.roblox.com/games/start?placeId=<id>&launchData=s:<code>`. Launch data is one string of up to 200 bytes, read with `GetJoinData().LaunchData`.
  - **Roblox share links don't fit.** Creator Dashboard share links are made one at a time by hand, so they can't carry per-code data.
  - **Only the code goes in the link.** The code's record already says what it is (`kind`) and who shared it (`ownerId`), so outfits, stores and user referral codes all share one link format. Fields follow the Mall R&D format, `key:value|key:value`.
  - **Analytics.** Share joins record `launch_data` as "share" (or the link's `c:` campaign field). DeepLinkService sends `share_join` {code, kind, owner_id, own}.
  - **The encoder.** We wrote our own: `Utils/QRCode`, byte mode, versions 1–10, all four error-correction levels, block interleaving, penalty-chosen mask. The Mall R&D generator (cloned to refs/) only scans up to version 4: it does single-block error correction and crashes on input that isn't byte mode.
  - **How it was checked.** Every version and level at full capacity decoded correctly with zxing-cpp. So did a Studio screenshot of the dialog's QR.
  - **On join.** Opens Outfits › Community › the shared outfit's page. Back lands on Community.
- **Outcome:** QR share links work end to end in Studio, using the TestLaunchData hook. The dialog has the QR on the left, with the code and hint on the right. Until the code is revealed the QR's place is an empty well with a lock: a dimmed QR looked as if it was ready to scan. The `s:` field marks share codes so they never collide with campaign tags. User referral codes will reuse this link with `kind = "user"` records. Still unverified: scanning on a phone in the public place (15.5).

### Task 16: Community outfits
- **Status:** [DONE]
- **Why here:** Layer 7. Reuses the cross-server store and share codes from Task 14 and the outfit screen from Task 12.
- **Depends on:** 12, 14
- **Refs:** Scope > Outfits (Community source); Risks (Cross-server data; moderation); Integration points
- **Acceptance criteria:**
  - A player can publish one of their outfits to Community; others (in any server) can browse and open it on the Community source.
  - Community cards show name and creator ("by pixelfox"); search by name or code works.
  - The creator can unpublish; moderation (name filtering, report or takedown path) is in place per the decision.
  - Browsing stays responsive (paged results, cached).
- **Associated UI:** 5d Outfit screen (Community source); Outfits root cards.
- **Replication:** logical cross-server data (**cosmetic**); outfit preview is a client-only rig.
- **Sub-tasks:**
  - [DONE] 16.1 Decisions (open questions): publishing rules (who can publish, limits, edit-after-publish), discovery/ordering (newest, most worn, curated), and moderation workflow. Present options; do not decide for the user.
    - **Publishing:** anyone can publish, with no cap. The best outfits surface through sort chips, modelled on CAC's dropdown: Popular · Trending · Newest · Favourited · Recent · Mine. Most Worn is folded into Popular.
    - **Frozen at publish (applies to shares as well, which reworks Task 14):** sharing or publishing makes an evergreen copy. Editing the original (rename, save over) detaches its code, so the old code keeps opening the old copy, and sharing again makes a new one. Creations keep their code only while the copy matches Roblox.
    - **Deleting an outfit:** its copies stay live, and stay published if they were, but the creator credit is hidden (anonymous).
    - **A code is its Community entry (changed after stage C):** revealing a share code lists the outfit on Community, so there's no separate Publish. Once published it stays, and it belongs to Community: there's no owner Remove (it was tried, then dropped). Deleting the outfit from your Wardrobe makes the copy anonymous; only admins take entries down.
    - **Moderation:** names are filtered, players can report, and an entry is auto-hidden at 3 distinct reports. Admins can take an entry down with `/communitycontroller Moderate <code> hide|restore|takedown` (rank 200+ in the group, or Studio/creator).
  - [DONE] 16.2 Extend `SharedContentService` with community publish/list/unpublish and paging; add a Community browse model (UserSession) delivering pages to the requester. `/create-model`.
  - [DONE] 16.3 Controller actions (Favourite, BrowseCommunity, Report, Open, Moderate; listing happens in Share) in `Outfits`/`Community` controller. `/create-controller`.
  - [DONE] 16.4 Community source UI (`/html-to-react-luau`): grid, paging, publish toggle on Mine outfit cards/outfit screen.
    - The Community tab has chips under the tabs and real cards (`catalogue/CommunityOutfits`, pages of 24 loaded on scroll). Search filters the loaded cards by name, or finds a share code. The placeholder Community outfits are gone.
    - No Publish button: revealing a code in the Share dialog lists the outfit (see 16.1), and a "Published to Community" line says so. An outfit with a code opens the dialog already revealed, with its QR, until an edit detaches the code; the outfit page shows "code XXXXXX" too. Opening the dialog lists an older code that wasn't yet.
    - You can star your own outfits, as on social media (changed after stage C).
    - A shared outfit's page, when listed, shows wears and favourites, a star (your own too) and Report (two taps). Opening the page adds it to Recent. Your own wear (on someone else's outfit) and your own star show at once, until the server's counts catch up.
    - New icons: `flag`, `cloud_off`.
  - [DONE] 16.5 Analytics: `community_publish`, `community_open`. In Studio these were queued and sent to GA4: outfit_share, community_publish (on reveal), community_open, community_wear, outfit_wear (source "community"), and community_report. They aren't confirmed in BigQuery yet: the BigQuery connection set up here (`bq_wgc`) is another game's property, so checking needs Ripple's GA4 export connected. *(Deferred: the BigQuery check waits for that connection.)*
  - [PARTIAL] 16.6 Playtest across servers, moderation edge cases (blocked names), unpublish. Done in Studio (one player; test entries owned by user id 1, cleaned up afterwards):
    - Wearing someone else's outfit counts a wear. The minute's flush wrote wears 1, Popular 1 and Trending 1.
    - With 2 reports seeded, the UI's report was the third and hid the entry ("reports"); it left the orderings and the grid.
    - The chat command `/communitycontroller Moderate <code> restore` relisted it, and `takedown` deleted it.
    - Name filtering fails safe: a failed filter refuses the rename, and a Creation's name falls back to "Outfit".
    - *(Deferred to the live game: two servers, real report thresholds, filtered names (Studio doesn't filter) and admin takedown seen from another server.)*
- **Outcome:** Community outfits work end to end in Studio, built in four stages (frozen shares, backend, UI, playtest).
  - **Frozen copies:** shares and Community entries are evergreen copies. Editing an outfit detaches its code, deleting it hides the creator's name, and the copy itself never changes.
  - **Code = Community entry:** revealing a code publishes the outfit, and nothing else does. The user merged the two actions. An owner Remove was tried and dropped: once published, an outfit belongs to Community.
  - **Orderings:** three OrderedDataStores: Newest, Popular (wears + 3 × favourites) and a weekly Trending store, so Trending never needs clearing. Counts are batched per server and written every 60 s and on shutdown. Pages of 24 are cached for 60 s on the server and the client.
  - **Personal chips:** Favourited, Recent and Mine come from the player's OutfitsModel lists.
  - **Instant feedback:** your own wear (on others' outfits) and your own star show at once, until the server's counts catch up. Self-stars are allowed (user: like social media); self-wears aren't counted.
  - **Moderation:** filtered names, one report per player, auto-hide at 3 reports, and admin `/communitycontroller Moderate <code> hide|restore|takedown`.
  - **Lessons:**
    - Lists cached in a module must be reloaded by whoever watches them after a reset, or the screen sits on a spinner. A failed load needs a back-off, or it loops.
    - Count-based UI needs the "max of server and seen + mine" rule, so a wear isn't counted twice.
    - From Studio tools, chat slash commands can be sent with `TextChannel:SendAsync` (the call hangs, so spawn it); CoreGui chat can't be typed into.
  - **Deferred:** live two-server checks, real report thresholds, filtered names, and BigQuery (16.5, 16.6).

### Task 17: Stores data and backend
- **Status:** [DONE]
- **Why here:** Layer 8. Stores add a new cross-server entity with ratings/visits and codes, plus several unresolved business questions, so the data model and backend are agreed and built before the UI.
- **Depends on:** 9, 14
- **Refs:** Scope > Stores (Home carousels, Store page, My stores); Scope > Share (store codes); Risks (What a store is; cross-server data); Integration points (favourite stores, owned stores)
- **Acceptance criteria:**
  - A store is persisted as a curated set of catalogue items with name, creator, rating and visits, published/unpublished, readable across servers.
  - Visits and rating update when players open or like a store; counts are bounded against abuse.
  - Store codes (`STR-XXXXXX`) resolve a store from any server.
  - Home categories (Sponsored, Popular, Top rated, Favourites, My stores) can be queried.
- **Associated UI:** none yet; data follows `logic.js` STORES (name, rating %, visits, sponsored flag) and the store-page sections.
- **Replication:** logical cross-server data (**cosmetic**); no world entity.
- **Sub-tasks:**
  - [DONE] 17.1 Decisions (made 2026-10-13):
    - **What a store is:** a curated set of any catalogue items, plus outfits. Anyone can make one. "Sell your own items" gets reworded (Task 19). An outfit put in a store is published to Community too (its own code, wears and favourites, like any Community outfit).
    - **Revenue share:** none in phase 1. Each purchase records the store it came through, so points for curators can be added later. **Ask this question again before moving on from Task 17.**
    - **Sponsored:** paused (no paid placement without a way to earn). The Sponsored category is left out for now.
    - **Rating:** favourites (a star, like Community outfits), not % liked. Top rated = most favourited.
    - **Visits:** one per player per store per day, never the owner's; batched like Community counts. The page shows total visits and Popular ranks by total.
    - **Codes:** the same 6-character pool as outfits, no `STR-` prefix. A store keeps its code for good through edits. An unpublished store is a private draft: its code works only for its owner.
    - **Moderation:** as Community. Names filtered on create and every rename; auto-hide at 3 reports; admin hide, restore and takedown.
    - **Limits:** 3 stores per player, 4–100 items to publish, names 3–30 characters (StoresConfig).
    - **Store page:** Bestsellers by purchases through the store (item favourite counts until there are sales); New arrivals by the order items were added; Collections rule-based from config. May change once seen in Task 18.
  - [DONE] 17.2 Config: `StoresConfig` (types synced; live module created in Studio, reference copy in `Source/ReplicatedStorage/Config/`).
  - [DONE] 17.3 `StoresService`: stores are `kind = "store"` records in the SharedContent code pool, edited in place; unique names (`StoreNames`); rankings Popular / Top rated / Newest; batched visits, favourites and sales; moderation. Community's ranking and paging code moved to a shared `RankedPages`, and report counting to `SharedContentService.report`.
  - [DONE] 17.4 Model: `StoresModel` (User): own stores, favourites, visit days. No browse model needed: browsing is a remote function, as for Community.
  - [DONE] 17.5 Controller: `StoresController`. Create, Rename, AddItem, RemoveItem, AddOutfit, RemoveOutfit, Publish, Unpublish and Delete are pulled forward from 19.2 so the backend can be tested. Also Favourite, Report, Open and Moderate; `StoreAction` (answers with an error the UI can show), `BrowseStores` and `GetStore` (a code or an exact name) remotes. Purchases carry the store they were bought through (PurchaseController).
  - [DONE] 17.6 Store page sections, server-side from item details (batched, cached): Featured, New arrivals, Bestsellers, Collections.
  - [DONE] 17.7 Slash-command playtest. Checked: create, add items (duplicates refused), Publish refused under 4 items, duplicate and taken names refused, 3-store cap, rename frees the old name, delete, outfits added once, own visit not counted, own favourite counted, hide/restore off and back on rankings, flush of visits/favourites/sales (an item not in the store ignored), page sections. Not yet: a second player's visit, 3 real reports, Buy through a store. The remotes were checked from a real client in Task 18.
- **Outcome:** Stores are records in the shared code pool (`kind = "store"`), edited in place so the code never changes; names are unique through a `StoreNames` DataStore. Ranked lists (Popular, Top rated, Newest) share `RankedPages` with Community; visits, favourites and sales are batched and flushed every minute and on shutdown. Lessons: in Studio each `SendAsync` slash command needs its own `task.spawn` (it never returns), and Bolt remote functions hang when invoked from the Client command bar, so server code is tested by requiring the service in a Server `execute_luau`. Revenue share: none in phase 1 (re-asked when the task closed).

### Task 18: Stores UI, home, store page, collections, favourites, store share
- **Status:** [DONE]
- **Why here:** The browsing half of layer 8, once the backend returns real data. It reuses the item card, carousel and share dialog from earlier tasks.
- **Depends on:** 3, 8, 15, 17
- **Refs:** Scope > Stores (Home, Store page); Scope > Share (store); Success criteria (fewer taps, nothing hidden)
- **Acceptance criteria:**
  - Stores home shows Netflix-style carousels per category (Sponsored, Popular, Top rated, Favourites, My stores), each with See all; tapping a category tab shows it as a grid and tapping it again returns home.
  - Search by name, or enter a store code, opens that store.
  - Store page: header with rating and visits, Favourite and Share; featured item viewer with arrows (try, basket, view); Bestsellers and New arrivals carousels with See all; Collections tiles that open their own grid.
  - Share on a store gives a `STR-XXXXXX` code and QR (via Tasks 14 and 15).
  - Favourite stores persist.
- **Associated UI:** 5h Stores home; 5c Store page; 5e Share (store variant); item cards from 5b.
- **Replication:** **Cosmetic**, client-rendered UI; featured item viewer previews are client-only rigs.
- **Sub-tasks:**
  - [DONE] 18.1 Stores home (frame 5h): tabs Popular · Top rated · Favourites · My stores (Sponsored paused, 17.1) that toggle a grid, a carousel per tab with See all (`Parts.CardRow`: a sideways ScrollingFrame, not `useDrag`), search by loaded names plus a code or exact name from any server, empty states. Store cards are a mosaic of the store's first items (no store logos yet).
  - [DONE] 18.2 Store page (frame 5c): header (favourites and visits instead of % liked), featured viewer with arrows (Try on, Basket; picture or name opens the item), Bestsellers and New arrivals carousels with See all, an Outfits row (the store's Community outfits), collection tiles, and the See all / collection grid (`storeSection`). Report (twice) on others' stores.
  - [DONE] 18.3 Favourite store toggle (StoresController / StoresModel rather than FavouritesModel); the count moves at once; Favourites carousel and tab.
  - [DONE] 18.4 Store share: the share dialog's store variant, shown at once (a store always has its code; no `STR-` prefix, per 14.2). A QR join opens the store (Hud, DeepLinkService).
  - [DONE] 18.5 Item cards inside stores reuse the card menu; Buy from a store carries its code (Bestsellers, purchase analytics).
  - [DONE] 18.6 Analytics: `store_open`, `store_favourite`, `store_share` (a Share action, analytics only).
  - [DONE] 18.7 Playtest. Checked on desktop in Studio: home carousels, tab toggle to grid and back, search by name, code and a miss, store page sections, share dialog, a collection grid with breadcrumbs, no console errors. User playtest on desktop: liked the Netflix-style rows (21.7 brings them to Catalogue and Outfits); See all now clears the scroll bar. Not yet: phone / iPad layouts, tap counts vs CAC (Task 21).
- **Outcome:** Stores home is a column of carousels (`Parts.CardRow`, a sideways ScrollingFrame with fixed cells) with See all; a tab shows its list as a grid and a second tap goes home. The user liked it and wants the same for Catalogue and Outfits (21.7). Store pages are cached on the client for 30 s and on the server for 60 s. Bestsellers and New arrivals order every item, so See all shows the lot. Scrolling lists need a right pad (8px) before the scroll bar, or right-aligned text runs under it.

### Task 19: My stores and Create store
- **Status:** [DONE]
- **Why here:** Last feature of layer 8. It has the most open design and business questions, so it is last, built on a fully working store browsing experience.
- **Depends on:** 17, 18
- **Refs:** Scope > Stores (My stores: Create store; own stores published/unpublished); Risks (What a store is)
- **Acceptance criteria:**
  - My stores carousel/grid shows "Create store" and the player's own stores marked Published or Unpublished.
  - A player can create a store (name, a chosen set of items), edit it, publish and unpublish it; a published store appears in browse and resolves via its code.
  - Names are filtered; per-player limits enforced.
- **Associated UI:** 5h "My stores" row and tab ("Create store - Sell your own items"; "My Store - Unpublished"). The create/edit flow is not in the design (gap).
- **Replication:** logical persisted/shared data (**cosmetic**).
- **Sub-tasks:**
  - [DONE] 19.1 Decided (user, 2026-10-14): edit in place, no separate editor. My stores starts with a Create store card (a name dialog; the new draft's page opens). Your own store page has an editable name (the outfit name field) and an owner bar: status (draft count towards the 4 to publish, Published, Hidden), Publish / Unpublish and Delete (twice). Items go in and out through a store button beside View in any item card's menu (shown once you have a store), which opens a picker of your stores with ticks; outfits likewise from your shared outfit's page (it must be on Community first). Revenue share re-asked on closing Task 17: still none for phase 1.
    - **Rows (user, 2026-10-14, after seeing it):** the owner lays out the page as rows. Featured is pinned first and owner-filled (no longer "the first items"). Named rows hold items or outfits (chosen when made). Bestsellers, New arrivals and Collections are rows the owner switches on or off and places. An item can be in several rows (the 100-item limit counts distinct items); it leaves the store when it's in no row. Adding from elsewhere picks store › row (ticks). Adding from inside a store: each row's Add tile opens the Catalogue in pick mode (banner "Adding to Store › Row", tap to add/remove, Done back to the store); an outfits row's opens a list of your Community outfits. Stores from before rows get Featured (first 4), "Items" (all), the automatic rows and "Outfits" on read.
    - **Rows reworked (user, 2026-10-14):** every row is Items or Outfits, filled By hand or By search, with a style (Square, Wide, Hero, Single, Grid, Tile; outfits Square, Grid, Tile), a limit (1, 4, 10, 20, 30, 60; Hero 2–6: portrait cards across, no scrolling, 2 both wide, 3–4 the first wide, 5–6 all narrow) and a name. Hand-filled rows show items as the owner puts them in (orders were tried and dropped, with the store's per-item sales count: purchases still carry the store code in analytics). Bestsellers, New arrivals and Collections rows are gone; Featured is an ordinary Single row. An items search is set in the Catalogue's setup mode ("Search for Store › Row", Use this search saves the tabs, chip, keyword, creator, colour, price and sort; Cancel or Back leaves it); an outfits search is a Community sort (Popular, Trending, Newest; no "only mine": there's no per-owner index). Search rows are found by each viewer's client, so they aren't the store's items (limits, sales). A store with a search row can publish without 4 hand-picked items. The row menu (Add row, a row's settings) opens from its button like a modal context menu (user: open where you're looking), not a centred dialog, and the row previews its settings live (Cancel puts it back). Name fields' pencils sit just after the name.
  - [DONE] 19.2 Controller actions: built in Task 17 (Create, Rename, Publish, Unpublish, Delete, with name filtering and item validation); AddItem / RemoveItem / AddOutfit / RemoveOutfit now take a row, plus AddRow, RenameRow, RemoveRow, MoveRow (StoresService row helpers, `StoresConfig.maxRows` 12, `rowNameLength` 1–24), and SetRowItems (a manual row's whole list in order: pick mode's Done and reordering; new items looked up on Roblox first; outfits rows can only reorder or drop their own).
  - [DONE] 19.3 Store editing UI: `StoreDialogs` (store › row picker, Add outfits, Add row, Create store; Hud-owned like the share dialog), the card menu's store button (`Parts`), the owner bar and in-place rename, row headings with Add items / Add outfits (a black button; the Add tiles went, 2026-10-15), the row menu, reorder, up / down, remove (StoresScreen), Catalogue pick mode (Hud state, banner with Cancel and Done, tap-to-toggle cards in CatalogueScreen; picks are kept until Done saves them with SetRowItems, `nav.restore` back to the store), reorder mode (the row in a line with left / right arrows on each card, Cancel / Done), outfits rows in every style (OutfitsScreen.mosaic lays an outfit's pictures out square, wide: big first plus 2×2, or tall: big first plus a line of three; a Single outfit has Wear all items and View), the outfit page's store button; `StoresClient.act` calls `StoreAction` and drops cached pages and lists on success. Checked in Studio: rows of every style render (search rows find items), the row menu opens by its button (above, below or beside), Add row → search setup → Use this search saves and returns to the store, old stores convert.
  - [DONE] 19.4 My stores wiring on Stores home: the Create store card in the My stores row and tab while under the limit.
  - [DONE] 19.5 Analytics: `store_create`, `store_publish` (with `store_unpublish`, `store_delete`, `store_open`, `store_favourite`, `store_share`, `store_report`: StoresController, Task 17); purchases carry `store_code`.
  - [TODO] 19.6 Playtest: create, publish from one server, see it from another. Deferred with Task 16's two-server checks: the user closed the task after single-server testing (2026-10-15).
- **Outcome:** Stores are edited in place on their own page, laid out as rows the owner chooses: Items or Outfits, filled by hand or by a search (a Catalogue browse chosen in setup mode, or a Community sort), each with a style (Square, Wide, Hero 2–6 portrait cards, Single, Grid, Tile) and a limit. Rows preview live while their menu is open; hand-filled rows keep the owner's order (reorder mode with arrows; ordering and per-store sales counting were dropped). Pick mode keeps picks until Done (SetRowItems), with Cancel. Decisions came from seeing it: menus open from their button rather than as pop-up modals ("open where you're looking"), and outfits get every style, with picture layouts that suit the card shape. Lessons: a Luau if-expression yields only its first value (`local a, b = if x then f() else nil, nil` leaves b nil); measure local size from the frame mounted on first render (a ref only on the loaded frame read 0, so scale fell back to 1); and a mode started from a task shouldn't end on the first render where its screen isn't showing, only when you move off it.

### Task 20: Retire template example features and refresh docs
- **Status:** [DONE]
- **Why here:** By now our own models, controllers, views, services and configs exist, so the guides can cite them. Removing the examples earlier would have left the docs with nothing to point at; removing them last satisfies "replaced as this work lands" without breaking the guides mid-way.
- **Depends on:** 19
- **Refs:** Constraints (Template example features replaced; doc and skill references updated in the same change); Integration points (HudApp, Analytics); `docs/PROJECT_BRIEF.md` Decisions
- **Acceptance criteria:**
  - Candles, Shrine, Cash Machine, Bazaar, Favours and the gold/treasure Inventory are removed from source (models, controllers, views, services, configs, Network entries), with no dangling references.
  - README, all `docs/*_GUIDE.md`, `docs/SLASH_COMMANDS.md` and `.claude/commands/*.md` examples point to the new in-repo equivalents (or, where no equivalent exists, are retained per the open-question decision) and `docs/PROJECT_BRIEF.md` Decisions is updated.
  - The project loads with no errors; the analytics "gold" dimension is replaced.
- **Replication:** none (removal).
- **Sub-tasks:**
  - [DONE] 20.1 Decide retirement policy (open question): remove every example, or keep one example for any pattern with no in-repo replacement (for instance the dynamic ServerEntity pattern and CollectionService workspace views). Decided 2026-10-16: remove all; patterns with no in-repo equivalent (Server, UserEntity, ServerEntity scopes; views on tagged interactables) stay in the guides as short samples labelled illustrative (tag `Monolith`).
  - [DONE] 20.2 Remove server examples: `models/user/InventoryModel`, `models/server/ShrineModel`, `models/userEntities/FavoursModel`, `models/serverEntities/CandlesModel`; controllers `BazaarController`, `CashMachineController`, `ShrineController`; `services/game/CandleService`; Network entries (Bazaar, CashMachine, Shrine controllers; Candles, Favours, Inventory, Shrine states, types).
  - [DONE] 20.3 Remove client examples: `BazaarView`, `CandleView`, `CashMachineView`, `ShrineView`, and configs `CandlesConfig`, `FavoursConfig` plus their ConfigTypes (and the Studio config modules; note that these are Studio-only).
  - [DONE] 20.4 Replace the `gold` example in `services/game/AnalyticsDimensions.luau` with a real dimension (for example basket count or worn count) and update `AnalyticsConfig.globalParams` (Studio config) and `docs/CONFIG_GUIDE.md`.
  - [DONE] 20.5 Update docs and skills: `README.md`, `docs/MODEL_GUIDE.md`, `docs/CONTROLLER_GUIDE.md`, `docs/VIEW_GUIDE.md`, `docs/SERVICES_GUIDE.md`, `docs/CONFIG_GUIDE.md`, `docs/SLASH_COMMANDS.md`, `docs/BOLT_API.md` if referencing, `.claude/commands/create-model.md`, `create-controller.md`, `create-view.md`, `create-service.md`, `create-config.md`, `html-to-react-luau.md`, `docs/PROJECT_BRIEF.md`, `CLAUDE.md` if needed.
  - [DONE] 20.6 Studio cleanup checklist: tagged Workspace objects (Shrine, Bazaar, CashMachine), `ReplicatedStorage.Assets` Candle, and config modules to be deleted by hand (not Rojo-managed). Done via MCP: also the disabled StarterGui StatusBar / Favours / Candles ScreenGuis and their ServerStorage.TagList entries; AnalyticsConfig.globalParams set to the four counts.
  - [DONE] 20.7 Smoke playtest: clean boot with no warnings; all features from Tasks 4 to 19 still work.
- **Outcome:** Every template example is gone from source, Studio and docs; the guides, README, SLASH_COMMANDS and create-* skills quote our own modules (BasketModel / BasketController as the primary worked examples), and the README tutorial became "Featured Picks". Scopes and patterns we don't use yet keep short samples labelled illustrative, so the monoliths can become their first real examples. Analytics global dimensions are now basket_count, worn_count, outfits_count and stores_count. While re-homing examples the docs turned out to be stale in other ways (src/ paths, a StateEvents/IntentActions world, "player always last", command-bar test scripts that can't work against getOrWait), and those were corrected too; the Hud.luau snippet in VIEW_GUIDE and MODEL_GUIDE's ModelRunner block are still simplified. Rojo moved to port 34879 (2026-10-16).

### Task 21: Polish, analytics completeness and success-criteria review
- **Status:** [DONE]
- **Why here:** The success criteria are judged side by side with CAC in playtests, not by a metric. This closing task audits against them and fills gaps accumulated during the build.
- **Depends on:** 20
- **Refs:** Success criteria (functional parity; fewer clicks, nothing hidden; state stays small; feels good); Integration points (Analytics); Devices
- **Acceptance criteria:**
  - A side-by-side CAC comparison records: feature parity (what CAC does vs ours or an equivalent), and tap counts for try on, take off, buy what you're wearing, save/load an outfit, find an item. Ours is lower on each.
  - Every feature is reachable from the three tabs, the HUD buttons or the avatar itself. No mode-dependent hidden UI.
  - Wearing and basket state show only as badges and counts, never always-on panels.
  - Every open/close, tab change, press and state change has motion and, where it helps, sound; nothing reads as clutter.
  - iPad and desktop equivalent; phone usable. Analytics covers try-on, basket, purchase, outfit save/share and navigation.
- **Associated UI:** All frames 5a to 5h, World options panel, buy prompt.
- **Replication:** none new.
- **Sub-tasks:**
  - [DONE] 21.1 Navigation analytics: a navigation intent/controller (or `trackEvent` calls) for tab opens, breadcrumb depth and screen views, validated against a fixed screen list. `/create-controller`.
  - [PARTIAL] 21.2 Verify analytics events from Tasks 4 to 19 reach GA4 with consistent naming; update `bigquery/` notes and `/analytics` references if events need documenting. Names checked and catalogued in `.claude/commands/analytics.md` (2026-10-20); batches send ("Sent batch"), but neither BigQuery connection holds Ripple's GA4 property, so arrival in GA4 is unchecked.
  - [PARTIAL] 21.3 CAC side-by-side playtest script: parity checklist plus tap-count table; record results in the feature folder notes (not a new doc unless asked). Script and traced counts at the end of this plan; the measured columns wait for the playtest.
  - [DONE] 21.4 Feel pass: audit every interactive element for hover/press states, motion and sounds; remove anything cluttering; tune springs and volumes. Audit done (2026-10-20); first fixes in: card press/hover springs, card menu in/out, badges grow in, filter popovers rise in, tap-outside closes sound, rename-on-Enter sound, leaving pick mode sounds, press released on any input end, blur on the panel springs, all volumes listed. Then (2026-10-20): going back slides the root screen in from the left (the crumb row's space stays instant: easing it too made the slides look diagonal); the World HUD's buttons sink away as the panel opens; and the spring solver sub-steps (1/240 s), since one step per frame went unstable at low frame rates (Studio unfocused) and stiff springs oscillated and grew. Still open, and not noticed in play (user, 2026-10-20), so low priority: StoreRowMenu and animation menu in/out, swapped content (Add a person, overwrite picker, skin editor, 3D viewer, banners), text links / swatches / list rows hover. Store row header clutter is accepted (user, 2026-10-20: stores carry some by nature, and only bought-in players make them). Carousels drag by their labels and gaps with the mouse (only a card's thumb is its button); scroll bars stay.
  - [TODO] 21.5 Device pass on desktop, iPad and phone: sizing issues captured in earlier tasks, touch targets, safe areas, performance (frame rate with previews and carousels).
  - [TODO] 21.6 Triage and fix, or log for phase 2, anything found. Confirm with the user that phase 1 is acceptable.
  - [DONE] 21.7 Netflix-style home rows for Catalogue and Outfits, like the Stores home (user liked it in Task 18): a titled carousel per list (`Parts.CardRow`) with See all opening the full grid, and the tabs toggling between rows and grid.
- **Outcome:** Closed by the user (2026-10-20) with 21.2's GA4 check, 21.3's measured playtest, 21.5's device pass and 21.6's sign-off left to the next wave of testing (a test plan to come), since they are testing and iterating. Built: navigation analytics (tab_open, screen_view, panel_close) and an event catalogue in the analytics skill; home rows for Catalogue (per chip) and Outfits (per source), sharing Parts.HomeRows with Stores; carousels drag by their labels (only a card's thumb is its button); a feel pass (card press/hover, card menu, badges, popovers, sounds, volumes, back slide, World HUD sinking away). Decisions: try-on and outfit cards keep their menu / page first (they feel good, even at a tap more than CAC); store clutter is fine. Lessons: an audit read from code isn't a list of visible faults (report it as such, with steps to see each); the spring solver took one Euler step per frame and went unstable when the frame rate dropped, so it now sub-steps; and two springs moving one thing on different axes read as a diagonal.

### Task 22: Other avatars in the world
- **Status:** [TODO]
- **Why here:** Added during Task 13 (user, 2026-10-13): copying what someone nearby is wearing belongs on the avatars themselves, not as cards on the Roblox tab (the "players in this server" cards were removed). Last in phase 1 so it builds on the finished outfit page.
- **Depends on:** 13
- **Refs:** Scope > HUD (tap your own avatar opens Wearing); Task 13 outcome (another user's look on the outfit page; `RobloxAvatarLookupService` already reads an in-server player's look as what they wear here)
- **Acceptance criteria:**
  - Tapping another player's avatar in the Workspace opens their look (what they're wearing here) on the outfit page: preview, items, skin colours, Wear all items / Wear selected, Add to basket, Buy, Follow.
  - Tapping your own avatar still opens Wearing.
- **Associated UI:** the outfit page (Task 12/13).
- **Replication:** none new (reads the other player's server-side look on request).
- **Sub-tasks:**
  - [TODO] 22.1 Extend the tap-avatar raycast (`useTapAvatar`) to other players' characters; open the outfit page for them.
  - [TODO] 22.2 Playtest with two clients.

---

## Open questions

Each needs a user decision (or a recorded finding) before or during the named task. None has been decided in this plan.

1. ~~**Sizing (Task 1).**~~ Decided: `fill`, scaled by height.
2. ~~**Fonts and icons (Task 1).**~~ Decided: Nunito (built in); one image per Material Symbols icon.
3. ~~**Glass panels (Task 1).**~~ Decided: blur behind full-screen panels.
4. ~~**Sound direction and asset source (Task 3).**~~ Decided: ObsydianX Interface SFX Pack 1 (CC0) + our synthesised swipes; see Task 3 outcome.
5. **Flight in a shared world (Task 4).** Collisions, griefing and where "quiet spots" are depend on world layout, which isn't designed. Phase-1 defaults are provisional.
6. ~~**Undo scope (Task 5).**~~ Decided (user, 2026-10-08): avatar changes only.
7. **Try-on coverage and failure behaviour (Task 5).** Which item types can be tried on without owning them, and what happens for off-sale or unloadable items and emotes.
   *Findings (Studio test, 2026-10-08):* server-side `Humanoid:ApplyDescription` applies **non-owned** items and they replicate: rigid accessories (hair, hat, face, back), layered clothing (shirt, jacket, pants via `SetAccessories(..., true)`), classic shirt/pants/T-shirt, emotes (`SetEmotes` + `SetEquippedEmotes`; `Humanoid:PlayEmote` works client-side, unowned) and animation packs (~0.5s per apply). Bundles carry a `UserOutfit` item: `Players:GetHumanoidDescriptionFromOutfitId` gives the whole bundle (dynamic heads, bodies, animation packs). Bad or unloadable ids are **silently skipped**, so the server must resolve type first; reusing one id in two slots makes the whole apply throw. Off-sale doesn't block wearing (the asset still exists); it only matters to Buy. **Respawn resets to the player's own avatar**, so the look must be re-applied on `CharacterAdded`. Shoes, classic faces and single animations aren't individually searchable (they arrive via bundles). Proposed approach: worn list seeded from the player's own avatar on join; the description is built from their own body plus worn items; Reset re-seeds; Undo restores the previous list.
   *Decided:* see Q6 and Q8. Gear (user): held but inert, scripts stripped.
8. ~~**Restore last look on rejoin (Task 5).**~~ Decided (user, 2026-10-08): yes, persisted. `AvatarModel` is User-scoped (saved); undo history stays session-only (`_undo`).
9. **Catalogue data source and limits (Task 7).** What the in-experience APIs expose, rate limits, and whether colour is a facet or a client-side filter.
   *Findings (Studio test, 2026-10-08):* `AvatarEditorService:SearchCatalog` works on server and client. `CatalogSearchParams` facets: keyword, min/max price, asset types, bundle types (BodyParts, Animations, Shoes, DynamicHead, DynamicHeadAvatar), sort (Relevance, price both ways, MostFavorited, RecentlyCreated, Bestselling) with aggregation window (12h to all time), category filter (Featured, Collectibles, CommunityCreations, Premium, Recommended), sales type, creator, include off-sale. Page `Limit` up to 120 (default 30); a search takes about 0.2–0.7s. Results already carry id, name, item type, asset/bundle type, price, creator name, favourites count and description; `GetItemDetails` / `GetBatchItemDetails` fill in single items. Thumbnails come free via `rbxthumb://`. **No colour facet**: colour can only be a keyword ("red" works well) or nothing. Untyped queries return non-wearables (e.g. AvatarBackground), so every query should pin asset/bundle types. **Rate limit:** about 36 searches in 26s, then HTTP 429, which lasted over 30s. The client has its **own budget** (40/40 succeeded while the server was throttled).
10. **Catalogue delivery architecture (Task 7).** Server-proxied (per-player session model through the existing intent/state pattern; cacheable, protects rate limits, extra latency) vs client-direct (lower latency, but each client spends its own budget and the server still has to validate try-on ids).
   *Finding:* the throttle is per caller, so a server proxy puts every player's browsing on one shared budget that a handful of active browsers would exhaust. *Recommendation (pending user call):* client-direct search (Pattern A client module with a small cache and debounce); the server only resolves single item details (cached) to validate try-on in Task 5.
11. ~~**Curation source (Task 7).**~~ Decided (user, 2026-10-08): drop Featured / Halloween / New / Trending (CAC leftovers). Categories follow the real marketplace instead, from `catalog.roblox.com/v1/search/navigation-menu-items`: **Body** (Full Bodies, Hair, Heads), **Clothing** (Shirts, T-Shirts, Sweaters, Jackets, Pants, Dresses & Skirts, Bodysuits, Shorts, Shoes), **Classic** (Classic Shirts, Classic T-Shirts, Classic Pants; split out of Clothing, which was too busy), **Accessories** (Head, Face, Neck, Shoulder, Front, Back, Waist, Gear; Gear kept for its history. Try-on means a Tool, not a HumanoidDescription: Roblox-made gear loads via `InsertService:LoadAsset` with its scripts (tested: Bloxy Cola, Body Swap Potion, a magic carpet), and R15 hands carry a `RightGripAttachment` the Tool's handle welds to. Task 5 decides held-and-inert (scripts stripped) vs working; CAC lists gear but wearing it fails), **Backgrounds** (avatar backdrops for thumbnails and the avatar editor, not in-world; we use them in the UI behind the avatar preview, as CAC does), **Animations** (Bundles, Emotes), **Makeup** (Eyes, Lips, Face, Eyelashes, Eyebrows). Each maps to `AvatarAssetType`/`BundleType` values in `CatalogueConfig`. Emotes move under Animations.
    *Delivery decided (user):* client-direct search (Q10).
    *Colour filter (open):* must stay (a major CAC feature) but not as a keyword. No colour facet exists in the API or the marketplace menu; **in-engine thumbnail analysis works in Studio** (user enabled Game Settings > Security > Allow Mesh & Image APIs; this needs an ID-verified 13+ creator but doesn't change the game's age rating). `AssetService:CreateEditableImageAsync(Content.fromUri("rbxthumb://type=Asset&id=…&w=150&h=150"))` read catalogue thumbnails despite the docs saying only creator-owned images load; a page of 58 thumbnails loaded and classified in parallel in **0.41s** on the client. Dominant colour by HSV buckets (sampling every 4th pixel) is roughly right but needs tuning: white garments read as Grey (thumbnail shading), and mannequin skin can tip items to Red/Orange/Brown. **Risk:** must be re-verified in a published live server, since the docs' ownership rule may be enforced there and not in Studio. Fallback: an external colour index built by the Phase 3 scraper, queried via the server's HttpService. The filter fetches and classifies pages as they arrive and hides the paging.
12. **Card imagery (Task 8).** Thumbnails (cheap, static) vs ViewportFrame previews (lively, heavier on phones).
13. ~~**What Create avatar does (Task 11).**~~ Decided (user, 2026-10-09): save the current look as a new Roblox outfit (`PromptCreateOutfit`).
14. ~~**Purchase and ownership specifics (Task 11).**~~ Found: bulk Buy all works (`PromptBulkPurchase`, server-only; result client-only); bundle ownership via `PlayerOwnsBundle`. See Task 11 outcome.
15. ~~**Roblox username lookup depth (Task 13).**~~ Found: only another user's current avatar is retrievable in-game (`Players:GetUserIdFromNameAsync`, `GetHumanoidDescriptionFromUserId`, `UserService:GetUserInfosByUserIdsAsync`); `AvatarEditorService:GetOutfits` lists only the local player's outfits (after `PromptAllowInventoryReadAccess`) and HttpService can't reach Roblox's own web APIs. Decided (user, 2026-10-12): the Roblox tab shows the username search result, then players in this server (what they wear here), recent lookups, then friends.
16. ~~**Cross-server storage technology (Task 14).**~~ Decided (user, 2026-10-13): Roblox DataStores. A global DataStore ("SharedContent", via `SharedContentService`) holds shared content by code; OrderedDataStore for rankings and MemoryStore for caches when Tasks 16-17 need them; no external service in phase 1. Codes are 6 characters (no prefix: one pool for every kind of shared thing; the record carries its kind) and open the thing as it is now (the owner's changes republish it).
17. **Moderation (Tasks 12, 14, 16, 17, 19).** Approach to user-named outfits and stores, and takedown/report workflow.
18. **Deep links and QR (Task 15).** What launch-data/deep-link route Roblox supports for landing on a specific screen, and how it coexists with the existing LaunchData acquisition attribution.
19. **Community outfits rules (Task 16).** Publishing eligibility, ordering/discovery, edits after publishing.
20. **What a store is commercially (Task 17).** Whether "Sell your own items" implies creator revenue share (a business question), how sponsored placement is sourced, and how ratings and visits are defined and protected from abuse.
21. **Store creation design (Task 19).** The create/edit/publish screens are not in the design.
22. **Retirement policy for template examples (Task 20).** Remove all, or keep one example for patterns with no in-repo replacement. **Decided (2026-10-16): remove all**, illustrative samples in the guides for patterns we don't use yet.

## Phase 1 playtest: CAC side by side (Task 21.3)

Start each flow in the world with the panel closed. Count every tap or click; typing doesn't count, and Roblox's own prompt confirm counts as one. "Ours" was traced from the code (2026-10-20); fill in "Ours (measured)" and "CAC (measured)" in the playtest.

| Flow | Ours (traced): path | Ours (measured) | CAC (measured) |
|------|---------------------|-----------------|----------------|
| Try on an item | 3: Catalogue › card (opens its menu) › Try | | |
| Take an item off | 2: Wearing (or tap your avatar) › Take off | | |
| Buy what you're wearing | 3: Wearing › Buy all › Roblox prompt | | |
| Save an outfit | 2: Wearing › Save as new outfit (no naming step) | | |
| Load an outfit | 3: Outfits › card (opens its page) › Wear all items | | |
| Find an item | 2 + typing: Catalogue › search (live, no Enter); +1 if the last browse was another tab | | |

Likely losses to CAC: try-on and loading an outfit, where a card opens a menu or a page before the action (CAC is thought to wear on tap). Kept as they are by choice (user, 2026-10-20: they feel good). Quicker paths to time as well: card menu Take off; paste a marketplace link (opens the item page); the panel's View N items for Wearing and Basket; Undo on the preview.

Parity checklist (ours › where; CAC: tick in the playtest):
- Catalogue: category tabs and chips, home rows per chip, infinite grid; sort, price, creator, sales type, off-sale, colour; keyword search; paste link or id (CatalogueScreen, CatalogueFilters)
- Try-on: card menu (Try · Basket · Buy · View · store), item page with 3D view and More like this, live preview with animations and emotes, Undo (Parts, ItemScreen, panel/)
- Wearing: rows with price or Owned, Buy, Basket, Take off; Take everything off; Buy all; Add unowned to basket (ListScreens)
- Body: layering order, scale sliders, skin tone per part (LayeringPanel, ScalePanel, SkinTonePanel)
- Basket: Buy all, Try on everything, Add what I'm wearing, Remove all (ListScreens)
- Outfits: home rows; Current (reset), Wardrobe (save, save over, rename, delete), Creations (Roblox outfits), Friends, people you follow, Community (sorts, star, report), share codes and QR, outfit page with wear or buy selected (OutfitsScreen, ShareDialog)
- Roblox account: Create avatar and Save to Roblox prompts (AccountPrompts)
- Stores: browse, search by name or code, store pages, favourite, share, report, create and edit (StoresScreen, StoreRowMenu, StoreDialogs)
- World: time, sky, floor and pattern, lighting; double-jump flight, sprint; tap your avatar for Wearing (WorldOptionsView, FlightView, SprintView)
- Not built yet: tapping other players to copy their look (Task 22)
