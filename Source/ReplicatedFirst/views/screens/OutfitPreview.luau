--!strict

--[[
	OutfitPreview (outfit page: your avatar wearing a saved outfit)

	Asks the server for the outfit's look over the "OutfitPreview" remote
	function: the server builds it with the same code that dresses characters
	(so bodies, heads and bundles come out right) and parents the
	HumanoidDescription into this player's PlayerGui, returning its name.
	Here a rig is built from it (Players:CreateHumanoidModelFromDescription),
	posed at rest and shown in a ModelViewer playing its idle animation.
	Drag to turn, wheel to zoom, middle-drag to move.

	Props:
		kind: "saved" | "own" | "roblox"   a saved outfit, your own Roblox
		                       avatar, or an outfit saved on Roblox
		outfitId: number?      the saved / Roblox outfit's id
		ring: boolean?         the orange "you're wearing this" ring
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local Bolt = require(ReplicatedStorage:WaitForChild("Bolt"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local ModelViewer = require(views:WaitForChild("components"):WaitForChild("ModelViewer"))
local ItemModel = require(views:WaitForChild("catalogue"):WaitForChild("ItemModel"))

local e = React.createElement

local remote = Bolt.RemoteFunction("OutfitPreview")
local PREVIEW_FOLDER = "OutfitPreviews"
local WAIT_SECONDS = 10

-- The rig for an outfit and its idle animation id (yields); nil if it fails.
local function build(kind: string, outfitId: number?): (Model?, string?)
	local ok, name = pcall(function()
		return remote:InvokeServer(kind, outfitId)
	end)
	if not ok or type(name) ~= "string" then
		return nil, nil
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local folder = gui:WaitForChild(PREVIEW_FOLDER, WAIT_SECONDS)
	local description = folder and folder:WaitForChild(name, WAIT_SECONDS)
	if not description or not description:IsA("HumanoidDescription") then
		return nil, nil
	end
	local built, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description:Clone(), Enum.HumanoidRigType.R15)
	end)
	if not built or not model then
		return nil, nil
	end
	-- The idle animation (a worn animation pack shows), read before the
	-- rig's scripts go.
	local idle: string? = nil
	local animate = model:FindFirstChild("Animate")
	local idleFolder = animate and animate:FindFirstChild("idle")
	local animation = idleFolder and idleFolder:FindFirstChildWhichIsA("Animation")
	if animation then
		idle = animation.AnimationId
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	ItemModel.restPose(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant.Name == "HumanoidRootPart"
			descendant.CanCollide = false
		end
	end
	model:PivotTo(CFrame.new()) -- facing -Z: the viewer's yaw 180 is the front
	return model, idle
end

local function OutfitPreview(props: { kind: string, outfitId: number?, ring: boolean? })
	local skin = useSkin()
	local model, setModel = React.useState(nil :: Model?)
	local idleIds = React.useRef({} :: { [Model]: string })

	-- Loop the idle animation on the built rig.
	React.useEffect(function()
		local id = model and idleIds.current[model]
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if not id or not animator then
			return nil
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or not track then
			return nil
		end
		track.Looped = true
		track:Play()
		return function()
			track:Stop(0)
			track:Destroy()
		end
	end, { model })

	return e("Frame", {
		Name = "OutfitPreview",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Viewer = e(ModelViewer, {
			onModel = setModel,
			buildKey = props.kind .. ":" .. tostring(props.outfitId),
			build = function()
				local rig, idle = build(props.kind, props.outfitId)
				if rig and idle then
					idleIds.current[rig] = idle
				end
				return rig
			end,
			autoSpin = false,
			yaw = 180 - 20,
			pitch = -8,
			fill = 0.9,
			backgroundColor = Color3.fromHex("#141414"),
			cornerRadius = 20,
			failedText = "Couldn't load this outfit",
		}),
		-- Drawn over the viewer, which clips its own children.
		Ring = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(20)) }),
			Stroke = e("UIStroke", {
				Color = if props.ring then Tokens.color.accent else Tokens.color.white,
				Transparency = if props.ring then 0 else 0.88,
				Thickness = skin.stroke(if props.ring then 2 else 1),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
	})
end

return OutfitPreview
