--!strict

--[[
	SkinColours (shared)

	A look's skin colours: one per body part, each "#RRGGBB" or absent (the
	wearer's own colour for that part). Used by the server (AvatarModel,
	AvatarService, outfits) and the client (Skin tone picker, outfit pages).

	An older form was a single "#RRGGBB" for the whole body; `normalise`
	turns that (or "" / nil) into the per-part table.

	API:
		PARTS                         the six parts, in display order
		property[part]                its HumanoidDescription colour property
		label[part]                   "Left arm" …
		normalise(raw) -> Colours     a table (parts with valid hex only)
		isEmpty(colours) -> boolean   all the wearer's own
		count(colours) -> number      how many parts are set
		equal(a, b) -> boolean
		name(hex) -> string           the nearest Roblox colour name
]]

local SkinColours = {}

export type Part = "Head" | "Torso" | "LeftArm" | "RightArm" | "LeftLeg" | "RightLeg"
export type Colours = { [string]: string }

SkinColours.PARTS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } :: { Part }

SkinColours.property = {
	Head = "HeadColor",
	Torso = "TorsoColor",
	LeftArm = "LeftArmColor",
	RightArm = "RightArmColor",
	LeftLeg = "LeftLegColor",
	RightLeg = "RightLegColor",
}

SkinColours.label = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left arm",
	RightArm = "Right arm",
	LeftLeg = "Left leg",
	RightLeg = "Right leg",
}

local function valid(hex: any): string?
	if type(hex) == "string" and string.match(hex, "^#%x%x%x%x%x%x$") then
		return string.upper(hex)
	end
	return nil
end

function SkinColours.normalise(raw: any): Colours
	local result: Colours = {}
	local whole = valid(raw)
	if whole then
		for _, part in SkinColours.PARTS do
			result[part] = whole
		end
	elseif type(raw) == "table" then
		for _, part in SkinColours.PARTS do
			local hex = valid(raw[part])
			if hex then
				result[part] = hex
			end
		end
	end
	return result
end

function SkinColours.count(colours: Colours): number
	local n = 0
	for _, part in SkinColours.PARTS do
		if colours[part] then
			n += 1
		end
	end
	return n
end

function SkinColours.isEmpty(colours: Colours): boolean
	return SkinColours.count(colours) == 0
end

function SkinColours.equal(a: Colours, b: Colours): boolean
	for _, part in SkinColours.PARTS do
		if a[part] ~= b[part] then
			return false
		end
	end
	return true
end

function SkinColours.name(hex: string): string
	local ok, colour = pcall(Color3.fromHex, hex)
	if not ok then
		return hex
	end
	return BrickColor.new(colour).Name
end

return SkinColours
