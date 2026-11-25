--!strict

--[[
	OthersRings (client view, renders nothing in the React tree)

	Other players' recommendation rings, so you can see what they're
	looking at: each item floats, turns and bobs over its spot like in
	your own ring (RecommendationRing), but there's nothing else: no glow
	on the floor, no loading orbs, no labels, and nothing to stand on. The
	back pad's item is a ghost. An item with no 3D view gets its thumbnail
	on a card.

	Tapping or clicking one of their items wears it (TryOn, replacing the
	same type, like a pick in your own ring): it pops, and that's reported
	as rec_others_pick (trying it out, user 2026-11-25). The hit test is a
	sphere round each item (the items aren't raycast targets, so they
	can't get in the way of your own ring's pad placement).

	Props:
	  enabled   false while a menu is open (taps go to the menu)

	What each ring holds comes from RingsModel (Network.State.Rings), which
	each player's own ring fills in (ShareRing). Your own entry is skipped:
	you see your real ring. A ring that changes or closes shrinks away; the
	new one grows in.

	Testing alone: set the Workspace attribute RingsShowMine = true and
	your own shared ring is drawn too, raised by SELF_LIFT studs so it
	shows above the real one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local RecommendationConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("RecommendationConfig"))

local views = script.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Sounds = require(views:WaitForChild("Sounds"))
local useBoltState = require(views:WaitForChild("hooks"):WaitForChild("useBoltState"))
local useWorldTap = require(views:WaitForChild("hooks"):WaitForChild("useWorldTap"))
local CatalogueClient = require(views:WaitForChild("catalogue"):WaitForChild("CatalogueClient"))
local ItemModel = require(views:WaitForChild("catalogue"):WaitForChild("ItemModel"))

type Item = CatalogueClient.Item
type RingPad = Network.RingPad

local RING = RecommendationConfig.ring
local POP = 0.4 -- seconds for an item to grow in / out
local SELF_LIFT = 5 -- RingsShowMine: how far above the real ring yours is drawn
local CARD_GROW = TweenInfo.new(POP, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CARD_SHRINK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TAP_POP = 0.3 -- seconds a tapped item swells for
local TAP_SWELL = 0.3 -- how much bigger it gets (0..1)
local TAP_REACH = 300 -- studs

type Shown = {
	item: Item,
	back: boolean, -- the back pad's ghost
	tappedAt: number?, -- when it was last tapped (it pops)
	spot: Vector3, -- the pad's spot on the ground
	model: Model?,
	card: BillboardGui?,
	fit: number, -- the model's full scale
	bornAt: number,
	phase: number, -- spin / bob offset, so they don't move in step
}

type Display = {
	key: string, -- what it shows, to spot a change
	folder: Folder,
	shown: { Shown },
	closingAt: number?,
}

local function keyOf(pads: { RingPad }): string
	local parts = {}
	for _, pad in pads do
		table.insert(parts, `{pad.kind}:{pad.id}@{math.round(pad.x)},{math.round(pad.z)}`)
	end
	return table.concat(parts, ";")
end

-- Back easing (overshoots a little), 0..1 -> 0..1.
local function backOut(t: number): number
	local s = 1.70158
	t -= 1
	return t * t * ((s + 1) * t + s) + 1
end

local function pivotOf(shown: Shown, now: number): CFrame
	local bob = math.sin(now * RING.bobSpeed + shown.phase) * RING.bobHeight
	return CFrame.new(shown.spot + Vector3.new(0, RING.modelHeight + bob, 0))
		* CFrame.Angles(0, now * RING.spinSpeed + shown.phase, 0)
end

-- The item's model over its spot (yields while it builds), else its card.
local function showItem(display: Display, item: Item, pad: RingPad)
	local shown: Shown = {
		item = item,
		back = pad.back,
		spot = Vector3.new(pad.x, pad.y, pad.z),
		fit = 1,
		bornAt = os.clock(),
		phase = math.random() * math.pi * 2,
	}
	local template = if ItemModel.supports(item) then ItemModel.build(item) else nil -- yields; cached
	if display.closingAt or not display.folder.Parent then
		return
	end
	if template then
		local model = template:Clone()
		model.Name = "Item"
		local box, size = model:GetBoundingBox()
		local extent = math.max(size.X, size.Y, size.Z)
		if extent > 0 then
			model.WorldPivot = box
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					if pad.back then
						part.Transparency = 0.5 + part.Transparency * 0.5
					end
				elseif part:IsA("Humanoid") then
					part.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
			end
			shown.fit = model:GetScale() * RING.modelSize / extent
			model:ScaleTo(shown.fit * 0.05)
			shown.bornAt = os.clock()
			model:PivotTo(pivotOf(shown, shown.bornAt))
			model.Parent = display.folder
			shown.model = model
		else
			model:Destroy()
		end
	end
	if not shown.model then
		-- No 3D view: a square thumbnail card, as in your own ring.
		local anchor = Instance.new("Part")
		anchor.Name = "CardSpot"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(shown.spot)
		anchor.Parent = display.folder
		local card = Instance.new("BillboardGui")
		card.Adornee = anchor
		card.LightInfluence = 0
		card.MaxDistance = RING.cardMaxDistance
		card.StudsOffsetWorldSpace = Vector3.new(0, RING.cardHeight, 0)
		card.Size = UDim2.fromScale(0, 0)
		card.Parent = anchor
		local backing = Instance.new("Frame")
		backing.Size = UDim2.fromScale(1, 1)
		backing.BackgroundColor3 = Tokens.color.white
		backing.BackgroundTransparency = if pad.back then 0.6 else 0.1
		backing.Parent = card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.12, 0)
		corner.Parent = backing
		local thumb = Instance.new("ImageLabel")
		thumb.BackgroundTransparency = 1
		thumb.AnchorPoint = Vector2.new(0.5, 0.5)
		thumb.Position = UDim2.fromScale(0.5, 0.5)
		thumb.Size = UDim2.fromScale(0.92, 0.92)
		thumb.ScaleType = Enum.ScaleType.Fit
		thumb.Image = item.thumbnail
		thumb.ImageTransparency = if pad.back then 0.5 else 0
		thumb.Parent = backing
		TweenService:Create(card, CARD_GROW, { Size = UDim2.fromScale(RING.cardSize, RING.cardSize) }):Play()
		shown.card = card
	end
	table.insert(display.shown, shown)
end

local function openDisplay(pads: { RingPad }, key: string, lift: number): Display
	local folder = Instance.new("Folder")
	folder.Name = "OthersRing"
	folder.Parent = workspace
	local display: Display = { key = key, folder = folder, shown = {} }
	task.spawn(function()
		local refs = {}
		for _, pad in pads do
			table.insert(refs, { kind = pad.kind :: any, targetId = pad.id })
		end
		local items = CatalogueClient.lookupMany(refs) -- yields
		for index, pad in pads do
			local item = items[if pad.kind == "Bundle" then -pad.id else pad.id]
			if item then
				local placed = table.clone(pad)
				placed.y += lift
				task.delay((index - 1) * 0.05, showItem, display, item, placed)
			end
		end
	end)
	return display
end

-- Displays shrinking away: still animated until they're gone.
local closing: { [Display]: boolean } = {}

local function closeDisplay(display: Display)
	if display.closingAt then
		return
	end
	display.closingAt = os.clock()
	closing[display] = true
	for _, shown in display.shown do
		if shown.card then
			TweenService:Create(shown.card, CARD_SHRINK, { Size = UDim2.fromScale(0, 0) }):Play()
		end
	end
	task.delay(CARD_SHRINK.Time + 0.05, function()
		closing[display] = nil
		display.folder:Destroy()
	end)
end

local function animate(display: Display, now: number)
	for _, shown in display.shown do
		local model = shown.model
		if not model then
			continue
		end
		local grow = math.clamp((now - shown.bornAt) / POP, 0, 1)
		local amount = backOut(grow)
		if display.closingAt then
			amount *= 1 - math.clamp((now - display.closingAt) / CARD_SHRINK.Time, 0, 1)
		end
		local tapped = shown.tappedAt
		local swell = if tapped then math.max(0, 1 - (now - tapped) / TAP_POP) else 0
		if tapped and swell == 0 then
			shown.tappedAt = nil
		end
		if grow < 1 or display.closingAt or tapped then
			model:ScaleTo(math.max(shown.fit * amount * (1 + TAP_SWELL * math.sin(swell * math.pi)), shown.fit * 0.01))
		end
		model:PivotTo(pivotOf(shown, now))
	end
end

-- The item (model or card) a tap at `position` lands on, nearest first.
local function tappedItem(displays: { [string]: Display }, position: Vector3): Shown?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local best: Shown?, bestAlong = nil, TAP_REACH
	for _, display in displays do
		if display.closingAt then
			continue
		end
		for _, shown in display.shown do
			local centre, radius
			if shown.model then
				centre = shown.model:GetPivot().Position
				radius = RING.modelSize / 2
			elseif shown.card then
				centre = shown.spot + Vector3.new(0, RING.cardHeight, 0)
				radius = RING.cardSize / 2
			else
				continue
			end
			-- Ray against a sphere round it: the nearest point on the ray.
			local along = (centre - ray.Origin):Dot(ray.Direction)
			if along > 0 and along < bestAlong then
				local closest = ray.Origin + ray.Direction * along
				if (closest - centre).Magnitude <= radius then
					best, bestAlong = shown, along
				end
			end
		end
	end
	return best
end

local function OthersRings(props: { enabled: boolean })
	local state = useBoltState(Network.State.Rings, { ownerId = "", rings = {} } :: any)
	local displays = React.useRef({} :: { [string]: Display })

	-- Tapping one of their items wears it.
	useWorldTap(function(position: Vector3)
		local shown = tappedItem(displays.current :: { [string]: Display }, position)
		if not shown then
			return
		end
		local item = shown.item
		shown.tappedAt = os.clock()
		Sounds.play("tryOn")
		Network.Intent.Avatar:FireServer(
			Network.Actions.Avatar.TryOn,
			{ targetId = item.targetId, kind = item.kind },
			{ replaceSameType = true }
		)
		Network.Intent.Recommendations:FireServer(
			Network.Actions.Recommendations.Track,
			{ event = "rec_others_pick", item_id = item.id, back = shown.back }
		)
	end, props.enabled)

	-- Open, change and close displays to match the shared rings.
	React.useEffect(function()
		local current = displays.current :: { [string]: Display }
		local mine = tostring(Players.LocalPlayer.UserId)
		for userId, ring in state.rings :: { [string]: { pads: { RingPad } } } do
			local isMine = userId == mine
			if isMine and workspace:GetAttribute("RingsShowMine") ~= true then
				continue
			end
			local key = keyOf(ring.pads)
			local display = current[userId]
			if display and display.key ~= key then
				closeDisplay(display)
				display = nil
			end
			if not display then
				current[userId] = openDisplay(ring.pads, key, if isMine then SELF_LIFT else 0)
			end
		end
		for userId, display in current do
			if not (state.rings :: any)[userId] then
				closeDisplay(display)
				current[userId] = nil
			end
		end
		return nil
	end, { state.rings })

	-- Everything moves every frame; all of it goes when this unmounts.
	React.useEffect(function()
		local connection = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			for _, display in displays.current :: { [string]: Display } do
				animate(display, now)
			end
			for display in closing do
				animate(display, now)
			end
		end)
		return function()
			connection:Disconnect()
			for _, display in displays.current :: { [string]: Display } do
				display.folder:Destroy()
			end
			table.clear(displays.current :: any)
			for display in closing do
				display.folder:Destroy()
			end
			table.clear(closing)
		end
	end, {})

	return nil
end

return OthersRings
