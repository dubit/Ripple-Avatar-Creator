--!strict

--[[
	OutfitsScreen (design frame 5d: Outfits root and the outfit page)

	Root: tabs for where the outfits come from, beside a search box whose
	meaning follows the tab:
	  · Current: Your avatar, your own Roblox avatar as it is (restart badge;
	    its Wear button reads "Reset to this"). No search.
	  · Wardrobe (the default): Save what I'm wearing, then the outfits saved
	    here (look.outfits). Search: by name.
	  · Creations: the outfits saved on Roblox itself, outside experiences
	    (RobloxOutfits). Roblox only lists them once you allow it, so until
	    then a "Show my Roblox outfits" card asks. Search: by name.
	  · Friends: your Roblox friends' current avatars. Search: by name.
	  · Roblox: the people you follow here (our own follow, private to you:
	    Roblox gives games no access to its follows), then the players in
	    this server (what they're wearing here). The first card, Add a
	    person, finds someone by exact username or user id (all Roblox lets
	    a game look up), shows who it found, and follows on confirm. Follow /
	    Following is also on a person's page. Search: the people listed.
	  · Community: placeholder outfits until Task 16.
	The outfit you're wearing exactly gets the orange ring. People are cards
	with their avatar picture (UserLooks); Roblox only lets a game read
	another user's current avatar, not their saved outfits, and their page
	shows those items, worn over your own body. Cards show a 2×2 mosaic of item thumbnails, the most telling first:
	bodies, then heads, layered clothing, accessories, classic clothing, and
	animations last.

	Outfit page: on the left the preview (your avatar wearing it, for a saved
	outfit: OutfitPreview), the name (edit a saved one's, then press the orange pencil), Wear all items and
	Delete (press twice). On the right "N items · M selected" with Select
	all / none, a row per item with a checkbox (the row itself opens the item
	page: Outfits › Name › Item), and Wear selected · Add to basket · Buy
	selected (priced for the unowned items selected).

	OutfitsScreen.Root props: nav, look
	OutfitsScreen.Outfit props: nav, look, source, index (a saved outfit's id
	for Mine; the placeholder list position otherwise)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local Sounds = require(views:WaitForChild("Sounds"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useInteraction = require(hooks:WaitForChild("useInteraction"))
local useSessionState = require(hooks:WaitForChild("useSessionState"))
local TextTab = require(components:WaitForChild("TextTab"))
local PillButton = require(components:WaitForChild("PillButton"))
local ConfirmButton = require(components:WaitForChild("ConfirmButton"))
local SearchBox = require(components:WaitForChild("SearchBox"))
local GlassPanel = require(components:WaitForChild("GlassPanel"))
local useBackInput = require(hooks:WaitForChild("useBackInput"))
local ShadowText = require(components:WaitForChild("ShadowText"))
local Icon = require(components:WaitForChild("Icon"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))
local OutfitPreview = require(script.Parent:WaitForChild("OutfitPreview"))
local RobloxOutfits = require(views:WaitForChild("catalogue"):WaitForChild("RobloxOutfits"))
local UserLooks = require(views:WaitForChild("catalogue"):WaitForChild("UserLooks"))
local Badge = require(components:WaitForChild("Badge"))
local Spinner = require(components:WaitForChild("Spinner"))
local HudContext = require(views:WaitForChild("HudContext"))

local AvatarConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AvatarConfig"))
local SkinColours = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("SkinColours"))

local e = React.createElement

local SEARCH_WIDTH = 270
local LEFT_WIDTH = 300

-- An outfit as the screens see it, whichever source it came from.
type OutfitView = {
	kind: "saved" | "own" | "roblox" | "user" | "placeholder",
	id: number?, -- the saved / Roblox outfit's id
	source: string, -- nav source: "Mine" (saved), "Own", "RobloxSaved", "User", or a placeholder tab
	index: number, -- nav index: the id, or the placeholder list position
	name: string,
	by: string,
	items: { number },
	labels: { [number]: string }?, -- row names that differ from the item's own
	skin: any?, -- skin colours that come with it (by body part; SkinColours)
}

-- Card / page order of a type's thumbnail: the most telling first.
local function rank(typeName: string?): number
	local t = typeName or ""
	if t == "BodyParts" or t == "DynamicHeadAvatar" or t == "Torso" or string.match(t, "^%a+Arm$") or string.match(t, "^%a+Leg$") then
		return 1 -- the character
	elseif t == "DynamicHead" or t == "Head" then
		return 2
	elseif t == "Shoes" or (string.match(t, "Accessory$") and (string.find(t, "Shirt") or string.find(t, "Pants") or string.find(t, "Jacket")
		or string.find(t, "Sweater") or string.find(t, "Shorts") or string.find(t, "Dress") or string.find(t, "Shoe"))) then
		return 3 -- layered clothing
	elseif t == "Shirt" or t == "Pants" or t == "TShirt" then
		return 5 -- classic clothing
	elseif string.find(t, "Animation") or t == "Animations" then
		return 6
	elseif string.find(t, "Background") then
		return 7
	end
	return 4 -- accessories, hair, makeup, gear
end

-- Wearing exactly this outfit: the same items, nothing more or less.
local function wearingExactly(look: any, items: { number }): boolean
	if #items == 0 or #items ~= #look.worn then
		return false
	end
	for _, id in items do
		if not look.isWorn(id) then
			return false
		end
	end
	return true
end

local function savedView(outfit: any): OutfitView
	return {
		kind = "saved",
		id = outfit.id,
		source = "Mine",
		index = outfit.id,
		name = outfit.name,
		by = "Your outfit",
		items = outfit.items,
		skin = outfit.skin,
	}
end

local function ownView(look: any): OutfitView
	return { kind = "own", id = nil, source = "Own", index = 0, name = "Your avatar", by = "Your Roblox avatar", items = look.own }
end

local function robloxView(outfit: RobloxOutfits.Outfit): OutfitView
	return {
		kind = "roblox",
		id = outfit.id,
		source = "RobloxSaved",
		index = outfit.id,
		name = outfit.name,
		by = "Saved on Roblox",
		items = outfit.items,
		labels = outfit.labels,
	}
end

local function outfitsFor(look: any, source: string): { OutfitView }
	local list: { OutfitView } = {}
	if source == "Mine" then
		for _, outfit in look.outfits do
			table.insert(list, savedView(outfit))
		end
	else
		for index, outfit in (PlaceholderData.outfits :: any)[source] or {} do
			table.insert(list, { kind = "placeholder", id = nil, source = source, index = index, name = outfit.name, by = outfit.by, items = outfit.items })
		end
	end
	return list
end

local function findOutfit(look: any, source: string, index: number): OutfitView?
	if source == "Mine" then
		for _, outfit in look.outfits do
			if outfit.id == index then
				return savedView(outfit)
			end
		end
		return nil
	elseif source == "Own" then
		return ownView(look)
	elseif source == "RobloxSaved" then
		for _, outfit in RobloxOutfits.outfits() do
			if outfit.id == index then
				return robloxView(outfit)
			end
		end
		return nil
	end
	local outfit = ((PlaceholderData.outfits :: any)[source] or {})[index]
	return if outfit
		then { kind = "placeholder", id = nil, source = source, index = index, name = outfit.name, by = outfit.by, items = outfit.items }
		else nil
end

-- Re-render when the Roblox-saved outfits (or their items) arrive.
local function useRobloxOutfits(active: boolean)
	local _version, setVersion = React.useState(0)
	React.useEffect(function()
		local connection = RobloxOutfits.changed:Connect(function()
			setVersion(function(v: number)
				return v + 1
			end)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	React.useEffect(function()
		if active then
			RobloxOutfits.check()
		end
		return nil
	end, { active })
end

-- Up to four item thumbnails in a 2×2 grid (items with pictures first).
local function mosaic(items: { number }): { [string]: any }
	local ordered = {}
	for index, id in items do
		local item = PlaceholderData.item(id)
		if item then
			table.insert(ordered, { item = item, rank = rank(item.typeName), index = index })
		end
	end
	table.sort(ordered, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.index < b.index
	end)
	local images = {}
	for _, entry in ordered do
		local image = Parts.image(entry.item)
		if image then
			table.insert(images, image)
			if #images == 4 then
				break
			end
		end
	end
	local cells: { [string]: any } = {}
	for index, image in images do
		local column, row = (index - 1) % 2, (index - 1) // 2
		local single = #images == 1
		cells["Cell" .. index] = e("ImageLabel", {
			AnchorPoint = if single then Vector2.new(0.5, 0.5) else Vector2.zero,
			Position = if single then UDim2.fromScale(0.5, 0.5) else UDim2.fromScale(0.04 + column * 0.48, 0.04 + row * 0.48),
			Size = if single then UDim2.fromScale(0.9, 0.9) else UDim2.fromScale(0.44, 0.44),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
		})
	end
	return cells
end

local function OutfitCard(props: {
	outfit: OutfitView,
	sub: string,
	ring: boolean,
	badge: any?, -- top-left marker (your avatar / from Roblox)
	onActivated: () -> (),
	layoutOrder: number,
})
	local skin = useSkin()
	local interaction = useInteraction()
	local first = PlaceholderData.item(props.outfit.items[1])
	local cells = mosaic(props.outfit.items)
	return e("TextButton", {
		Name = "OutfitCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(props.onActivated),
		[React.Event.Activated] = Press.activated(props.onActivated),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Parts.swatch(if first then first.colour else ""),
			radius = 14,
			hovered = interaction.hovered,
			selected = props.ring,
			caption = if next(cells) then nil else "outfit",
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
			Mosaic = e(React.Fragment, nil, cells),
			Badge = if props.badge
				then e("Frame", {
					Position = UDim2.fromOffset(skin.px(8), skin.px(8)),
					Size = UDim2.fromOffset(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					ZIndex = 2,
				}, { Badge = props.badge })
				else nil,
		}),
		Meta = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, skin.px(36)),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(2)) }),
			Name = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(13.5) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.outfit.name,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			}),
			Sub = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(12) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.sub,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(700),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
		}),
	})
end

-- A dashed orange action card in the grid: save what you're wearing, or
-- show your Roblox outfits.
local function ActionCard(props: {
	icon: string,
	label: string, -- inside the card
	title: string, -- under it, like an outfit's name
	sub: string,
	onActivated: () -> (),
	layoutOrder: number,
})
	local skin = useSkin()
	local interaction = useInteraction()
	local orange = Tokens.color.accentText
	return e("TextButton", {
		Name = "ActionCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(props.onActivated),
		[React.Event.Activated] = Press.activated(props.onActivated),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Well = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Tokens.color.accent,
			BackgroundTransparency = if interaction.hovered then 0.86 else 0.94,
			BorderSizePixel = 0,
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
			Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
			Stroke = e("UIStroke", {
				Color = orange,
				Transparency = 0.3,
				Thickness = skin.stroke(1.5),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			Layout = e("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(4)),
			}),
			Icon = e(Icon, { name = props.icon, size = 36, color = orange, layoutOrder = 1 }),
			Label = e("TextLabel", {
				Size = UDim2.new(1, -skin.px(12), 0, skin.textPx(13) * 2 + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.label,
				TextColor3 = orange,
				TextSize = skin.textPx(13),
				FontFace = Tokens.font(900),
				TextWrapped = true,
				LayoutOrder = 2,
			}),
		}),
		Meta = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, skin.px(36)),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(2)) }),
			Name = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(13.5) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.title,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 1,
			}),
			Sub = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(12) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.sub,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(700),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
			}),
		}),
	})
end

local SEARCH_DELAY = 0.6 -- seconds after typing stops before a username lookup

-- The tabs: where the outfits come from. Each sets what the search box does.
local SOURCES = {
	{ id = "Current", label = "Current", search = nil }, -- just your own avatar: no search
	{ id = "Wardrobe", label = "Wardrobe", search = "Search my outfits" },
	{ id = "Creations", label = "Creations", search = "Search my creations" },
	{ id = "Friends", label = "Friends", search = "Search friends" },
	{ id = "Roblox", label = "Roblox", search = "Search people you follow" },
	{ id = "Community", label = "Community", search = "Search community outfits" },
} :: { { id: string, label: string, search: string? } }
local SOURCE_IDS: { [string]: boolean } = {}
for _, entry in SOURCES do
	SOURCE_IDS[entry.id] = true
end

local ERRORS = {
	notfound = "No one has that username or id",
	busy = "Too many lookups. Try again in a moment",
	failed = "Couldn't reach Roblox. Try again",
}

-- A person on the Roblox tab: their avatar picture, name, and where they're from.
local function PersonCard(props: { user: UserLooks.User, sub: string, onActivated: () -> (), layoutOrder: number })
	local skin = useSkin()
	local interaction = useInteraction()
	return e("TextButton", {
		Name = "PersonCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(props.onActivated),
		[React.Event.Activated] = Press.activated(props.onActivated),
		[React.Event.MouseEnter] = interaction.onEnter,
		[React.Event.MouseLeave] = interaction.onLeave,
	}, {
		Thumb = e(Parts.Thumb, {
			colour = Parts.swatch(""),
			radius = 14,
			hovered = interaction.hovered,
			image = "rbxthumb://type=Avatar&id=" .. props.user.userId .. "&w=150&h=150",
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
		}),
		Meta = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, skin.px(36)),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(2)) }),
			Name = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(13.5) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.user.displayName,
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(13.5),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 1,
			}),
			Sub = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.textPx(12) + skin.px(2)),
				BackgroundTransparency = 1,
				Text = props.sub,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(700),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = 2,
			}),
		}),
	})
end

-- A full-width line in the grid's place (search messages).
local function GridMessage(props: { text: string })
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
	}, {
		Text = e(ShadowText, {
			text = props.text,
			style = Tokens.type.cardTitle,
			transparency = Tokens.alpha.textDim,
			shadow = false,
		}),
	})
end

-- The username search: the user found for `query` (after a pause in typing).
local function useUserSearch(query: string, active: boolean): (UserLooks.User?, string?, boolean)
	local result, setResult = React.useState(nil :: { query: string, user: UserLooks.User?, error: string? }?)
	local name = string.match(query, "^%s*@?(.-)%s*$") or ""
	local long = #name >= 3 or (#name > 0 and string.match(name, "^%d+$") ~= nil) -- a name, or any user id
	React.useEffect(function()
		if not active or not long then
			return nil
		end
		local alive = true
		local thread = task.delay(SEARCH_DELAY, function()
			local user, err = UserLooks.find(name)
			if alive then
				setResult({ query = name, user = user, error = err })
			end
		end)
		return function()
			alive = false
			task.cancel(thread)
		end
	end, { name, active } :: { any })
	if not active or not long then
		return nil, nil, false
	end
	if not result or result.query ~= name then
		return nil, nil, true -- still looking
	end
	return result.user, result.error, false
end

-- Re-render when names / friends arrive, and players come and go.
local function usePeople(active: boolean)
	local _version, setVersion = React.useState(0)
	React.useEffect(function()
		if not active then
			return nil
		end
		local function bump()
			setVersion(function(v: number)
				return v + 1
			end)
		end
		local connections = {
			UserLooks.changed:Connect(bump),
			game:GetService("Players").PlayerAdded:Connect(bump),
			game:GetService("Players").PlayerRemoving:Connect(function()
				task.defer(bump)
			end),
		}
		return function()
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end, { active })
end

-- Another user's look, loaded for their outfit page.
local function useUserLook(userId: number?): (UserLooks.Look?, string?)
	local state, setState = React.useState(nil :: { userId: number, look: UserLooks.Look?, error: string? }?)
	React.useEffect(function()
		if not userId then
			return nil
		end
		local alive = true
		task.spawn(function()
			local look, err = UserLooks.look(userId)
			if alive then
				setState({ userId = userId, look = look, error = err })
			end
		end)
		return function()
			alive = false
		end
	end, { userId })
	if not userId or not state or state.userId ~= userId then
		return nil, nil
	end
	return state.look, state.error
end

local function userView(look: UserLooks.Look): OutfitView
	return {
		kind = "user",
		id = look.userId,
		source = "User",
		index = look.userId,
		name = look.displayName,
		by = "@" .. look.username .. (if look.inServer then " · wearing here" else " · Roblox avatar"),
		items = look.items,
		skin = look.skin,
	}
end

-- Over the Roblox grid: find someone by username or user id, see who it
-- is, then confirm with Follow. Back or the close button shuts it.
local function AddPersonPanel(props: { look: any, onClose: () -> (), onOpen: (user: UserLooks.User) -> () })
	local skin = useSkin()
	local query, setQuery = React.useState("")
	local user, err, searching = useUserSearch(query, true)
	useBackInput(function()
		props.onClose()
		return true
	end)
	local name = string.match(query, "^%s*@?(.-)%s*$") or ""
	local status = if name == "" then "Type someone's exact username, or their user id"
		elseif searching then "Looking…"
		elseif err then ERRORS[err] or ERRORS.failed
		elseif not user and #name < 3 and not string.match(name, "^%d+$") then "Usernames are at least 3 characters"
		else nil
	local isSelf = user ~= nil and user.userId == game:GetService("Players").LocalPlayer.UserId
	local following = user ~= nil and props.look.isFollowing(user.userId)
	local picture = skin.px(220)

	local result = if user and not searching
		then e("Frame", {
			Position = UDim2.fromOffset(0, skin.px(110)),
			Size = UDim2.new(1, 0, 0, picture),
			BackgroundTransparency = 1,
		}, {
			Picture = e(Parts.Thumb, {
				colour = Parts.swatch(""),
				radius = 18,
				image = "rbxthumb://type=Avatar&id=" .. user.userId .. "&w=420&h=420",
				size = UDim2.fromOffset(picture, picture),
			}),
			Info = e("Frame", {
				Position = UDim2.fromOffset(picture + skin.px(20), 0),
				Size = UDim2.new(1, -(picture + skin.px(20)), 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(8)) }),
				Name = e(ShadowText, { text = user.displayName, style = { size = 24, weight = 900 }, layoutOrder = 1 }),
				Handle = e(ShadowText, {
					text = "@" .. user.username .. " · user " .. user.userId,
					style = Tokens.type.meta,
					transparency = Tokens.alpha.textSoft,
					shadow = false,
					layoutOrder = 2,
				}),
				Gap = e("Frame", { Size = UDim2.new(1, 0, 0, skin.px(8)), BackgroundTransparency = 1, LayoutOrder = 3 }),
				Follow = if isSelf
					then e(ShadowText, { text = "That's you!", style = Tokens.type.cardTitle, layoutOrder = 4 })
					else e(PillButton, {
						variant = "pill",
						size = Tokens.size.ctaHeight,
						width = 220,
						icon = if following then "check" else "person_add",
						iconSize = 18,
						label = if following then "Already following" else "Follow",
						active = not following,
						disabled = following,
						sound = false, -- following plays its own sound
						layoutOrder = 4,
						onActivated = function()
							props.look.toggleFollow(user.userId)
							props.onClose()
						end,
					}),
				Open = if isSelf then nil else e(PillButton, {
					variant = "pill",
					size = Tokens.size.ctaHeight,
					width = 220,
					icon = "checkroom",
					iconSize = 18,
					label = "See their avatar",
					layoutOrder = 5,
					onActivated = function()
						props.onOpen(user)
					end,
				}),
			}),
		})
		else nil

	return e(GlassPanel, {
		variant = "bar",
		cornerRadius = 18,
		shadow = true,
		position = UDim2.fromOffset(0, skin.px(Tokens.size.textTabHeight) + skin.px(14)),
		size = UDim2.new(1, 0, 1, -(skin.px(Tokens.size.textTabHeight) + skin.px(14))),
		zIndex = 5,
	}, {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(16)),
			PaddingBottom = UDim.new(0, skin.px(16)),
			PaddingLeft = UDim.new(0, skin.px(18)),
			PaddingRight = UDim.new(0, skin.px(14)),
		}),
		Title = e(ShadowText, { text = "Add a person", style = Tokens.type.cardTitle }),
		Close = e(PillButton, {
			variant = "round",
			size = Tokens.size.small.size,
			icon = "close",
			iconSize = Tokens.size.small.icon,
			glowRadius = 0,
			sound = "back",
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.fromScale(1, 0),
			onActivated = props.onClose,
		}),
		Search = e(SearchBox, {
			text = query,
			placeholder = "Username or user id",
			onChange = setQuery,
			position = UDim2.fromOffset(0, skin.px(44)),
			size = UDim2.fromOffset(skin.px(SEARCH_WIDTH + 60), skin.px(40)),
		}),
		Status = if status
			then e("Frame", {
				Position = UDim2.fromOffset(0, skin.px(110)),
				Size = UDim2.new(1, 0, 0, skin.px(30)),
				BackgroundTransparency = 1,
			}, {
				Text = e(ShadowText, { text = status, style = Tokens.type.cardTitle, transparency = Tokens.alpha.textDim, shadow = false }),
			})
			else nil,
		Result = result,
	})
end

local function OutfitsScreen(props: { nav: any, look: any })
	local skin = useSkin()
	local look = props.look
	local storedSource, setSource = useSessionState("outfits.source", "Wardrobe")
	local source = if SOURCE_IDS[storedSource] then storedSource else "Wardrobe"
	local query, setQuery = useSessionState("outfits.query", "")
	local searchHint: string? = nil
	local adding, setAdding = React.useState(false) -- the Add a person panel (Roblox tab)

	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(22)),
		}),
	}
	for index, entry in SOURCES do
		if entry.id == source then
			searchHint = entry.search
		end
		tabs["Tab" .. index] = e(TextTab, {
			label = entry.label,
			active = entry.id == source,
			layoutOrder = index,
			onActivated = function()
				if entry.id ~= source then
					setQuery("") -- each tab's search means something different
					setAdding(false)
				end
				setSource(entry.id)
			end,
		})
	end

	useRobloxOutfits(source == "Creations")
	usePeople(source == "Friends" or source == "Roblox")
	-- Current shows your Roblox avatar as it is now (it may have changed
	-- since you joined).
	React.useEffect(function()
		if source == "Current" then
			look.refreshOwn()
		end
		return nil
	end, { source })
	local needle = string.lower(query)
	local function matches(name: string): boolean
		return needle == "" or string.find(string.lower(name), needle, 1, true) ~= nil
	end
	local cards: { [string]: any } = {}
	local count = 0
	local function addOutfit(outfit: OutfitView, sub: string, badge: any?)
		if not matches(outfit.name) then
			return
		end
		count += 1
		cards["Outfit" .. count] = e(OutfitCard, {
			outfit = outfit,
			sub = sub,
			ring = wearingExactly(look, outfit.items),
			badge = badge,
			layoutOrder = count,
			onActivated = function()
				Sounds.play("press")
				props.nav.push({
					kind = "outfit",
					id = { source = outfit.source, index = outfit.index },
					label = outfit.name,
				})
			end,
		})
	end
	local function addAction(key: string, card: { [string]: any })
		count += 1
		card.layoutOrder = count
		cards[key] = e(ActionCard, card :: any)
	end

	local seen: { [number]: boolean } = { [game:GetService("Players").LocalPlayer.UserId] = true }
	local function addPerson(user: UserLooks.User?, sub: string)
		if not user or seen[user.userId] then
			return
		end
		seen[user.userId] = true
		count += 1
		cards["Person" .. count] = e(PersonCard, {
			user = user,
			sub = sub,
			layoutOrder = count,
			onActivated = function()
				Sounds.play("press")
				props.nav.push({
					kind = "outfit",
					id = { source = "User", index = user.userId },
					label = user.displayName,
				})
			end,
		})
	end

	if source == "Current" then
		-- Your own Roblox avatar as it is: wearing it is a reset.
		if #look.own > 0 then
			addOutfit(ownView(look), "Reset to your avatar", e(Badge, { kind = "marker", tone = "white", icon = "restart_alt" }))
		end
	elseif source == "Wardrobe" then
		if needle == "" then
			addAction("Save", {
				icon = "add_circle",
				label = "Save what I'm wearing",
				title = "New outfit",
				sub = #look.worn .. " items",
				onActivated = look.saveOutfit,
			})
		end
		for _, outfit in outfitsFor(look, "Mine") do
			addOutfit(outfit, #outfit.items .. " items")
		end
	elseif source == "Creations" then
		-- Outfits saved on Roblox itself (once Roblox lets us see them).
		local status = RobloxOutfits.status()
		if status == "ready" then
			for _, outfit in RobloxOutfits.outfits() do
				addOutfit(robloxView(outfit), #outfit.items .. " items · saved on Roblox")
			end
		elseif status == "loading" or status == "unknown" then
			count += 1
			cards.RobloxLoading = e(Parts.LoadingCard, { layoutOrder = count })
		elseif (status == "locked" or status == "denied") and needle == "" then
			addAction("Roblox", {
				icon = "lock",
				label = "Show my Roblox outfits",
				title = "Outfits on Roblox",
				sub = if status == "denied" then "Roblox needs your OK" else "Saved outside this game",
				onActivated = function()
					Sounds.play("press")
					RobloxOutfits.request()
				end,
			})
		end
	elseif source == "Friends" then
		for _, user in UserLooks.friends() do
			if matches(user.displayName) or matches(user.username) then
				addPerson(user, "@" .. user.username)
			end
		end
	elseif source == "Roblox" then
		-- People you follow here; the first card adds someone.
		if needle == "" then
			addAction("AddPerson", {
				icon = "person_add",
				label = "Add a person",
				title = "Follow someone",
				sub = "By username or id",
				onActivated = function()
					Sounds.play("press")
					setAdding(true)
				end,
			})
		end
		UserLooks.prefetch(look.following)
		for _, userId in look.following do
			local user = UserLooks.known(userId)
			if user and (matches(user.displayName) or matches(user.username)) then
				addPerson(user, "@" .. user.username)
			end
		end
		-- Then whoever's in this server, to follow someone you've just seen.
		for _, player in game:GetService("Players"):GetPlayers() do
			local user = { userId = player.UserId, username = player.Name, displayName = player.DisplayName }
			if matches(user.displayName) or matches(user.username) then
				addPerson(user, "In this server")
			end
		end
	else
		for _, outfit in outfitsFor(look, source) do
			addOutfit(outfit, outfit.by)
		end
	end
	local message: string? = nil
	if source == "Roblox" and needle ~= "" and count == 0 then
		message = "Nobody you follow has that name"
	elseif source == "Friends" and count == 0 then
		message = if needle ~= "" then "No friends with that name" else "Your friends will show here"
	elseif source == "Creations" and count == 0 and RobloxOutfits.status() == "ready" then
		message = "You haven't saved any outfits on Roblox"
	end

	local tabsHeight = skin.px(Tokens.size.textTabHeight)
	local searchWidth = skin.px(SEARCH_WIDTH)
	return e("Frame", {
		Name = "OutfitsScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Top = e("Frame", {
			Size = UDim2.new(1, 0, 0, tabsHeight),
			BackgroundTransparency = 1,
		}, {
			Tabs = e("Frame", {
				Size = UDim2.new(1, -(searchWidth + skin.px(16)), 1, 0),
				BackgroundTransparency = 1,
			}, tabs),
			Rule = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, -(searchWidth + skin.px(16)), 0, skin.stroke(1)),
				BackgroundColor3 = Tokens.color.white,
				BackgroundTransparency = 0.9,
				BorderSizePixel = 0,
			}),
			Search = if searchHint == nil then nil else e(SearchBox, {
				text = query,
				placeholder = searchHint,
				onChange = setQuery,
				anchorPoint = Vector2.new(1, 0.5),
				position = UDim2.fromScale(1, 0.5),
				size = UDim2.fromOffset(searchWidth, skin.px(40)),
			}),
		}),
		AddPerson = if adding and source == "Roblox"
			then e(AddPersonPanel, {
				look = look,
				onClose = function()
					setAdding(false)
				end,
				onOpen = function(user: UserLooks.User)
					setAdding(false)
					props.nav.push({ kind = "outfit", id = { source = "User", index = user.userId }, label = user.displayName })
				end,
			})
			else nil,
		Grid = if adding and source == "Roblox" then nil else e(Parts.CardGrid, {
			columns = 5,
			extraHeight = 40,
			count = count,
			position = UDim2.fromOffset(0, tabsHeight + skin.px(14)),
			size = UDim2.new(1, 0, 1, -(tabsHeight + skin.px(14))),
			scrollKey = "outfits|" .. source .. "|" .. query,
		}, cards),
		Message = if message
			then e("Frame", {
				Position = UDim2.fromOffset(0, tabsHeight + skin.px(14) + (if count > 0 then skin.px(260) else 0)),
				Size = UDim2.new(1, 0, 0, skin.px(40)),
				BackgroundTransparency = 1,
			}, { Text = e(GridMessage, { text = message }) })
			else nil,
	})
end

-- A row's checkbox: orange with a tick when selected.
local function Checkbox(props: { on: boolean, onToggle: () -> () })
	local skin = useSkin()
	local function toggle()
		Sounds.play("press")
		props.onToggle()
	end
	return e("TextButton", {
		Name = "Checkbox",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(skin.px(28), skin.px(28)),
		BackgroundColor3 = if props.on then Tokens.color.accent else Color3.fromHex("#111111"),
		AutoButtonColor = false,
		Text = "",
		[React.Event.InputBegan] = Press.began(toggle),
		[React.Event.Activated] = Press.activated(toggle),
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(8)) }),
		Stroke = e("UIStroke", { Color = Tokens.color.black, Thickness = skin.stroke(1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Tick = if props.on
			then e(Icon, {
				name = "check",
				size = 19,
				anchorPoint = Vector2.new(0.5, 0.5),
				position = UDim2.fromScale(0.5, 0.5),
			})
			else nil,
	})
end

-- The outfit's name. A saved outfit's can be edited in place: once the text
-- differs from the saved name the pencil turns orange, and pressing it (or
-- Enter) saves the new name, after which it goes back to black. Pressing
-- the black pencil puts the cursor in the name.
local function NameField(props: { name: string, editable: boolean, onRename: (name: string) -> () })
	local skin = useSkin()
	local style = { size = 24, weight = 900 }
	local draft, setDraft = React.useState(props.name)
	local boxRef = React.useRef(nil :: TextBox?)
	-- A new saved name (ours arriving, or a rename elsewhere) replaces the draft.
	React.useEffect(function()
		setDraft(props.name)
		return nil
	end, { props.name })
	if not props.editable then
		return e(ShadowText, { text = props.name, style = style, maxWidth = skin.px(LEFT_WIDTH), layoutOrder = 2 })
	end
	local changed = draft ~= props.name and string.match(draft, "%S") ~= nil
	local function save()
		if changed then
			props.onRename(draft)
		end
	end
	local pencil = skin.px(Tokens.size.small.size)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, math.max(skin.textPx(24) + skin.px(6), pencil)),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, {
		Box = e("TextBox", {
			Size = UDim2.new(1, -(pencil + skin.px(8)), 1, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			Text = draft,
			TextColor3 = Tokens.color.white,
			TextSize = skin.textPx(24),
			FontFace = Tokens.font(900),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ref = boxRef,
			[React.Change.Text] = function(box: TextBox)
				-- Names are capped (the server caps them too).
				local text = box.Text
				if (utf8.len(text) or 0) > AvatarConfig.outfits.nameLength then
					text = string.sub(text, 1, (utf8.offset(text, AvatarConfig.outfits.nameLength + 1) or (#text + 1)) - 1)
					box.Text = text
				end
				setDraft(text)
			end,
			[React.Event.FocusLost] = function(_box: TextBox, enterPressed: boolean)
				if enterPressed then
					save()
				end
			end,
		}),
		Pencil = e(PillButton, {
			variant = "round",
			size = Tokens.size.small.size,
			icon = "edit",
			iconSize = Tokens.size.small.icon,
			glowRadius = 0,
			active = changed,
			sound = if changed then "confirm" else nil,
			anchorPoint = Vector2.new(1, 0.5),
			position = UDim2.fromScale(1, 0.5),
			onActivated = function()
				if changed then
					save()
				elseif boxRef.current then
					boxRef.current:CaptureFocus()
				end
			end,
		}),
	})
end

local function smallIcon(name: string, color: Color3, order: number)
	return e(Icon, { name = name, size = 20, color = color, layoutOrder = order })
end

local function OutfitScreen(props: { nav: any, look: any, source: string, index: number })
	local skin = useSkin()
	local hud = React.useContext(HudContext)
	local look = props.look
	useRobloxOutfits(props.source == "RobloxSaved")
	local userLook, userError = useUserLook(if props.source == "User" then props.index else nil)
	local outfit = if props.source == "User"
		then (if userLook then userView(userLook) else nil)
		else findOutfit(look, props.source, props.index)
	-- Selected rows by position; everything starts selected (the skin tone
	-- row too).
	local deselected, setDeselected = React.useState({} :: { [number]: boolean })
	local skinOff, setSkinOff = React.useState(false)

	-- Find out what's owned, for prices and the Buy label.
	React.useEffect(function()
		if outfit then
			look.checkOwned(outfit.items)
		end
		return nil
	end, { props.source, props.index, userLook ~= nil } :: { any })

	-- Keep the breadcrumb in step with a rename.
	React.useEffect(function()
		local top = props.nav.top
		if outfit and top and top.kind == "outfit" and top.label ~= outfit.name then
			props.nav.replaceTop({ kind = top.kind, id = top.id, label = outfit.name })
		end
		return nil
	end, { outfit and outfit.name })

	if not outfit then
		-- Another user's look still loading (or unavailable); a deleted outfit
		-- shows nothing (the Delete handler goes back).
		local note = if props.source ~= "User" then nil
			elseif userError then (if userError == "busy" then ERRORS.busy else "This avatar isn't available")
			else nil
		return e("Frame", { Name = "OutfitScreen", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Spinner = if props.source == "User" and not note
				then e(Spinner, { size = 40, anchorPoint = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.4) })
				else nil,
			Note = if note then e(GridMessage, { text = note }) else nil,
		})
	end

	local items = outfit.items
	local selected: { number } = {} -- positions
	local selectedIds: { number } = {}
	local cost = 0
	local unownedSelected = 0
	for index, id in items do
		if not deselected[index] then
			table.insert(selected, index)
			table.insert(selectedIds, id)
			local item = PlaceholderData.item(id)
			if item and not item.owned then
				cost += item.price
				unownedSelected += 1
			end
		end
	end
	local colours = SkinColours.normalise(outfit.skin)
	local skinTone = if SkinColours.isEmpty(colours) then nil else colours
	local skinOn = skinTone ~= nil and not skinOff
	local allSelected = #selected == #items and (skinTone == nil or skinOn)
	local ring = wearingExactly(look, items)

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(6)) }),
		-- Inset so row strokes at the edges aren't clipped by the ScrollingFrame.
		Inset = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(3)),
			PaddingBottom = UDim.new(0, skin.px(3)),
			PaddingLeft = UDim.new(0, skin.px(3)),
			PaddingRight = UDim.new(0, skin.px(8)),
		}),
	}
	-- The skin tone, as a row like the items (ticked to come along).
	if skinTone then
		local set = SkinColours.count(skinTone)
		local first = skinTone.Head or skinTone.Torso or (next(skinTone) and skinTone[next(skinTone)])
		local whose = if outfit.kind == "saved" then "Saved with this outfit" else "Their skin tone"
		rows.Skin = e(Parts.ListRow, {
			title = "Skin tone",
			subtitle = whose .. " · " .. (if set == #SkinColours.PARTS then "every part" else set .. " of 6 parts"),
			colour = Color3.fromHex(first or "#2a2a2a"),
			flat = true,
			layoutOrder = 0,
			trailingWidth = 40,
			leading = e(Checkbox, {
				on = skinOn,
				onToggle = function()
					setSkinOff(skinOn)
				end,
			}),
			trailing = {
				Wearing = if SkinColours.equal(look.skin, skinTone) then smallIcon("checkroom", Tokens.color.accentText, 1) else nil,
			},
			-- Opens the colours part by part, as an item row opens the item.
			onActivated = function()
				props.nav.push({
					kind = "skin",
					id = { colours = skinTone, from = whose .. " · " .. outfit.name },
					label = "Skin tone",
				})
			end,
		})
	end
	for index, id in items do
		local item = PlaceholderData.item(id)
		if not item then
			continue
		end
		local on = not deselected[index]
		rows["Row" .. index] = e(Parts.ListRow, {
			title = (outfit.labels and outfit.labels[id]) or item.name,
			subtitle = item.main .. " · " .. item.sub,
			colour = Parts.swatch(item.colour),
			image = Parts.image(item),
			layoutOrder = index,
			trailingWidth = 150,
			leading = e(Checkbox, {
				on = on,
				onToggle = function()
					setDeselected(function(current: { [number]: boolean })
						local result = table.clone(current)
						result[index] = if on then true else nil
						return result
					end)
				end,
			}),
			trailing = {
				Price = e(Parts.PriceTag, { item = item, size = 14, layoutOrder = 1 }),
				Wearing = if look.isWorn(id) then smallIcon("checkroom", Tokens.color.accentText, 2) else nil,
				InBasket = if look.inBasket(id) then smallIcon("shopping_basket", Tokens.color.white, 3) else nil,
			},
			onActivated = function()
				props.nav.push({ kind = "item", id = id, label = item.name })
			end,
		})
	end

	local function bottomButton(label: string, icon: string, order: number, disabled: boolean, onActivated: () -> (), extra: { [string]: any }?)
		local button = {
			variant = "pill",
			size = Tokens.size.ctaHeight,
			label = label,
			icon = icon,
			iconSize = 18,
			disabled = disabled,
			sound = false, -- each action plays its own sound
			onActivated = onActivated,
		}
		for key, value in extra or {} do
			(button :: any)[key] = value
		end
		return e("Frame", {
			Size = UDim2.new(1 / 3, -skin.px(6), 1, 0),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, { Button = e(PillButton, button :: any) })
	end

	local saved = outfit.kind == "saved"
	local outfitId = outfit.id
	local kind = outfit.kind
	local leftWidth = skin.px(LEFT_WIDTH)
	local buttonsHeight = skin.px(Tokens.size.ctaHeight)
	local headerHeight = skin.px(26)

	return e("Frame", {
		Name = "OutfitScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Left = e("Frame", {
			Size = UDim2.new(0, leftWidth, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(10)),
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
			}),
			Preview = e("Frame", {
				-- Whatever height the details below leave.
				Size = UDim2.new(1, 0, 1, -(skin.textPx(24) + skin.px(6) + skin.px(18) + buttonsHeight * (if saved or kind == "user" then 2 else 1) + skin.px(10) * (if saved or kind == "user" then 4 else 3))),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				View = if kind ~= "placeholder"
					then e(OutfitPreview, { kind = kind, outfitId = outfitId, ring = ring })
					else e(Parts.Thumb, {
						colour = Parts.swatch(""),
						radius = 20,
						caption = if next(mosaic(items)) then nil else "outfit preview",
						selected = ring,
					}, mosaic(items)),
			}),
			Name = e(NameField, {
				name = outfit.name,
				editable = saved,
				onRename = function(name: string)
					if outfitId then
						look.renameOutfit(outfitId, name)
					end
				end,
			}),
			By = e("Frame", {
				Size = UDim2.new(1, 0, 0, skin.px(18)),
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, {
				Text = e(ShadowText, {
					text = outfit.by .. " · " .. #items .. " items",
					style = Tokens.type.meta,
					transparency = Tokens.alpha.textSoft,
					shadow = false,
				}),
			}),
			WearAll = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				icon = if kind == "own" then "restart_alt" else "checkroom",
				iconSize = 18,
				label = if kind == "own" then "Reset to this" else "Wear all items",
				active = true,
				disabled = kind ~= "own" and #items == 0,
				sound = false, -- the look change plays its own sound
				layoutOrder = 4,
				onActivated = function()
					if kind == "own" then
						look.reset()
					elseif kind == "roblox" and outfitId then
						look.wearRobloxOutfit(outfitId)
					elseif kind == "user" and outfitId then
						look.wearUserLook(outfitId)
					elseif kind == "saved" and outfitId then
						look.wearOutfit(outfitId)
					else
						look.wearAll(items)
					end
				end,
			}),
			-- Follow at once; unfollow takes a second press.
			Follow = if kind == "user" and outfitId and look.isFollowing(outfitId)
				then e(ConfirmButton, {
					label = "Following",
					icon = "check",
					armedLabel = "Tap again to unfollow",
					layoutOrder = 5,
					onConfirm = function()
						look.toggleFollow(outfitId)
					end,
				})
				elseif kind == "user" and outfitId then e(PillButton, {
					variant = "pill",
					size = Tokens.size.ctaHeight,
					icon = "person_add",
					iconSize = 18,
					label = "Follow",
					sound = false, -- following plays its own sound
					layoutOrder = 5,
					onActivated = function()
						look.toggleFollow(outfitId)
					end,
				})
				else nil,
			Delete = if saved
				then e(ConfirmButton, {
					label = "Delete outfit",
					icon = "delete",
					armedLabel = "Tap again to delete",
					layoutOrder = 5,
					onConfirm = function()
						if outfitId then
							look.deleteOutfit(outfitId)
							props.nav.back()
						end
					end,
				})
				else nil,
		}),
		Right = e("Frame", {
			Position = UDim2.fromOffset(leftWidth + skin.px(20), 0),
			Size = UDim2.new(1, -(leftWidth + skin.px(20)), 1, 0),
			BackgroundTransparency = 1,
		}, {
			Header = e("Frame", {
				Size = UDim2.new(1, 0, 0, headerHeight),
				BackgroundTransparency = 1,
			}, {
				Count = e(ShadowText, {
					text = #items .. " items · " .. (#selected + (if skinOn then 1 else 0)) .. " selected",
					style = { size = 17, weight = 900 },
				}),
				Toggle = if #items == 0 and not skinTone then nil else e("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.new(0, skin.px(110), 1, 0),
					BackgroundTransparency = 1,
					Text = if allSelected then "Select none" else "Select all",
					TextColor3 = Tokens.color.accentText,
					TextSize = skin.textPx(13.5),
					FontFace = Tokens.font(800),
					TextXAlignment = Enum.TextXAlignment.Right,
					[React.Event.InputBegan] = Press.began(function()
						Sounds.play("press")
						if allSelected then
							local none = {}
							for index in items do
								none[index] = true
							end
							setDeselected(none)
							setSkinOff(true)
						else
							setDeselected({})
							setSkinOff(false)
						end
					end),
				}),
			}),
			Rows = e("ScrollingFrame", {
				Position = UDim2.fromOffset(0, headerHeight + skin.px(10)),
				Size = UDim2.new(1, 0, 1, -(headerHeight + skin.px(10) + buttonsHeight + skin.px(10))),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromOffset(0, (#items + (if skinTone then 1 else 0)) * (skin.px(64) + skin.px(6)) + skin.px(6)),
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = skin.px(8),
				ScrollBarImageColor3 = Tokens.color.accent,
				VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			}, rows),
			Buttons = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, buttonsHeight),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, skin.px(8)),
				}),
				WearSelected = bottomButton("Wear selected", "checkroom", 1, #selected == 0 and not skinOn, function()
					if saved and outfitId then
						look.wearOutfitItems(outfitId, selected, skinOn)
					else
						look.wearAll(selectedIds, if skinOn then skinTone else nil)
					end
				end),
				-- Basket and Buy only when something selected isn't owned yet.
				Basket = bottomButton("Add to basket", "add_shopping_cart", 2, unownedSelected == 0, function()
					local unowned = {}
					for _, id in selectedIds do
						local item = PlaceholderData.item(id)
						if item and not item.owned then
							table.insert(unowned, id)
						end
					end
					look.addToBasket(unowned)
				end),
				Buy = bottomButton(
					if cost > 0 then "Buy · " .. Tokens.robux(cost) else "Buy",
					"toll",
					3,
					unownedSelected == 0,
					function()
						hud.buy(selectedIds, "outfit")
					end,
					{ loading = hud.buying("outfit") }
				),
			}),
		}),
	})
end

return {
	Root = OutfitsScreen,
	Outfit = OutfitScreen,
}
