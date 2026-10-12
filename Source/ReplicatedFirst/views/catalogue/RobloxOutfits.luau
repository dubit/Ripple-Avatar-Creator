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

export type Outfit = { id: number, name: string, items: { number } }
export type Status = "unknown" | "locked" | "loading" | "ready" | "denied"

local MAX_OUTFITS = 50

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

local function itemsOf(outfitId: number): { number }
	local ok, details = pcall(function()
		return AvatarEditorService:GetOutfitDetails(outfitId)
	end)
	local ids = {}
	if not ok or type(details) ~= "table" then
		return ids
	end
	for _, asset in details.Assets or {} do
		local id = tonumber(asset.Id or asset.id)
		local typeName = nameOf(asset.AssetType or asset.assetType)
		if id and typeName then
			local item = CatalogueClient.remember({
				targetId = id,
				kind = "Asset",
				typeName = typeName,
				name = tostring(asset.Name or asset.name or ""),
				owned = true, -- outfits on Roblox are made from your own items
			})
			table.insert(ids, item.id)
		end
	end
	return ids
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
				table.insert(loaded, { id = id, name = tostring(entry.Name or entry.name or "Outfit"), items = {} })
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
			outfit.items = itemsOf(outfit.id)
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
