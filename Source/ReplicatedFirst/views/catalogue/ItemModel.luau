--!strict

--[[
	ItemModel (client)

	A 3D model of a catalogue item on its own, for the item page's 3D view.
	The client can't load assets directly (InsertService is server-only), so
	it builds a throwaway avatar from a HumanoidDescription holding just the
	item (Players:CreateHumanoidModelFromDescription, ~0.3s) and lifts the
	item out of it:

	  accessories, hair, layered clothing     the item's own part(s)
	  shoes (bundle)                          the two shoe parts
	  heads (bundle)                          the head
	  classic shirt / T-shirt / pants, bodies the whole (plain) body — they're
	                                          textures / body parts, not objects

	Animations, emotes, backgrounds, gear and makeup (eyelashes, eyebrows,
	face/lip/eye makeup need a dynamic head to show at all) have no 3D view.

	  supports(item)   whether the item gets a 3D view
	  build(item)      a Model to clone (yields; cached per item); nil if it
	                   couldn't be built
	  restPose(model)  put an avatar's parts where its joints say, at rest
	                   (also used for the panel's avatar preview)
]]

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")

local ItemModel = {}

-- Rigid accessories: HumanoidDescription property per asset type.
local RIGID: { [string]: string } = {
	Hat = "HatAccessory",
	HairAccessory = "HairAccessory",
	FaceAccessory = "FaceAccessory",
	NeckAccessory = "NeckAccessory",
	ShoulderAccessory = "ShouldersAccessory", -- the property is plural
	FrontAccessory = "FrontAccessory",
	BackAccessory = "BackAccessory",
	WaistAccessory = "WaistAccessory",
}

-- Layered clothing: AccessoryType per asset type.
local LAYERED: { [string]: Enum.AccessoryType } = {
	ShirtAccessory = Enum.AccessoryType.Shirt,
	TShirtAccessory = Enum.AccessoryType.TShirt,
	SweaterAccessory = Enum.AccessoryType.Sweater,
	JacketAccessory = Enum.AccessoryType.Jacket,
	PantsAccessory = Enum.AccessoryType.Pants,
	ShortsAccessory = Enum.AccessoryType.Shorts,
	DressSkirtAccessory = Enum.AccessoryType.DressSkirt,
}

-- Classic clothing: HumanoidDescription property per asset type.
local CLASSIC: { [string]: string } = {
	Shirt = "Shirt",
	Pants = "Pants",
	TShirt = "GraphicTShirt",
}

-- What to keep from the built avatar.
type Keep = "accessories" | "head" | "body"

local BUNDLES: { [string]: Keep } = {
	Shoes = "accessories",
	DynamicHead = "head",
	DynamicHeadAvatar = "head",
	BodyParts = "body",
}

local cache: { [number]: Model | false } = {}

local function plan(item: any): (Keep?, ((HumanoidDescription) -> ())?)
	local typeName = item.typeName
	if item.kind == "Bundle" then
		return BUNDLES[typeName], nil
	elseif RIGID[typeName] then
		return "accessories", function(d)
			(d :: any)[RIGID[typeName]] = tostring(item.targetId)
		end
	elseif LAYERED[typeName] then
		return "accessories", function(d)
			d:SetAccessories({ { AssetId = item.targetId, AccessoryType = LAYERED[typeName], IsLayered = true, Order = 1 } }, true)
		end
	elseif CLASSIC[typeName] then
		return "body", function(d)
			(d :: any)[CLASSIC[typeName]] = item.targetId
		end
	end
	return nil, nil
end

function ItemModel.supports(item: any): boolean
	if item.thumbnail == "" then
		return false -- mock items
	end
	return (plan(item)) ~= nil
end

local function descriptionFor(item: any, fill: ((HumanoidDescription) -> ())?): HumanoidDescription
	if item.kind == "Bundle" then
		-- A bundle's UserOutfit item is its whole look.
		local info = AssetService:GetBundleDetailsAsync(item.targetId)
		for _, entry in info.Items do
			if entry.Type == "UserOutfit" then
				return Players:GetHumanoidDescriptionFromOutfitId(entry.Id)
			end
		end
		error("bundle has no outfit")
	end
	local description = Instance.new("HumanoidDescription")
	if fill then
		fill(description)
	end
	return description
end

-- Parts copied out of the avatar into a loose, anchored model.
local function loose(parts: { BasePart }): Model
	local model = Instance.new("Model")
	for _, part in parts do
		local copy = part:Clone()
		for _, child in copy:GetDescendants() do
			if child:IsA("JointInstance") or child:IsA("WeldConstraint") or child:IsA("Attachment") then
				child:Destroy()
			end
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.Parent = model
	end
	return model
end

-- Puts every part where its joints say it goes, working out from the root.
-- Nothing simulates in a ViewportFrame, and the builder can place parts
-- before their final meshes (and rig attachments) arrive, so a body can come
-- out with a head off to one side or a leg adrift — differently each build.
--
-- Joints come in two kinds, solved at rest pose:
--   attachment joints (AnimationConstraint, RigidConstraint — current rigs
--   and accessories): part1 = attachment0.WorldCFrame * attachment1.CFrame⁻¹
--   classic joints (enabled Motor6D / Weld): part1 = part0 * C0 * C1⁻¹
-- A part takes the first joint that reaches it from an already-placed part;
-- attachment joints are tried before classic ones, whose offsets can be stale.
type Edge = { a: BasePart, b: BasePart, place: (fromA: boolean) -> () }

local function edgesOf(avatar: Model): { Edge }
	local attachmentEdges, classicEdges = {}, {}
	for _, d in avatar:GetDescendants() do
		if d:IsA("AnimationConstraint") or d:IsA("RigidConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if a0 and a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				table.insert(attachmentEdges, {
					a = p0,
					b = p1,
					place = function(fromA: boolean)
						if fromA then
							p1.CFrame = a0.WorldCFrame * a1.CFrame:Inverse()
						else
							p0.CFrame = a1.WorldCFrame * a0.CFrame:Inverse()
						end
					end,
				})
			end
		elseif
			(d:IsA("Motor6D") or d:IsA("Weld"))
			and d.Enabled
			and d.Part0
			and d.Part1
			and not d:FindFirstAncestorWhichIsA("Accessory") -- see attachAccessories
		then
			local joint = d
			local p0, p1 = joint.Part0 :: BasePart, joint.Part1 :: BasePart
			table.insert(classicEdges, {
				a = p0,
				b = p1,
				place = function(fromA: boolean)
					if fromA then
						p1.CFrame = p0.CFrame * joint.C0 * joint.C1:Inverse()
					else
						p0.CFrame = p1.CFrame * joint.C1 * joint.C0:Inverse()
					end
				end,
			})
		end
	end
	for _, edge in classicEdges do
		table.insert(attachmentEdges, edge)
	end
	return attachmentEdges
end

-- Accessories go on the way Roblox attaches them: the Handle's attachment
-- meets the body attachment of the same name (HairAttachment, …). Their
-- welds in a freshly built model carry stale offsets, so they're ignored.
local function attachAccessories(avatar: Model)
	local bodyAttachments: { [string]: Attachment } = {}
	for _, part in avatar:GetChildren() do
		if part:IsA("BasePart") then
			for _, child in part:GetChildren() do
				if child:IsA("Attachment") then
					bodyAttachments[child.Name] = child
				end
			end
		end
	end
	for _, accessory in avatar:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			for _, child in handle:GetChildren() do
				local target = child:IsA("Attachment") and bodyAttachments[child.Name]
				if target then
					handle.CFrame = target.WorldCFrame * (child :: Attachment).CFrame:Inverse()
					break
				end
			end
		end
	end
end

local function solveJoints(avatar: Model)
	local root = avatar:FindFirstChild("HumanoidRootPart") or avatar.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		return
	end
	local edges = edgesOf(avatar)
	local placed: { [BasePart]: boolean } = { [root] = true }
	local progress = true
	while progress do
		progress = false
		for _, edge in edges do
			if placed[edge.a] and not placed[edge.b] then
				edge.place(true)
				placed[edge.b] = true
				progress = true
			elseif placed[edge.b] and not placed[edge.a] then
				edge.place(false)
				placed[edge.a] = true
				progress = true
			end
		end
	end
	attachAccessories(avatar)
end

function ItemModel.restPose(avatar: Model)
	solveJoints(avatar)
end

local function extract(avatar: Model, keep: Keep): Model?
	if keep == "body" then
		solveJoints(avatar)
		for _, child in avatar:GetChildren() do
			if child:IsA("Humanoid") then
				child.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			elseif child:IsA("Script") or child:IsA("LocalScript") then
				child:Destroy()
			elseif child:IsA("BasePart") then
				child.Anchored = true
			end
		end
		return avatar
	elseif keep == "head" then
		local head = avatar:FindFirstChild("Head")
		return if head and head:IsA("BasePart") then loose({ head }) else nil
	end
	local handles = {}
	for _, child in avatar:GetChildren() do
		local handle = child:IsA("Accessory") and child:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			table.insert(handles, handle)
		end
	end
	return if #handles > 0 then loose(handles) else nil
end

-- Yields. Returns a model to clone, or nil.
function ItemModel.build(item: any): Model?
	local cached = cache[item.id]
	if cached ~= nil then
		return cached or nil
	end
	local keep, fill = plan(item)
	if not keep then
		return nil
	end
	local ok, result = pcall(function()
		local avatar = Players:CreateHumanoidModelFromDescription(descriptionFor(item, fill), Enum.HumanoidRigType.R15)
		local model = extract(avatar, keep)
		if model ~= avatar then
			avatar:Destroy()
		end
		return model
	end)
	if not ok then
		warn(`[ItemModel] {item.name}: {result}`)
	end
	local model = if ok then result else nil
	cache[item.id] = model or false
	return model
end

return ItemModel
