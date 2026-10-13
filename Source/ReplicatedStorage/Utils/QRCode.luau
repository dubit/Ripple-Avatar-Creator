--!strict

--[[
	QRCode

	Turns text (a link) into a QR code: a square grid of dark and light
	modules, ready to draw. Byte mode, versions 1 to 10 (21 to 57 modules a
	side, up to 271 characters at level L), any error-correction level, with
	the data split into blocks and interleaved as the standard says and the
	mask picked by the standard's penalty score. Follows Project Nayuki's
	QR Code generator (MIT), cut down to what links need.

	Checked against a real decoder (zxing-cpp) for every level and version.
	A quiet zone (4 light modules round the edge) is up to whoever draws it.

	API:
		encode(text, level?) -> ({ { boolean } }?, string?)
		    rows of modules (true = dark), [row][column], 1-based; or nil
		    and "empty" | "toolong". `level` is "L" | "M" | "Q" | "H"
		    (default "M": still scans with a bit of glare or a smudge)
]]

local QRCode = {}

export type Level = "L" | "M" | "Q" | "H"

local MAX_VERSION = 10

-- Per level, per version: { ec codewords per block, blocks in group 1, data
-- codewords per group-1 block, blocks in group 2 (one more data codeword) }.
local BLOCKS: { [Level]: { { number } } } = {
	L = {
		{ 7, 1, 19, 0 }, { 10, 1, 34, 0 }, { 15, 1, 55, 0 }, { 20, 1, 80, 0 }, { 26, 1, 108, 0 },
		{ 18, 2, 68, 0 }, { 20, 2, 78, 0 }, { 24, 2, 97, 0 }, { 30, 2, 116, 0 }, { 18, 2, 68, 2 },
	},
	M = {
		{ 10, 1, 16, 0 }, { 16, 1, 28, 0 }, { 26, 1, 44, 0 }, { 18, 2, 32, 0 }, { 24, 2, 43, 0 },
		{ 16, 4, 27, 0 }, { 18, 4, 31, 0 }, { 22, 2, 38, 2 }, { 22, 3, 36, 2 }, { 26, 4, 43, 1 },
	},
	Q = {
		{ 13, 1, 13, 0 }, { 22, 1, 22, 0 }, { 18, 2, 17, 0 }, { 26, 2, 24, 0 }, { 18, 2, 15, 2 },
		{ 24, 4, 19, 0 }, { 18, 2, 14, 4 }, { 22, 4, 18, 2 }, { 20, 4, 16, 4 }, { 24, 6, 19, 2 },
	},
	H = {
		{ 17, 1, 9, 0 }, { 28, 1, 16, 0 }, { 22, 2, 13, 0 }, { 16, 4, 9, 0 }, { 22, 2, 11, 2 },
		{ 28, 4, 15, 0 }, { 26, 4, 13, 1 }, { 26, 4, 14, 2 }, { 24, 4, 12, 4 }, { 28, 6, 15, 2 },
	},
}

-- The level's two bits in the format information.
local LEVEL_BITS: { [Level]: number } = { L = 1, M = 0, Q = 3, H = 2 }

-- Alignment pattern centres (0-based), per version.
local ALIGNMENT: { { number } } = {
	{},
	{ 6, 18 },
	{ 6, 22 },
	{ 6, 26 },
	{ 6, 30 },
	{ 6, 34 },
	{ 6, 22, 38 },
	{ 6, 24, 42 },
	{ 6, 26, 46 },
	{ 6, 28, 50 },
}

local band, bxor, lshift, rshift = bit32.band, bit32.bxor, bit32.lshift, bit32.rshift

local function bit(value: number, index: number): boolean
	return band(rshift(value, index), 1) ~= 0
end

local function dataCapacity(version: number, level: Level): number
	local row = BLOCKS[level][version]
	return row[2] * row[3] + row[4] * (row[3] + 1)
end

-- Reed-Solomon over GF(2^8), modulus 0x11D.
local function multiply(x: number, y: number): number
	local z = 0
	for i = 7, 0, -1 do
		z = bxor(lshift(z, 1), rshift(z, 7) * 0x11D)
		z = bxor(z, band(rshift(y, i), 1) * x)
	end
	return z
end

local function divisor(degree: number): { number }
	local result = table.create(degree, 0)
	result[degree] = 1
	local root = 1
	for _ = 1, degree do
		for j = 1, degree do
			result[j] = multiply(result[j], root)
			if j < degree then
				result[j] = bxor(result[j], result[j + 1])
			end
		end
		root = multiply(root, 2)
	end
	return result
end

local function remainder(data: { number }, div: { number }): { number }
	local result = table.create(#div, 0)
	for _, byte in data do
		local factor = bxor(byte, table.remove(result, 1) :: number)
		table.insert(result, 0)
		for i, coefficient in div do
			result[i] = bxor(result[i], multiply(coefficient, factor))
		end
	end
	return result
end

-- The data codewords: mode, length, the bytes, terminator and padding.
local function dataCodewords(text: string, version: number, level: Level): { number }
	local bits: { number } = {}
	local function append(value: number, length: number)
		for i = length - 1, 0, -1 do
			table.insert(bits, band(rshift(value, i), 1))
		end
	end
	append(0x4, 4)
	append(#text, if version <= 9 then 8 else 16)
	for i = 1, #text do
		append(string.byte(text, i), 8)
	end
	local capacityBits = dataCapacity(version, level) * 8
	append(0, math.min(4, capacityBits - #bits))
	append(0, (8 - #bits % 8) % 8)
	local pad = 0xEC
	while #bits < capacityBits do
		append(pad, 8)
		pad = if pad == 0xEC then 0x11 else 0xEC
	end
	local codewords = table.create(#bits // 8, 0)
	for i, b in bits do
		local index = (i - 1) // 8 + 1
		codewords[index] = bxor(codewords[index], lshift(b, 7 - (i - 1) % 8))
	end
	return codewords
end

-- Split into blocks, add each block's error correction, and interleave.
local function withErrorCorrection(data: { number }, version: number, level: Level): { number }
	local row = BLOCKS[level][version]
	local ecLength, shortCount, shortLength, longCount = row[1], row[2], row[3], row[4]
	local div = divisor(ecLength)
	local blocks: { { data: { number }, ec: { number } } } = {}
	local at = 1
	for index = 1, shortCount + longCount do
		local length = if index <= shortCount then shortLength else shortLength + 1
		local chunk = table.move(data, at, at + length - 1, 1, {})
		at += length
		table.insert(blocks, { data = chunk, ec = remainder(chunk, div) })
	end
	local result: { number } = {}
	for i = 1, shortLength + 1 do
		for _, block in blocks do
			if block.data[i] then
				table.insert(result, block.data[i])
			end
		end
	end
	for i = 1, ecLength do
		for _, block in blocks do
			table.insert(result, block.ec[i])
		end
	end
	return result
end

-- Masks, by (column, row), 0-based.
local MASKS: { (number, number) -> boolean } = {
	function(x, y) return (x + y) % 2 == 0 end,
	function(_x, y) return y % 2 == 0 end,
	function(x, _y) return x % 3 == 0 end,
	function(x, y) return (x + y) % 3 == 0 end,
	function(x, y) return (x // 3 + y // 2) % 2 == 0 end,
	function(x, y) return x * y % 2 + x * y % 3 == 0 end,
	function(x, y) return (x * y % 2 + x * y % 3) % 2 == 0 end,
	function(x, y) return ((x + y) % 2 + x * y % 3) % 2 == 0 end,
}

-- The standard's penalty for a finished grid (lower scans better).
local function penalty(grid: { { boolean } }, size: number): number
	local score = 0
	local function line(get: (number) -> boolean)
		local run, last = 0, nil :: boolean?
		for i = 1, size do
			local value = get(i)
			if value == last then
				run += 1
			else
				if run >= 5 then
					score += run - 2
				end
				run, last = 1, value
			end
		end
		if run >= 5 then
			score += run - 2
		end
		-- Finder-like 1:1:3:1:1 with four light modules on one side.
		for i = 1, size - 10 do
			local s = ""
			for k = 0, 10 do
				s ..= if get(i + k) then "1" else "0"
			end
			if s == "10111010000" or s == "00001011101" then
				score += 40
			end
		end
	end
	for r = 1, size do
		line(function(c) return grid[r][c] end)
		line(function(c) return grid[c][r] end)
	end
	local dark = 0
	for r = 1, size do
		for c = 1, size do
			if grid[r][c] then
				dark += 1
			end
			if r < size and c < size then
				local v = grid[r][c]
				if grid[r][c + 1] == v and grid[r + 1][c] == v and grid[r + 1][c + 1] == v then
					score += 3
				end
			end
		end
	end
	local total = size * size
	score += 10 * (math.abs(dark * 20 - total * 10) // total)
	return score
end

local function build(codewords: { number }, version: number, level: Level): { { boolean } }
	local size = version * 4 + 17
	local grid: { { boolean } } = {}
	local fixed: { { boolean } } = {}
	for r = 1, size do
		grid[r] = table.create(size, false)
		fixed[r] = table.create(size, false)
	end
	-- (x, y) are 0-based column and row, as in the standard.
	local function set(x: number, y: number, dark: boolean)
		grid[y + 1][x + 1] = dark
		fixed[y + 1][x + 1] = true
	end

	-- Timing, finders (over the timing), alignment.
	for i = 0, size - 1 do
		set(6, i, i % 2 == 0)
		set(i, 6, i % 2 == 0)
	end
	for _, centre in { { 3, 3 }, { size - 4, 3 }, { 3, size - 4 } } do
		for dy = -4, 4 do
			for dx = -4, 4 do
				local x, y = centre[1] + dx, centre[2] + dy
				if x >= 0 and x < size and y >= 0 and y < size then
					local distance = math.max(math.abs(dx), math.abs(dy))
					set(x, y, distance ~= 2 and distance ~= 4)
				end
			end
		end
	end
	local positions = ALIGNMENT[version]
	for i, cx in positions do
		for j, cy in positions do
			local corner = (i == 1 and j == 1) or (i == 1 and j == #positions) or (i == #positions and j == 1)
			if not corner then
				for dy = -2, 2 do
					for dx = -2, 2 do
						set(cx + dx, cy + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
					end
				end
			end
		end
	end

	local function drawFormat(mask: number)
		local data = bxor(lshift(LEVEL_BITS[level], 3), mask)
		local rem = data
		for _ = 1, 10 do
			rem = bxor(lshift(rem, 1), rshift(rem, 9) * 0x537)
		end
		local bits = bxor(bxor(lshift(data, 10), rem), 0x5412)
		for i = 0, 5 do
			set(8, i, bit(bits, i))
		end
		set(8, 7, bit(bits, 6))
		set(8, 8, bit(bits, 7))
		set(7, 8, bit(bits, 8))
		for i = 9, 14 do
			set(14 - i, 8, bit(bits, i))
		end
		for i = 0, 7 do
			set(size - 1 - i, 8, bit(bits, i))
		end
		for i = 8, 14 do
			set(8, size - 15 + i, bit(bits, i))
		end
		set(8, size - 8, true) -- the dark module
	end
	drawFormat(0) -- reserves the format areas; redrawn once the mask is known
	if version >= 7 then
		local rem = version
		for _ = 1, 12 do
			rem = bxor(lshift(rem, 1), rshift(rem, 11) * 0x1F25)
		end
		local bits = bxor(lshift(version, 12), rem)
		for i = 0, 17 do
			local a, b = size - 11 + i % 3, i // 3
			set(a, b, bit(bits, i))
			set(b, a, bit(bits, i))
		end
	end

	-- The codewords, in the zigzag from the bottom right.
	local index = 0
	local total = #codewords * 8
	local right = size - 1
	while right >= 1 do
		if right == 6 then
			right = 5
		end
		for vertical = 0, size - 1 do
			for j = 0, 1 do
				local x = right - j
				local upward = band(right + 1, 2) == 0
				local y = if upward then size - 1 - vertical else vertical
				if not fixed[y + 1][x + 1] and index < total then
					grid[y + 1][x + 1] = bit(codewords[index // 8 + 1], 7 - index % 8)
					index += 1
				end
			end
		end
		right -= 2
	end

	local function applyMask(mask: number)
		local rule = MASKS[mask + 1]
		for y = 0, size - 1 do
			for x = 0, size - 1 do
				if not fixed[y + 1][x + 1] and rule(x, y) then
					grid[y + 1][x + 1] = not grid[y + 1][x + 1]
				end
			end
		end
	end
	local best, bestScore = 0, math.huge
	for mask = 0, 7 do
		applyMask(mask)
		drawFormat(mask)
		local score = penalty(grid, size)
		if score < bestScore then
			best, bestScore = mask, score
		end
		applyMask(mask) -- undo (masks are their own inverse)
	end
	applyMask(best)
	drawFormat(best)
	return grid
end

function QRCode.encode(text: string, level: Level?): ({ { boolean } }?, string?)
	if text == "" then
		return nil, "empty"
	end
	local chosen: Level = level or "M"
	for version = 1, MAX_VERSION do
		local lengthBits = if version <= 9 then 8 else 16
		if 4 + lengthBits + #text * 8 <= dataCapacity(version, chosen) * 8 then
			local codewords = withErrorCorrection(dataCodewords(text, version, chosen), version, chosen)
			return build(codewords, version, chosen), nil
		end
	end
	return nil, "toolong"
end

return QRCode
