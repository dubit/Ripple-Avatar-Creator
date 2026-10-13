--!strict

--[[
	SharedCodes (client)

	Share codes typed into the Outfits search ("OUT-7KQ2XM", any case, with
	or without the dash): resolved by the server ("ResolveShareCode", Bolt)
	from the shared DataStore. Outfits only for now; the result carries its
	kind so other kinds of shared things can join later.

	API:
		normalise(text) -> string?      "out-7kq2xm" -> "OUT-7KQ2XM"; nil if
		                                it isn't code-shaped
		resolve(code) -> (Shared?, error?)   yields; cached briefly;
		                                error "notfound" | "busy" | "failed"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bolt = require(ReplicatedStorage:WaitForChild("Bolt"))
local CatalogueClient = require(script.Parent:WaitForChild("CatalogueClient"))
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))
local BodyScale = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("BodyScale"))

local SharedCodes = {}

export type Shared = {
	code: string,
	kind: string, -- "outfit"
	name: string,
	by: string, -- the owner's username
	ownerId: number,
	items: { number }, -- CatalogueClient item ids
	skin: { [string]: string },
	scale: { [string]: number },
}

local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local CACHE_SECONDS = 20

local remote = Bolt.RemoteFunction("ResolveShareCode")
local cache: { [string]: { shared: Shared?, error: string?, at: number } } = {}

function SharedCodes.normalise(text: string): string?
	local prefix, body = string.match(string.upper(text), "^%s*(%u%u%u)%-?([%w]+)%s*$")
	if not prefix or not body or #body ~= 6 then
		return nil
	end
	for i = 1, #body do
		if not string.find(ALPHABET, string.sub(body, i, i), 1, true) then
			return nil
		end
	end
	return prefix .. "-" .. body
end

function SharedCodes.resolve(code: string): (Shared?, string?)
	local cached = cache[code]
	if cached and os.clock() - cached.at < CACHE_SECONDS then
		return cached.shared, cached.error
	end
	local ok, result = pcall(function()
		return remote:InvokeServer(code)
	end)
	if not ok or type(result) ~= "table" then
		return nil, "failed"
	end
	if not result.ok or type(result.outfit) ~= "table" then
		local err = result.error or "failed"
		if err == "notfound" then
			cache[code] = { shared = nil, error = err, at = os.clock() }
		end
		return nil, err
	end
	local raw = result.outfit
	local items = {}
	for _, entry in raw.items or {} do
		table.insert(items, CatalogueClient.remember(entry).id)
	end
	local shared: Shared = {
		code = result.code,
		kind = result.kind,
		name = tostring(raw.name or "Outfit"),
		by = tostring(raw.by or ""),
		ownerId = tonumber(raw.ownerId) or 0,
		items = items,
		skin = SkinColours.normalise(raw.skin),
		scale = BodyScale.normalise(raw.scale),
	}
	cache[code] = { shared = shared, at = os.clock() }
	return shared, nil
end

return SharedCodes
