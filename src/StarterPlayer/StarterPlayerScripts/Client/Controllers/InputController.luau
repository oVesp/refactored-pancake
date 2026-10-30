--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Disciplines = require(ReplicatedStorage.Content.Disciplines)
local Gait = require(ReplicatedStorage.Shared.Gait)
local Tuning = require(ReplicatedStorage.Content.Tuning)

local HOTBAR_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
}
local TOUCH_SLOTS = 4

--[=[
	Input bindings through ContextActionService (remappable later, gamepad and touch buttons
	included). Mouse 1 / R1 = light attack, Mouse 2 (combat mode) / R2 = heavy; with a bow, holding
	heavy aims and draws and light shoots; while guarding with a shield, light bashes. Tab / R3 / Target button cycle the target lock. Left Alt /
	D-pad up / the Combat button toggle combat mode (CameraController).
	Double-tap W runs until W is released or the character stops moving.
	Screens: B spellbook, I inventory, C sheet, F2 debug.
]=]
local InputController = {}

local CombatController: any
local TargetController: any
local CameraController: any
local UIController: any

local gait = Gait.new()
local sentRunning = false

local function syncRunning()
	if sentRunning ~= gait.running then
		sentRunning = gait.running
		CombatController.SetRun(gait.running)
	end
end

-- W stays a movement key, so this listens beside the default controls instead of binding it.
local function onForwardInput(input: InputObject, processed: boolean)
	if input.KeyCode ~= Enum.KeyCode.W then
		return
	end
	if input.UserInputState == Enum.UserInputState.Begin then
		Gait.ForwardBegan(gait, processed, os.clock(), Tuning.Base.Run.DoubleTapWindow)
	elseif input.UserInputState == Enum.UserInputState.End then
		Gait.ForwardEnded(gait)
	end
	syncRunning()
end

local function stopWhenIdle()
	if not gait.running then
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		Gait.Step(gait, true, humanoid.Health, humanoid.MoveDirection.Magnitude)
	else
		Gait.Step(gait, false, 0, 0)
	end
	syncRunning()
end

local function sink(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function onAttack(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if UIController.IsWorldOpen() then
		-- Clicks belong to the floating menu while one holds the camera.
		CombatController.CancelDraw()
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		if CombatController.DrawIfSheathed() then
			return sink()
		end
		if CombatController.Weapon().drawn then
			CombatController.ReleaseDraw()
		else
			CombatController.Attack(false)
		end
	elseif state == Enum.UserInputState.Cancel then
		CombatController.CancelDraw()
	end
	return sink()
end

-- Heavy attack (bow: hold to aim and draw). Mouse 2 rotates the exploration camera, so it only
-- belongs to combat mode; the pad trigger and touch button work in both.
local function onHeavy(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if UIController.IsWorldOpen() then
		CombatController.CancelDraw()
		return Enum.ContextActionResult.Pass
	end
	local drawn = CombatController.Weapon().drawn
	if state == Enum.UserInputState.Begin then
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not CameraController.InCombat() then
			return Enum.ContextActionResult.Pass
		end
		if CombatController.DrawIfSheathed() then
			return sink()
		end
		if drawn then
			CombatController.StartDraw()
		else
			CombatController.Attack(true)
		end
	elseif drawn then
		CombatController.CancelDraw()
	end
	return sink()
end

local function bindAttack()
	ContextActionService:BindAction("Attack", onAttack, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("Attack", "Attack")
	ContextActionService:BindAction("Heavy", onHeavy, true, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("Heavy", "Heavy")
end

local function onSlot(index: number)
	return function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			CombatController.ActivateSlot(index)
		elseif state == Enum.UserInputState.End then
			CombatController.ReleaseSlot(index)
		elseif state == Enum.UserInputState.Cancel then
			CombatController.CancelDraw()
		end
		return sink()
	end
end

local function onPress(fn: () -> ())
	return function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			fn()
		end
		return sink()
	end
end

local function onGuard(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		if CombatController.DrawIfSheathed() then
			return sink()
		end
		CombatController.SetGuard(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		CombatController.SetGuard(false)
	end
	return sink()
end

function InputController.Init(deps: { [string]: any })
	CombatController = deps.CombatController
	TargetController = deps.TargetController
	CameraController = deps.CameraController
	UIController = deps.UIController
end

function InputController.Start()
	UserInputService.InputBegan:Connect(onForwardInput)
	UserInputService.InputEnded:Connect(onForwardInput)
	RunService.Heartbeat:Connect(stopWhenIdle)
	bindAttack()
	ContextActionService:BindAction(
		"Dodge",
		onPress(CombatController.Dodge),
		true,
		Enum.KeyCode.Q,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle("Dodge", "Dodge")
	ContextActionService:BindAction("Guard", onGuard, true, Enum.KeyCode.F, Enum.KeyCode.ButtonL2)
	ContextActionService:SetTitle("Guard", "Guard")
	ContextActionService:BindAction(
		"CycleTarget",
		onPress(TargetController.Cycle),
		true,
		Enum.KeyCode.Tab,
		Enum.KeyCode.ButtonR3
	)
	ContextActionService:SetTitle("CycleTarget", "Target")
	ContextActionService:BindAction(
		"CombatMode",
		onPress(CameraController.ToggleCombat),
		true,
		Enum.KeyCode.LeftAlt,
		Enum.KeyCode.DPadUp
	)
	ContextActionService:SetTitle("CombatMode", "Combat")

	for index, key in HOTBAR_KEYS do
		ContextActionService:BindAction(`Slot{index}`, onSlot(index), index <= TOUCH_SLOTS, key)
		if index <= TOUCH_SLOTS then
			ContextActionService:SetTitle(`Slot{index}`, tostring(index))
		end
	end
	ContextActionService:BindAction("SlotPadNext", onSlot(1), false, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("SlotPadAlt", onSlot(2), false, Enum.KeyCode.ButtonY)

	ContextActionService:BindAction(
		"DisciplineA",
		onPress(function()
			CombatController.ToggleDiscipline(Disciplines.Order[1])
		end),
		false,
		Enum.KeyCode.Z
	)
	ContextActionService:BindAction(
		"DisciplineB",
		onPress(function()
			CombatController.ToggleDiscipline(Disciplines.Order[2])
		end),
		false,
		Enum.KeyCode.X
	)

	ContextActionService:BindAction(
		"Spellbook",
		onPress(function()
			UIController.Toggle("Spellbook")
		end),
		false,
		Enum.KeyCode.B
	)
	ContextActionService:BindAction(
		"Inventory",
		onPress(function()
			UIController.Toggle("Inventory")
		end),
		false,
		Enum.KeyCode.I
	)
	ContextActionService:BindAction(
		"CharacterSheet",
		onPress(function()
			UIController.Toggle("CharacterSheet")
		end),
		false,
		Enum.KeyCode.C
	)
	ContextActionService:BindAction(
		"DebugOverlay",
		onPress(function()
			local screen = UIController.GetScreen("DebugOverlay")
			if game:GetService("Players").LocalPlayer:GetAttribute("IsDev") then
				screen.Enabled = not screen.Enabled
			end
		end),
		false,
		Enum.KeyCode.F2
	)
	ContextActionService:BindAction("CloseModal", function(_, state)
		if state == Enum.UserInputState.Begin and UIController.CloseTop() then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonSelect)

	-- Attack must not fire while a modal is open and the pointer is over UI.
	UIController.ModalChanged:Connect(function(_, isOpen: boolean)
		if isOpen then
			ContextActionService:UnbindAction("Attack")
			ContextActionService:UnbindAction("Heavy")
		else
			bindAttack()
		end
	end)
end

return InputController
