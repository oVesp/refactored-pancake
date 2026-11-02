--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Signal = require(ReplicatedStorage.Shared.Signal)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local templates = ReplicatedStorage:WaitForChild("UiTemplates", Constants.ClientWaitTimeout) :: Folder
local rigs = ReplicatedStorage:WaitForChild("UiRigs", Constants.ClientWaitTimeout) :: Folder

local CAMERA_IN = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CAMERA_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DEFAULT_SCREEN_FILL = 0.8
local VIEW_STEP = "UIControllerWorldView"
local HOLD_ACTION = "UIControllerWorldHold"

--[=[
	Owns Studio-authored screens and templates (game-design.md 6.2). Opens one modal at a time,
	wires close buttons and gamepad focus. Nothing builds UI in code: rows are template clones.

	A screen with a rig in `ReplicatedStorage.UiRigs` opens in the world (docs/art/ui-style.md,
	Floating UI): the camera goes first person at the character's head, its `Window` frame moves
	into the `WorldPanel` SurfaceGui on a copy of the rig's `Panel` part standing in front of it,
	and movement and world prompts are off until it closes. The rig's `Root` maps to the head,
	facing the camera's view (or the target, when the screen is opened at one); `Panel` gives the
	direction and size of the panel. It is placed as far away as makes it fill `ScreenFill` of the
	view (default 0.8), so text keeps the same size on every screen; `PixelsPerStud` overrides the
	canvas density.
]=]
local UIController = {}

--[=[ Fires `(screenName, isOpen)` when a modal opens or closes. ]=]
UIController.ModalChanged = Signal.new() :: Signal.Signal<string, boolean>

local openModal: ScreenGui? = nil
-- A locked modal stays open: no other modal opens and it cannot be closed until unlocked.
local lockedModal: string? = nil
local switching = false

type WorldView = {
	screen: ScreenGui,
	window: GuiObject,
	size: UDim2,
	position: UDim2,
	anchor: Vector2,
	surface: SurfaceGui,
	anchorPart: BasePart,
}

type SavedCamera = {
	cameraType: Enum.CameraType,
	cframe: CFrame,
}

local world: WorldView? = nil
-- Camera state from before the first world screen opened; kept while switching between screens.
local savedCamera: SavedCamera? = nil
local MOVE_INPUTS: { Enum.KeyCode } = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
}

-- Movement is held by sinking its keys above the character controls, and the touch thumbstick is hidden.
-- Gamepad sticks and A are left alone: while a menu button is selected they drive GUI navigation.
local function holdMovement(hold: boolean)
	if hold then
		ContextActionService:BindActionAtPriority(HOLD_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(MOVE_INPUTS))
	else
		ContextActionService:UnbindAction(HOLD_ACTION)
	end
	GuiService.TouchControlsEnabled = not hold
	ProximityPromptService.Enabled = not hold
end

local function flatLook(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else nil
end

-- Turns the character to face the camera's view (or the target) and returns the head frame.
local function rigBasis(root: BasePart, eye: Vector3, target: PVInstance?): CFrame?
	local look = flatLook(
		if target then target:GetPivot().Position - root.Position else workspace.CurrentCamera.CFrame.LookVector
	)
	if not look then
		return nil
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	return CFrame.lookAt(eye, eye + look)
end

-- Distance at which a panel of `size` studs fills `fill` of the view in both directions.
local function fillDistance(camera: Camera, size: Vector3, fill: number): number
	local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
	local viewport = camera.ViewportSize
	local tanX = tanY * viewport.X / math.max(viewport.Y, 1)
	return math.max(size.Y / (2 * tanY * fill), size.X / (2 * tanX * fill))
end

-- First person: the character's own parts would cover the panel.
local function hideCharacter(character: Model, hidden: boolean)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function rigPart(rig: Instance, name: string): BasePart
	local part = rig:FindFirstChild(name)
	assert(part and part:IsA("BasePart"), `UiRigs.{rig.Name} needs a {name} part`)
	return part
end

local function closeInWorld(screen: ScreenGui)
	local view = world
	if not view or view.screen ~= screen then
		return
	end
	world = nil
	view.window.Parent = screen
	view.window.Size = view.size
	view.window.Position = view.position
	view.window.AnchorPoint = view.anchor
	view.surface:Destroy()
	view.anchorPart:Destroy()
end

local function openInWorld(screen: ScreenGui, target: PVInstance?)
	local stale = world
	if stale then
		closeInWorld(stale.screen)
	end
	local rig = rigs:FindFirstChild(screen.Name)
	local window = screen:FindFirstChild("Window")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (rig and window and window:IsA("GuiObject") and character and root and root:IsA("BasePart")) then
		return
	end
	local head = character:FindFirstChild("Head")
	local eye = if head and head:IsA("BasePart") then head.Position else root.Position
	local rigRoot = rigPart(rig, "Root").CFrame
	local rigPanel = rigPart(rig, "Panel")
	local basis = rigBasis(root, eye, target)
	if not basis then
		return
	end

	local camera = workspace.CurrentCamera
	local fill = rigPanel:GetAttribute("ScreenFill")
	local distance = fillDistance(camera, rigPanel.Size, if type(fill) == "number" then fill else DEFAULT_SCREEN_FILL)
	local direction = basis:VectorToWorldSpace(rigRoot:PointToObjectSpace(rigPanel.Position)).Unit
	local panelAt = eye + direction * distance
	local anchorPart = rigPanel:Clone()
	anchorPart.Name = `WorldPanel_{screen.Name}`
	-- Square to the view (not turned to the eye) so off-centre panels are not keystoned.
	anchorPart.CFrame = CFrame.lookAt(panelAt, panelAt - basis.LookVector)
	anchorPart.Parent = camera

	local surface = UIController.Clone("WorldPanel") :: SurfaceGui
	surface.Name = `WorldPanel_{screen.Name}`
	surface.Adornee = anchorPart
	local pixelsPerStud = rigPanel:GetAttribute("PixelsPerStud")
	if type(pixelsPerStud) == "number" then
		surface.PixelsPerStud = pixelsPerStud
	end
	surface.Parent = playerGui

	world = {
		screen = screen,
		window = window,
		size = window.Size,
		position = window.Position,
		anchor = window.AnchorPoint,
		surface = surface,
		anchorPart = anchorPart,
	}
	if not savedCamera then
		savedCamera = { cameraType = camera.CameraType, cframe = camera.CFrame }
	end
	window.Size = UDim2.fromScale(1, 1)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Parent = surface

	camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(camera, CAMERA_IN, { CFrame = basis }):Play()

	holdMovement(true)
	RunService:UnbindFromRenderStep(VIEW_STEP)
	RunService:BindToRenderStep(VIEW_STEP, Enum.RenderPriority.Camera.Value + 1, function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		hideCharacter(character, true)
	end)
end

-- Gives the camera and movement back once no world screen is open.
local function restoreCamera()
	local saved = savedCamera
	if world or not saved then
		return
	end
	savedCamera = nil
	RunService:UnbindFromRenderStep(VIEW_STEP)
	holdMovement(false)
	local character = player.Character
	if character then
		hideCharacter(character, false)
	end
	local camera = workspace.CurrentCamera
	local tween = TweenService:Create(camera, CAMERA_OUT, { CFrame = saved.cframe })
	tween.Completed:Connect(function()
		if world == nil then
			camera.CameraType = saved.cameraType
		end
	end)
	tween:Play()
end

--[=[ Returns a screen from PlayerGui, waiting for it to replicate. Errors if it never appears. ]=]
function UIController.GetScreen(name: string): ScreenGui
	local screen = playerGui:WaitForChild(name, Constants.ClientWaitTimeout)
	assert(screen and screen:IsA("ScreenGui"), `Screen {name} is missing from StarterGui`)
	return screen
end

--[=[
	Finds every named binding (`Bind_` prefix) under a root. Errors loudly listing all missing
	names, so a renamed instance in Studio breaks at startup rather than at runtime.
]=]
function UIController.Bind(root: Instance, names: { string }): { [string]: GuiObject }
	local found: { [string]: GuiObject } = {}
	local missing: { string } = {}
	for _, name in names do
		assert(string.sub(name, 1, 5) == "Bind_", `Binding {name} must use the Bind_ prefix`)
		local instance = root:FindFirstChild(name, true)
		if instance and instance:IsA("GuiObject") then
			found[name] = instance
		else
			table.insert(missing, name)
		end
	end
	assert(#missing == 0, `{root.Name} is missing bindings: {table.concat(missing, ", ")}`)
	return found
end

--[=[ Clones a template from ReplicatedStorage.UiTemplates. Errors if it does not exist. ]=]
function UIController.Clone(name: string): Instance
	local template = templates:FindFirstChild(name)
	assert(template, `UI template {name} is missing`)
	return template:Clone()
end

--[=[ Sets the text of a bound TextLabel or TextButton. Errors on any other class. ]=]
function UIController.SetText(target: GuiObject, text: string)
	assert(target:IsA("TextLabel") or target:IsA("TextButton"), `{target:GetFullName()} has no text`)
	local label = target :: TextLabel
	label.Text = text
end

--[=[ Destroys every GuiObject child of a container (keeps layouts and padding). ]=]
function UIController.ClearRows(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function firstButton(root: Instance): GuiObject?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant.Visible then
			return descendant
		end
	end
	return nil
end

--[=[
	Opens a modal screen, closing any other modal first. A screen with a rig opens in the world;
	`target` anchors the rig at that object instead of the character.
]=]
function UIController.Open(name: string, target: PVInstance?)
	if lockedModal and lockedModal ~= name then
		return
	end
	local screen = UIController.GetScreen(name)
	if openModal and openModal ~= screen then
		switching = true
		UIController.Close(openModal.Name)
		switching = false
	end
	if openModal ~= screen then
		openInWorld(screen, target)
		restoreCamera()
	end
	screen.Enabled = true
	openModal = screen
	if GuiService:IsTenFootInterface() or GuiService.SelectedObject ~= nil then
		local view = world
		GuiService.SelectedObject = firstButton(if view then view.window else screen)
	end
	UIController.ModalChanged:Fire(name, true)
end

--[=[ Closes a modal screen if open. ]=]
function UIController.Close(name: string)
	if lockedModal == name then
		return
	end
	local screen = UIController.GetScreen(name)
	local view = world
	if not screen.Enabled and not (view and view.screen == screen) then
		return
	end
	screen.Enabled = false
	closeInWorld(screen)
	if not switching then
		restoreCamera()
	end
	if openModal == screen then
		openModal = nil
		GuiService.SelectedObject = nil
	end
	UIController.ModalChanged:Fire(name, false)
end

--[=[ Toggles a modal screen. ]=]
function UIController.Toggle(name: string)
	if UIController.GetScreen(name).Enabled then
		UIController.Close(name)
	else
		UIController.Open(name)
	end
end

--[=[ Closes whichever modal is open. Returns true if one was. ]=]
function UIController.CloseTop(): boolean
	if openModal and lockedModal ~= openModal.Name then
		UIController.Close(openModal.Name)
		return true
	end
	return false
end

--[=[
	Locks a modal (the character creator): while locked, other modals do not open and this one
	ignores close requests. Pass nil to unlock.
]=]
function UIController.SetLocked(name: string?)
	lockedModal = name
end

--[=[ True while a screen is open in the world, holding the camera and movement. ]=]
function UIController.IsWorldOpen(): boolean
	return world ~= nil
end

--[=[ Wires a modal's `Bind_Close` button. ]=]
function UIController.BindClose(name: string)
	local screen = UIController.GetScreen(name)
	local close = UIController.Bind(screen, { "Bind_Close" }).Bind_Close
	assert(close:IsA("GuiButton"), `{name}.Bind_Close must be a button`)
	close.Activated:Connect(function()
		UIController.Close(name)
	end)
end

function UIController.Init(_deps: { [string]: any }) end

function UIController.Start()
	player.CharacterRemoving:Connect(function()
		UIController.CloseTop()
	end)
end

return UIController
