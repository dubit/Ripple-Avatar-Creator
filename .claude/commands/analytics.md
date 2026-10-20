---
description: Analyse GA4 analytics data from BigQuery — heatmaps, sessions, actions, insights
allowed-tools: mcp__bigquery__query, Bash, Read, Write, Glob, AskUserQuestion
---

I'll help you analyse your GA4 analytics data from BigQuery. This command guides you through querying and interpreting your game's analytics.

## Prerequisites Check

Before doing anything else, verify:

1. **A BigQuery MCP connection is available.** The connection can be named anything — `bigquery`, `bq_<game>`, etc. — so **don't assume a fixed tool name**: look for any connected tool matching `mcp__*__query` (backed by an `@ergut/mcp-bigquery-server`) and use whichever exists. Confirm it works with a trivial `SELECT 1`. Only if **no** such tool is connected, stop and give the user the one-time setup below.

   **One-time setup:**
   1. **Link GA4 → BigQuery** (if not already): GA4 Admin → *Product links* → *BigQuery links* → *Link*. Without this there is no `analytics_<propertyId>` dataset to query at all. Export lags — intraday appears within minutes/hours, finalised `events_YYYYMMDD` tables next day.
   2. **Grant a service account access** to the analytics project: roles **BigQuery Data Viewer** + **BigQuery Job User**. Either create a new SA (Google Cloud → IAM & Admin → Service Accounts → create → download a JSON key), or reuse one from another game and grant it those two roles here — one SA can serve many projects via cross-project grants.
   3. **Find the dataset's region** — BigQuery Studio → your `analytics_*` dataset → *Details* → *Data location* (e.g. `US`, `EU`, `europe-west2`). You need it for `--location`. A wrong region does **not** fail on connect — it fails at *query* time with "not found in location", which is easy to misdiagnose, so get it right now.
   4. **Add the connection**, substituting placeholders literally (no angle brackets — a stray `<REGION>` is read as a shell redirect):
      ```
      claude mcp add bq_<game> -s user -- npx -y @ergut/mcp-bigquery-server --project-id YOUR_PROJECT --location YOUR_REGION --key-file /path/to/key.json
      ```
   5. **Restart Claude Code** — MCP servers only connect at startup.

2. **Analytics config**: Read `bigquery/.analytics-config.json` (gitignored, so it's per-clone — a fresh fork won't have one). If it doesn't exist, this is the first run — proceed to Dataset Discovery.

## Dataset Discovery (First Run Only)

If `bigquery/.analytics-config.json` doesn't exist:

1. Ask the user for their **BigQuery project ID** (e.g., `roblox-template-analytics`)
2. Query BigQuery to list available datasets: `SELECT schema_name FROM INFORMATION_SCHEMA.SCHEMATA`
3. Show datasets matching `analytics_*` pattern and ask the user to confirm which one
4. Save to `bigquery/.analytics-config.json`:
   ```json
   {
     "projectId": "roblox-template-analytics",
     "dataset": "analytics_528555006"
   }
   ```

## Analysis Wizard

After prerequisites pass and config is loaded, proceed to the interactive wizard.

### Step 1: What do you want to know?

Ask the user what they'd like to explore:

1. **Heatmap** — Where do players spend time? Hot zones, dead zones, spatial patterns.
2. **Action analysis** — Which controller actions are most/least popular? Feature adoption over time.
3. **Session metrics** — Average session length, daily active users, retention patterns.
4. **Player flow** — What do players do first? What sequences lead to leaving? Action ordering.
5. **Demographics** — Player breakdown by country, locale, membership type.
6. **Campaign / acquisition** — Which ad campaigns drive the most (and best-retained) players? Segments by the `launch_data` user property; `"organic"` = untagged joins.
7. **Insights** — Holistic analysis across all data. Identify patterns, anomalies, and actionable findings.
8. **Custom query** — Describe what you want in natural language. I'll write and run the SQL.

**Cross-cutting segmentation — offer these proactively.** Most of the above can be sliced further:
- **By campaign** (`launch_data` user property) or **by player state** (global dimensions `basket_count` / `worn_count` / `outfits_count` / `stores_count`, registered in `services/game/AnalyticsDimensions.luau` and present as event params when listed in `AnalyticsConfig.globalParams`). If the user's question touches acquisition, monetisation cohorts, or "do players with a full basket behave differently", add the relevant UNNEST as a column and `GROUP BY` it — see the Campaign / Acquisition and Demographics query patterns.
- **Heatmap must be scoped to a single `heatmap_gen`** (grid version) — never sum across generations. See the Heatmap Query note.
If a dimension the user asks for is missing from the data, tell them it likely isn't enabled in `AnalyticsConfig.globalParams` (or, for campaign, that joins weren't tagged).

### Step 2: Date Range

Ask: "What date range? (default: last 7 days, or specify e.g. '2026-03-10 to 2026-03-17')"

Compute the `_TABLE_SUFFIX` range from the date range for cost-efficient querying. All queries below should include this filter.

### Step 3: Run Queries and Analyse

Use the query templates below. Replace `PROJECT.DATASET` with the values from `.analytics-config.json`. Replace `DATE_START` and `DATE_END` with the computed `_TABLE_SUFFIX` values (YYYYMMDD format, no hyphens).

---

## Event Catalogue (Ripple Avatar Creator)

Every custom event the game sends, with its params (all snake_case). Besides these, every controller action is logged as `controller_action` (`controller_name`, `action_name`) unless listed in `AnalyticsConfig.excludedActions` (currently `View`, since navigation logs its own events), and every event carries the global dimensions above when they're enabled.

| Area | Event | Params | Sent from |
|------|-------|--------|-----------|
| Session | `player_join`, `player_leave` | (session props; `launch_data` user property) | AnalyticsService |
| Navigation | `tab_open` | `tab` (Catalogue / Stores / Outfits / Basket / Wearing), `from` (`world` or the previous root) | NavigationController |
| | `screen_view` | `root`, `screen` (`home`, `item`, `store`, `storeSection`, `outfit`, `skin`), `depth` (breadcrumb levels) | NavigationController |
| | `panel_close` | `root`, `depth` | NavigationController |
| Try-on | `try_on`, `take_off` | `item_id`, `item_kind` (Asset / Bundle), `item_type` | AvatarController |
| | `reset` | (none) | AvatarController |
| Basket | `basket_add`, `basket_remove` | `item_id`, `item_kind`, `item_type` (one event per item) | BasketController |
| Favourites | `favourite`, `unfavourite` | `item_id`, `item_kind` | FavouritesController |
| Purchase | `purchase_prompted` | `item_ids`, `item_count`, `store_code` | PurchaseController |
| | `purchase_completed` | `item_ids`, `item_count`, `robux_spent`, `store_code` | PurchaseController |
| | `purchase_cancelled` | `item_count`, `reason` | PurchaseController |
| Outfits | `outfit_save` | `outfit_id`, `item_count`, `replaced` (overwrite) | OutfitsController |
| | `outfit_delete` | `outfit_id`, `item_count` | OutfitsController |
| | `outfit_wear` | `outfit_id`, `item_count`, `partial`, `source` (`roblox`, `server_player`, `roblox_user`, `community`, `share_code`; none = saved outfit) | Outfits / AvatarController |
| | `outfit_share` | `outfit_id`, `item_count`, `source` | OutfitsController |
| | `user_follow`, `user_unfollow` | `followed_user_id` | OutfitsController |
| Sharing | `share_resolve` | `kind` | OutfitsController |
| | `share_join` | `code`, `kind`, `owner_id`, `own` | DeepLinkService |
| Community | `community_publish` | `code`, `source` | OutfitsController |
| | `community_open`, `community_report` | `code` | CommunityController |
| | `community_wear` | `code` | OutfitsController |
| Stores | `store_create`, `store_publish`, `store_unpublish`, `store_delete`, `store_report` | `code` | StoresController |
| | `store_open`, `store_share` | `code`, `own` | StoresController |
| | `store_favourite` | `code`, `on` | StoresController |
| World | `heatmap_summary`, `heatmap_cell`, `heatmap_presence` | see Heatmap Query | HeatmapService |

When adding an event, add its row here in the same change.

## Query Templates

### Heatmap Query
```sql
SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'cell_x') AS cell_x,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'cell_z') AS cell_z,
  SUM((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'player_seconds')) AS total_player_seconds,
  MAX((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'unique_players')) AS peak_unique_players,
  SUM((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'dwell_seconds')) AS total_dwell_seconds
FROM `PROJECT.DATASET.events_*`
WHERE event_name IN ('heatmap_summary', 'heatmap_cell', 'heatmap_presence')
  AND _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
GROUP BY cell_x, cell_z
ORDER BY total_player_seconds DESC, total_dwell_seconds DESC
```

**Filter by grid version.** Every heatmap event carries a `heatmap_gen` param identifying the grid config (cellSize + bounds) that produced it. When the grid changes, `heatmap_gen` changes automatically, so old and new data don't silently blend. If you have more than one generation in range, pick one — otherwise cells from different resolutions/areas are summed together nonsensically. Add `AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'heatmap_gen') = '<gen>'` to the WHERE clause (list generations first with a `GROUP BY heatmap_gen` count if unsure which exist).

After running, identify:
- Hottest cells (highest player_seconds or dwell_seconds)
- Cold/dead zones (cells with zero or near-zero activity)
- Clusters and spatial patterns
- After presenting text analysis, ask: "Would you like me to generate a heatmap image?"

**If user wants an image:**
1. Check `bigquery/.venv/` exists. If not, create it:
   ```bash
   cd "bigquery" && python -m venv .venv && .venv/Scripts/pip install -r requirements.txt
   ```
2. Format query results as JSON: `[{"cell_x": N, "cell_z": N, "value": N}, ...]` using `total_player_seconds` (or `total_dwell_seconds` for transitions mode) as the value
3. Pipe to heatmap.py:
   ```bash
   echo '<json_data>' | "bigquery/.venv/Scripts/python" "bigquery/scripts/heatmap.py" --title "Player Heatmap" --output "bigquery/output/heatmap.png"
   ```
4. Read the output image file to display it to the user

### Controller Actions Query
```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'controller_name') AS controller_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'action_name') AS action_name,
  COUNT(*) AS action_count,
  COUNT(DISTINCT user_id) AS unique_users
FROM `PROJECT.DATASET.events_*`
WHERE event_name = 'controller_action'
  AND _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
GROUP BY controller_name, action_name
ORDER BY action_count DESC
```

Also run a daily trend query:
```sql
SELECT
  event_date,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'action_name') AS action_name,
  COUNT(*) AS action_count
FROM `PROJECT.DATASET.events_*`
WHERE event_name = 'controller_action'
  AND _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
GROUP BY event_date, action_name
ORDER BY event_date, action_count DESC
```

Analyse: most/least popular actions, feature adoption, engagement depth.

### Session Metrics Query
```sql
SELECT
  COUNT(*) AS total_leave_events,
  COUNT(DISTINCT user_id) AS unique_users,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'session_duration_seconds')) AS avg_session_seconds,
  MIN((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'session_duration_seconds')) AS min_session_seconds,
  MAX((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'session_duration_seconds')) AS max_session_seconds
FROM `PROJECT.DATASET.events_*`
WHERE event_name = 'player_leave'
  AND _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
```

Also run daily session counts:
```sql
SELECT
  event_date,
  COUNT(*) AS sessions,
  COUNT(DISTINCT user_id) AS unique_users
FROM `PROJECT.DATASET.events_*`
WHERE event_name = 'player_join'
  AND _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
GROUP BY event_date
ORDER BY event_date
```

### Player Flow Query
```sql
SELECT
  user_id,
  TIMESTAMP_MILLIS((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'timestamp')) AS action_time,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'controller_name') AS controller_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'action_name') AS action_name
FROM `PROJECT.DATASET.events_*`
WHERE event_name = 'controller_action'
  AND _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
ORDER BY user_id, action_time
```

Note: Uses the `timestamp` param (captured at queue time) rather than `event_timestamp` (set at HTTP send time) for accurate action ordering. Analyse action sequences: first actions, common paths, actions before leaving.

### Demographics Query
```sql
SELECT
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'country') AS country,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'locale') AS locale,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership') AS membership,
  COUNT(*) AS session_count,
  AVG((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'session_duration_seconds')) AS avg_session_seconds
FROM `PROJECT.DATASET.events_*`
WHERE event_name = 'player_leave'
  AND _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
GROUP BY country, locale, membership
ORDER BY session_count DESC
```

### Campaign / Acquisition Query
Every player carries a `launch_data` user property — the experience link's `LaunchData`, set per ad campaign/creative (`"wknd-adA"`, …), or `"organic"` for untagged joins. Because it's a GA4 **user property**, it rides on every event, so you can segment ANY metric by campaign. Example — retention and engagement by campaign:
```sql
SELECT
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'launch_data') AS campaign,
  COUNT(DISTINCT user_pseudo_id) AS players,
  COUNTIF(event_name = 'player_leave') AS sessions,
  AVG(IF(event_name = 'player_leave',
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'session_duration_seconds'), NULL)) AS avg_session_seconds
FROM `PROJECT.DATASET.events_*`
WHERE _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
GROUP BY campaign
ORDER BY players DESC
```
To segment any other query by campaign, add the same `launch_data` UNNEST as a `SELECT` column and `GROUP BY` it. To compare one campaign against the rest, filter `WHERE (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'launch_data') = 'wknd-adA'`.

### Experiment Cohorts (A/B & multivariate)

Experiments assign each player a **deterministic** cohort (hash of UserId + salt;
see `ExperimentService` / the Studio `ExperimentsConfig`). Every event carries the
active cohorts as `exp_<name>` params (e.g. `exp_example_sweep`) — stamped on
*every* event type including `player_join`, so you can segment **any** metric by
cohort.

**Type gotcha (read this):** a `numericRange` cohort (a numeric sweep) is a
numeric-looking value and GA4 files it under `value.int_value`; a `variants`
cohort (like `"control"`/`"variant"`) lands under `value.string_value`. Reading
the wrong one returns NULL and makes a present cohort look absent. Always extract
with COALESCE:

```sql
SELECT
  COALESCE(CAST(ec.value.int_value AS STRING), ec.value.string_value) AS cohort,
  COUNT(DISTINCT user_id) AS users,
  COUNT(*) AS events
FROM `PROJECT.DATASET.events_*`,
  UNNEST(event_params) AS ec
WHERE ec.key = 'exp_example_sweep'         -- the experiment param (exp_<name>)
  AND _TABLE_SUFFIX BETWEEN 'DATE_START' AND 'DATE_END'
GROUP BY cohort
ORDER BY SAFE_CAST(cohort AS INT64)
```

To compare an *outcome* across cohorts (e.g. session length by assigned cohort),
take the cohort from any of the player's events and the metric from the relevant
event, joined per `user_id`. Numeric cohorts can be range-filtered directly on
`int_value` (e.g. `... AND ec.value.int_value BETWEEN 2 AND 4`) — no CAST needed.

### Insights (Holistic)
Run ALL of the above queries, then provide a comprehensive analysis covering:
- What stands out? What's surprising?
- Are there dead zones in the map?
- Are there underused features?
- Do certain player demographics behave differently?
- What actionable recommendations can you make?

### Custom Query
The user describes what they want in natural language. Write SQL using the same UNNEST patterns above against `PROJECT.DATASET.events_*`. Run it and explain the results.

## Important Notes

- Always use `_TABLE_SUFFIX` filtering for date ranges to control query costs
- Default to last 7 days if the user doesn't specify
- Present text analysis first, offer visualisations on request
- When showing numbers, include context (e.g., "847 player-seconds in cell (3,5) — that's 3x the average")
- For insights, go beyond raw numbers — identify patterns, anomalies, and make recommendations
- If a query returns no data, suggest the user check their date range or whether the relevant events are being tracked
- **Campaign attribution is available on every event** via the `launch_data` user property (see the Campaign / Acquisition Query). If the user asks about ad campaigns, creatives, traffic sources, or "where players came from", segment on `launch_data`. Untagged joins show as `"organic"`. In Studio playtests, `launch_data` reflects a `workspace.TestLaunchData` attribute/StringValue if one is set (otherwise `"organic"`).
- **Heatmap data is versioned by `heatmap_gen`** (an event param on all heatmap events). Always scope a heatmap query to a single `heatmap_gen` — summing across generations mixes grids with different cell sizes/bounds. See the Heatmap Query note.
- **Global dimensions** (registered in `AnalyticsDimensions.luau`, enabled by `AnalyticsConfig.globalParams`: `basket_count`, `worn_count`, `outfits_count`, `stores_count`) are stamped as event params on almost every event, so you can segment ANY metric by player state — add the relevant `event_params` UNNEST as a column and `GROUP BY` it, exactly like the demographics/campaign patterns. They're absent from aggregate events (`heatmap_summary`) and `player_join`. If a dimension the user asks about isn't present, it likely isn't listed in `globalParams`.
- **Experiment cohorts** ride every event as `exp_<name>` params (deterministic per player; see the Experiment Cohorts Query). Any metric can be segmented by cohort. Unlike global dimensions these are stamped even on `player_join`. `place_version` / `place_id` also ride every event — use `place_version` to scope analysis to a specific published build (it increments on each Studio publish; `0` = unpublished Studio session).
- **GA4 infers each param's value type — read the matching field.** The Measurement Protocol files every event/user param into exactly one of `value.string_value`, `value.int_value`, or `value.double_value` based on what the value *looks like*, regardless of how the game sent it. A numeric-looking value — even one the game sent as a string via `tostring()`, e.g. an experiment cohort `"35"` — lands in `int_value`, so reading `string_value` returns NULL and makes a present param look missing. When a param's type is uncertain (especially `exp_*` cohorts and anything stamped via `tostring()`), extract with `COALESCE(CAST(value.int_value AS STRING), value.string_value)`. **If a *column* comes back all-NULL but the events clearly exist, suspect this before concluding the data isn't there.**
- **Always measure standard deviation alongside any mean.** Whenever you compute an average (session length, action counts per user, player-seconds per cell, etc.), also query STDDEV in the same pass. Then act on what the SD reveals:
  - If SD is low relative to the mean → the mean is trustworthy, report it confidently
  - If SD is high relative to the mean → flag the spread, consider reporting median/mode instead, and if the data exists to explain *why* (e.g., outlier sessions, demographic splits, time-of-day effects), dig into that
  - This applies across all analysis types, not just sessions — heatmap cell values, action counts, demographics breakdowns, etc.
