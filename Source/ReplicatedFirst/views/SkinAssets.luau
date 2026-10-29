--!strict

--[[
	SkinAssets

	The single home for HUD image asset IDs.

	Icons: one white-fill 128px image per Material Symbols Rounded glyph,
	tinted at runtime with ImageColor3. Source PNGs: assets/ui/icons/, built by
	tools/build_icons.py from the design's icon font. To add an icon: add
	it to the script's ICONS list, rebuild, upload the PNG via Studio's Asset
	Manager, and add its IMAGE asset ID (not a Decal ID) below.

	An icon with no ID renders a deliberately ugly placeholder so missing art
	is obvious.
]]

local SkinAssets = {}

SkinAssets.icons = {
	add_business = 97532956820465,
	add_circle = 135005117071279,
	add_shopping_cart = 82527124583124,
	apparel = 94177734376541,
	arrow_back = 121766949760746,
	bookmark_add = 86911205794599,
	check = 88158457528017,
	check_circle = 92221501449673,
	checkroom = 78096217583635,
	chevron_left = 123626147887091,
	chevron_right = 114670021870771,
	close = 139136293752542,
	cloud_off = 81068975444668,
	cloud_upload = 91562809650291,
	content_copy = 101027253209192,
	delete = 101639546014495,
	delete_sweep = 96618116522731,
	edit = 88379064804243,
	expand_less = 123341703772881,
	expand_more = 75001266556239,
	swap_horiz = 115185155398662,
	flag = 118640759523298,
	flight = 71395858478083,
	ios_share = 90787313571068,
	landscape = 93716528650433,
	link = 109659227478159,
	lock = 74847788561694,
	person_add = 98841581564997,
	remove = 90125229559734,
	remove_shopping_cart = 128883588652032,
	restart_alt = 89689435225163,
	search = 113580527499154,
	share = 112275740280984,
	shopping_basket = 99889459944389,
	star = 138473232558734,
	storefront = 126209902090800,
	toll = 108231234324649,
	undo = 138050190849416,
	visibility = 95037949648164,
	-- Animation bar (panel preview)
	accessibility_new = 92809236173438, -- idle
	directions_walk = 111496783629433,
	directions_run = 133195607663065,
	sports_gymnastics = 86267274461026, -- jump
	paragliding = 97940208976119, -- fall
	stairs = 78234124652504, -- climb
	pool = 107183700626092, -- swim
	emoji_people = 107200103596168, -- emotes
	-- World options tabs + the music player
	wb_sunny = 139103723332673, -- Sky
	grid_on = 80848591679330, -- Floor
	music_note = 82485118182956, -- Music
	play_arrow = 78845549983838,
	pause = 83770782533186,
	skip_next = 106490187937706,
	skip_previous = 98701137308324,
	volume_up = 136975718563958,
	volume_off = 85932727839184,
	graphic_eq = 88626857826555, -- the playing track
} :: { [string]: number }

-- UI sounds (views/Sounds plays them). 0 = no sound (silent).
-- Source files + provenance: assets/ui/sounds/ (ObsydianX "Interface SFX
-- Pack 1", CC0). Upload each as an Audio asset and paste its ID here.
SkinAssets.sounds = {
	press = 86214318732742, -- generic button tap
	tab = 137020234333191, -- tab / chip / text-tab change
	open = 136825638209267, -- full panel opens
	close = 104996324201849, -- full panel closes
	back = 113202025743542, -- back / crumb / take off / remove
	confirm = 104754532075322, -- add to basket, wear all
	tryOn = 127245626247954, -- try an item on
	purchase = 117574271567470, -- purchase succeeded
	error = 119476330011065, -- blocked action
	-- Synthesised swipes (tools/build_swipes.py):
	switch = 131203168288426, -- switch Catalogue / Stores / Outfits while the panel is open
	worldIn = 84390395665043, -- World options slides on
	worldOut = 129860135845572, -- World options slides off
} :: { [string]: number }

-- World floor pattern textures (WorldRenderer + the World options thumbnails).
-- White/greyscale on transparent, tinted by the pattern colour.
SkinAssets.floorTextures = {
	Grid = 6372755229, -- Roblox's default baseplate grid
	Studs = 10455712361, -- classic studs, 2×2 per image
	Checker = 92292194903425, -- 2×2 white/transparent checker
	Clouds = 113580888960089, -- assets/world/clouds.png (tools/build_clouds.py)
	Grass = 100227557484882, -- assets/world/grass.png
	Water = 98759281326939, -- assets/world/water.png
} :: { [string]: number }

-- Full skyboxes for the other sky presets (WorldRenderer): the six Sky
-- faces, from Creator Store skies (the store asset in each comment). `bodies`
-- shows the sun, moon and stars (they follow the time of day); `sunSize` /
-- `moonSize` (degrees) and `turn` (SkyboxOrientation Y, degrees) as the store
-- sky set them. `light` is a colour from the sky the avatar is lit with.
export type Skybox = {
	Bk: number,
	Dn: number,
	Ft: number,
	Lf: number,
	Rt: number,
	Up: number,
	bodies: boolean,
	sunSize: number?,
	moonSize: number?,
	turn: number?,
	light: string,
}
SkinAssets.skyboxes = {
	-- 16262385808 Space Sky HD
	Space = { Bk = 16262356578, Dn = 16262358026, Ft = 16262360469, Lf = 16262362003, Rt = 16262363873, Up = 16262366016, bodies = false, light = "#7a62a8" },
	-- 8202961731 Pink sky
	Daydream = { Bk = 271042516, Dn = 271077243, Ft = 271042556, Lf = 271042310, Rt = 271042467, Up = 271077958, bodies = true, light = "#f0a3b3" },
	-- 14559810477 Warped Anime Sky (its sun is a 1 degree speck)
	Breeze = { Bk = 14556558767, Dn = 14556564331, Ft = 14556576655, Lf = 14556567190, Rt = 14556579194, Up = 14556582671, bodies = true, sunSize = 1, light = "#a8e4f4" },
	-- 239322399 Orange Sky
	Ember = { Bk = 150939022, Dn = 150939038, Ft = 150939047, Lf = 150939056, Rt = 150939063, Up = 150939082, bodies = true, light = "#f08a2c" },
	-- 12877202335 Rainbow Sky
	Aura = { Bk = 12877085497, Dn = 12877086914, Ft = 12877085497, Lf = 12877085497, Rt = 12877085497, Up = 12877083856, bodies = false, light = "#b4c8f0" },
	-- 138907351102721 Dune Sky
	Nova = { Bk = 119761561936004, Dn = 112913253029218, Ft = 71766471664507, Lf = 73469705958603, Rt = 130460752130304, Up = 73402351227920, bodies = true, sunSize = 0, moonSize = 0, light = "#e0b878" },
	-- 115260535914035 Rune Forest Sky
	Rune = { Bk = 73287257796967, Dn = 95571517151564, Ft = 93852950520084, Lf = 73675662307776, Rt = 111303043418465, Up = 84372379620971, bodies = true, sunSize = 0, moonSize = 0, turn = 280, light = "#c8a27e" },
	-- 16573629759 Rainbow Skybox
	Prism = { Bk = 16573503947, Dn = 16573505309, Ft = 16573505942, Lf = 16573506632, Rt = 16573507805, Up = 16573508618, bodies = true, light = "#8cc8f4" },
} :: { [string]: Skybox }

-- The colour line along the bottom of each sky chip (World options), left to
-- right: the sky's top down to its horizon, brightened to read on the dark
-- panel. Studio and Void draw their slider's gradient instead (SkyDial).
SkinAssets.skyStrips = {
	Clear = { "#5d9ce6", "#cfe5ff" },
	Clouds = { "#8fb3dd", "#ffffff" },
	Space = { "#8a6fc0", "#5b4f8f" },
	Daydream = { "#e08f9a", "#ffc2c4" },
	Breeze = { "#1fc4ec", "#e8f6fb" },
	Ember = { "#c4581a", "#f5b83a" },
	Aura = { "#efcba0", "#9fd8d8", "#a79ffc" },
	Nova = { "#3d4fa8", "#f2b552", "#3b8ad8" },
	Rune = { "#a8706a", "#a8b07e" },
	Prism = { "#5f8ee6", "#b8eaff" },
} :: { [string]: { string } }

-- The cloudless blue sky under Clear and Clouds (WorldRenderer), from
-- Creator Store 96012904102415 "Clear Blue Sky - No clouds": one image on the
-- four sides, one on top. Its bottom (seen through a see-through floor) is
-- ours, the horizon's colour: assets/world/sky_clear_down.png. (The place's
-- own Sky has clouds painted in.)
SkinAssets.clearSkybox = { side = 13805860897, top = 13500260075, down = 134814657408892 }

-- Flat skybox images for the Studio / Void sky presets (WorldRenderer).
-- 0 = not uploaded (the dense Atmosphere alone tints the sky).
SkinAssets.skyTextures = {
	Studio = 122230543831024, -- assets/world/sky_studio.png
	Void = 105362083220450, -- assets/world/sky_void.png
} :: { [string]: number }

-- "rbxassetid://..." for an icon name, or nil if it has no art yet.
function SkinAssets.iconImage(name: string): string?
	local id = SkinAssets.icons[name]
	if id == nil then
		return nil
	end
	return "rbxassetid://" .. id
end

-- Every icon name with an ID, sorted (for galleries).
function SkinAssets.iconNames(): { string }
	local names = {}
	for name in SkinAssets.icons do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return SkinAssets
