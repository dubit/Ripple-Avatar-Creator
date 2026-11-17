--!strict

--[[
	RecommendationRing (renders nothing in the HUD — builds the ring in this
	client's world)

	While `open`, a ring of pads (invisible: they only mark the spots; the
	items float over them) lies on the ground around where the player
	stood when it opened (fixed in the world; it doesn't follow them). Each
	pad carries a card above it, facing the camera, with the item's thumbnail
	and name. The pads appear empty (loading) at once, then fill in when the
	Recommender answers. Then each item's 3D model (catalogue/ItemModel,
	built on this client) pops in above its pad, turning slowly and bobbing,
	and the card shrinks to a name tag over it; an item with no 3D view, or
	whose model fails, keeps its card. Only this player sees it: the parts are made by this
	client, so they never replicate.

	  · pads sit on whatever is below them (raycast down); one that would be
	    inside a wall is pulled in towards the centre, and one with no ground
	    under it (off a ledge) is left out
	  · the first ring is based on the whole outfit being worn
	  · walking well away from the ring (RecommendationConfig.ring.walkAway
	    beyond its radius), respawning or `open` going false closes it
	  · in and out with motion (cards pop / shrink, models grow / shrink);
	    a card breathes while its item loads

	Props:
	  open      whether the ring is showing
	  wornIds   the item ids being worn (CatalogueClient ids), oldest first
	  onClose   called when the ring closes itself (walking away, respawn)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local RecommendationConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("RecommendationConfig"))

local views = script.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Sounds = require(views:WaitForChild("Sounds"))
local CatalogueClient = require(views:WaitForChild("catalogue"):WaitForChild("CatalogueClient"))
local Recommender = require(views:WaitForChild("catalogue"):WaitForChild("Recommender"))
local ItemModel = require(views:WaitForChild("catalogue"):WaitForChild("ItemModel"))

type Item = CatalogueClient.Item

export type Props = {
	open: boolean,
	wornIds: { number },
	onClose: () -> (),
}

local RING = RecommendationConfig.ring
local PAD_THICKNESS = 0.4
local PAD_TRANSPARENCY = 1 -- no podia (user, 2026-11-17): the pad just marks the spot
local GROW = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHRINK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PULSE = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

type Pad = {
	part: Part,
	card: BillboardGui,
	thumb: ImageLabel,
	label: TextLabel,
	pulse: Tween?,
	model: Model?, -- the item's 3D model, once built
	fit: number, -- the model's scale that fits it in ring.modelSize
	bornAt: number, -- when the model appeared (os.clock)
	phase: number, -- spin / bob offset, so the pads don't move in step
}

type Ring = {
	folder: Folder,
	centre: Vector3,
	pads: { Pad },
	closingAt: number?,
}

local MODEL_POP = 0.4 -- seconds for a model to grow in / out

-- Back easing (overshoots a little), 0..1 -> 0..1.
local function backOut(t: number): number
	local s = 1.70158
	t -= 1
	return t * t * ((s + 1) * t + s) + 1
end

local function groundBelow(position: Vector3, ignore: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = false
	local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -RING.groundSearch, 0), params)
	return if hit then hit.Position else nil
end

-- Where each pad goes: evenly round the centre, the first straight ahead of
-- the camera. Pads pulled in by walls, or with no ground, are adjusted or
-- dropped.
local function padPositions(centre: Vector3, count: number, ignore: { Instance }): { Vector3 }
	local camera = workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
	local flat = Vector3.new(look.X, 0, look.Z)
	local start = if flat.Magnitude > 0.01 then math.atan2(flat.X, flat.Z) else 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local eye = centre + Vector3.new(0, 2, 0)
	local positions = {}
	for index = 1, count do
		local angle = start + (index - 1) * (2 * math.pi / count)
		local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local distance = RING.radius
		local wall = workspace:Raycast(eye, direction * (RING.radius + RING.padSize / 2), params)
		if wall then
			distance = (wall.Position - eye).Magnitude - RING.padSize / 2 - 0.5
		end
		if distance >= RING.radius * 0.5 then
			local ground = groundBelow(centre + direction * distance, ignore)
			if ground and math.abs(ground.Y - centre.Y) <= RING.maxStep then
				table.insert(positions, ground)
			end
		end
	end
	return positions
end

local function makePad(position: Vector3, folder: Folder): Pad
	local part = Instance.new("Part")
	part.Name = "Pad"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Tokens.color.white
	part.Transparency = PAD_TRANSPARENCY
	-- A cylinder's axis is X: turn it upright.
	part.CFrame = CFrame.new(position + Vector3.new(0, PAD_THICKNESS / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Size = Vector3.new(PAD_THICKNESS, 0.1, 0.1)
	part.Parent = folder

	local card = Instance.new("BillboardGui")
	card.Name = "Card"
	card.Adornee = part
	card.LightInfluence = 0
	card.MaxDistance = RING.cardMaxDistance
	card.StudsOffsetWorldSpace = Vector3.new(0, RING.cardHeight, 0)
	card.Size = UDim2.fromScale(0, 0)
	card.Parent = part

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Tokens.color.white
	back.BackgroundTransparency = 0.1
	back.Parent = card
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = back

	local thumb = Instance.new("ImageLabel")
	thumb.Name = "Thumb"
	thumb.BackgroundTransparency = 1
	thumb.AnchorPoint = Vector2.new(0.5, 0)
	thumb.Position = UDim2.fromScale(0.5, 0.04)
	thumb.Size = UDim2.fromScale(0.92, 0.72)
	thumb.ScaleType = Enum.ScaleType.Fit
	thumb.Image = ""
	thumb.Parent = back

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0.97)
	label.Size = UDim2.fromScale(0.9, 0.2)
	label.FontFace = Tokens.font(800)
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(30, 30, 36)
	label.Text = "…"
	label.Parent = back

	return { part = part, card = card, thumb = thumb, label = label, fit = 1, bornAt = 0, phase = math.random() * math.pi * 2 }
end

-- Where a pad's model sits this frame: above the pad, bobbing, turning.
local function modelPivot(pad: Pad, now: number): CFrame
	local top = pad.part.Position + Vector3.new(0, PAD_THICKNESS / 2, 0)
	local bob = math.sin(now * RING.bobSpeed + pad.phase) * RING.bobHeight
	return CFrame.new(top + Vector3.new(0, RING.modelHeight + bob, 0)) * CFrame.Angles(0, now * RING.spinSpeed + pad.phase, 0)
end

-- The item's model above the pad; the card becomes a name tag over it.
local function showModel(pad: Pad, item: Item)
	if not ItemModel.supports(item) then
		return
	end
	local template = ItemModel.build(item) -- yields; cached per item
	if not template or not pad.part.Parent then
		return
	end
	local model = template:Clone()
	model.Name = "Item"
	local box, size = model:GetBoundingBox()
	local extent = math.max(size.X, size.Y, size.Z)
	if extent <= 0 then
		model:Destroy()
		return
	end
	model.WorldPivot = box
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		elseif part:IsA("Humanoid") then
			part.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	pad.fit = model:GetScale() * RING.modelSize / extent -- the scale it ends up at
	model:ScaleTo(pad.fit * 0.05)
	pad.bornAt = os.clock()
	model:PivotTo(modelPivot(pad, pad.bornAt))
	model.Parent = pad.part.Parent
	pad.model = model

	-- Card -> name tag above the model.
	pad.thumb.Visible = false
	local back = pad.thumb.Parent :: Frame
	back.BackgroundTransparency = 1
	pad.label.Position = UDim2.fromScale(0.5, 1)
	pad.label.Size = UDim2.fromScale(1, 1)
	pad.label.TextColor3 = Tokens.color.white
	pad.label.TextStrokeTransparency = 0.4
	pad.card.StudsOffsetWorldSpace = Vector3.new(0, RING.modelHeight + RING.modelSize / 2 + 0.9, 0)
	pad.card.Size = UDim2.fromScale(0, 0)
	TweenService:Create(pad.card, GROW, { Size = UDim2.fromScale(RING.cardSize * 1.4, 0.8) }):Play()
end

-- Spins and bobs the models; grows them in, and shrinks them as the ring
-- closes.
local function animate(ring: Ring)
	local now = os.clock()
	for _, pad in ring.pads do
		local model = pad.model
		if not model then
			continue
		end
		local grow = math.clamp((now - pad.bornAt) / MODEL_POP, 0, 1)
		local amount = backOut(grow)
		if ring.closingAt then
			amount *= 1 - math.clamp((now - ring.closingAt) / SHRINK.Time, 0, 1)
		end
		local scale = math.max(pad.fit * amount, pad.fit * 0.01)
		if grow < 1 or ring.closingAt then
			model:ScaleTo(scale)
		end
		model:PivotTo(modelPivot(pad, now))
	end
end

local function growPad(pad: Pad, delay: number)
	task.delay(delay, function()
		if not pad.part.Parent then
			return
		end
		TweenService:Create(pad.part, GROW, { Size = Vector3.new(PAD_THICKNESS, RING.padSize, RING.padSize) }):Play()
		TweenService:Create(pad.card, GROW, { Size = UDim2.fromScale(RING.cardSize, RING.cardSize * 1.2) }):Play()
		-- Loading: the card breathes until its item arrives.
		local pulse = TweenService:Create(pad.thumb.Parent :: Frame, PULSE, { BackgroundTransparency = 0.6 })
		pad.pulse = pulse
		pulse:Play()
	end)
end

local function fillPad(pad: Pad, item: Item, delay: number)
	task.delay(delay, function()
		if not pad.part.Parent then
			return
		end
		if pad.pulse then
			pad.pulse:Cancel()
			pad.pulse = nil
		end
		(pad.thumb.Parent :: Frame).BackgroundTransparency = 0.1
		pad.thumb.Image = item.thumbnail
		pad.label.Text = item.name
		-- A little pop as it fills.
		pad.card.Size = UDim2.fromScale(RING.cardSize * 0.85, RING.cardSize * 1.2 * 0.85)
		TweenService:Create(pad.card, GROW, { Size = UDim2.fromScale(RING.cardSize, RING.cardSize * 1.2) }):Play()
		showModel(pad, item)
	end)
end

local function closeRing(ring: Ring)
	ring.closingAt = os.clock()
	for _, pad in ring.pads do
		if pad.pulse then
			pad.pulse:Cancel()
		end
		TweenService:Create(pad.part, SHRINK, { Size = Vector3.new(PAD_THICKNESS, 0.1, 0.1) }):Play()
		TweenService:Create(pad.card, SHRINK, { Size = UDim2.fromScale(0, 0) }):Play()
	end
	task.delay(SHRINK.Time + 0.05, function()
		ring.folder:Destroy()
	end)
end

local function itemsFor(ids: { number }): { Item }
	local items = {}
	for _, id in ids do
		local item = CatalogueClient.item(id)
		if item then
			table.insert(items, item)
		end
	end
	return items
end

local function RecommendationRing(props: Props)
	local latest = React.useRef(props)
	latest.current = props

	React.useEffect(function()
		if not props.open then
			return nil
		end
		local player = Players.LocalPlayer
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			latest.current.onClose()
			return nil
		end

		local folder = Instance.new("Folder")
		folder.Name = "RecommendationRing"
		folder.Parent = workspace
		local ignore = { character, folder }
		local centre = groundBelow(root.Position, ignore) or (root.Position - Vector3.new(0, 3, 0))
		local ring: Ring = { folder = folder, centre = centre, pads = {} }
		for index, position in padPositions(centre, RING.count, ignore) do
			local pad = makePad(position, folder)
			table.insert(ring.pads, pad)
			growPad(pad, (index - 1) * 0.04)
		end
		Sounds.play("open")

		-- Fill the pads from the recommender (yields; abandoned if closed).
		local closed = false
		task.spawn(function()
			local worn = itemsFor(latest.current.wornIds)
			local list = Recommender.recommend({
				basis = worn,
				worn = worn,
				count = #ring.pads,
			})
			if closed then
				return
			end
			for index, pad in ring.pads do
				local entry = list[index]
				if entry then
					fillPad(pad, entry.item, (index - 1) * 0.05)
				else
					pad.label.Text = "—"
				end
			end
		end)

		-- The models move every frame, through the closing shrink too.
		local motion = RunService.RenderStepped:Connect(function()
			animate(ring)
		end)
		folder.Destroying:Connect(function()
			motion:Disconnect()
		end)

		-- Walking well away, or respawning, closes it.
		local function selfClose()
			if not closed then
				latest.current.onClose()
			end
		end
		local watch = RunService.Heartbeat:Connect(function()
			local current = player.Character
			local hrp = current and current:FindFirstChild("HumanoidRootPart") :: BasePart?
			if current ~= character or not hrp then
				selfClose()
				return
			end
			local offset = hrp.Position - centre
			if Vector3.new(offset.X, 0, offset.Z).Magnitude > RING.radius + RING.walkAway then
				selfClose()
			end
		end)

		return function()
			closed = true
			watch:Disconnect()
			Sounds.play("close")
			closeRing(ring)
		end
	end, { props.open })

	return nil
end

return RecommendationRing
