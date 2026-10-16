# Ripple Avatar Creator — Project Brief

The north star for this project. Per-feature detail lives in `features/<slug>/SPEC.md`
and `features/<slug>/PLAN.md` (worked task by task with `/next-task`).
Keep this doc short and update it when the vision shifts.

## What we're making

Our take on Roblox's [Catalog Avatar Creator](https://www.roblox.com/games/7041939546/Catalog-Avatar-Creator)
(CAC, by @Muneeb): an experience where players try on catalog items for free, build
and save outfits, and buy what they like — with purchases landing in their real Roblox
inventory.

We differentiate on three fronts:

1. **Our own design and a tidier HUD.** CAC is HUD-heavy with almost nothing in the
   world. We use the world: a series of **interactable monoliths** that host
   secondary functionality diegetically, keeping the HUD focused on core
   try-on/browse/buy.
2. **A points economy with UGC auctions** (retention).
3. **Item-to-item recommendations** powered by our own external services.

## Workstreams

### 1. CAC adaptation pass

Take the features we like from CAC, change what we don't, and apply our own design —
all within the template's MVC architecture and react-luau UI system (`views/components`,
`views/hooks`, `HudApp`).

CAC's public feature set, as a starting checklist to keep / change / cut:

- Free try-on of catalog items: accessories, hats, limiteds, hair combos, bundles,
  animation packs, clothing
- Catalog browsing, search and filtering
- Body customisation: body type, scaling (height, width, head, proportions), colours
- Save avatars created in-experience; load another user's outfit
- Outfit share codes
- A large library of community-created outfits to browse (CAC claims 50M+)
- Purchasing items in-experience (they go to the player's Roblox inventory)
- Group join call-to-action

### 2. Points & UGC auctions

- Players **earn points** for spending Robux in-experience and for a handful of other
  tasks (e.g. joining the group, inviting friends).
- **Every point gained and spent is logged per user** (an auditable ledger, not just a
  balance).
- Points are spent on **minted UGC** via an in-game, eBay-style **auction system**.
- Why: better value than the marketplace for the player's spend; an active auction
  gives us a legitimate reason to re-engage players (notifications); and minting UGC
  associated with the experience helps discovery.

### 3. Recommendation engine

- Recommend items based on an item a user has clicked, liked, worn, etc.
- The **UGC-to-UGC connection services live outside this repo.** This repo is the
  client of those services: it emits the signals they need (views, try-ons, likes,
  wears, purchases) and renders the recommendations they return.

## Design principles

- **Diegetic first.** If a feature isn't core to the try-on/buy loop, give it a
  monolith in the world before giving it HUD space.
- **Template architecture, not around it.** New features are new Models / Controllers /
  Views / Services / Configs, following `docs/*_GUIDE.md`.
- **Server-authoritative economy.** Points, auctions and the ledger are server state;
  clients only express intent.

## Decisions

- **Template example features** (Candles, Shrine, Cash Machine, Bazaar, Favours,
  gold/treasure Inventory) were all removed in phase 1, Task 20 (2026-10-16). The
  guides and skills now cite our own models, controllers, services, configs and
  views. Patterns we don't use yet (Server, UserEntity and ServerEntity scopes,
  views on tagged Workspace interactables) are kept as short illustrative samples
  in the guides, and the monoliths can become their first real examples.
- **Workstream 1 kicks off from a design** made in Claude Design, which seeds the
  phase 1 spec.

## Open questions

- Points earn rates, auction mechanics (duration, bid increments, snipe protection),
  UGC minting pipeline and supply.
- Contract with the external recommendation service (transport, auth, payloads).
- Monolith roster: which features get one, and how they're placed.
