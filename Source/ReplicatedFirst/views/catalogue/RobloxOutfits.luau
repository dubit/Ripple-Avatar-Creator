--!strict

--[[
	RobloxOutfits (client)

	The outfits the player has saved on Roblox itself (in the Roblox avatar
	editor, outside any experience), for Outfits › Mine.

	Roblox only lists them once the player allows it
	(AvatarEditorService:PromptAllowInventoryReadAccess). So:
	  · `check()` tries quietly: if access was already given, the outfits
	    load; otherwise status stays "locked" and Mine shows a "Show my
	    Roblox outfits" card.
	  · `request()` (that card) asks Roblox's own permission prompt, then
	    loads them.

	Each outfit's items come from AvatarEditorService:GetOutfitDetails, as
	CatalogueClient items (via `remember`). At most MAX_OUTFITS are loaded.

	Roblox lists a body as its separate parts (torso, arms, legs), though
	they're bought as one bundle. So the parts are grouped back together:
	a catalogue search on the parts' shared name ("Korblox Deathspeaker Left
	Arm" … → "Korblox Deathspeaker", body bundles only) finds the bundle
	whose contents include the torso, and the parts, plus anything else of
	that bundle's in the outfit (a hood, a head), become that one bundle
	item. If no bundle turns up, the parts stay single (wearable) items,
	which outfit pages show together as one Body row. Searches are one at
	a time and cached by torso.

	API:
		status() -> "unknown" | "locked" | "loading" | "ready" | "denied"
		outfits() -> { { id, name, items = { itemId } } }
		check()           quiet first look (once)
		request()         ask permission, then load
		changed           signal: status or outfits changed
]]

local AvatarEditorService = game:GetService("AvatarEditorService")

local CatalogueClient = require(script.Parent:WaitForChild("CatalogueClient"))

local RobloxOutfits = {}

export type Outfit = {
	id: number,
	name: string,
	items: { number },
	labels: { [number]: string }, -- display names that differ from the item's own
}
export type Status = "unknown" | "locked" | "loading" | "ready" | "denied"

local MAX_OUTFITS = 50
local BODY_PARTS = { Torso = true, LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true }

-- Torso id -> the body bundle holding it ({ id, name, contents }) or false.
local bundleCache: { [number]: any } = {}
local searching = false -- one bundle search at a time (the catalogue throttles)

local status: Status = "unknown"
local list: { Outfit } = {}
local checked = false

local changedEvent = Instance.new("BindableEvent")
RobloxOutfits.changed = changedEvent.Event

local function setStatus(next: Status)
	status = next
	changedEvent:Fire()
end

-- An enum item's name, from an EnumItem, a { Name } table or a string.
local function nameOf(value: any): string?
	if typeof(value) == "EnumItem" then
		return value.Name
	elseif type(value) == "table" then
		return value.Name or value.name
	elseif type(value) == "string" then
		return value
	end
	return nil
end

-- The words every name starts with ("Korblox Deathspeaker").
local function sharedName(names: { string }): string
	local words = string.split(names[1] or "", " ")
	local shared = #words
	for _, name in names do
		local other = string.split(name, " ")
		local n = 0
		while n < shared and other[n + 1] == words[n + 1] do
			n += 1
		end
		shared = n
	end
	return table.concat(words, " ", 1, shared)
end

-- The body bundle whose contents include this torso (yields; cached).
local function bodyBundle(torsoId: number, keyword: string): any
	local cached = bundleCache[torsoId]
	if cached ~= nil then
		return cached or nil
	end
	while searching do
		task.wait(0.1)
	end
	cached = bundleCache[torsoId]
	if cached ~= nil then
		return cached or nil
	end
	searching = true
	local found: any = false
	if keyword ~= "" then
		pcall(function()
			local params = CatalogSearchParams.new()
			params.SearchKeyword = keyword
			params.BundleTypes = { Enum.BundleType.BodyParts }
			local page = AvatarEditorService:SearchCatalog(params):GetCurrentPage()
			for _, result in page do
				local contents = {}
				local holds = false
				for _, part in result.BundledItems or {} do
					if part.Type == "Asset" then
						contents[tonumber(part.Id) or 0] = true
						if tonumber(part.Id) == torsoId then
							holds = true
						end
					end
				end
				if holds then
					found = { id = result.Id, name = result.Name, contents = contents }
					break
				end
			end
		end)
	end
	bundleCache[torsoId] = found
	searching = false
	return found or nil
end

-- An outfit's items, with its body parts grouped back into one entry.
local function itemsOf(outfitId: number): ({ number }, { [number]: string })
	local ok, details = pcall(function()
		return AvatarEditorService:GetOutfitDetails(outfitId)
	end)
	local ids = {}
	local labels: { [number]: string } = {}
	if not ok or type(details) ~= "table" then
		return ids, labels
	end
	local assets = {}
	local partNames = {}
	local torso: any = nil
	for _, asset in details.Assets or {} do
		local id = tonumber(asset.Id or asset.id)
		local typeName = nameOf(asset.AssetType or asset.assetType)
		if id and typeName then
			local entry = { id = id, typeName = typeName, name = tostring(asset.Name or asset.name or "") }
			table.insert(assets, entry)
			if BODY_PARTS[typeName] then
				table.insert(partNames, entry.name)
				if typeName == "Torso" then
					torso = entry
				end
			end
		end
	end
	torso = torso or (function()
		for _, entry in assets do
			if BODY_PARTS[entry.typeName] then
				return entry
			end
		end
		return nil
	end)()
	local keyword = sharedName(partNames)
	local bundle = if torso then bodyBundle(torso.id, keyword) else nil
	local bodyAdded = false
	for _, entry in assets do
		local inBundle = bundle and (BODY_PARTS[entry.typeName] or bundle.contents[entry.id])
		if inBundle then
			-- The whole bundle once, where its first part was.
			if not bodyAdded then
				bodyAdded = true
				local item = CatalogueClient.remember({
					targetId = bundle.id,
					kind = "Bundle",
					typeName = "BodyParts",
					name = bundle.name,
					owned = true,
				})
				table.insert(ids, item.id)
			end
		else
			-- (Without a bundle, body parts stay single items; outfit pages
			-- show them as one Body row.)
			local item = CatalogueClient.remember({
				targetId = entry.id,
				kind = "Asset",
				typeName = entry.typeName,
				name = entry.name,
				owned = true, -- outfits on Roblox are made from your own items
			})
			table.insert(ids, item.id)
		end
	end
	return ids, labels
end

-- Load the list (yields). False if Roblox wouldn't give it.
local function load(): boolean
	local ok, pages = pcall(function()
		return AvatarEditorService:GetOutfits(Enum.OutfitSource.Created, Enum.OutfitType.Avatar)
	end)
	if not ok or not pages then
		return false
	end
	setStatus("loading")
	local loaded: { Outfit } = {}
	while #loaded < MAX_OUTFITS do
		local page = pages:GetCurrentPage()
		for _, entry in page do
			if #loaded >= MAX_OUTFITS then
				break
			end
			local id = tonumber(entry.Id or entry.id)
			if id then
				table.insert(loaded, { id = id, name = tostring(entry.Name or entry.name or "Outfit"), items = {}, labels = {} })
			end
		end
		if pages.IsFinished then
			break
		end
		local advanced = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanced then
			break
		end
	end
	list = loaded
	setStatus("ready")
	-- Each outfit's items, showing as they arrive.
	for _, outfit in loaded do
		task.spawn(function()
			outfit.items, outfit.labels = itemsOf(outfit.id)
			changedEvent:Fire()
		end)
	end
	return true
end

function RobloxOutfits.status(): Status
	return status
end

function RobloxOutfits.outfits(): { Outfit }
	return list
end

function RobloxOutfits.check()
	if checked then
		return
	end
	checked = true
	task.spawn(function()
		if not load() then
			setStatus("locked")
		end
	end)
end

function RobloxOutfits.request()
	if status == "loading" or status == "ready" then
		return
	end
	task.spawn(function()
		local done = false
		local result: Enum.AvatarPromptResult? = nil
		local connection = AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(answer)
			result = answer
			done = true
		end)
		local ok = pcall(function()
			AvatarEditorService:PromptAllowInventoryReadAccess()
		end)
		if not ok then
			connection:Disconnect()
			setStatus("denied")
			return
		end
		while not done do
			task.wait()
		end
		connection:Disconnect()
		if result == Enum.AvatarPromptResult.Success and load() then
			return
		end
		setStatus("denied")
	end)
end

return RobloxOutfits
