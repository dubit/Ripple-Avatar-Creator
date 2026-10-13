--!strict

--[[
	PlaceholderData (Task 2 — replaced by real data from Task 7 onwards)

	Mock items, stores and outfits ported from the design prototype
	(features/cac-adaptation/design/logic.js) so the shell's screens have
	believable content to navigate. Nothing here is persisted or networked.

	The Catalogue screen now shows real items (CatalogueClient, Task 7);
	`item(id)` falls back to them, so the screens that look items up by id
	(item page, basket, wearing) work for both. The mock items
	remain for the starting basket/wearing state and the mock outfits/stores.
]]

local CatalogueClient = require(script.Parent.Parent:WaitForChild("catalogue"):WaitForChild("CatalogueClient"))

local PlaceholderData = {}

export type Item = CatalogueClient.Item

export type Store = { id: number, name: string, rating: number, visits: number, sponsored: boolean }
export type Outfit = { name: string, by: string, items: { number } }

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

local RAW_STORES = {
	{ "Mini Basics", 89, 18.6e6, true },
	{ "Grouchy UGC", 94, 294e3, true },
	{ "Hair Studio", 100, 596, true },
	{ "Cartoony Rainbow", 100, 28.4e3, true },
	{ "Dolce", 95, 261.9e3, false },
	{ "Y2K Store", 96, 461.5e3, false },
	{ "Anime World", 86, 10.2e6, false },
	{ "Free Shop", 89, 18e6, false },
	{ "Kings UGC", 96, 45.6e3, false },
	{ "Chibi Store", 85, 7.4e3, false },
	{ "Pawing Outfits", 91, 13.6e6, false },
	{ "Formal Attire", 95, 15.8e3, false },
	{ "Cosplay Corner", 95, 42.5e3, false },
	{ "Goth Garden", 97, 1.7e6, false },
	{ "Blox Fits", 82, 10.1e6, false },
	{ "Pastel Lab", 93, 88e3, false },
	{ "Street Kings", 90, 512e3, false },
	{ "Tiny Hats", 99, 3.2e3, false },
}

PlaceholderData.stores = {} :: { Store }
for index, raw in RAW_STORES do
	table.insert(PlaceholderData.stores, {
		id = index,
		name = raw[1] :: string,
		rating = raw[2] :: number,
		visits = raw[3] :: number,
		sponsored = raw[4] :: boolean,
	})
end

PlaceholderData.storeSorts = { "Sponsored", "Popular", "Top rated", "Favourites", "My stores" }

-- Items a store "sells" (deterministic, as in the prototype).
function PlaceholderData.storeItems(storeId: number): { Item }
	local list = {}
	for _, item in PlaceholderData.items do
		local i = item.id - 1
		if (i * 7 + storeId * 3) % 5 < 2 or (i + storeId) % 11 == 0 then
			table.insert(list, item)
		end
	end
	return list
end

-- Placeholder Community outfits until Task 16. Item ids are 1-based
-- (prototype ids + 1).
PlaceholderData.outfits = {
	Community = {
		{ name = "Neon Rider", by = "by pixelfox", items = { 12, 17, 19, 30, 28 } },
		{ name = "Cottagecore", by = "by mossy_m", items = { 3, 16, 22, 29 } },
		{ name = "Street Ninja", by = "by k4tana", items = { 13, 15, 20, 37 } },
		{ name = "Goth Princess", by = "by nyxie", items = { 10, 16, 20, 24 } },
		{ name = "Cyber Punk", by = "by zeroday", items = { 4, 14, 17, 26 } },
		{ name = "Cozy Winter", by = "by snowpea", items = { 2, 10, 22, 28 } },
		{ name = "Skater", by = "by ollie_o", items = { 5, 11, 17, 19 } },
		{ name = "Pumpkin Patch", by = "by JON.", items = { 9, 15, 19, 27 } },
		{ name = "Fairy Core", by = "by glimmer", items = { 8, 16, 21, 25 } },
		{ name = "Sporty", by = "by dashr", items = { 1, 11, 18, 19 } },
	} :: { Outfit },
}

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
