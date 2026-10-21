--!strict

--[[
	useContentHeight

	The height of what a UIListLayout lays out, in LOCAL units (as
	useLocalSize), for a ScrollingFrame's CanvasSize when its rows aren't all
	one height (a ListRow drops its buttons to a second line when narrow).
	AutomaticCanvasSize mis-sizes under the SkinRoot canvas's UIScale, so the
	layout's AbsoluteContentSize is read instead. 0 until the layout mounts.

	Usage:
		local layoutRef, contentHeight = useContentHeight()
		rows.Layout = e("UIListLayout", { ref = layoutRef, ... })
		CanvasSize = UDim2.fromOffset(0, math.max(contentHeight, estimate) + padding)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local useSkin = require(script.Parent:WaitForChild("useSkin"))

local function useContentHeight(): (any, number)
	local skin = useSkin()
	local ref = React.useRef(nil :: UIListLayout?)
	local watched = React.useRef(nil :: { layout: UIListLayout, connection: RBXScriptConnection }?)
	local absolute, setAbsolute = React.useState(0)
	-- Every render: the layout may mount later than this hook (a page still
	-- loading), or be replaced.
	React.useEffect(function()
		local layout = ref.current
		local current = watched.current
		if current and current.layout == layout then
			return
		end
		if current then
			current.connection:Disconnect()
			watched.current = nil
		end
		if layout then
			setAbsolute(layout.AbsoluteContentSize.Y)
			watched.current = {
				layout = layout,
				connection = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
					setAbsolute(layout.AbsoluteContentSize.Y)
				end),
			}
		end
	end)
	React.useEffect(function()
		return function()
			if watched.current then
				watched.current.connection:Disconnect()
				watched.current = nil
			end
		end
	end, {})
	return ref, skin.fromScreen(absolute)
end

return useContentHeight
