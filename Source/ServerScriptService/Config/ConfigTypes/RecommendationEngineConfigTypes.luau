--!strict
--[[
	RecommendationEngineConfigTypes
	Type definitions for the recommendation engine connection (Ripple's own
	recommendation service, called by RecommendationsController).

	The config lives in ServerScriptService (not ReplicatedStorage): clients
	never see where the engine is. The API key isn't in it at all: it's a
	Roblox secret (Game Settings > Security > Secrets), named by `secretName`,
	with its allowed domain set to the engine's host.

	Create the config in Studio: ServerScriptService > Config >
	RecommendationEngineConfig (ModuleScript). While testing through a
	Cloudflare quick tunnel, `baseUrl` changes every time the tunnel starts.
]]

export type RecommendationEngineConfig = {
	enabled: boolean, -- false: the ring shows "Engine failed: disabled"
	baseUrl: string, -- e.g. "https://something.trycloudflare.com" (no trailing slash)
	secretName: string, -- the Roblox secret holding the API key, e.g. "ripple_recs"
	count: number, -- how many to ask for; the client picks the ring from these
	                 -- (skipping worn, already shown, and crowded body areas)
	debug: boolean, -- print each request's outcome on the server
}

return nil
