--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Maid = require(ReplicatedStorage.Shared.Maid)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)

local FLY_SPEED = 40
local DETECT_FILL = Color3.fromRGB(120, 255, 140)
local VISION_FADE = 0.4

local player = Players.LocalPlayer

--[=[
	Client side of the dev skills (docs/systems/dev-tools.md): flies the character while the
	server-set `Flying` attribute is on, and highlights Detect Life results for this player only.
]=]
local DevSpellController = {}

local flight = Maid.new()
local vision: ColorCorrectionEffect? = nil

local function vertical(): number
	local up = if UserInputService:IsKeyDown(Enum.KeyCode.Space) then 1 else 0
	local down = if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then 1 else 0
	return up - down
end

local function stopFlying()
	flight:Clean()
end

local function startFlying(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlyAttachment"
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "FlyVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	attachment.Parent = root
	velocity.Parent = root
	flight:Give(attachment)
	flight:Give(velocity)
	flight:Give(RunService.RenderStepped:Connect(function()
		velocity.VectorVelocity = (humanoid.MoveDirection + Vector3.new(0, vertical(), 0)) * FLY_SPEED
	end))
end

-- Night vision lifts the dark for this player only. The effect lives under the camera so it never
-- mixes with the atmosphere's own ColorCorrection in Lighting.
local function setNightVision(on: boolean)
	local camera = workspace.CurrentCamera
	if on and not vision and camera then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "NightVision"
		effect.Brightness = 0
		effect.Contrast = 0
		effect.Saturation = 0
		effect.TintColor = Color3.new(1, 1, 1)
		effect.Parent = camera
		TweenService:Create(effect, TweenInfo.new(VISION_FADE), {
			Brightness = 0.28,
			Contrast = 0.12,
			Saturation = -0.35,
			TintColor = Color3.fromRGB(170, 255, 190),
		}):Play()
		vision = effect
	elseif not on and vision then
		local effect = vision
		vision = nil
		local fade = TweenService:Create(effect, TweenInfo.new(VISION_FADE), {
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
			TintColor = Color3.new(1, 1, 1),
		})
		fade.Completed:Once(function()
			effect:Destroy()
		end)
		fade:Play()
	end
end

local function watchCharacter(character: Model)
	stopFlying()
	local function update()
		stopFlying()
		if character:GetAttribute("Flying") == true then
			startFlying(character)
		end
	end
	character:GetAttributeChangedSignal("Flying"):Connect(update)
	character:GetAttributeChangedSignal("NightVision"):Connect(function()
		setNightVision(character:GetAttribute("NightVision") == true)
	end)
	setNightVision(character:GetAttribute("NightVision") == true)
	update()
end

local function showDetected(models: { Model }, seconds: number)
	for _, model in models do
		if typeof(model) == "Instance" and model:IsA("Model") then
			local highlight = Instance.new("Highlight")
			highlight.Name = "DetectLife"
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = DETECT_FILL
			highlight.FillTransparency = 0.7
			highlight.OutlineColor = DETECT_FILL
			highlight.Adornee = model
			highlight.Parent = model
			task.delay(seconds, function()
				highlight:Destroy()
			end)
		end
	end
end

function DevSpellController.Init(_deps: { [string]: any }) end

function DevSpellController.Start()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	NetClient.Connect("ShowDetectedLife", showDetected)
end

return DevSpellController
