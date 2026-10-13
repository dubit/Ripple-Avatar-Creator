--!strict

--[[
	QrTile

	A QR code on a white rounded tile (dark modules on white, with a quiet
	margin), for a phone camera to scan off the screen. Modules are whole
	pixels so they stay sharp; each row's dark runs are one Frame apiece.

	Without `text` (nothing to share yet, or not revealed) it shows a
	scrambled stand-in that looks like a QR code but doesn't scan, dimmed.

	Props:
		text: string?          what to encode (a link); nil = the stand-in
		size: number           the tile's side in pixels (already scaled)
		position, anchorPoint
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local QRCode = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("QRCode"))

local e = React.createElement

local QUIET = 3 -- light modules round the code (scanners want some margin)
local DARK = Color3.fromHex("#111111")

local function standIn(): { { boolean } }
	local grid = QRCode.encode("https://www.roblox.com/games/start?placeId=0&launchData=s:XXXXXX", "L") :: { { boolean } }
	local random = Random.new(7)
	local size = #grid
	for r = 1, size do
		for c = 1, size do
			local finder = (r <= 8 and c <= 8) or (r <= 8 and c > size - 8) or (r > size - 8 and c <= 8)
			if not finder and random:NextNumber() < 0.45 then
				grid[r][c] = not grid[r][c]
			end
		end
	end
	return grid
end

local function QrTile(props: { text: string?, size: number, position: UDim2?, anchorPoint: Vector2? })
	local grid = React.useMemo(function()
		if props.text then
			-- Level L keeps a link at 33 modules, so each is as big as can be.
			local encoded = QRCode.encode(props.text, "L")
			if encoded then
				return encoded
			end
		end
		return standIn()
	end, { props.text })
	local real = props.text ~= nil
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
		GroupTransparency = if real then 0 else 0.8,
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
