--!strict

--[[
	useContentHeight

	useContentSize's height alone: a ScrollingFrame's CanvasSize when its rows
	aren't all one height (a ListRow drops its buttons to a second line when
	narrow). 0 until the layout mounts.

	Usage:
		local layoutRef, contentHeight = useContentHeight()
		rows.Layout = e("UIListLayout", { ref = layoutRef, ... })
		CanvasSize = UDim2.fromOffset(0, math.max(contentHeight, estimate) + padding)
]]

local useContentSize = require(script.Parent:WaitForChild("useContentSize"))

local function useContentHeight(): (any, number)
	local ref, size = useContentSize()
	return ref, size.Y
end

return useContentHeight
