--!strict

--[[
	useContentSize

	The size of what a UIListLayout lays out, in LOCAL units (as
	useLocalSize): a ScrollingFrame's CanvasSize when its rows aren't all one
	height, or the width a row of buttons really takes.
	AutomaticCanvasSize mis-sizes under the SkinRoot canvas's UIScale, so the
	layout's AbsoluteContentSize is read instead. 0 until the layout mounts.

	Usage:
		local layoutRef, content = useContentSize()
		Layout = e("UIListLayout", { ref = layoutRef, ... })
		-- content.X / content.Y
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local useSkin = require(script.Parent:WaitForChild("useSkin"))

local function useContentSize(): (any, Vector2)
	local skin = useSkin()
	local ref = React.useRef(nil :: UIListLayout?)
	local watched = React.useRef(nil :: { layout: UIListLayout, connection: RBXScriptConnection }?)
	local absolute, setAbsolute = React.useState(Vector2.zero)
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
			setAbsolute(layout.AbsoluteContentSize)
			watched.current = {
				layout = layout,
				connection = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
					setAbsolute(layout.AbsoluteContentSize)
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
	return ref, Vector2.new(skin.fromScreen(absolute.X), skin.fromScreen(absolute.Y))
end

return useContentSize
