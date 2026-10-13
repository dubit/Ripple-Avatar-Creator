--!strict

--[[
	ScalePanel (Catalogue › Scale)

	Roblox's avatar Scale: Height, Width, Head, Body type and Proportions,
	each a slider within Roblox's limits (BodyScale), starting at what you're
	wearing (your own avatar's value where you haven't chosen one). A change
	goes on when you let go of the slider (undoable; outfits save it).
	"Your own" clears every choice.

	Props:
		look: the HUD look (scale, ownScale, setScale)
		size, position
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local BodyScale = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("BodyScale"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local ShadowText = require(views:WaitForChild("components"):WaitForChild("ShadowText"))
local PillButton = require(views:WaitForChild("components"):WaitForChild("PillButton"))
local Slider = require(views:WaitForChild("components"):WaitForChild("Slider"))

local e = React.createElement

local WIDTH = 520 -- design px: the sliders' column

local function ScalePanel(props: { look: any, size: UDim2, position: UDim2 })
	local skin = useSkin()
	local chosen = BodyScale.normalise(props.look.scale)
	local own = BodyScale.normalise(props.look.ownScale)
	-- Slider positions while dragging (sent on release).
	local dragging, setDragging = React.useState({} :: BodyScale.Scale)
	-- Your Roblox avatar may have changed since you joined.
	React.useEffect(function()
		props.look.refreshOwn()
		return nil
	end, {})

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(14)) }),
		Padding = e("UIPadding", { PaddingTop = UDim.new(0, skin.px(14)) }),
	}
	for index, key in BodyScale.KEYS do
		local info = BodyScale.info[key]
		local value = dragging[key] or chosen[key] or own[key] or info.default
		rows[key] = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(56)),
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, {
			Label = e(ShadowText, {
				text = info.label .. "  " .. math.floor(value * 100 + 0.5) .. "%" .. (if chosen[key] or dragging[key] then "" else "  (your own)"),
				style = Tokens.type.meta,
				transparency = Tokens.alpha.textSoft,
				shadow = false,
			}),
			Track = e("Frame", {
				Position = UDim2.fromOffset(0, skin.px(22)),
				Size = UDim2.new(1, 0, 0, skin.px(30)),
				BackgroundTransparency = 1,
			}, {
				Slider = e(Slider, {
					value = value,
					min = info.min,
					max = info.max,
					step = 0.01,
					onChange = function(next: number)
						setDragging(function(current)
							local result = table.clone(current)
							result[key] = next
							return result
						end)
					end,
					onCommit = function(final: number)
						setDragging({})
						local next: BodyScale.Scale = table.clone(chosen)
						next[key] = final
						props.look.setScale(BodyScale.normalise(next))
					end,
				}),
			}),
		})
	end
	rows.Own = e(PillButton, {
		variant = "pill",
		size = Tokens.size.ctaHeight,
		width = 200,
		icon = "restart_alt",
		iconSize = 18,
		label = "Your own",
		disabled = BodyScale.isEmpty(chosen),
		sound = false, -- the change plays its own sound
		layoutOrder = #BodyScale.KEYS + 1,
		onActivated = function()
			props.look.setScale({})
		end,
	})

	return e("Frame", {
		Name = "ScalePanel",
		Position = props.position,
		Size = props.size,
		BackgroundTransparency = 1,
	}, {
		Column = e("Frame", {
			Size = UDim2.new(0, skin.px(WIDTH), 1, 0),
			BackgroundTransparency = 1,
		}, rows),
	})
end

return ScalePanel
