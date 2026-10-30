--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Archery = require(ReplicatedStorage.Shared.Archery)
local Chain = require(ReplicatedStorage.Shared.Chain)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Hotbar = require(ReplicatedStorage.Shared.Hotbar)
local Loadout = require(ReplicatedStorage.Shared.Loadout)
local GuardClips = require(script.Parent.Parent.Animation.GuardClips)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Skills = require(ReplicatedStorage.Content.Skills)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(ReplicatedStorage.Content.Types)
local Weapons = require(ReplicatedStorage.Content.Weapons)

-- Studs the screen-centre aim ray reaches; stays inside the server's aim sanity check.
local AIM_RANGE = 280
local DODGE_SECONDS = 0.2
-- Seconds a queued action may wait past its predicted ready time for the server's cast to end.
local QUEUE_GRACE = 0.5
-- Studs a melee lunge stops short of the aim point.
local LUNGE_STOP_SHORT = 3

local player = Players.LocalPlayer

export type Slot = {
	kind: "Skill" | "Discipline",
	id: string,
}

--[=[
	Client side of combat: aim, predicted cooldowns, GCD and animation lock, a one-action input
	queue, `UseSkill` with sequence numbers and rollback on `RejectSkill` or an interrupted cast,
	the equipped weapon's basic attacks (light chain, heavy, bow draw, shield bash), guard and dodge. Each delivery reads the target from TargetController its own
	way (docs/systems/combat.md, Targeting). The server decides every outcome (game-design.md 5.5).
]=]
local CombatController = {}

--[=[ Fires when the hotbar layout changes; the map holds only filled slots (1..Hotbar.Size). ]=]
CombatController.HotbarChanged = Signal.new() :: Signal.Signal<{ [number]: Slot }>
--[=[ Fires `(skillId, reason)` when the server rejects a predicted use. ]=]
CombatController.Rejected = Signal.new() :: Signal.Signal<string, string>
--[=[ Fires `(skillId, aim)` when a use is sent (local feedback). ]=]
CombatController.Used = Signal.new() :: Signal.Signal<string, Vector3>
--[=[ Fires when the bow reaches full draw: releasing within `PerfectWindow` is a perfect shot. ]=]
CombatController.DrawReady = Signal.new() :: Signal.Signal<>

local ProfileController: any
local TargetController: any
local CameraController: any

local seq = 0
local pending: { [number]: string } = {}
local predictedReady: { [string]: number } = {}
local gcdStartedAt = 0
local gcdReadyAt = 0
local lockedUntil = 0
-- Melee swing in progress (windup + recovery) and the skill that started it.
local swingId: string? = nil
local swingEndsAt = 0
local queued: string? = nil
local queuedUntil = 0
local hotbar: { [number]: Slot } = {}
local chainLast: string? = nil
local chainAt = 0
local guarding = false
-- os.clock() when the current bow draw started.
local drawStartedAt: number? = nil
local drawConnection: RBXScriptConnection? = nil

local function character(): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model and root and root:IsA("BasePart") and humanoid then
		return model, root, humanoid
	end
	return nil, nil, nil
end

--[=[
	World point the player is aiming at: what the ray through the screen centre (the shift-lock
	crosshair) hits, else a point far along it. The same on mouse, touch and gamepad.
]=]
function CombatController.GetAim(): Vector3
	local model, root = character()
	local camera = workspace.CurrentCamera
	if not camera then
		return if root then root.Position else Vector3.zero
	end
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	local direction = ray.Direction.Unit
	-- Start the ray level with the character so nothing between the camera and it is hit.
	local skip = if root then math.max(0, (root.Position - ray.Origin):Dot(direction)) else 0
	local origin = ray.Origin + direction * skip
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if model then { model } else {}
	local result = workspace:Raycast(origin, direction * AIM_RANGE, params)
	return if result then result.Position else origin + direction * AIM_RANGE
end

--[=[ Weapon type the local character holds (its `Weapon` attribute), fists when unarmed. ]=]
function CombatController.Weapon(): Types.WeaponDef
	local id = player.Character and player.Character:GetAttribute("Weapon")
	return Weapons.ById[if type(id) == "string" then id else Weapons.Default] or Weapons.ById[Weapons.Default]
end

local function hasShield(): boolean
	return player.Character ~= nil and player.Character:GetAttribute("Shield") ~= nil
end

local function lightChain(): { string }
	return Chain.Members(Skills.ById, CombatController.Weapon().light)
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

-- Aim point and target for a skill. Melee swings where the character faces (the camera yaw)
-- and turns toward a close target in front of it (magnetism); skillshots stay free-aim through
-- the screen centre, with a small bend toward the target off the mouse; Target and Dash need an
-- enemy target; Ground lands on the target off the mouse; Ally takes the ally target (nil means
-- self). Returns nil aim when the skill cannot be used without a target.
local function aimFor(skill: any, root: BasePart): (Vector3?, Model?)
	local aim = CombatController.GetAim()
	local delivery = skill.delivery
	if delivery == "Melee" or delivery == "Cone" then
		local look = root.CFrame.LookVector
		local reach = math.max(skill.range or 0, LUNGE_STOP_SHORT + (skill.lunge or 0))
		aim = root.Position + Vector3.new(look.X, 0, look.Z).Unit * reach
	end
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

local function hasted(seconds: number): number
	local haste = player.Character and player.Character:GetAttribute("Extra_Haste")
	return Formulas.Hasted(seconds, if type(haste) == "number" then haste else 0, Tuning.Combat.Gcd.MaxHaste)
end

--[=[
	Seconds until the client predicts a skill is ready, and the length of the timer it is waiting
	on (its own cooldown, or the GCD when that is longer).
]=]
function CombatController.Cooldown(skillId: string): (number, number)
	local now = os.clock()
	local skill = Skills.ById[skillId]
	local total = if skill then skill.cooldown or 0 else 0
	local charges = player.Character and player.Character:GetAttribute("Charges_" .. skillId)
	local own = Formulas.ChargeReadyIn(
		predictedReady[skillId] or 0,
		now,
		total,
		if type(charges) == "number" then charges else 1
	)
	if skill and skill.gcd then
		local gcd = math.max(0, gcdReadyAt - now)
		if gcd > own then
			return gcd, gcdReadyAt - gcdStartedAt
		end
	end
	return own, total
end

--[=[ Seconds until the client predicts a skill is ready. ]=]
function CombatController.Remaining(skillId: string): number
	return (CombatController.Cooldown(skillId))
end

-- Seconds until this skill could be sent: its timers, the animation lock and, for a light chain
-- hit, the previous hit's cooldown.
local function waitFor(skillId: string): number
	local wait = math.max(CombatController.Remaining(skillId), lockedUntil - os.clock())
	if chainLast and table.find(lightChain(), skillId) then
		wait = math.max(wait, CombatController.Remaining(chainLast))
	end
	return wait
end

-- Steps the character toward the aim at the start of a melee swing, stopping short of the aim.
local function lunge(skill: any, root: BasePart, aim: Vector3)
	local offset = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	local distance = math.min(skill.lunge, offset.Magnitude - LUNGE_STOP_SHORT)
	if distance <= 0.1 then
		return
	end
	local seconds = Tuning.Combat.Commit.LungeSeconds
	local direction = offset.Unit
	local attachment = Instance.new("Attachment")
	attachment.Name = "LungeAttachment"
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "LungeVelocity"
	velocity.Attachment0 = attachment
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / seconds)
	velocity.MaxForce = 1e6
	attachment.Parent = root
	velocity.Parent = root
	task.delay(seconds, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end

-- Swing windup as the server computes it (HeavySpeed shortens weapon heavy attacks).
local function windupOf(skill: any): number
	local windup = skill.windup or 0
	if skill.heavy then
		local speed = player.Character and player.Character:GetAttribute("Extra_HeavySpeed")
		windup *= math.max(0.1, 1 - (if type(speed) == "number" then speed else 0))
	end
	return windup
end

-- Sends the use now. Returns false while the character is stunned or still casting.
local function send(skillId: string): boolean
	local skill = Skills.ById[skillId]
	local model, root = character()
	if not skill or not model or not root or waitFor(skillId) > 0 then
		return false
	end
	if model:GetAttribute("Stunned") == true or model:GetAttribute("Casting") ~= nil then
		return false
	end
	local aim, target = aimFor(skill, root)
	if not aim then
		CombatController.Rejected:Fire(skillId, "NoTarget")
		return true
	end
	local now = os.clock()
	seq += 1
	pending[seq] = skillId
	if skill.cooldown then
		predictedReady[skillId] = Formulas.ChargeSpend(predictedReady[skillId] or 0, now, skill.cooldown)
	end
	if skill.gcd then
		gcdStartedAt = now
		gcdReadyAt = now + hasted(Tuning.Combat.Gcd.Base)
	end
	if table.find(lightChain(), skillId) then
		chainLast = skillId
		chainAt = now
	end
	if skill.recovery then
		-- A melee swing commits the character until its recovery ends.
		swingId = skillId
		swingEndsAt = now + windupOf(skill) + skill.recovery
		lockedUntil = swingEndsAt
		if skill.lunge then
			lunge(skill, root, aim)
		end
	elseif skill.source ~= "Basic" or skill.castTime then
		-- Non-basic actions lock for the animation; a basic with a cast time locks for the cast.
		local cast = if skill.castTime then hasted(skill.castTime) else 0
		lockedUntil = now + math.max(cast, Tuning.Combat.Gcd.AnimationLock)
	end
	NetClient.Fire("UseSkill", skillId, aim, seq, target)
	CombatController.Used:Fire(skillId, aim)
	return true
end

--[=[
	Sends a skill use if the local prediction allows it. A hotbar skill pressed within
	`QueueWindow` of becoming ready is queued (one at a time, the latest press wins) and sent the
	moment it is, which buffers presses made during a swing's recovery. The light attack entry continues the chain: it
	uses the last hit's `chainNext` within Tuning.Combat.Chain.Window, else starts over.
]=]
function CombatController.UseSkill(skillId: string)
	if skillId == CombatController.Weapon().light then
		skillId = Chain.Next(Skills.ById, skillId, chainLast, chainAt, os.clock(), Tuning.Combat.Chain.Window)
	end
	local skill = Skills.ById[skillId]
	if not skill then
		return
	end
	local wait = waitFor(skillId)
	if wait <= 0 then
		queued = nil
		send(skillId)
	elseif wait <= Tuning.Combat.Gcd.QueueWindow then
		queued = skillId
		queuedUntil = os.clock() + wait + QUEUE_GRACE
	end
end

-- Gives back predicted timers after a rejected use or an interrupted cast.
local function rollback(skillId: string)
	local skill = Skills.ById[skillId]
	predictedReady[skillId] = nil
	if skill and skill.gcd then
		gcdReadyAt = 0
	end
	if table.find(lightChain(), skillId) then
		chainLast = nil
	end
	lockedUntil = 0
	swingId = nil
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

--[=[ Current hotbar slots by index; empty slots are absent. ]=]
function CombatController.Hotbar(): { [number]: Slot }
	return hotbar
end

--[=[
	Light or heavy attack with the equipped weapon (docs/systems/weapons.md): the shield bash while
	guarding with a shield, else the weapon's heavy or light chain. Bow shots go through the draw.
]=]
function CombatController.Attack(heavy: boolean)
	local weapon = CombatController.Weapon()
	if guarding and hasShield() then
		CombatController.UseSkill(Weapons.ShieldBash)
	elseif heavy and weapon.heavy then
		CombatController.UseSkill(weapon.heavy)
	elseif not weapon.drawn then
		CombatController.UseSkill(weapon.light)
	end
end

local function endDrawCamera()
	if drawConnection then
		drawConnection:Disconnect()
		drawConnection = nil
	end
	CameraController.SetAiming(false)
end

--[=[ Starts drawing the bow: the camera aims in tighter (CameraController) and the archer slows down. ]=]
function CombatController.StartDraw()
	local _, root = character()
	if drawStartedAt or not root or not CombatController.Weapon().drawn then
		return
	end
	if guarding or waitFor(CombatController.Weapon().light) > 0 then
		return
	end
	drawStartedAt = os.clock()
	NetClient.Fire("SetDraw", true)
	CameraController.SetAiming(true)
	local announced = false
	drawConnection = RunService.Heartbeat:Connect(function()
		if not announced and drawStartedAt and os.clock() - drawStartedAt >= Tuning.Combat.Bow.FullDraw then
			announced = true
			CombatController.DrawReady:Fire()
		end
	end)
end

--[=[ Releases the bow: shoots if the draw was long enough, otherwise lowers it. ]=]
function CombatController.ReleaseDraw()
	local startedAt = drawStartedAt
	if not startedAt then
		return
	end
	drawStartedAt = nil
	endDrawCamera()
	local scale = Archery.DrawScale(os.clock() - startedAt, Tuning.Combat.Bow)
	if scale <= 0 or not send(CombatController.Weapon().light) then
		NetClient.Fire("SetDraw", false)
	end
end

--[=[ Lowers the bow without shooting. ]=]
function CombatController.CancelDraw()
	if drawStartedAt then
		drawStartedAt = nil
		endDrawCamera()
		NetClient.Fire("SetDraw", false)
	end
end

--[=[ Starts or stops guarding; weapons that cannot guard need a shield. ]=]
function CombatController.SetGuard(on: boolean)
	if on and not Loadout.CanGuard(CombatController.Weapon(), hasShield()) then
		return
	end
	if on then
		CombatController.CancelDraw()
	end
	guarding = on
	NetClient.Fire("SetGuard", on)
end

--[=[ Dodges along the move direction (or backward): local impulse, server grants i-frames. ]=]
function CombatController.Dodge()
	local _, root, humanoid = character()
	if not root or not humanoid or CombatController.Remaining("__dodge") > 0 then
		return
	end
	queued = nil
	CombatController.CancelDraw()
	-- Dodge cancels a swing in progress and its recovery.
	if swingId and os.clock() < swingEndsAt then
		CombatController.Rejected:Fire(swingId, "Dodge")
	end
	swingId = nil
	lockedUntil = 0
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
	local slots: { [number]: Slot } = {}
	for index = 1, Hotbar.Size do
		local kind: Hotbar.Kind?, id: string? = Hotbar.Decode(snapshot.hotbar[index] or "")
		if kind and id then
			slots[index] = { kind = kind, id = id }
		end
	end
	hotbar = slots
	CombatController.HotbarChanged:Fire(slots)
end

function CombatController.Init(deps: { [string]: any })
	ProfileController = deps.ProfileController
	TargetController = deps.TargetController
	CameraController = deps.CameraController
end

function CombatController.Start()
	NetClient.Connect("RejectSkill", function(rejectedSeq: number, reason: string)
		local skillId = pending[rejectedSeq]
		pending[rejectedSeq] = nil
		if skillId == "__dodge" then
			predictedReady[skillId] = nil
		elseif skillId then
			rollback(skillId)
			CombatController.Rejected:Fire(skillId, reason)
		end
	end)
	NetClient.Connect("ShowCast", function(info: { [string]: any })
		if info.kind == "Interrupted" and info.caster == player.Character then
			rollback(info.skillId)
		end
	end)
	RunService.Heartbeat:Connect(function()
		local skillId = queued
		if not skillId then
			return
		end
		if os.clock() > queuedUntil or (waitFor(skillId) <= 0 and send(skillId)) then
			queued = nil
		end
	end)
	ProfileController.Changed:Connect(rebuildHotbar)
	player.CharacterAdded:Connect(function()
		guarding = false
		if drawConnection then
			drawConnection:Disconnect()
			drawConnection = nil
		end
		drawStartedAt = nil
	end)
	GuardClips.Start()
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
