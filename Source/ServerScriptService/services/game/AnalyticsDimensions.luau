--!strict

--[[
	AnalyticsDimensions

	Game-specific wiring for AnalyticsService "global dimensions": absolute model
	values stamped onto (almost) every analytics event, so ANY event can be
	segmented by where the player is in BigQuery (e.g. "do players with a full
	basket buy more than ones with one item in it?"). Ours are counts:
	basket_count, worn_count, outfits_count and stores_count. Registering a resolver here keeps
	AnalyticsService itself model-agnostic and reusable across games — swap this
	module's resolvers for your game's models.

	How it fits together:
	  1. Register a resolver per dimension key below (registerDimension).
	  2. Turn each one ON by listing its key in AnalyticsConfig.globalParams,
	     e.g. globalParams = { "basket_count", "worn_count" }. A registered key that ISN'T in
	     globalParams is simply never stamped — registering is harmless.
	  3. AnalyticsService stamps the enabled keys onto every event except the
	     aggregate / pre-hydration events it excludes (heatmap_summary,
	     player_join — where there's no meaningful per-player value yet).

	Resolvers MUST be non-yielding — they run inline while an event is queued.
	Reading a per-player model is safe here: by the time a player is firing
	events their models are already loaded, so Model.get returns immediately
	rather than waiting. Return nil to omit the param (model absent / not ready).

	This module is a game service: ServiceRunner auto-discovers it and calls
	init() — no manual wiring needed.
]]

local AnalyticsService = require(script.Parent.Parent.framework.AnalyticsService)
local ExperimentService = require(script.Parent.Parent.framework.ExperimentService)
local models = script.Parent.Parent.Parent.models
local AvatarModel = require(models.user.AvatarModel)
local BasketModel = require(models.user.BasketModel)
local OutfitsModel = require(models.user.OutfitsModel)
local StoresModel = require(models.user.StoresModel)

-- A dimension that counts one list field of a per-player model.
local function count(name: string, Model: any, field: string)
	AnalyticsService.registerDimension(name, function(player: Player): any
		local model = Model.get(tostring(player.UserId))
		local list = if model then model[field] else nil
		return if type(list) == "table" then #list else nil
	end)
end

local AnalyticsDimensions = {}

function AnalyticsDimensions.init()
	-- Each is on only while its key is in AnalyticsConfig.globalParams.
	count("basket_count", BasketModel, "items")
	count("worn_count", AvatarModel, "worn")
	count("outfits_count", OutfitsModel, "outfits")
	count("stores_count", StoresModel, "mine")

	-- Experiment cohorts: one dimension per enabled experiment, keyed "exp_<name>"
	-- (e.g. "exp_example_sweep"). Registered with always = true so the cohort rides
	-- every event (cohorts are deterministic — no model hydration needed — so this
	-- is safe pre-hydration; see ExperimentService). Auto-derived from
	-- ExperimentsConfig, so adding a test needs no analytics or globalParams edit.
	for _, experimentKey in ExperimentService.getEnabledKeys() do
		local paramKey = "exp_" .. experimentKey
		AnalyticsService.registerDimension(paramKey, function(player: Player): any
			return ExperimentService.getVariantKey(player, experimentKey)
		end, true)
	end
end

return AnalyticsDimensions
