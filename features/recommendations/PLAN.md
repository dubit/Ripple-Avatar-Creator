# Recommendations: PLAN

Worked task by task with `/next-task`. Spec: `features/recommendations/SPEC.md`.
Branch: `feature/recommendations`.

### Task 1: Interim recommender
- **Status:** [IN PROGRESS]
- **Why here:** Everything else shows its output. Built first and on its own so
  the rings can be judged on what they recommend, and so the real service can
  replace it behind the same interface.
- **Depends on:** none
- **Refs:** SPEC > Interim recommender; `CatalogueClient` (search, cache,
  backoff); `CatalogueConfig` (categories, chips, types)
- **Acceptance criteria:**
  - `Recommender.recommend(context)` returns `count` distinct, wearable items,
    none in `exclude` or worn, each with a `reason`.
  - For a seed item, the results look related on inspection: the same creator,
    the same style or colour, and other body areas. Checked on a handful of
    real items (hair, a jacket, a hat, a full outfit).
  - A ring costs at most 6 searches and survives a 429 (backs off; returns what
    it has rather than nothing).
- **Associated UI:** none (checked from a Client `execute_luau` with `Recommender.describe`).
- **Replication:** client-only.
- **Sub-tasks:**
  - [DONE] 1.1 Config: style word list, slot recipe, body areas (which chips
    count as covering which area).
  - [DONE] 1.2 `Source/ReplicatedFirst/views/catalogue/Recommender.luau`: style
    words from names, uncovered areas from the outfit, the slot searches through
    `CatalogueClient`, fall-through when a slot comes back empty.
  - [DONE] 1.3 Check it on real items in Studio and tune. Tuned (2026-11-17): the
    basis's own type counts as a "spare" (at most one per ring), so a
    creator's recolours of the chosen item no longer fill the creator slots;
    areas are weighted (hair, top, legs and shoes first) so "complete" offers
    clothes rather than small accessories; the wildcard is MostFavorited over
    the past month (Bestselling past week was junk). A ring takes about
    0.5 s. The HUD's catalogue home rows search at startup on the same
    client budget, so a ring opened right after joining can wait out a 429
    backoff (30 s).

### Task 2: The ring in the world
- **Status:** [DONE]
- **Why here:** The core of the milestone: seeing recommendations around you.
- **Depends on:** 1
- **Refs:** SPEC > The experience
- **Acceptance criteria:**
  - Starting it puts 7 pads in a circle on the ground around the player,
    fixed in the world (they don't follow the player), each showing its
    item's thumbnail and name; they appear with motion.
  - Pads sit on the ground (raycast down), and a pad that would land inside a
    wall or off a ledge is moved in or left out.
  - Closing removes the ring with motion.
  - Only the local player sees it.
- **Associated UI:** none on the HUD: tapping your own avatar opens and closes the ring (open question 1).
- **Replication:** client-only.
- **Sub-tasks:**
  - [DONE] 2.1 The ring view (client): pads, thumbnails, names, appear and
    disappear.
  - [DONE] 2.2 Start and close: tap yourself to open / close; walking away
    (radius + `ring.walkAway`) or respawning closes it.
  - [DONE] 2.3 Loading state while the recommender runs (pads breathe, cards
    show "…").
  - [DONE] 2.4 3D models (user, 2026-11-17): each item's model
    (`ItemModel`, built on the client) turns slowly and bobs above its pad so
    it reads as collectable; the card shrinks to a name tag over it. Items with
    no 3D view (or a failed build) keep the thumbnail card.
  - [DONE] 2.5 Glowing rings (user, 2026-11-17, after a Gemini mock-up): a soft
    ring of light under each item in the item's own colour (ItemColour's
    dominant bucket mapped to a tuned glow palette; black / grey / white take
    the second colour, else cool white; the back pad white). Colour is
    identity, not information. The ring fills with light while you stand on
    it. Dwell cut to 0.25 s. Images drawn by `tools/build_rings.py`.
  - [DONE] 2.6 No item labels (user, 2026-11-17): just the model (or, with no
    3D view, a square thumbnail card).
  - [DONE] 2.7 Back pad gets a plain "← Back" label over its ghost (not final;
    without it the back pad didn't read). Loading is a small pulsing glow ball
    where the item will appear, not a card (user, 2026-11-17).
  - [DONE] 2.8 The loading ball becomes an orb: a white core with three comets
    in brand colours (accent orange, floor-swatch purple and green) orbiting on
    tilted planes with short trails; they fall into the core as the item pops
    in. A pad's floor ring appears only once its item has loaded, and it can't
    be picked before then (user, 2026-11-18).
- **Outcome:** Confirmed by the user (2026-11-17). Decisions: tapping yourself
  opens / closes the ring (not Wearing); items are turning, bobbing 3D models
  with no podia (the pad is an invisible marker). Lessons: a BillboardGui on a
  rotated part (an upright cylinder) sits off to one side, so cards hang off
  an unrotated block; billboard text is sized in studs, so cap it
  (UITextSizeConstraint) or names by the camera fill the screen;
  `HumanoidDescription`'s shoulder property is `ShouldersAccessory` (ItemModel
  had it wrong, so shoulder items never got a 3D view anywhere).

### Task 3: Walk on to wear, the next ring
- **Status:** [DONE]
- **Why here:** Turns the ring from a display into the loop.
- **Depends on:** 2
- **Refs:** SPEC > Decisions (automatic take-off); `AvatarController.TryOn`;
  `AvatarModel` slot rules
- **Acceptance criteria:**
  - Standing on a pad fills it over about half a second, then wears its item;
    stepping off before that cancels. Walking across a pad doesn't wear it.
  - Wearing replaces the same slot and, for accessories, the same accessory
    type.
  - The old ring goes and a new ring opens around the player, based on the
    item just worn, with the back pad.
- **Replication:** `Avatar.TryOn` gains an optional replace-same-type flag
  (validated server-side); otherwise client-only.
- **Sub-tasks:**
  - [DONE] 3.1 Pad dwell and fill (a disc grows under the item over `ring.dwell`; stepping off drains it).
  - [DONE] 3.2 TryOn replace-same-type (`AvatarController`, `AvatarModel`).
  - [DONE] 3.3 Ring trail: a stack of rings (items, back item, the outfit after the pick); nothing offered twice on a trail.

### Task 4: Back pad
- **Status:** [DONE]
- **Note:** built with Task 3 (a ring after the first needs its back pad).
- **Depends on:** 3
- **Acceptance criteria:**
  - Every ring after the first has a back pad that looks different and holds
    the item walked through.
  - Walking onto it undoes that outfit change and brings back the previous ring
    (the same items, around the player's current position).
  - If the outfit was changed some other way since (the HUD), back still
    returns to the previous ring and doesn't undo the wrong change.
- **Replication:** none new (`Avatar.Undo`).
- **Sub-tasks:**
  - [DONE] 4.1 Back pad: on the side you came from, a ghosted model, "↩ Back · name" in the accent colour, a white disc.
  - [DONE] 4.2 Guard: Undo only if the outfit still matches what the pick made it (signature of worn ids); otherwise it only goes back a ring. Confirmed by the user.
- **Outcome (Tasks 3 and 4):** Confirmed by the user (2026-11-17): accessory
  same-type replacement and the Undo guard both behave. Built together, since
  every ring after the first needs its back pad. The pick sends TryOn with
  `replaceSameType`; Back sends Undo only when the worn-id signature still
  matches the one recorded when the pick landed.

### Task 5: Analytics
- **Status:** [IN PROGRESS]
- **Depends on:** 4
- **Refs:** SPEC > Analytics; `.claude/commands/analytics.md` (event catalogue)
- **Acceptance criteria:**
  - `rec_open`, `rec_ring`, `rec_pick`, `rec_back`, `rec_close` are sent with
    the parameters in the spec, validated server-side.
  - The event catalogue in the analytics skill lists them.
- **Replication:** a new intent to `RecommendationsController` (no state back).
- **Sub-tasks:**
  - [DONE] 5.1 RecommendationsController (track only; one `Track` action, excluded from `controller_action`; every event and param validated; 30 reports / 10 s budget).
  - [DONE] 5.2 Client reports from the ring. `rec_ring` lists its items as `item_1..7` / `reason_1..7` (GA4 caps a param value at 100 characters, so not one joined list). Checked in Studio: every event queues and the batch sends; arrival in GA4 is unchecked (no BigQuery link to Ripple's property, as in phase 1).

### Task 6: Playtest and tune
- **Status:** [TODO]
- **Depends on:** 5
- **Acceptance criteria:**
  - A few people use it together; we decide what other players should see of
    a ring (open question 2), whether automatic take-off is enough (open
    question 3), and whether the recipe needs tuning.
- **Sub-tasks:**
  - [TODO] 6.1 Playtest with several clients.
  - [TODO] 6.2 Triage what comes out of it.

---

## Open questions

1. ~~**How it starts (Task 2).**~~ Decided (user, 2026-11-17): tapping your own
   avatar opens and closes the ring; it no longer opens Wearing (Wearing has
   its own HUD button). Options were: tap yourself (but tapping yourself
   already opens Wearing), a HUD button, an item near or above the player, or
   a button on the Wearing screen. Clean videos for social media matter: the
   ring must be easy to close, and whatever starts it should be easy to hide.
2. **What other players see (Task 6).** Nothing for now; decide after a
   playtest with a few people.
3. **Automatic take-off (Task 6).** Is same-slot / same-type replacement
   enough, or does the outfit pile up (e.g. a cap on accessories while in
   the ring, or a "take this off" pad)?
4. **The real service's contract.** Transport, auth, payloads; what it takes
   as input (one item, or the session's trail and outfit).
