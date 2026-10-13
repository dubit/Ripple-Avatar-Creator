--!strict

--[[
	QrTile

	A QR code on a white rounded tile (dark modules on white, with a quiet
	margin), for a phone camera to scan off the screen. Modules are whole
	pixels so they stay sharp; each row's dark runs are one Frame apiece.

	Props:
		text: string           what to encode (a link)
		size: number           the tile's side in pixels (already scaled)
		position, anchorPoint
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local QRCode = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("QRCode"))

local e = React.createElement

local QUIET = 3 -- light modules round the code (scanners want some margin)
local DARK = Color3.fromHex("#111111")

local function QrTile(props: { text: string, size: number, position: UDim2?, anchorPoint: Vector2? })
	-- Level L keeps a link at 33 modules, so each is as big as can be.
	local grid = React.useMemo(function()
		return QRCode.encode(props.text, "L") or {}
	end, { props.text })
	local count = #grid
	local module = math.max(1, math.floor(props.size / (count + QUIET * 2)))
	local inset = math.floor((props.size - module * count) / 2)

	local cells: { [string]: any } = {}
	for r = 1, count do
		local c = 1
		while c <= count do
			if grid[r][c] then
				local start = c
				while c <= count and grid[r][c] do
					c += 1
				end
				cells["M" .. r .. "_" .. start] = e("Frame", {
					Position = UDim2.fromOffset(inset + (start - 1) * module, inset + (r - 1) * module),
					Size = UDim2.fromOffset((c - start) * module, module),
					BackgroundColor3 = DARK,
					BorderSizePixel = 0,
				})
			else
				c += 1
			end
		end
	end

	return e("CanvasGroup", {
		AnchorPoint = props.anchorPoint,
		Position = props.position,
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, module * 2) }),
		Cells = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, cells),
	})
end

return QrTile
