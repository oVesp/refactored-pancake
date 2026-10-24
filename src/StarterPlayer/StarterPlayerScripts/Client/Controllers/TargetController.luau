--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Tuning = require(ReplicatedStorage.Content.Tuning)

local ENEMY_TAGS = { "Enemy", "TrainingDummy" }
local REFRESH_SECONDS = 0.1
local PICK_RAY = 300
local SOFT_COLOR = Theme.Gold
local LOCK_COLOR = Theme.HpBright

local Attributes = Constants.Attributes
local player = Players.LocalPlayer

--[=[
	Client side of targeting (docs/systems/combat.md, Targeting). Keeps a soft enemy target (the
	enemy nearest the screen centre, sticky so crowds do not flicker), an optional hard lock
	(Tab / R3 cycles, tapping an enemy locks it) and picks ally targets for support skills. The
	server re-validates every target it receives.
]=]
local TargetController = {}

--[=[ Fires `(model?, locked)` when the enemy target changes. ]=]
TargetController.Changed = Signal.new() :: Signal.Signal<Model?, boolean>

local UIController: any

local soft: Model? = nil
local locked: Model? = nil
local shown: Model? = nil
local shownLocked = false
local marker: BillboardGui
local arrow: TextLabel
local lastPointerWasMouse = UserInputService.MouseEnabled
local refreshAt = 0

local function rootOf(model: Model?): BasePart?
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	return if root and root:IsA("BasePart") then root else nil
end

local function ownRoot(): BasePart?
	return rootOf(player.Character)
end

local function isAlive(model: Model): boolean
	local hp = model:GetAttribute(Attributes.Hp)
	return model.Parent ~= nil and (type(hp) ~= "number" or hp > 0)
end

local function enemyCandidates(): { Targeting.Candidate<Model> }
	local list: { Targeting.Candidate<Model> } = {}
	for _, tag in ENEMY_TAGS do
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("Model") and isAlive(instance) then
				local root = rootOf(instance)
				if root then
					table.insert(list, { key = instance, position = root.Position })
				end
			end
		end
	end
	return list
end

local function allyCandidates(woundedOnly: boolean): { Targeting.Candidate<Model> }
	local list: { Targeting.Candidate<Model> } = {}
	for _, other in Players:GetPlayers() do
		local model = other.Character
		if other ~= player and model and model:GetAttribute("Team") == "Players" and isAlive(model) then
			local hp = model:GetAttribute(Attributes.Hp)
			local maxHp = model:GetAttribute(Attributes.MaxHp)
			local wounded = type(hp) == "number" and type(maxHp) == "number" and hp < maxHp
			local root = rootOf(model)
			if root and (wounded or not woundedOnly) then
				table.insert(list, { key = model, position = root.Position })
			end
		end
	end
	return list
end

local function options(range: number, current: Model?): Targeting.Options<Model>?
	local camera = workspace.CurrentCamera
	local root = ownRoot()
	if not camera or not root then
		return nil
	end
	local t = Tuning.Targeting
	return {
		eye = camera.CFrame.Position,
		forward = camera.CFrame.LookVector,
		from = root.Position,
		range = range,
		coneDegrees = t.ConeDegrees,
		angleWeight = t.AngleWeight,
		stickiness = t.Stickiness,
		current = current,
	}
end

local function withinRange(model: Model, range: number): boolean
	local root, own = rootOf(model), ownRoot()
	return root ~= nil and own ~= nil and (root.Position - own.Position).Magnitude <= range
end

-- Model under a screen point, walking up to a character or tagged enemy.
local function modelAt(screen: Vector2): Model?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * PICK_RAY, params)
	local current: Instance? = hit and hit.Instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("Team") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isEnemyModel(model: Model): boolean
	for _, tag in ENEMY_TAGS do
		if CollectionService:HasTag(model, tag) then
			return true
		end
	end
	return false
end

local function render()
	local target = locked or soft
	local isLocked = locked ~= nil
	if target == shown and isLocked == shownLocked then
		return
	end
	shown, shownLocked = target, isLocked
	local head = target and target:FindFirstChild("Head")
	local adornee: BasePart? = if head and head:IsA("BasePart") then head else rootOf(target)
	marker.Adornee = adornee :: any
	marker.Enabled = target ~= nil
	arrow.TextColor3 = if isLocked then LOCK_COLOR else SOFT_COLOR
	TargetController.Changed:Fire(target, isLocked)
end

local function refresh()
	local range = Tuning.Targeting.Range
	if locked and (not isAlive(locked) or not withinRange(locked, range)) then
		locked = nil
	end
	local opts = options(range, soft)
	soft = if opts then Targeting.Pick(enemyCandidates(), opts) else nil
	render()
end

--[=[ True while the last pointer input was a mouse (desktop aim follows the cursor). ]=]
function TargetController.UsingMouse(): boolean
	return lastPointerWasMouse
end

--[=[ Current enemy target: the lock if any, otherwise the soft target. ]=]
function TargetController.Enemy(): Model?
	return locked or soft
end

--[=[ True when the enemy target is a hard lock. ]=]
function TargetController.IsLocked(): boolean
	return locked ~= nil
end

--[=[ Locks the next enemy in score order; past the last one it releases the lock. ]=]
function TargetController.Cycle()
	local opts = options(Tuning.Targeting.Range, nil)
	locked = if opts then Targeting.Next(enemyCandidates(), opts, locked) else nil
	render()
end

--[=[ Locks a specific enemy, or releases the lock when it is already locked. ]=]
function TargetController.ToggleLock(model: Model)
	locked = if locked == model then nil else model
	render()
end

--[=[
	Ally for a support skill within `range`: the ally under the mouse, else the wounded ally
	nearest the screen centre, else nil (the server then uses the caster).
]=]
function TargetController.Ally(range: number): Model?
	if lastPointerWasMouse then
		local hovered = modelAt(UserInputService:GetMouseLocation())
		if hovered and hovered ~= player.Character and hovered:GetAttribute("Team") == "Players" then
			return if withinRange(hovered, range) then hovered else nil
		end
	end
	local opts = options(range, nil)
	return if opts then Targeting.Pick(allyCandidates(true), opts) else nil
end

function TargetController.Init(deps: { [string]: any })
	UIController = deps.UIController
end

function TargetController.Start()
	marker = UIController.Clone("TargetMarker") :: BillboardGui
	arrow = UIController.Bind(marker, { "Bind_Arrow" }).Bind_Arrow :: TextLabel
	marker.Enabled = false
	marker.Parent = player:WaitForChild("PlayerGui")

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.MouseButton1 then
			lastPointerWasMouse = true
		elseif inputType == Enum.UserInputType.Touch or inputType == Enum.UserInputType.Gamepad1 then
			lastPointerWasMouse = false
		end
	end)
	-- Tapping an enemy on a touch screen locks it; tapping it again releases.
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
		if processedByUI then
			return
		end
		local model = modelAt(position)
		if model and isEnemyModel(model) and isAlive(model) then
			TargetController.ToggleLock(model)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now >= refreshAt then
			refreshAt = now + REFRESH_SECONDS
			refresh()
		end
	end)
end

return TargetController
