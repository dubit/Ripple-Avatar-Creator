--!strict
--[[
	AnalyticsService
	Server-side GA4 analytics via the Measurement Protocol.

	Auto-instruments controller actions and player lifecycle events.
	Events are batched in memory and flushed periodically to minimize HTTP requests.

	Setup:
	1. Create a ModuleScript in Studio at ServerScriptService.Config.AnalyticsConfig
	2. Fill in measurementId, apiSecret, hashSalt, and set enabled = true
	3. Enable HttpService in Game Settings

	Custom events:
		local AnalyticsService = require(ServerScriptService.services.framework.AnalyticsService)
		AnalyticsService:trackEvent(player, "store_open", {
			code = "7KQ2XM",
			own = false,
		})
	(Ripple's events are listed in .claude/commands/analytics.md.)
]]

local HttpService = game:GetService("HttpService")
local LocalizationService = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaunchData = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("LaunchData"))

local AnalyticsService = {}

-- Types
type GA4Event = {
	name: string,
	params: { [string]: any },
	timestamp_micros: number?,
}

type QueuedEvent = {
	clientId: string,
	event: GA4Event,
}

type UserProperties = {
	locale: { value: string },
	country: { value: string },
	account_age_days: { value: string },
	membership: { value: string },
	-- Acquisition attribution: the experience link's launchData, set on join via
	-- player:GetJoinData().LaunchData. Tag each ad campaign/creative with a
	-- distinct launchData ("wknd-adA", …) and this rides on EVERY event the
	-- player fires (GA4 attaches user properties to all events), so behaviour can
	-- be segmented by campaign in BigQuery. "organic" when the join wasn't tagged;
	-- "share" when it came through a share link (LaunchData).
	launch_data: { value: string },
}

-- Build/version identity, stamped on every event for filtering in BigQuery.
-- `place_version` is Roblox's own publish counter (game.PlaceVersion): an
-- integer that auto-increments each time the place is published — no dev action
-- and no config to keep in sync, so it can't silently drift. It's monotonic, so
-- BigQuery can range-filter ("everything since v45"). It's per-place and opaque
-- (v47 carries no date/commit), hence `place_id` rides alongside it to
-- distinguish dev vs prod places. Captured once here — a running server's
-- PlaceVersion is fixed for its lifetime (a publish spins up new servers).
-- In Studio PlaceVersion is 0, which conveniently marks non-published sessions.
local PLACE_VERSION: number = game.PlaceVersion
local PLACE_ID: number = game.PlaceId

-- State
local config = nil :: any
local eventQueue: { QueuedEvent } = {}
local userPropertiesCache: { [string]: UserProperties } = {}
local playerJoinTimes: { [string]: number } = {}
local numericSessionId: number = 0
local isRunning = false

-- Lookup of controller action names to skip (built from config.excludedActions)
local excludedActionSet: { [string]: boolean } = {}

-- Global dimensions: absolute model values stamped onto (almost) every event.
-- `dimensionFetchers` maps a config key -> a (player) -> value resolver,
-- registered by a game-specific module via AnalyticsService.registerDimension —
-- the service stays model-agnostic. `globalParamKeys` is the ordered subset
-- enabled in config.globalParams. Events in GLOBAL_PARAM_EXCLUDED_EVENTS are
-- skipped: aggregate (heatmap_summary, attributed to an arbitrary player) and
-- pre-hydration (player_join, before per-player models exist).
local dimensionFetchers: { [string]: (Player) -> any } = {}
local globalParamKeys: { string } = {}
local GLOBAL_PARAM_EXCLUDED_EVENTS: { [string]: boolean } = {
	heatmap_summary = true,
	player_join = true,
}

-- Always-stamp dimensions (registered with registerDimension(..., true)): a
-- second tier for values that are known independently of per-player model
-- hydration — chiefly deterministic experiment cohorts (see ExperimentService).
-- Unlike globalParams these ride EVERY event, so cohort is present on
-- player_join too. The one carve-out is genuinely aggregate events: a
-- heatmap_summary row is attributed to an arbitrary online player (its cell data
-- spans everyone), so stamping that player's cohort would misattribute aggregate
-- data — those events are excluded here.
local alwaysDimensionKeys: { string } = {}
local ALWAYS_STAMP_EXCLUDED_EVENTS: { [string]: boolean } = {
	heatmap_summary = true,
}

-- Public flag checked by AbstractController to avoid require overhead
AnalyticsService.isEnabled = false

-- Salted pseudonymising hash for UserIds, emitted as 16 hex chars (64-bit).
--
-- This is NOT a cryptographic / irreversible hash. Its job is to keep raw Roblox
-- UserIds out of the GA4 + BigQuery dataset. Anyone holding `hashSalt` (it lives
-- in the server-only AnalyticsConfig) can rebuild the hash -> UserId map by
-- enumerating UserIds, so treat the emitted id as a stable pseudonym, not as
-- anonymisation.
--
-- Collision limit: the output spans a full 64-bit space (2^64). By the birthday
-- bound, the chance of *any* collision reaches ~50% only after ~5 billion
-- distinct users have been seen; at realistic game scale (even tens of millions
-- of players) the probability is negligible (~n^2 / 2^65). A single 32-bit DJB2
-- lane (the previous implementation) hit ~50% collision odds at only ~77k users
-- — well within a successful game's lifetime audience — which is why this is
-- widened to 64 bits.
--
-- Implementation note: Luau numbers are IEEE-754 doubles (53-bit integer
-- precision), so native 64-bit integer arithmetic would lose precision. Instead
-- we run two independent 32-bit lanes (DJB2 + SDBM) — every intermediate value
-- stays under 2^53 — and concatenate them for an effective 2^64 output space.
--
-- ⚠️ Changing this function (or `hashSalt`) changes every emitted id, creating a
-- one-time discontinuity: rows from before and after the change won't reconcile
-- to the same user. Set it before a game goes live; changing it mid-life splits
-- each player's history in two.
local function hashUserIdString(input: string): string
	local a: number = 5381 -- DJB2 lane (seed 5381, multiplier 33)
	local b: number = 0 -- SDBM lane (multiplier 65599)
	for i = 1, #input do
		local byte = string.byte(input, i)
		a = ((a * 33) + byte) % 4294967296 -- mod 2^32
		b = ((b * 65599) + byte) % 4294967296 -- mod 2^32
	end
	return string.format("%08x%08x", a, b)
end

local function hashUserId(userId: number): string
	return hashUserIdString(config.hashSalt .. tostring(userId))
end

-- Convert JobId (UUID string) to a numeric session ID for GA4
local function generateNumericSessionId(): number
	local hash: number = 5381
	local jobId = game.JobId
	if jobId == "" then
		-- Studio doesn't have a JobId; use a random number
		return math.random(1, 2^31 - 1)
	end
	for i = 1, #jobId do
		hash = ((hash * 33) + string.byte(jobId, i)) % (2 ^ 32)
	end
	return hash
end

-- Build the GA4 endpoint URL
local function getEndpointUrl(): string
	return string.format(
		"https://www.google-analytics.com/mp/collect?measurement_id=%s&api_secret=%s",
		config.measurementId,
		config.apiSecret
	)
end

-- Send a batch of events to GA4 for a single client
local function sendBatch(clientId: string, events: { GA4Event }, userProperties: UserProperties?): boolean
	local body = HttpService:JSONEncode({
		client_id = clientId,
		user_id = clientId,
		user_properties = userProperties,
		events = events,
	})

	local success, err = pcall(function()
		HttpService:PostAsync(getEndpointUrl(), body, Enum.HttpContentType.ApplicationJson, false)
	end)

	if success then
		if config.debug then
			print(string.format("[AnalyticsService] Sent batch of %d event(s) for client %s", #events, clientId))
		end
	else
		warn(string.format("[AnalyticsService] Failed to send batch: %s", tostring(err)))
	end

	return success
end

-- Flush all queued events, grouped by clientId and chunked into batches
local function flushEvents(filterClientId: string?)
	if #eventQueue == 0 then
		return
	end

	-- Separate events to flush vs events to keep
	local toFlush: { QueuedEvent } = {}
	local toKeep: { QueuedEvent } = {}

	for _, queuedEvent in eventQueue do
		if filterClientId == nil or queuedEvent.clientId == filterClientId then
			table.insert(toFlush, queuedEvent)
		else
			table.insert(toKeep, queuedEvent)
		end
	end

	eventQueue = toKeep

	if #toFlush == 0 then
		return
	end

	-- Group by clientId
	local grouped: { [string]: { GA4Event } } = {}
	for _, queuedEvent in toFlush do
		if not grouped[queuedEvent.clientId] then
			grouped[queuedEvent.clientId] = {}
		end
		table.insert(grouped[queuedEvent.clientId], queuedEvent.event)
	end

	-- Send each group in chunks of maxBatchSize
	for clientId, events in grouped do
		local userProps = userPropertiesCache[clientId]

		for i = 1, #events, config.maxBatchSize do
			local batch: { GA4Event } = {}
			for j = i, math.min(i + config.maxBatchSize - 1, #events) do
				table.insert(batch, events[j])
			end
			local ok = sendBatch(clientId, batch, userProps)
			if not ok then
				for _, event in batch do
					table.insert(eventQueue, { clientId = clientId, event = event })
				end
			end
		end
	end

	if config.debug then
		print(string.format("[AnalyticsService] Flushed %d event(s)", #toFlush))
	end
end

-- Background loop to periodically flush events
local function startFlushLoop()
	if isRunning then
		return
	end
	isRunning = true

	task.spawn(function()
		while true do
			task.wait(config.flushIntervalSeconds)
			flushEvents()
		end
	end)
end

-- Queue an event for a player
local function queueEvent(player: Player, eventName: string, params: { [string]: any }?)
	if not AnalyticsService.isEnabled then
		return
	end

	local clientId = hashUserId(player.UserId)

	local now = DateTime.now()
	local timestampMs = now.UnixTimestampMillis
	local timestampMicros = timestampMs * 1000

	local eventParams: { [string]: any } = params and table.clone(params) or {}
	eventParams.session_id = tostring(numericSessionId)
	eventParams.engagement_time_msec = 1
	eventParams.timestamp = timestampMs
	eventParams.place_version = PLACE_VERSION
	eventParams.place_id = PLACE_ID

	-- Always-stamp dimensions (experiment cohorts): resolved for every event
	-- except genuinely aggregate ones (see ALWAYS_STAMP_EXCLUDED_EVENTS). Fetchers
	-- are deterministic and don't depend on model hydration, so this is safe on
	-- pre-hydration events like player_join. nil results are omitted.
	if not ALWAYS_STAMP_EXCLUDED_EVENTS[eventName] then
		for _, key in alwaysDimensionKeys do
			local fetcher = dimensionFetchers[key]
			if fetcher then
				local value = fetcher(player)
				if value ~= nil then
					eventParams[key] = value
				end
			end
		end
	end
	if config.debug then
		eventParams.debug_mode = true
	end

	-- Stamp configured global dimensions (e.g. basket_count, worn_count) onto the event, except
	-- aggregate / pre-hydration events. Each fetcher reads the current model
	-- value; nil results are omitted (model not ready / absent).
	if not GLOBAL_PARAM_EXCLUDED_EVENTS[eventName] then
		for _, key in globalParamKeys do
			local fetcher = dimensionFetchers[key]
			if fetcher then
				local value = fetcher(player)
				if value ~= nil then
					eventParams[key] = value
				end
			end
		end
	end

	local event: GA4Event = {
		name = eventName,
		params = eventParams,
		timestamp_micros = timestampMicros,
	}

	table.insert(eventQueue, {
		clientId = clientId,
		event = event,
	})

	if config.debug then
		print(string.format("[AnalyticsService] Queued event '%s' for player %s (queue size: %d)", eventName, player.Name, #eventQueue))
	end

	-- Auto-flush if this player's events hit the batch limit
	local playerEventCount = 0
	for _, queuedEvent in eventQueue do
		if queuedEvent.clientId == clientId then
			playerEventCount += 1
		end
	end

	if playerEventCount >= config.maxBatchSize then
		flushEvents(clientId)
	end
end

-- Initialize the AnalyticsService
function AnalyticsService.init()
	-- Load config from ServerScriptService.Config
	local configFolder = ServerScriptService:FindFirstChild("Config")
	if not configFolder then
		warn("[AnalyticsService] No Config folder found in ServerScriptService")
		return
	end

	local analyticsConfig = configFolder:FindFirstChild("AnalyticsConfig")
	if not analyticsConfig then
		warn("[AnalyticsService] No AnalyticsConfig found in ServerScriptService.Config - create it in Studio")
		return
	end

	config = require(analyticsConfig)

	if not config.enabled then
		print("[AnalyticsService] Analytics disabled in config")
		return
	end

	if config.measurementId == "" or config.apiSecret == "" then
		warn("[AnalyticsService] Missing measurementId or apiSecret in AnalyticsConfig")
		return
	end

	-- Build the excluded-action lookup: controller actions named here are
	-- skipped by trackControllerAction (high-volume, low-value events).
	excludedActionSet = {}
	if config.excludedActions then
		for _, actionName in config.excludedActions do
			excludedActionSet[actionName] = true
		end
	end

	-- Snapshot the ordered list of global dimensions to stamp on every event
	-- (resolved via registerDimension). Order is cosmetic — all enabled keys are
	-- sent, well under GA4's 25-param/event limit.
	globalParamKeys = {}
	if config.globalParams then
		for _, key in config.globalParams do
			table.insert(globalParamKeys, key)
		end
	end

	AnalyticsService.isEnabled = true
	numericSessionId = generateNumericSessionId()

	-- Flush all events on server shutdown
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		print("[AnalyticsService] Server shutting down - flushing all analytics events")
		AnalyticsService:flushAll()
	end)

	startFlushLoop()
	print("[AnalyticsService] Initialized")
end

-- Cache demographic user properties on player join
function AnalyticsService:cacheUserProperties(player: Player)
	if not AnalyticsService.isEnabled then
		return
	end

	local clientId = hashUserId(player.UserId)

	-- Get country code (async call, may fail)
	local country = "unknown"
	local countrySuccess, countryResult = pcall(function()
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	if countrySuccess and countryResult then
		country = countryResult
	end

	-- Acquisition attribution from the join link's launchData (set per ad
	-- campaign; LaunchData.read, which has the Studio `TestLaunchData` hook).
	-- Truncated to GA4's 36-char user-property limit; "organic" when no
	-- launchData (arrived without a tagged link). A share link ("s:<code>",
	-- from a share QR) records as "share" (its own campaign tag "c:" if it
	-- carries one), so per-code values don't swamp the campaign tags; which
	-- code brought the player is the `share_join` event (DeepLinkService).
	local launchData = LaunchData.read(player)
	if LaunchData.shareCode(launchData) then
		launchData = LaunchData.parse(launchData).c or "share"
	end
	local launchValue = if launchData ~= "" then string.sub(launchData, 1, 36) else "organic"

	userPropertiesCache[clientId] = {
		locale = { value = player.LocaleId },
		country = { value = country },
		account_age_days = { value = tostring(player.AccountAge) },
		membership = { value = tostring(player.MembershipType) },
		launch_data = { value = launchValue },
	}

	playerJoinTimes[clientId] = os.clock()

	if config.debug then
		print(string.format(
			"[AnalyticsService] Cached properties for %s: locale=%s, country=%s, age=%d, membership=%s, launch_data=%s",
			player.Name,
			player.LocaleId,
			country,
			player.AccountAge,
			tostring(player.MembershipType),
			launchValue
		))
	end
end

-- Register a resolver for a dimension. A game-specific module wires these so
-- AnalyticsService stays model-agnostic. The fetcher must be non-yielding and
-- return the value (or nil to omit).
--
-- `always = false` (default): a global dimension, stamped on events per
-- config.globalParams (skipped on the pre-hydration / aggregate events in
-- GLOBAL_PARAM_EXCLUDED_EVENTS).
-- `always = true`: stamped on EVERY event (except aggregate ones), independent
-- of config.globalParams — for deterministic values like experiment cohorts.
function AnalyticsService.registerDimension(key: string, fetcher: (Player) -> any, always: boolean?)
	dimensionFetchers[key] = fetcher
	if always then
		table.insert(alwaysDimensionKeys, key)
	end
end

-- Track a custom event
function AnalyticsService:trackEvent(player: Player, eventName: string, params: { [string]: any }?)
	queueEvent(player, eventName, params)
end

-- Track a controller action (called automatically by AbstractController)
function AnalyticsService:trackControllerAction(player: Player, controllerName: string, actionName: string)
	-- Skip high-volume / low-value actions listed in config.excludedActions.
	if excludedActionSet[actionName] then
		return
	end
	queueEvent(player, "controller_action", {
		controller_name = controllerName,
		action_name = actionName,
	})
end

-- Track player join
function AnalyticsService:trackPlayerJoin(player: Player)
	queueEvent(player, "player_join", {})
end

-- Track player leave
function AnalyticsService:trackPlayerLeave(player: Player)
	local clientId = hashUserId(player.UserId)
	local joinTime = playerJoinTimes[clientId]
	local sessionDuration = if joinTime then math.floor(os.clock() - joinTime) else 0

	queueEvent(player, "player_leave", {
		session_duration_seconds = sessionDuration,
	})
end

-- Flush all queued events for a specific player
function AnalyticsService:flushPlayer(player: Player)
	if not AnalyticsService.isEnabled then
		return
	end

	local clientId = hashUserId(player.UserId)
	flushEvents(clientId)

	-- Only clean up cached data if no events remain queued for this client
	-- (failed sends re-queue events and still need the cached properties)
	local hasRemainingEvents = false
	for _, queuedEvent in eventQueue do
		if queuedEvent.clientId == clientId then
			hasRemainingEvents = true
			break
		end
	end

	if not hasRemainingEvents then
		userPropertiesCache[clientId] = nil
		playerJoinTimes[clientId] = nil
	end
end

-- Flush all queued events
function AnalyticsService:flushAll()
	if not AnalyticsService.isEnabled then
		return
	end
	flushEvents()
end

return AnalyticsService
