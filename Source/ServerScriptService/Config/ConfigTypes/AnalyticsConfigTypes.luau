--!strict
--[[
	AnalyticsConfigTypes
	Type definitions for GA4 analytics configuration

	The AnalyticsConfig lives in ServerScriptService (not ReplicatedStorage) because
	it contains an API secret that should not be visible to clients.

	Create the config in Studio: ServerScriptService > Config > AnalyticsConfig (ModuleScript)
]]

-- Heatmap tracking: records where players spend time on a 2D grid (X/Z).
-- Two tracking modes:
--   "summary"     - Accumulates dwell time per cell in memory, flushes periodically.
--                   Low event volume, suitable for production. Answers "where do players go?"
--   "transitions" - Fires an event each time a player crosses a cell boundary.
--                   High granularity, captures player paths/flow. Best for small-scale playtesting.
export type HeatmapConfig = {
	enabled: boolean,
	trackingMode: string,              -- "summary" (production) or "transitions" (playtesting)
	boundsMin: { number },             -- { X, Z } world-space minimum corner
	boundsMax: { number },             -- { X, Z } world-space maximum corner
	cellSize: number,                  -- studs per cell
	sampleIntervalSeconds: number,     -- how often to check player positions
	flushIntervalSeconds: number,      -- summary mode: how often to flush aggregates to GA4
	heartbeatIntervalSeconds: number,  -- transitions mode: interval for stationary player events
	version: string?,                  -- optional label stamped on heatmap events as `heatmap_gen`,
	                                   -- so a specific grid config can be filtered in BigQuery. When
	                                   -- omitted, an id is auto-derived from cellSize + bounds, so any
	                                   -- grid change yields a new `heatmap_gen` automatically. Set an
	                                   -- explicit value (e.g. "arena-v2") for a friendly tag.
}

-- GA4 analytics via the Measurement Protocol.
-- Controller actions and player lifecycle events are tracked automatically.
-- Custom events can be sent via AnalyticsService:trackEvent(player, name, params).
--
-- Acquisition attribution is automatic (no config needed): AnalyticsService
-- reads player:GetJoinData().LaunchData on join and stores it as the
-- `launch_data` GA4 user property, so every event can be segmented by ad
-- campaign in BigQuery. Tag each campaign link with a distinct LaunchData;
-- untagged joins record as "organic". To test in Studio (no real LaunchData),
-- set a `TestLaunchData` attribute or StringValue on Workspace. See the
-- /analytics skill's "Campaign / Acquisition Query" for how to segment on it.
export type AnalyticsConfig = {
	enabled: boolean,                  -- master toggle for all analytics
	measurementId: string,             -- GA4 measurement ID (e.g., "G-XXXXXXXXXX")
	apiSecret: string,                 -- GA4 Measurement Protocol API secret
	hashSalt: string,                  -- salt for one-way hashing UserIds (change per game)
	flushIntervalSeconds: number,      -- how often to send batched events to GA4
	maxBatchSize: number,              -- max events per GA4 request (GA4 limit is 25)
	debug: boolean,                    -- log events to output + send to GA4 DebugView
	excludedActions: { string }?,      -- controller action names to skip auto-tracking (noise reduction)
	globalParams: { string }?,         -- absolute model values stamped onto (almost) every event, e.g.
	                                   -- { "basket_count", "worn_count" }. Each key needs a resolver registered via
	                                   -- AnalyticsService.registerDimension (see AnalyticsDimensions).
	                                   -- Lets any event be segmented by player progression in BigQuery.
	heatmap: HeatmapConfig,            -- spatial heatmap tracking settings
}

return nil
