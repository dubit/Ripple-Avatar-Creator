--!strict

--[[
	BodyScale (shared)

	A look's body scale, as Roblox's avatar editor has it ("Scale"): height,
	width, head, body type and proportions. Each is a number within Roblox's
	avatar limits, or absent (the wearer's own). Width also sets depth, as
	the avatar editor does. Used by the server (AvatarModel, AvatarService,
	outfits) and the client (Catalogue › Scale, outfit pages).

	API:
		KEYS                          in display order
		info[key]                     { label, property, min, max, default }
		normalise(raw) -> Scale       valid keys only, clamped, 2 decimals
		isEmpty(scale) / equal(a, b)
		summary(scale) -> string      "Height 105% · Width 80%"
]]

local BodyScale = {}

export type Scale = { [string]: number }

BodyScale.KEYS = { "height", "width", "head", "bodyType", "proportion" }

-- Roblox's avatar scale limits.
BodyScale.info = {
	height = { label = "Height", property = "HeightScale", min = 0.9, max = 1.05, default = 1 },
	width = { label = "Width", property = "WidthScale", min = 0.7, max = 1, default = 1 },
	head = { label = "Head", property = "HeadScale", min = 0.95, max = 1, default = 1 },
	bodyType = { label = "Body type", property = "BodyTypeScale", min = 0, max = 1, default = 0 },
	proportion = { label = "Proportions", property = "ProportionScale", min = 0, max = 1, default = 0 },
}

function BodyScale.normalise(raw: any): Scale
	local result: Scale = {}
	if type(raw) ~= "table" then
		return result
	end
	for _, key in BodyScale.KEYS do
		local value = raw[key]
		if type(value) == "number" and value == value then
			local info = BodyScale.info[key]
			result[key] = math.floor(math.clamp(value, info.min, info.max) * 100 + 0.5) / 100
		end
	end
	return result
end

function BodyScale.isEmpty(scale: Scale): boolean
	return next(scale) == nil
end

function BodyScale.equal(a: Scale, b: Scale): boolean
	for _, key in BodyScale.KEYS do
		if a[key] ~= b[key] then
			return false
		end
	end
	return true
end

function BodyScale.summary(scale: Scale): string
	local parts = {}
	for _, key in BodyScale.KEYS do
		local value = scale[key]
		if value then
			table.insert(parts, BodyScale.info[key].label .. " " .. math.floor(value * 100 + 0.5) .. "%")
		end
	end
	return table.concat(parts, " · ")
end

return BodyScale
