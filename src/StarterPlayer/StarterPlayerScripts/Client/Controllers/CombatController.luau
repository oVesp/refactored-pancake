--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Disciplines = require(ReplicatedStorage.Content.Disciplines)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Skills = require(ReplicatedStorage.Content.Skills)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Tuning = require(ReplicatedStorage.Content.Tuning)

local AIM_RANGE = 300
local PAD_AIM_DISTANCE = 30
local DODGE_SECONDS = 0.2
local HOTBAR_SIZE = 8

local player = Players.LocalPlayer

export type Slot = {
	kind: "Skill" | "Discipline",
	id: string,
}

--[=[
	Client side of combat: aim, predicted cooldowns, `UseSkill` with sequence numbers and rollback
	on `RejectSkill`, guard and dodge. Each delivery reads the target from TargetController its own
	way (docs/systems/combat.md, Targeting). The server decides every outcome (game-design.md 5.5).
]=]
local CombatController = {}

--[=[ Fires when the hotbar layout changes. ]=]
CombatController.HotbarChanged = Signal.new() :: Signal.Signal<{ Slot }>
--[=[ Fires `(skillId, reason)` when the server rejects a predicted use. ]=]
CombatController.Rejected = Signal.new() :: Signal.Signal<string, string>
--[=[ Fires `(skillId, aim)` when a use is sent (local feedback). ]=]
CombatController.Used = Signal.new() :: Signal.Signal<string, Vector3>

local ProfileController: any
local TargetController: any

local seq = 0
local pending: { [number]: string } = {}
local predictedReady: { [string]: number } = {}
local hotbar: { Slot } = {}

local function character(): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model and root and root:IsA("BasePart") and humanoid then
		return model, root, humanoid
	end
	return nil, nil, nil
end

--[=[ World point the player is aiming at: mouse hit on desktop, a point ahead of the camera otherwise. ]=]
function CombatController.GetAim(): Vector3
	local model, root = character()
	local camera = workspace.CurrentCamera
	if TargetController.UsingMouse() and camera then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = if model then { model } else {}
		local result = workspace:Raycast(ray.Origin, ray.Direction * AIM_RANGE, params)
		return if result then result.Position else ray.Origin + ray.Direction * AIM_RANGE
	end
	if root and camera then
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else root.CFrame.LookVector
		return root.Position + flat * PAD_AIM_DISTANCE
	end
	return Vector3.zero
end

local function positionOf(model: Model?): Vector3?
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function face(root: BasePart, point: Vector3)
	local look = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
	if look.Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
end

-- Aim point and target for a skill. Melee turns toward a close target in front of the aim
-- (magnetism); skillshots stay free-aim, with a small bend toward the target off the mouse;
-- Target and Dash need an enemy target; Ground lands on the target off the mouse; Ally takes the
-- ally target (nil means self). Returns nil aim when the skill cannot be used without a target.
local function aimFor(skill: any, root: BasePart): (Vector3?, Model?)
	local aim = CombatController.GetAim()
	local delivery = skill.delivery
	local enemy = TargetController.Enemy()
	local enemyAt = positionOf(enemy)
	local t = Tuning.Targeting
	if delivery == "Target" or delivery == "Dash" then
		if not enemy or not enemyAt then
			return nil, nil
		end
		return enemyAt, enemy
	elseif delivery == "Ally" then
		local ally = TargetController.Ally(skill.range or 0)
		return positionOf(ally) or root.Position, ally
	elseif not enemyAt then
		return aim, nil
	end
	local angle = Targeting.FlatAngle(aim - root.Position, enemyAt - root.Position)
	if delivery == "Melee" or delivery == "Cone" then
		local close = (enemyAt - root.Position).Magnitude <= t.MeleeAssistRange + (skill.range or 0)
		if close and (angle <= t.MeleeAssistDegrees or TargetController.IsLocked()) then
			face(root, enemyAt)
			return enemyAt, nil
		end
	elseif delivery == "Projectile" and not TargetController.UsingMouse() then
		if angle <= t.AimAssistDegrees or TargetController.IsLocked() then
			return enemyAt, nil
		end
	elseif delivery == "Ground" and not TargetController.UsingMouse() then
		return enemyAt, nil
	end
	return aim, nil
end

--[=[ Seconds until the client predicts a skill is ready. ]=]
function CombatController.Remaining(skillId: string): number
	return math.max(0, (predictedReady[skillId] or 0) - os.clock())
end

--[=[ Sends a skill use if the local prediction allows it. ]=]
function CombatController.UseSkill(skillId: string)
	local skill = Skills.ById[skillId]
	local model, root = character()
	if not skill or not model or not root or CombatController.Remaining(skillId) > 0 then
		return
	end
	if model:GetAttribute("Stunned") == true or model:GetAttribute("Casting") ~= nil then
		return
	end
	local aim, target = aimFor(skill, root)
	if not aim then
		CombatController.Rejected:Fire(skillId, "NoTarget")
		return
	end
	seq += 1
	pending[seq] = skillId
	predictedReady[skillId] = os.clock() + (skill.cooldown or 0)
	NetClient.Fire("UseSkill", skillId, aim, seq, target)
	CombatController.Used:Fire(skillId, aim)
end

--[=[ Toggles a Discipline. ]=]
function CombatController.ToggleDiscipline(id: string)
	NetClient.Fire("ToggleDiscipline", id)
end

--[=[ Activates hotbar slot `index` (1-based). ]=]
function CombatController.ActivateSlot(index: number)
	local slot = hotbar[index]
	if not slot then
		return
	end
	if slot.kind == "Skill" then
		CombatController.UseSkill(slot.id)
	else
		CombatController.ToggleDiscipline(slot.id)
	end
end

--[=[ Current hotbar slots. ]=]
function CombatController.Hotbar(): { Slot }
	return hotbar
end

--[=[ Starts or stops guarding. ]=]
function CombatController.SetGuard(on: boolean)
	NetClient.Fire("SetGuard", on)
end

--[=[ Dodges along the move direction (or backward): local impulse, server grants i-frames. ]=]
function CombatController.Dodge()
	local _, root, humanoid = character()
	if not root or not humanoid or CombatController.Remaining("__dodge") > 0 then
		return
	end
	local dodge = Tuning.Combat.Dodge
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = -root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	seq += 1
	pending[seq] = "__dodge"
	predictedReady["__dodge"] = os.clock() + dodge.Cooldown
	NetClient.Fire("Dodge", direction, seq)

	local attachment = Instance.new("Attachment")
	attachment.Name = "DodgeAttachment"
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DodgeVelocity"
	velocity.Attachment0 = attachment
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (dodge.Distance / DODGE_SECONDS)
	velocity.MaxForce = 1e6
	attachment.Parent = root
	velocity.Parent = root
	task.delay(DODGE_SECONDS, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end

local function rebuildHotbar(snapshot: { [string]: any })
	local slots: { Slot } = {}
	for _, skillId in snapshot.actives do
		if skillId ~= Skills.Basic.Light and skillId ~= Skills.Basic.Heavy and #slots < HOTBAR_SIZE then
			table.insert(slots, { kind = "Skill", id = skillId })
		end
	end
	for _, id in Disciplines.Order do
		if table.find(snapshot.disciplines, id) and #slots < HOTBAR_SIZE then
			table.insert(slots, { kind = "Discipline", id = id })
		end
	end
	hotbar = slots
	CombatController.HotbarChanged:Fire(slots)
end

function CombatController.Init(deps: { [string]: any })
	ProfileController = deps.ProfileController
	TargetController = deps.TargetController
end

function CombatController.Start()
	NetClient.Connect("RejectSkill", function(rejectedSeq: number, reason: string)
		local skillId = pending[rejectedSeq]
		pending[rejectedSeq] = nil
		if skillId then
			predictedReady[skillId] = nil
			CombatController.Rejected:Fire(skillId, reason)
		end
	end)
	ProfileController.Changed:Connect(rebuildHotbar)
	-- Old sequence numbers never resolve on success; trim them so the table stays small.
	task.spawn(function()
		while true do
			task.wait(10)
			for key in pending do
				if key < seq - 50 then
					pending[key] = nil
				end
			end
		end
	end)
end

return CombatController
