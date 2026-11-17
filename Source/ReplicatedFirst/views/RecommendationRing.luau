--!strict

--[[
	RecommendationRing (renders nothing in the HUD — builds the rings in this
	client's world)

	While `open`, a ring of items floats around where the player stood when
	it opened (fixed in the world; it doesn't follow them). Each item sits
	over an invisible pad that marks its spot: its 3D model
	(catalogue/ItemModel, built on this client) turning slowly and bobbing,
	no label (user, 2026-11-17). Until the model is ready (and for items with
	no 3D view) a card shows the thumbnail; it breathes while the
	Recommender is still choosing. Only this player sees any of it: the parts
	are made by this client, so they never replicate.

	The trail:
	  · the first ring (RecommendationConfig.ring.count items) is based on
	    the whole outfit being worn
	  · each item has a soft glowing ring under it in its own colour
	    (ItemColour's dominant colour from the thumbnail; black / grey / white
	    items take their second colour, else a cool white; the back pad is
	    always white). Colour is identity, not information (user, 2026-11-17)
	  · standing on a pad for ring.dwell seconds wears its item (the ring
	    fills with light; stepping off drains it). The item replaces its slot and,
	    for accessories, the same accessory type (TryOn's replaceSameType).
	    That ring goes, and a new one opens round the player, based on that
	    item: count - 1 new items plus a back pad holding the item walked
	    through, on the side they came from
	  · the back pad undoes that outfit change and brings back the previous
	    ring (the same items) round the player. If the outfit has changed some
	    other way since (the HUD), nothing is undone: it only goes back a ring
	  · nothing is recommended twice on one trail

	  · pads sit on whatever is below them (raycast down); one that would be
	    inside a wall is pulled in towards the centre, and one with no ground
	    under it (off a ledge) is left out
	  · walking well away from the ring (ring.walkAway beyond its radius),
	    respawning or `open` going false closes it
	  · in and out with motion (cards pop / shrink, models grow / shrink)

	Analytics: each ring shown, pick, back and close is reported to
	RecommendationsController (rec_open / rec_ring / rec_pick / rec_back /
	rec_close), the feedback the external engine will learn from.

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
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local RecommendationConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("RecommendationConfig"))

local views = script.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Sounds = require(views:WaitForChild("Sounds"))
local CatalogueClient = require(views:WaitForChild("catalogue"):WaitForChild("CatalogueClient"))
local Recommender = require(views:WaitForChild("catalogue"):WaitForChild("Recommender"))
local ItemModel = require(views:WaitForChild("catalogue"):WaitForChild("ItemModel"))
local ItemColour = require(views:WaitForChild("catalogue"):WaitForChild("ItemColour"))
local SkinAssets = require(views:WaitForChild("SkinAssets"))

type Item = CatalogueClient.Item

export type Props = {
	open: boolean,
	wornIds: { number },
	onClose: () -> (),
}

local RING = RecommendationConfig.ring
local PAD_THICKNESS = 0.4
local GROW = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHRINK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PULSE = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local MODEL_POP = 0.4 -- seconds for a model to grow in / out
local GLOW_SPREAD = 1.3 -- the glow image is this much wider than the pad (its ring sits at 78%)
local GLOW_BRIGHTNESS = 2.5
local RING_IDLE = 0.15 -- the ring's ImageTransparency at rest (0 while you stand on it)

-- Glow colour per ItemColour bucket: tuned to glow, not the raw swatches.
local GLOW: { [string]: Color3 } = {
	Red = Color3.fromHex("#ff5a6a"),
	Orange = Color3.fromHex("#ffa040"),
	Yellow = Color3.fromHex("#ffe066"),
	Green = Color3.fromHex("#6cf59a"),
	Blue = Color3.fromHex("#5cc8ff"),
	Purple = Color3.fromHex("#b58cff"),
	Pink = Color3.fromHex("#ff85dd"),
	Brown = Color3.fromHex("#f0b070"),
	Neutral = Color3.fromHex("#e8ecff"), -- black / grey / white items
	Pending = Color3.fromHex("#ffffff"), -- loading, or colour not known yet
	Back = Color3.fromHex("#ffffff"),
}
local NEUTRAL = { Black = true, Grey = true, White = true }

type Pad = {
	part: Part, -- invisible: marks the spot; the card hangs off it
	glow: Part, -- flat, just above the ground: carries the glow images
	ringImage: ImageLabel, -- the glowing ring
	fillImage: ImageLabel, -- fills it while the player stands on the pad
	glowKey: string, -- which GLOW colour it shows
	card: BillboardGui,
	thumb: ImageLabel,
	label: TextLabel,
	pulse: Tween?,
	item: Item?, -- nil while loading
	reason: string?, -- why the recommender chose it
	slot: number?, -- its place among the ring's new items (1..)
	back: boolean, -- the back pad
	dwell: number, -- seconds stood on it
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

-- One ring on the trail.
type Entry = {
	items: { Item }?, -- its new items, once recommended
	reasons: { string }?, -- why each was chosen
	backItem: Item?, -- the item walked through to get here (the back pad)
	wornAfter: string?, -- the outfit just after that item went on (to guard Undo)
}

local trails = 0 -- numbers each trail (rec_* trail_id)

local function report(event: string, params: { [string]: any })
	params.event = event
	Network.Intent.Recommendations:FireServer(Network.Actions.Recommendations.Track, params)
end

-- Back easing (overshoots a little), 0..1 -> 0..1.
local function backOut(t: number): number
	local s = 1.70158
	t -= 1
	return t * t * ((s + 1) * t + s) + 1
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function signature(ids: { number }): string
	local sorted = table.clone(ids)
	table.sort(sorted)
	return table.concat(sorted, ",")
end

local function groundBelow(position: Vector3, ignore: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = false
	local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -RING.groundSearch, 0), params)
	return if hit then hit.Position else nil
end

-- Where the pad at each angle goes (nil: left out). Pads that would be
-- inside a wall are pulled in; ones with no ground under them are dropped.
local function padPosition(centre: Vector3, angle: number, ignore: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local eye = centre + Vector3.new(0, 2, 0)
	local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
	local distance = RING.radius
	local wall = workspace:Raycast(eye, direction * (RING.radius + RING.padSize / 2), params)
	if wall then
		distance = (wall.Position - eye).Magnitude - RING.padSize / 2 - 0.5
	end
	if distance < RING.radius * 0.5 then
		return nil
	end
	local ground = groundBelow(centre + direction * distance, ignore)
	if ground and math.abs(ground.Y - centre.Y) <= RING.maxStep then
		return ground
	end
	return nil
end

local function angleOf(direction: Vector3): number
	return math.atan2(direction.X, direction.Z)
end

local function makePad(position: Vector3, folder: Folder, back: boolean): Pad
	-- A plain, unrotated block: the card hangs off it, and a turned part (an
	-- upright cylinder) put cards off to one side of the models. Invisible:
	-- no podia (user, 2026-11-17).
	local part = Instance.new("Part")
	part.Name = "Pad"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position + Vector3.new(0, PAD_THICKNESS / 2, 0))
	part.Size = Vector3.new(RING.padSize, PAD_THICKNESS, RING.padSize)
	part.Parent = folder

	-- The glow: two white images on a flat, invisible part's top face, tinted
	-- and lit (LightInfluence 0, Brightness > 1) so they read as light.
	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.CastShadow = false
	glow.Transparency = 1
	glow.Size = Vector3.new(RING.padSize * GLOW_SPREAD, 0.05, RING.padSize * GLOW_SPREAD)
	glow.CFrame = CFrame.new(position + Vector3.new(0, 0.04, 0))
	glow.Parent = folder

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.LightInfluence = 0
	surface.Brightness = GLOW_BRIGHTNESS
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Parent = glow

	local function glowImage(name: string, image: number, transparency: number): ImageLabel
		local label = Instance.new("ImageLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0, 0)
		label.Image = `rbxassetid://{image}`
		label.ImageColor3 = GLOW.Pending
		label.ImageTransparency = transparency
		label.Parent = surface
		return label
	end
	local fillImage = glowImage("Fill", SkinAssets.ringFill, 0.35)
	local ringImage = glowImage("Ring", SkinAssets.ringGlow, 0.6)

	local card = Instance.new("BillboardGui")
	card.Name = "Card"
	card.Adornee = part
	card.LightInfluence = 0
	card.MaxDistance = RING.cardMaxDistance
	card.StudsOffsetWorldSpace = Vector3.new(0, RING.cardHeight, 0)
	card.Size = UDim2.fromScale(0, 0)
	card.Parent = part

	local backing = Instance.new("Frame")
	backing.Name = "Back"
	backing.Size = UDim2.fromScale(1, 1)
	backing.BackgroundColor3 = Tokens.color.white
	backing.BackgroundTransparency = 0.1
	backing.Parent = card
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = backing

	local thumb = Instance.new("ImageLabel")
	thumb.Name = "Thumb"
	thumb.BackgroundTransparency = 1
	thumb.AnchorPoint = Vector2.new(0.5, 0)
	thumb.Position = UDim2.fromScale(0.5, 0.04)
	thumb.Size = UDim2.fromScale(0.92, 0.72)
	thumb.ScaleType = Enum.ScaleType.Fit
	thumb.Image = ""
	thumb.Parent = backing

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
	label.Parent = backing
	-- Cards are sized in studs, so text right by the camera would fill the
	-- screen: cap it.
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 26
	limit.Parent = label

	return {
		part = part,
		glow = glow,
		ringImage = ringImage,
		fillImage = fillImage,
		glowKey = "Pending",
		card = card,
		thumb = thumb,
		label = label,
		back = back,
		dwell = 0,
		fit = 1,
		bornAt = 0,
		phase = math.random() * math.pi * 2,
	}
end

-- Where a pad's model sits this frame: above the pad, bobbing, turning.
local function modelPivot(pad: Pad, now: number): CFrame
	local top = pad.part.Position + Vector3.new(0, PAD_THICKNESS / 2, 0)
	local bob = math.sin(now * RING.bobSpeed + pad.phase) * RING.bobHeight
	return CFrame.new(top + Vector3.new(0, RING.modelHeight + bob, 0)) * CFrame.Angles(0, now * RING.spinSpeed + pad.phase, 0)
end

-- The item's model above the pad, in place of its card.
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
			if pad.back then
				-- The way back reads as a ghost of the item.
				part.Transparency = 0.5 + part.Transparency * 0.5
			end
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

	-- The card goes; the model stands on its own.
	TweenService:Create(pad.card, SHRINK, { Size = UDim2.fromScale(0, 0) }):Play()
end

-- Which GLOW colour a pad shows now.
local function glowKeyOf(pad: Pad): string
	local item = pad.item
	if pad.back then
		return "Back"
	elseif not item or item.colour == "" then
		return "Pending"
	elseif not NEUTRAL[item.colour] then
		return if GLOW[item.colour] then item.colour else "Neutral"
	end
	-- Black / grey / white: the item's second colour, if it has a real one.
	for _, name in item.colours do
		if not NEUTRAL[name] and GLOW[name] then
			return name
		end
	end
	return "Neutral"
end

local function updateGlow(pad: Pad)
	local key = glowKeyOf(pad)
	if key ~= pad.glowKey then
		pad.glowKey = key
		local colour = GLOW[key]
		TweenService:Create(pad.ringImage, SHRINK, { ImageColor3 = colour }):Play()
		TweenService:Create(pad.fillImage, SHRINK, { ImageColor3 = colour }):Play()
	end
end

-- Spins and bobs the models, grows them in and shrinks them as the ring
-- closes; keeps each glow in its item's colour (worked out in the
-- background, so it can arrive late).
local function animate(ring: Ring)
	local now = os.clock()
	for _, pad in ring.pads do
		if not ring.closingAt then
			updateGlow(pad)
		end
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
		TweenService:Create(pad.card, GROW, { Size = UDim2.fromScale(RING.cardSize, RING.cardSize * 1.2) }):Play()
		TweenService:Create(pad.ringImage, GROW, { Size = UDim2.fromScale(1, 1) }):Play()
		if not pad.item then
			-- Loading: the card breathes until its item arrives.
			local pulse = TweenService:Create(pad.thumb.Parent :: Frame, PULSE, { BackgroundTransparency = 0.6 })
			pad.pulse = pulse
			pulse:Play()
		end
	end)
end

local function fillPad(pad: Pad, item: Item, delay: number)
	pad.item = item
	ItemColour.classify(item) -- no yield; fills item.colour in the background
	TweenService:Create(pad.ringImage, SHRINK, { ImageTransparency = RING_IDLE }):Play()
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
		-- No name: the thumbnail fills a square card.
		pad.label.Visible = false
		pad.thumb.Position = UDim2.fromScale(0.5, 0.04)
		pad.thumb.Size = UDim2.fromScale(0.92, 0.92)
		-- A little pop as it fills.
		pad.card.Size = UDim2.fromScale(RING.cardSize * 0.85, RING.cardSize * 0.85)
		TweenService:Create(pad.card, GROW, { Size = UDim2.fromScale(RING.cardSize, RING.cardSize) }):Play()
		showModel(pad, item)
	end)
end

-- The dwell fill for a pad's progress (0..1): the ring fills with light
-- and burns brighter.
local function setDisc(pad: Pad, progress: number)
	local amount = math.clamp(progress, 0, 1)
	pad.fillImage.Size = UDim2.fromScale(amount, amount)
	if pad.item then
		pad.ringImage.ImageTransparency = RING_IDLE * (1 - amount)
	end
end

local function closeRing(ring: Ring)
	ring.closingAt = os.clock()
	for _, pad in ring.pads do
		if pad.pulse then
			pad.pulse:Cancel()
		end
		TweenService:Create(pad.card, SHRINK, { Size = UDim2.fromScale(0, 0) }):Play()
		TweenService:Create(pad.ringImage, SHRINK, { Size = UDim2.fromScale(0, 0) }):Play()
		TweenService:Create(pad.fillImage, SHRINK, { Size = UDim2.fromScale(0, 0) }):Play()
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
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			latest.current.onClose()
			return nil
		end

		local closed = false
		local trail: { Entry } = {}
		local shown: { [number]: boolean } = {} -- every id offered on this trail
		local ring: Ring? = nil
		local picked: Item? = nil -- the latest pick, until its outfit change lands
		trails += 1
		local trailId = trails
		local ringsShown, picks = 0, 0
		local closeReason = "tap"

		local function rootPosition(): Vector3?
			local current = player.Character
			local hrp = current and current:FindFirstChild("HumanoidRootPart") :: BasePart?
			return if hrp then hrp.Position else nil
		end

		-- Builds a ring for the trail's top entry round the player. `from`:
		-- the direction (flat) the back pad goes in.
		local function openRing(entry: Entry, from: Vector3?)
			local position = rootPosition()
			if not position then
				return
			end
			local folder = Instance.new("Folder")
			folder.Name = "RecommendationRing"
			folder.Parent = workspace
			local ignore: { Instance } = { folder }
			if player.Character then
				table.insert(ignore, player.Character)
			end
			local centre = groundBelow(position, ignore) or (position - Vector3.new(0, 3, 0))
			local current: Ring = { folder = folder, centre = centre, pads = {} }
			ring = current

			local step = 2 * math.pi / RING.count
			local start
			if entry.backItem and from and from.Magnitude > 0.01 then
				start = angleOf(from)
			else
				local camera = workspace.CurrentCamera
				local look = flat(if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1))
				start = if look.Magnitude > 0.01 then angleOf(look) else 0
			end
			local newPads: { Pad } = {}
			for index = 1, RING.count do
				local isBack = entry.backItem ~= nil and index == 1
				local spot = padPosition(centre, start + (index - 1) * step, ignore)
				if spot then
					local pad = makePad(spot, folder, isBack)
					table.insert(current.pads, pad)
					if isBack then
						fillPad(pad, entry.backItem :: Item, 0)
					else
						table.insert(newPads, pad)
					end
					growPad(pad, (index - 1) * 0.04)
				end
			end

			-- New items: the ones this entry already has (coming back to it),
			-- else from the recommender (yields; abandoned if the ring went).
			local depth = #trail
			local function fill(items: { Item }, reasons: { string }, revisit: boolean)
				ringsShown += 1
				local back = entry.backItem
				local params: { [string]: any } = {
					trail_id = trailId,
					depth = depth,
					basis_id = if back then back.id else 0,
					back_id = if back then back.id else 0,
					revisit = revisit,
				}
				for index, item in items do
					params["item_" .. index] = item.id
					params["reason_" .. index] = reasons[index]
				end
				report("rec_ring", params)
				for index, pad in newPads do
					local item = items[index]
					if item then
						pad.reason = reasons[index]
						pad.slot = index
						fillPad(pad, item, (index - 1) * 0.05)
					else
						pad.label.Text = "—"
					end
				end
			end
			if entry.items then
				fill(entry.items, entry.reasons or {}, true)
			else
				task.spawn(function()
					local worn = itemsFor(latest.current.wornIds)
					local basis = worn
					if entry.backItem then
						basis = { entry.backItem :: Item }
						if not table.find(latest.current.wornIds, (entry.backItem :: Item).id) then
							table.insert(worn, entry.backItem :: Item) -- the pick may not have landed yet
						end
					end
					local list = Recommender.recommend({
						basis = basis,
						worn = worn,
						exclude = shown,
						count = #newPads,
					})
					if ring ~= current or closed then
						return
					end
					local items, reasons = {}, {}
					for _, recommendation in list do
						table.insert(items, recommendation.item)
						table.insert(reasons, recommendation.reason)
						shown[recommendation.item.id] = true
					end
					entry.items = items
					entry.reasons = reasons
					fill(items, reasons, false)
				end)
			end

			-- The models move every frame, through the closing shrink too.
			local motion = RunService.RenderStepped:Connect(function()
				animate(current)
			end)
			folder.Destroying:Connect(function()
				motion:Disconnect()
			end)
		end

		local function replaceRing(entry: Entry, from: Vector3?)
			if ring then
				closeRing(ring)
				ring = nil
			end
			openRing(entry, from)
		end

		local function pick(pad: Pad)
			local item = pad.item :: Item
			local oldCentre = (ring :: Ring).centre
			Sounds.play("tryOn")
			Network.Intent.Avatar:FireServer(
				Network.Actions.Avatar.TryOn,
				{ targetId = item.targetId, kind = item.kind },
				{ replaceSameType = true }
			)
			picks += 1
			report("rec_pick", {
				trail_id = trailId,
				depth = #trail,
				item_id = item.id,
				reason = pad.reason or "fill",
				slot = pad.slot or 1,
			})
			picked = item
			local entry: Entry = { backItem = item }
			table.insert(trail, entry)
			local position = rootPosition() or pad.part.Position
			replaceRing(entry, flat(oldCentre - position))
		end

		local function goBack()
			local depth = #trail
			local entry = table.remove(trail) :: Entry
			-- Undo only if the outfit is still what that pick made it.
			local undone = entry.wornAfter ~= nil and entry.wornAfter == signature(latest.current.wornIds)
			if undone then
				Network.Intent.Avatar:FireServer(Network.Actions.Avatar.Undo)
			end
			report("rec_back", { trail_id = trailId, depth = depth, undone = undone })
			picked = nil
			Sounds.play("back")
			local camera = workspace.CurrentCamera
			local behind = flat(if camera then -camera.CFrame.LookVector else Vector3.new(0, 0, 1))
			replaceRing(trail[#trail], behind)
		end

		report("rec_open", { outfit_size = #latest.current.wornIds })
		table.insert(trail, {})
		openRing(trail[1], nil)
		Sounds.play("open")

		-- Standing on pads, the outfit change landing, walking away.
		local function selfClose(reason: string)
			if not closed then
				closeReason = reason
				latest.current.onClose()
			end
		end
		local watch = RunService.Heartbeat:Connect(function(dt: number)
			local current = player.Character
			local hrp = current and current:FindFirstChild("HumanoidRootPart") :: BasePart?
			if current ~= character or not hrp then
				selfClose("respawn")
				return
			end
			-- The latest pick's outfit, once the server has put it on.
			if picked and table.find(latest.current.wornIds, picked.id) then
				trail[#trail].wornAfter = signature(latest.current.wornIds)
				picked = nil
			end
			local active = ring
			if not active then
				return
			end
			local feet = flat(hrp.Position)
			if (feet - flat(active.centre)).Magnitude > RING.radius + RING.walkAway then
				selfClose("walk_away")
				return
			end
			for _, pad in active.pads do
				local on = pad.item ~= nil and (feet - flat(pad.part.Position)).Magnitude <= RING.padSize / 2
				pad.dwell = if on then pad.dwell + dt else math.max(0, pad.dwell - dt * 2)
				setDisc(pad, pad.dwell / RING.dwell)
				if pad.dwell >= RING.dwell then
					pad.dwell = 0
					if pad.back then
						goBack()
					else
						pick(pad)
					end
					return
				end
			end
		end)

		return function()
			closed = true
			watch:Disconnect()
			report("rec_close", {
				trail_id = trailId,
				depth = math.max(#trail, 1),
				rings = math.max(ringsShown, 1),
				picks = picks,
				reason = closeReason,
			})
			Sounds.play("close")
			if ring then
				closeRing(ring)
				ring = nil
			end
		end
	end, { props.open })

	return nil
end

return RecommendationRing
