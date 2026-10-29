--!strict

--[[
	WorldOptionsSections

	The World options panel's three sections and the saved settings each one
	owns, shared by the panel (its tabs, and Reset for the open section), the
	client's draft (useWorldOptions) and the server (WorldOptionsController /
	WorldOptionsModel reset one section at a time).

	  sky    time of day, sky preset, lighting, shadows
	  floor  floor colour, pattern colour, pattern texture and strength
	  music  the playlist (track keys), whether it's playing, its volume

	Also the one playlist rule both sides apply: known track keys only, each
	once, in the library's order (the grid's), never empty.
]]

local WorldOptionsSections = {}

export type Section = "sky" | "floor" | "music"

WorldOptionsSections.ORDER = { "sky", "floor", "music" } :: { Section }

WorldOptionsSections.KEYS = {
	sky = { "time", "sky", "brightness", "shadows" },
	floor = { "floor", "floorLightness", "pattern", "patternColor", "patternLightness", "patternStrength" },
	music = { "playlist", "musicOn" },
} :: { [string]: { string } }

-- `raw` as a playlist of the library's track keys (tracks: { { key } }), in
-- library order, each once; nil when nothing in it is a known track.
function WorldOptionsSections.playlist(raw: any, tracks: { { key: string } }): { string }?
	if type(raw) ~= "table" then
		return nil
	end
	local wanted: { [string]: boolean } = {}
	for _, key in raw do
		if type(key) == "string" then
			wanted[key] = true
		end
	end
	local list = {}
	for _, track in tracks do
		if wanted[track.key] then
			table.insert(list, track.key)
		end
	end
	return if #list > 0 then list else nil
end

-- True if two playlists hold the same keys in the same order.
function WorldOptionsSections.samePlaylist(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for index, key in a do
		if b[index] ~= key then
			return false
		end
	end
	return true
end

return WorldOptionsSections
