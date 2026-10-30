--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local STEP_NAME = "ShoulderCamera"
-- Over-the-shoulder offset (studs, camera space) in combat and while aiming the bow.
local SHOULDER_OFFSET = Vector3.new(1.75, 0.5, 0)
local AIM_OFFSET = Vector3.new(2, 0.6, 0)
local AIM_FOV = 55
-- Blend speed toward the target offset and field of view (about 0.2 s to settle).
local BLEND_RATE = 15

local player = Players.LocalPlayer

-- Humanoid states where the character must not be turned to the camera.
local NO_TURN_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
}

--[=[
	Combat camera (docs/systems/combat.md, Camera): shift lock is always on, third person over the
	right shoulder. The cursor stays locked at the screen centre, the character faces where the
	camera looks, and every attack aims through the screen centre. Any open modal, a world menu or
	the Roblox menu releases the lock until it closes. Touch and gamepad keep the same framing.
]=]
local CameraController = {}

local UIController: any

local modalOpen = false
local aiming = false
local released = false
local baseFov: number? = nil

local function shouldRelease(): boolean
	return modalOpen or UIController.IsWorldOpen() or GuiService.MenuIsOpen
end

local function blend(dt: number): number
	return 1 - math.exp(-BLEND_RATE * dt)
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not humanoid then
		return
	end
	local fov = baseFov or camera.FieldOfView
	baseFov = fov

	released = shouldRelease()
	local offset = if released then Vector3.zero elseif aiming then AIM_OFFSET else SHOULDER_OFFSET
	local targetFov = if aiming and not released then AIM_FOV else fov
	local alpha = blend(dt)
	if (humanoid.CameraOffset - offset).Magnitude > 1e-3 then
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(offset, alpha)
	end
	if math.abs(camera.FieldOfView - targetFov) > 1e-2 then
		camera.FieldOfView += (targetFov - camera.FieldOfView) * alpha
	end

	if released then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		humanoid.AutoRotate = true
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	humanoid.AutoRotate = false
	if not root or not root:IsA("BasePart") or root.Anchored or NO_TURN_STATES[humanoid:GetState()] then
		return
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end
end

--[=[ Narrows the view and pushes the camera further over the shoulder while the bow is drawn. ]=]
function CameraController.SetAiming(on: boolean)
	aiming = on
end

--[=[ True while the shift lock is on (no menu holds the cursor). ]=]
function CameraController.IsLocked(): boolean
	return not released
end

function CameraController.Init(deps: { [string]: any })
	UIController = deps.UIController
end

function CameraController.Start()
	-- One modal at a time: switching closes the old one before the new one opens.
	UIController.ModalChanged:Connect(function(_, isOpen: boolean)
		modalOpen = isOpen
	end)
	player.CharacterAdded:Connect(function()
		aiming = false
	end)
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
