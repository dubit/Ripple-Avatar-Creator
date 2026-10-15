--!strict

--[[
	PlaceholderData (Task 2 — replaced by real data from Task 7 onwards)

	Mock items ported from the design prototype
	(features/cac-adaptation/design/logic.js) so the shell's screens have
	believable content to navigate. Nothing here is persisted or networked.

	The Catalogue screen now shows real items (CatalogueClient, Task 7);
	`item(id)` falls back to them, so the screens that look items up by id
	(item page, basket, wearing) work for both. The mock items
	remain for the starting basket/wearing state (Community outfits are
	real since Task 16, stores since Task 18).
]]

local CatalogueClient = require(script.Parent.Parent:WaitForChild("catalogue"):WaitForChild("CatalogueClient"))

local PlaceholderData = {}

export type Item = CatalogueClient.Item

local CREATORS = { "JON.", "pixelfox", "mossy_m", "k4tana", "nyxie", "Roblox" }

-- name, main, sub, price, colour, flags (o = owned; h/n/t were the dropped Halloween/New/Trending tabs)
local RAW_ITEMS = {
	{ "Wavy Middle Part", "Hair", "Long", 65, "Brown", "" },
	{ "Messy Bob", "Hair", "Short", 65, "Black", "" },
	{ "Long Ponytail", "Hair", "Long", 80, "Orange", "n" },
	{ "Space Buns", "Hair", "Updo", 70, "Pink", "t" },
	{ "Curly Afro", "Hair", "Curly", 75, "Black", "" },
	{ "Side Swept", "Hair", "Short", 0, "Brown", "o" },
	{ "Braided Crown", "Hair", "Updo", 85, "Brown", "n" },
	{ "Ringlets", "Hair", "Curly", 70, "Purple", "" },
	{ "Pumpkin Hoodie", "Clothing", "Tops", 65, "Orange", "ht" },
	{ "Striped Knit", "Clothing", "Tops", 70, "Black", "" },
	{ "Cropped Tee", "Clothing", "Tops", 55, "White", "o" },
	{ "Varsity Jacket", "Clothing", "Jackets", 90, "Blue", "t" },
	{ "Puffer Vest", "Clothing", "Jackets", 85, "Green", "" },
	{ "Skeleton Tee", "Clothing", "Tops", 65, "Black", "h" },
	{ "Cargo Pants", "Clothing", "Bottoms", 60, "Green", "" },
	{ "Plaid Skirt", "Clothing", "Bottoms", 55, "Pink", "" },
	{ "Baggy Jeans", "Clothing", "Bottoms", 65, "Blue", "n" },
	{ "Track Pants", "Clothing", "Bottoms", 0, "Black", "" },
	{ "Chunky Sneakers", "Clothing", "Shoes", 60, "White", "t" },
	{ "Platform Boots", "Clothing", "Shoes", 75, "Black", "" },
	{ "Canvas High-tops", "Clothing", "Shoes", 55, "Pink", "o" },
	{ "Fur Boots", "Clothing", "Shoes", 60, "Pink", "" },
	{ "Cat Ears", "Accessories", "Hat", 40, "Black", "" },
	{ "Witch Hat", "Accessories", "Hat", 95, "Purple", "h" },
	{ "Heart Tiara", "Accessories", "Hat", 95, "Pink", "t" },
	{ "Sunglasses", "Accessories", "Face", 45, "Black", "" },
	{ "Ghost Mask", "Accessories", "Face", 85, "White", "h" },
	{ "Scarf", "Accessories", "Neck", 30, "Orange", "" },
	{ "Pearl Necklace", "Accessories", "Neck", 50, "White", "n" },
	{ "Backpack", "Accessories", "Back", 55, "Blue", "" },
	{ "Bat Wings", "Accessories", "Back", 120, "Black", "ht" },
	{ "Classic Smile", "Head & Body", "Faces", 0, "White", "o" },
	{ "Sleepy", "Head & Body", "Faces", 45, "White", "" },
	{ "Freckles", "Head & Body", "Faces", 30, "Brown", "" },
	{ "Round Head", "Head & Body", "Heads", 40, "White", "n" },
	{ "Floating Pack", "Animations", "Packs", 315, "Purple", "t" },
	{ "Ninja Pack", "Animations", "Packs", 250, "Black", "" },
	{ "Bubbly Pack", "Animations", "Packs", 250, "Pink", "o" },
	{ "Cool Idle", "Animations", "Idle", 60, "Blue", "" },
	{ "Victory Jump", "Emotes", "Gesture", 58, "Orange", "t" },
	{ "Salute", "Emotes", "Gesture", 40, "Green", "" },
	{ "Dance Groove", "Emotes", "Dance", 75, "Purple", "n" },
	{ "Wave", "Emotes", "Gesture", 0, "Blue", "o" },
	{ "Zombie Shuffle", "Emotes", "Dance", 60, "Green", "h" },
	{ "Spooky Float", "Emotes", "Pose", 70, "Purple", "h" },
	{ "Hero Pose", "Emotes", "Pose", 50, "Orange", "" },
}

PlaceholderData.items = {} :: { Item }
for index, raw in RAW_ITEMS do
	local flags = raw[6] :: string
	table.insert(PlaceholderData.items, {
		id = index,
		kind = "Asset",
		targetId = index,
		name = raw[1] :: string,
		main = raw[2] :: string,
		sub = raw[3] :: string,
		typeName = raw[3] :: string,
		price = raw[4] :: number,
		limited = false,
		resale = false,
		creator = CREATORS[(index - 1) % #CREATORS + 1],
		description = "",
		favourites = 0,
		thumbnail = "",
		colour = raw[5] :: string,
		colours = { raw[5] :: string },
		owned = string.find(flags, "o", 1, true) ~= nil,
	} :: Item)
end

function PlaceholderData.item(id: number): Item
	return PlaceholderData.items[id] or CatalogueClient.item(id) :: Item
end

-- "18.6M" / "294.0K" / "596"
function PlaceholderData.formatCount(n: number): string
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

return PlaceholderData
