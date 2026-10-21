--!strict

--[[
	LayeringPanel (Catalogue › Clothing › Layering)

	The layered clothing you're wearing, in the order it goes on: first is
	closest to the body, last is the outermost layer (so a jacket after a
	shirt sits over it). Move in / Move out swap an item with the next
	layered item that way (undoable, like any change).

	Props:
		look: the HUD look (worn, moveLayer)
		nav: to open an item's page
		size, position
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local useContentHeight = require(views:WaitForChild("hooks"):WaitForChild("useContentHeight"))
local ShadowText = require(views:WaitForChild("components"):WaitForChild("ShadowText"))
local PillButton = require(views:WaitForChild("components"):WaitForChild("PillButton"))
local Parts = require(script.Parent:WaitForChild("Parts"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))

local e = React.createElement

-- Item types that are layered clothing (AvatarService.isLayered).
local LAYERED = {
	TShirtAccessory = true,
	ShirtAccessory = true,
	SweaterAccessory = true,
	JacketAccessory = true,
	PantsAccessory = true,
	ShortsAccessory = true,
	DressSkirtAccessory = true,
	LeftShoeAccessory = true,
	RightShoeAccessory = true,
	EyebrowAccessory = true,
	EyelashAccessory = true,
	Shoes = true,
}

local function button(label: string, order: number, disabled: boolean, onActivated: () -> ())
	return e(PillButton, {
		variant = "pill",
		size = 32,
		width = 100,
		label = label,
		textStyle = Tokens.type.small,
		disabled = disabled,
		sound = false, -- the change plays its own sound
		layoutOrder = order,
		onActivated = onActivated,
	})
end

local function LayeringPanel(props: { look: any, nav: any, size: UDim2, position: UDim2 })
	local skin = useSkin()
	local layoutRef, contentHeight = useContentHeight()
	local layered = {}
	for _, id in props.look.worn do
		local item = PlaceholderData.item(id)
		if item and LAYERED[item.typeName] then
			table.insert(layered, item)
		end
	end

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { ref = layoutRef, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(6)) }),
		Inset = e("UIPadding", {
			PaddingTop = UDim.new(0, skin.px(3)),
			PaddingLeft = UDim.new(0, skin.px(3)),
			PaddingRight = UDim.new(0, skin.px(8)),
		}),
	}
	for index, item in layered do
		local where = if index == 1 then "closest to the body"
			elseif index == #layered then "outermost"
			else "layer " .. index
		rows["Row" .. index] = e(Parts.ListRow, {
			title = item.name,
			subtitle = index .. " · " .. where .. " · " .. item.sub,
			colour = Parts.swatch(item.colour),
			image = Parts.image(item),
			layoutOrder = index,
			trailingWidth = 230,
			trailing = {
				In = button("Move in", 1, index == 1, function()
					props.look.moveLayer(item.id, -1)
				end),
				Out = button("Move out", 2, index == #layered, function()
					props.look.moveLayer(item.id, 1)
				end),
			},
			onActivated = function()
				props.nav.push({ kind = "item", id = item.id, label = item.name })
			end,
		})
	end

	return e("Frame", {
		Name = "LayeringPanel",
		Position = props.position,
		Size = props.size,
		BackgroundTransparency = 1,
	}, {
		Hint = e(ShadowText, {
			text = if #layered == 0
				then "You're not wearing any layered clothing"
				else "Layered clothing goes on in this order: first is closest to the body",
			style = Tokens.type.meta,
			transparency = Tokens.alpha.textSoft,
			shadow = false,
		}),
		Rows = e("ScrollingFrame", {
			Position = UDim2.fromOffset(0, skin.px(28)),
			Size = UDim2.new(1, 0, 1, -skin.px(28)),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, math.max(contentHeight, #layered * (skin.px(64) + skin.px(6))) + skin.px(6)),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = skin.px(8),
			ScrollBarImageColor3 = Tokens.color.accent,
		}, rows),
	})
end

return LayeringPanel
