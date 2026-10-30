--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Disciplines = require(ReplicatedStorage.Content.Disciplines)

local HEAVY_HOLD_SECONDS = 0.35
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
	included). Tap attack = light, hold = heavy; with a bow, hold draws and release shoots; while
	guarding with a shield, attack bashes. Tab / R3 / Target button cycle the target lock.
	Screens: B spellbook, I inventory, C sheet, F2 debug.
]=]
local InputController = {}

local CombatController: any
local TargetController: any
local UIController: any

local attackPressedAt: number? = nil

local function sink(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function onAttack(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if UIController.IsWorldOpen() then
		-- Clicks belong to the floating menu while one holds the camera.
		attackPressedAt = nil
		CombatController.CancelDraw()
		return Enum.ContextActionResult.Pass
	end
	local drawn = CombatController.Weapon().drawn
	if state == Enum.UserInputState.Begin then
		attackPressedAt = os.clock()
		if drawn then
			CombatController.StartDraw()
		end
	elseif state == Enum.UserInputState.End and attackPressedAt then
		local held = os.clock() - attackPressedAt
		attackPressedAt = nil
		if drawn then
			CombatController.ReleaseDraw()
		else
			CombatController.Attack(held >= HEAVY_HOLD_SECONDS)
		end
	elseif state == Enum.UserInputState.Cancel then
		attackPressedAt = nil
		CombatController.CancelDraw()
	end
	return sink()
end

local function onSlot(index: number)
	return function(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			CombatController.ActivateSlot(index)
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
		CombatController.SetGuard(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		CombatController.SetGuard(false)
	end
	return sink()
end

function InputController.Init(deps: { [string]: any })
	CombatController = deps.CombatController
	TargetController = deps.TargetController
	UIController = deps.UIController
end

function InputController.Start()
	ContextActionService:BindAction("Attack", onAttack, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("Attack", "Attack")
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
		else
			ContextActionService:BindAction(
				"Attack",
				onAttack,
				true,
				Enum.UserInputType.MouseButton1,
				Enum.KeyCode.ButtonR2
			)
			ContextActionService:SetTitle("Attack", "Attack")
		end
	end)
end

return InputController
