--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Shared.Signal)

local STEP_NAME = "ShoulderCamera"
-- Over-the-shoulder offset (studs, camera space) in combat, while locked on and while aiming the bow.
local SHOULDER_OFFSET = Vector3.new(1.75, 0.5, 0)
local AIM_OFFSET = Vector3.new(2, 0.6, 0)
local AIM_FOV = 55
-- Blend speed toward the target offset and field of view (about 0.2 s to settle).
local BLEND_RATE = 15
-- Blend speed of the lock-on framing, and the pitch range it keeps (look vector Y).
local LOCK_BLEND_RATE = 8
local LOCK_PITCH_MIN = -0.5
local LOCK_PITCH_MAX = 0.15

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
	Camera modes (docs/systems/combat.md, Camera). Exploration (the default) is the normal Roblox
	camera. Combat mode, toggled by the player, is shift lock over the right shoulder: the cursor
	stays at the screen centre and the character faces where the camera looks. A hard target lock
	frames the target in either mode (camera and character turn toward it) until it is released.
	Drawing the bow narrows the view. An open modal, a world menu or the Roblox menu releases all
	of it until it closes.
]=]
local CameraController = {}

--[=[ Fires `(inCombat)` when the player switches between combat and exploration mode. ]=]
CameraController.Changed = Signal.new() :: Signal.Signal<boolean>

local UIController: any
local TargetController: any

local combat = false
local modalOpen = false
local aiming = false
local cursorLocked = false
local cursorFree = false
local turning = false
local baseFov: number? = nil

local function menuOpen(): boolean
	return modalOpen or UIController.IsWorldOpen() or GuiService.MenuIsOpen
end

local function lockedRoot(): BasePart?
	if not TargetController.IsLocked() then
		return nil
	end
	local model = TargetController.Enemy()
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	return if root and root:IsA("BasePart") then root else nil
end

-- Turns the camera around its focus toward the locked target, keeping its zoom.
local function frameTarget(camera: Camera, target: BasePart, alpha: number)
	local focus = camera.Focus.Position
	local current = camera.CFrame
	local toTarget = target.Position - focus
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local pitch = math.clamp(toTarget.Unit.Y, LOCK_PITCH_MIN, LOCK_PITCH_MAX)
	local look = flat.Unit * math.sqrt(1 - pitch * pitch) + Vector3.new(0, pitch, 0)
	local blended = current.LookVector:Lerp(look, alpha)
	if blended.Magnitude < 1e-3 then
		return
	end
	local distance = (current.Position - focus).Magnitude
	camera.CFrame = CFrame.lookAt(focus - blended.Unit * distance, focus)
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

	local menu = menuOpen()
	local target = if menu then nil else lockedRoot()
	local offset = if menu
		then Vector3.zero
		elseif aiming then AIM_OFFSET
		elseif combat or target then SHOULDER_OFFSET
		else Vector3.zero
	local targetFov = if aiming and not menu then AIM_FOV else fov
	local alpha = 1 - math.exp(-BLEND_RATE * dt)
	if (humanoid.CameraOffset - offset).Magnitude > 1e-3 then
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(offset, alpha)
	end
	if math.abs(camera.FieldOfView - targetFov) > 1e-2 then
		camera.FieldOfView += (targetFov - camera.FieldOfView) * alpha
	end

	-- Only the transitions touch the cursor and AutoRotate, so exploration keeps Roblox's own camera.
	local lockCursor = combat and not menu and not cursorFree
	if lockCursor then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	elseif cursorLocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	cursorLocked = lockCursor

	local turn = not menu and (combat or aiming or target ~= nil)
	if not turn then
		if turning then
			humanoid.AutoRotate = true
		end
		turning = false
		return
	end
	turning = true
	humanoid.AutoRotate = false
	if target then
		frameTarget(camera, target, 1 - math.exp(-LOCK_BLEND_RATE * dt))
	end
	if not root or not root:IsA("BasePart") or root.Anchored or NO_TURN_STATES[humanoid:GetState()] then
		return
	end
	local look = if target then target.Position - root.Position else camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end
end

--[=[ Switches between combat mode (shift lock over the shoulder) and exploration mode. ]=]
function CameraController.SetCombat(on: boolean)
	if combat ~= on then
		combat = on
		CameraController.Changed:Fire(on)
	end
end

--[=[ Flips between combat and exploration mode. ]=]
function CameraController.ToggleCombat()
	CameraController.SetCombat(not combat)
end

--[=[ True in combat mode. ]=]
function CameraController.InCombat(): boolean
	return combat
end

--[=[ Narrows the view and pushes the camera further over the shoulder while the bow is drawn. ]=]
function CameraController.SetAiming(on: boolean)
	aiming = on
end

--[=[ Frees the combat cursor while a small HUD choice is open (the summon picker). ]=]
function CameraController.SetCursorFree(on: boolean)
	cursorFree = on
end

function CameraController.Init(deps: { [string]: any })
	UIController = deps.UIController
	TargetController = deps.TargetController
end

function CameraController.Start()
	-- One modal at a time: switching closes the old one before the new one opens.
	UIController.ModalChanged:Connect(function(_, isOpen: boolean)
		modalOpen = isOpen
	end)
	player.CharacterAdded:Connect(function()
		aiming = false
		turning = false
	end)
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
