# Recommendations: SPEC

Milestone 2 of three. The experience splits by place: **CaC parity lives in the
HUD** (milestone 1, `features/cac-adaptation`), **recommendations live around
the avatar** (this milestone), and **points and auctions are spread around the
world** (milestone 3). See `docs/PROJECT_BRIEF.md`, workstream 3.

## The experience

A player starts recommendations and a **ring of 7 items** appears on the ground
around them. Each item stands on a pad. **Walking onto a pad wears that item**,
and a new ring opens where the player now stands, with new recommendations that
take the item they just chose into account. One pad in every ring after the first
is the **back pad**: it holds the item they came through, and walking onto it
**undoes that outfit change** and brings back the previous ring. The rings
the player has walked through work like a breadcrumb trail they can walk back
along.

The player can close the ring at any time. Nothing about the ring is on the HUD
except the way to start and close it.

## Decisions (user, 2026-11-17)

- **7 items per ring.** The back pad is one of the 7, so a ring after the first
  shows 6 new items plus the back pad.
- **Back undoes the outfit change**, not just the ring.
- **What a ring is based on:** the first ring uses **the whole outfit being
  worn**. Each later ring uses **the item just walked through**. This will
  probably change when the real engine arrives, but it's enough for tests.
- **Only the player who owns a ring sees it** (it's client-side). Other players
  should eventually see *something* (social reassurance that this is a feature
  to use), but we start with nothing and come back to it after watching a few
  people use it. Watching people move around and change outfits may be enough.
- **Taking items off is automatic (plan A).** Inside the ring, a new item
  replaces whatever is in its slot (the normal rules), and an accessory also
  replaces a worn accessory **of the same type** (a hat replaces your hat, not
  the oldest accessory). Back covers mistakes.
- **Interim recommendations, better than random.** The recommendation server
  (built by the user, outside this repo) has no endpoints yet. Until it does, a
  client-side heuristic over `AvatarEditorService:SearchCatalog` fills each ring,
  behind an interface the real service will replace.
  - Checked and ruled out (2026-11-17): Roblox's
    `catalog.roblox.com/v2/recommendations/assets` answers without auth, but
    ignores `contextAssetId`: it returns the same popular list per asset type
    whatever the context item.

## Interim recommender

`recommend(context) -> { Item }`, where `context` is
`{ basis = { Item }, worn = { Item }, exclude = { [id] = true }, count }`:
`basis` is the outfit (first ring) or the one item walked through; `worn` is the
current outfit; `exclude` is everything already shown on this trail or worn.
Each returned item carries a `reason` (for analytics and tuning).

A ring of 6 new items is built from:

| Slots | Reason | How |
|---|---|---|
| 2 | `creator` | same creator as the basis item(s), Bestselling |
| 2 | `complete` | an area of the body the outfit doesn't cover yet, searched with the basis's style words |
| 1 | `style` | the basis's style words, any wearable type, MostFavorited |
| 1 | `wildcard` | popular in an area not yet covered, no keyword |

The first ring (7 new items, no back pad) adds one more `style` slot.
**Style words** come from the basis items' names, matched against a fixed list
in config (colours, and styles such as goth, y2k, emo, cyber, kawaii, preppy,
grunge, fairy, ...). If a slot comes back empty it falls through to the next
reason. Searches go through `CatalogueClient`, so they use its cache, its
backoff and the client's own rate limit (about 36 searches per 26 s). That's
about 4 to 6 searches per ring.

## Analytics (training data for the real engine)

Each ring is a set of items shown plus one choice, which is exactly the
implicit feedback the real engine needs. Tracked server-side through a thin
`RecommendationsController` (the client only reports; the server validates
shape and size):

- `rec_open` (how it was started, outfit size)
- `rec_ring` (depth, basis id, the 7 ids with their reasons)
- `rec_pick` (id, reason, depth, slot index)
- `rec_back` (depth)
- `rec_close` (depth, rings seen, picks)

## Out of scope for this milestone

- Calling the real recommendation service (its contract is still open; the
  interface above is what it plugs into).
- What other players see of someone's ring.
- Points, auctions and monoliths (milestone 3).

## Replication

- The ring, its pads and the recommender are **client-only** (Pattern A, no
  server state).
- Wearing goes through the existing `Avatar.TryOn` / `Avatar.Undo` intents,
  validated server-side as now. TryOn gains an optional "replace same type"
  flag for the automatic take-off.
- Analytics events go through a new intent; no state is sent back.
