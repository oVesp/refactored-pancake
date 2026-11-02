--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Archery = require(ReplicatedStorage.Shared.Archery)
local Casting = require(ReplicatedStorage.Shared.Casting)
local Chain = require(ReplicatedStorage.Shared.Chain)
local ChatCast = require(ReplicatedStorage.Shared.ChatCast)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Hotbar = require(ReplicatedStorage.Shared.Hotbar)
local Loadout = require(ReplicatedStorage.Shared.Loadout)
local Animations = require(script.Parent.Parent.Animation.Animations)
local GuardAnimations = require(script.Parent.Parent.Animation.GuardAnimations)
local RunAnimations = require(script.Parent.Parent.Animation.RunAnimations)
local WeaponAnimations = require(script.Parent.Parent.Animation.WeaponAnimations)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Skills = require(ReplicatedStorage.Content.Skills)
local SummonFamilies = require(ReplicatedStorage.Content.Summons)
local Summons = require(ReplicatedStorage.Shared.Summons)
local Targeting = require(ReplicatedStorage.Shared.Targeting)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(ReplicatedStorage.Content.Types)
local Weapons = require(ReplicatedStorage.Content.Weapons)

-- Studs the screen-centre aim ray reaches; stays inside the server's aim sanity check.
local AIM_RANGE = 280
-- Seconds a queued action may wait past its predicted ready time for the server's cast to end.
local QUEUE_GRACE = 0.5
-- Seconds a fizzled release waits for the server's `Interrupted` before giving up the lock anyway.
local FIZZLE_CONFIRM = 1
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
	spells held to charge and released to fire, the equipped weapon's basic attacks (light chain,
	heavy, bow draw, shield bash), guard and dodge. Each delivery reads the target from TargetController its own
	way (docs/systems/combat.md, Targeting). The server decides every outcome (game-design.md 5.5).
]=]
local CombatController = {}

--[=[ Fires when the hotbar layout changes; the map holds only filled slots (1..Hotbar.Size). ]=]
CombatController.HotbarChanged = Signal.new() :: Signal.Signal<{ [number]: Slot }>
--[=[ Fires `(skillId, reason)` when the server rejects a predicted use. ]=]
CombatController.Rejected = Signal.new() :: Signal.Signal<string, string>
--[=[ Fires `(skillId, aim)` when a use is sent (local feedback). ]=]
CombatController.Used = Signal.new() :: Signal.Signal<string, Vector3>
--[=[ Fires `(skillId, options)` when a summon skill with more than one option is pressed (SummonController). ]=]
CombatController.SummonPrompted = Signal.new() :: Signal.Signal<string, { string }>
--[=[ Fires at full bow draw (a release within `PerfectWindow` is a perfect shot) and at a spell's full charge. ]=]
CombatController.DrawReady = Signal.new() :: Signal.Signal<>
--[=[ Fires when the local player starts a dodge. ]=]
CombatController.Dodged = Signal.new() :: Signal.Signal<>

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
local queuedArg: string? = nil
local queuedUntil = 0
local hotbar: { [number]: Slot } = {}
local chainLast: string? = nil
local chainAt = 0
local guarding = false
-- os.clock() when the current bow draw started.
local drawStartedAt: number? = nil
-- Skill the current draw will shoot: the bow's light attack or a `weaponAttack` skill.
local drawSkill: string? = nil
local drawConnection: RBXScriptConnection? = nil
-- Spell being charged. `hold` waits for the button; otherwise it fires when full (chat, summon picker).
-- After a release that fizzles it stays set, blocking new presses, until the server's `Interrupted`.
local activeCast: { skillId: string, seq: number, fullAt: number, hold: boolean, full: boolean, releasedAt: number? }? =
	nil

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

-- The skill as the character uses it: a `weaponAttack` skill follows the held weapon.
local function skillOf(skillId: string): any
	local skill = Skills.ById[skillId]
	return skill and Loadout.Attack(Skills.ById, skill, CombatController.Weapon())
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
-- the screen centre, with a small bend toward the target off the mouse; a hard lock sends
-- skillshots and Ground at the locked target; Target and Dash need an enemy target; Ground lands
-- on the target off the mouse; Ally takes the ally target (nil means self). Returns nil aim when
-- the skill cannot be used without a target.
local function aimFor(skill: any, root: BasePart): (Vector3?, Model?)
	local aim = CombatController.GetAim()
	local delivery = skill.delivery
	if delivery == "Dev" then
		return aim, TargetController.Enemy() or TargetController.Ally(math.huge)
	end
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
	elseif delivery == "Projectile" or delivery == "Ground" then
		if TargetController.IsLocked() then
			return enemyAt, nil
		elseif TargetController.UsingMouse() then
			return aim, nil
		elseif delivery == "Ground" or angle <= t.AimAssistDegrees then
			return enemyAt, nil
		end
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
-- `chatText`: the chat message that cast it, sent instead of the id (chat casting).
-- `arg`: the summon a Summon delivery raises.
local function send(skillId: string, chatText: string?, arg: string?): boolean
	local skill = skillOf(skillId)
	local model, root = character()
	if not skill or not model or not root or waitFor(skillId) > 0 then
		return false
	end
	if model:GetAttribute("Stunned") == true or model:GetAttribute("Casting") ~= nil then
		return false
	end
	local autoFire = chatText ~= nil or arg ~= nil
	local aimed, target = aimFor(skill, root)
	if not aimed and (not skill.castTime or autoFire) then
		CombatController.Rejected:Fire(skillId, "NoTarget")
		return true
	end
	-- A held spell picks its target at the release.
	local aim: Vector3 = aimed or CombatController.GetAim()
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
	elseif skill.castTime then
		-- A spell locks until it fires or is cancelled (`castFired`, `rollback`).
		activeCast = {
			skillId = skillId,
			seq = seq,
			fullAt = now + hasted(skill.castTime),
			hold = not autoFire,
			full = false,
		}
		lockedUntil = math.huge
	elseif skill.source ~= "Basic" then
		-- Non-basic actions lock for the animation.
		lockedUntil = now + Tuning.Combat.Gcd.AnimationLock
	end
	if chatText then
		NetClient.Fire("CastSpellByName", chatText, aim, seq, target)
	else
		NetClient.Fire("UseSkill", skillId, aim, seq, target, arg)
	end
	-- A spell's clip and effects wait for it to fire.
	if not skill.castTime then
		CombatController.Used:Fire(skillId, aim)
	end
	return true
end

-- The spell left the caster: only the animation lock remains.
local function castFired(skillId: string, aim: Vector3)
	activeCast = nil
	lockedUntil = os.clock() + Tuning.Combat.Gcd.AnimationLock
	CombatController.Used:Fire(skillId, aim)
end

--[=[
	Lets go of the held spell. Full (or just short of it) it fires at the current aim and target;
	earlier it fizzles, and the lock stays until the server's `Interrupted` confirms it. The server
	decides from its own clock.
]=]
function CombatController.ReleaseCast()
	local cast = activeCast
	if not cast or not cast.hold or cast.releasedAt then
		return
	end
	cast.releasedAt = os.clock()
	local skill = skillOf(cast.skillId)
	local _, root = character()
	local aim: Vector3?, target: Model? = nil, nil
	local grace = Tuning.Combat.Cast.ReleaseGrace
	if skill and root and Casting.Release(os.clock(), cast.fullAt, grace) ~= "Fizzle" then
		aim, target = aimFor(skill, root)
		if not aim then
			CombatController.Rejected:Fire(cast.skillId, "NoTarget")
		end
	end
	if aim then
		NetClient.Fire("ReleaseCast", cast.seq, aim, target)
		castFired(cast.skillId, aim)
	else
		NetClient.Fire("ReleaseCast", cast.seq)
	end
end

--[=[ Cancels the held spell whatever its charge, as when a menu takes the button. ]=]
function CombatController.CancelCast()
	local cast = activeCast
	if cast and cast.hold and not cast.releasedAt then
		cast.releasedAt = os.clock()
		NetClient.Fire("ReleaseCast", cast.seq)
	end
end

--[=[ True while a spell is charging or held at full charge. ]=]
function CombatController.Casting(): boolean
	return activeCast ~= nil
end

--[=[
	Sends a skill use if the local prediction allows it. A hotbar skill pressed within
	`QueueWindow` of becoming ready is queued (one at a time, the latest press wins) and sent the
	moment it is, which buffers presses made during a swing's recovery. A spell charges while the
	button is held and fires on release (`ReleaseSlot`, `ReleaseHeavy`). The light attack entry continues the chain: it
	uses the last hit's `chainNext` within Tuning.Combat.Chain.Window, else starts over. A skill the
	held weapon draws starts the draw; releasing the slot shoots it (`ReleaseSlot`). A summon skill
	with more than one option asks SummonController first, which comes back with `arg`.
]=]
function CombatController.UseSkill(skillId: string, arg: string?)
	if skillId == CombatController.Weapon().light then
		skillId = Chain.Next(Skills.ById, skillId, chainLast, chainAt, os.clock(), Tuning.Combat.Chain.Window)
	end
	local skill = skillOf(skillId)
	if not skill then
		return
	end
	if skill.drawn then
		CombatController.StartDraw(skillId)
		return
	end
	if skill.summon and not arg then
		local snapshot = ProfileController.Get()
		local options = Summons.Options(SummonFamilies.ById[skill.summon], snapshot and snapshot.discoveries or {})
		if #options > 1 then
			CombatController.SummonPrompted:Fire(skillId, options)
			return
		end
	end
	local wait = waitFor(skillId)
	if wait <= 0 then
		queued = nil
		send(skillId, nil, arg)
	elseif wait <= Tuning.Combat.Gcd.QueueWindow then
		queued = skillId
		queuedArg = arg
		queuedUntil = os.clock() + wait + QUEUE_GRACE
	end
end

--[=[
	Casts the known spell a chat message names (Shared/ChatCast), if it is ready. Returns false
	for ordinary chat. The server resolves the text again and decides.
]=]
function CombatController.CastByName(text: string): boolean
	local snapshot = ProfileController.Get()
	local skillId = snapshot and ChatCast.Resolve(text, snapshot.actives or {}, Skills.ById)
	if not skillId then
		return false
	end
	if waitFor(skillId) > 0 then
		CombatController.Rejected:Fire(skillId, "Cooldown")
	else
		send(skillId, text)
	end
	return true
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
	-- A late answer about an older press must not unlock a spell being charged.
	if activeCast and activeCast.skillId ~= skillId then
		return
	end
	lockedUntil = 0
	swingId = nil
	activeCast = nil
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

-- A button let go on `skillId`: a queued spell has no hold left, a spell it charged is released.
local function letGo(skillId: string)
	local skill = skillOf(skillId)
	if queued == skillId and not queuedArg and skill and skill.castTime then
		queued = nil
	end
	if activeCast and activeCast.skillId == skillId then
		CombatController.ReleaseCast()
	end
end

--[=[ Hotbar slot `index` let go: shoots the draw or releases the spell that slot started. ]=]
function CombatController.ReleaseSlot(index: number)
	local slot = hotbar[index]
	if slot and slot.id == drawSkill then
		CombatController.ReleaseDraw()
	elseif slot then
		letGo(slot.id)
	end
end

--[=[ Heavy attack let go: releases the weapon's spell. ]=]
function CombatController.ReleaseHeavy()
	local heavy = CombatController.Weapon().heavy
	if heavy then
		letGo(heavy)
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
	if guarding and hasShield() and not heavy then
		CombatController.UseSkill(Weapons.ShieldBash)
		return
	end
	if guarding then
		CombatController.SetGuard(false)
	end
	if heavy and weapon.heavy then
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

--[=[
	Starts drawing the bow: the camera aims in tighter (CameraController) and the archer slows down.
	`skillId` is what the release shoots, the light attack by default; naming one during a draw
	switches the shot to it.
]=]
function CombatController.StartDraw(skillId: string?)
	local _, root = character()
	local shot = skillId or CombatController.Weapon().light
	if (drawStartedAt and not skillId) or not root or not CombatController.Weapon().drawn then
		return
	end
	if guarding or waitFor(shot) > 0 then
		return
	end
	drawSkill = shot
	if drawStartedAt then
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
	local shot = drawSkill or CombatController.Weapon().light
	drawStartedAt = nil
	drawSkill = nil
	endDrawCamera()
	local scale = Archery.DrawScale(os.clock() - startedAt, Tuning.Combat.Bow)
	if scale <= 0 or not send(shot) then
		NetClient.Fire("SetDraw", false)
	end
end

--[=[ Lowers the bow without shooting. ]=]
function CombatController.CancelDraw()
	if drawStartedAt then
		drawStartedAt = nil
		drawSkill = nil
		endDrawCamera()
		NetClient.Fire("SetDraw", false)
	end
end

--[=[ Lowers a bow draw and cancels a held spell, as when a menu or the system takes the button. ]=]
function CombatController.CancelHold()
	CombatController.CancelDraw()
	CombatController.CancelCast()
end

--[=[ Starts or stops guarding; weapons that cannot guard need a shield. ]=]
function CombatController.SetGuard(on: boolean)
	if on and (activeCast or not Loadout.CanGuard(CombatController.Weapon(), hasShield())) then
		return
	end
	if on then
		CombatController.CancelDraw()
	end
	guarding = on
	NetClient.Fire("SetGuard", on)
end

--[=[
	Draws the held weapon when it is sheathed: switches to combat mode, which tells the server.
	Returns true when the press only drew (it is consumed); false when nothing was sheathed.
]=]
function CombatController.DrawIfSheathed(): boolean
	if CameraController.InCombat() then
		return false
	end
	local model = player.Character
	local holdsGear = CombatController.Weapon().id ~= Weapons.Default or hasShield()
	if not model or not holdsGear then
		return false
	end
	CameraController.SetCombat(true)
	return true
end

-- Tells the server the combat mode so it can draw or sheathe the held models, and waits out the swap.
local function syncCombatMode(on: boolean, lock: boolean)
	NetClient.Fire("SetCombatMode", on)
	if lock then
		lockedUntil = math.max(lockedUntil, os.clock() + Tuning.Combat.DrawLock)
	end
	if not on then
		CombatController.CancelDraw()
		if guarding then
			CombatController.SetGuard(false)
		end
	end
end

--[=[ Starts or stops running (the server sets the walk speed). ]=]
function CombatController.SetRun(on: boolean)
	NetClient.Fire("SetRun", on)
	RunAnimations.SetRunning(on)
end

-- Plays the dodge roll on the local character; the loaded track is kept per animator.
local dodgeTracks: { [Animator]: AnimationTrack } = setmetatable({}, { __mode = "k" }) :: any

local function playDodge()
	local _, _, humanoid = character()
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local track = dodgeTracks[animator] or Animations.Load(animator, "Dodge", Enum.AnimationPriority.Action3, false)
	if not track then
		return
	end
	dodgeTracks[animator] = track
	track:Play(0.05)
	-- The roll lasts Tuning.Combat.Dodge.Duration whatever the clip's own length.
	if track.Length > 0 then
		track:AdjustSpeed(track.Length / Tuning.Combat.Dodge.Duration)
	end
end

--[=[ Dodges along the move direction (or backward): local impulse, server grants i-frames. ]=]
function CombatController.Dodge()
	local _, root, humanoid = character()
	if not root or not humanoid or CombatController.Remaining("__dodge") > 0 then
		return
	end
	queued = nil
	CombatController.CancelDraw()
	-- Dodge drops a spell at once: the server does the same on the press.
	if activeCast then
		rollback(activeCast.skillId)
	end
	-- Dodge cancels a swing in progress and its recovery.
	if swingId and os.clock() < swingEndsAt then
		CombatController.Rejected:Fire(swingId, "Dodge")
	end
	swingId = nil
	local dodge = Tuning.Combat.Dodge
	lockedUntil = os.clock() + dodge.Duration
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = -root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	seq += 1
	pending[seq] = "__dodge"
	predictedReady["__dodge"] = os.clock() + dodge.Duration + dodge.Cooldown
	NetClient.Fire("Dodge", direction, seq)
	playDodge()
	CombatController.Dodged:Fire()

	local attachment = Instance.new("Attachment")
	attachment.Name = "DodgeAttachment"
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DodgeVelocity"
	velocity.Attachment0 = attachment
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.zero
	velocity.MaxForce = 1e6
	attachment.Parent = root
	velocity.Parent = root
	-- Speed 1.5 x Distance / Duration x (1 - u^2) integrates to Distance over the roll: quick off the
	-- mark, slowing as the character comes out of it.
	local peak = 1.5 * dodge.Distance / dodge.Duration
	local startedAt = os.clock()
	local step: RBXScriptConnection
	-- The roll turns the character along its direction, after the camera script has run so shift lock
	-- and auto-rotate cannot turn it back toward the camera.
	local facing = CFrame.lookAt(Vector3.zero, direction)
	local rotateName = "DodgeFace"
	local autoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	local function turn()
		root.CFrame = CFrame.new(root.Position) * facing
	end
	turn()
	RunService:BindToRenderStep(rotateName, Enum.RenderPriority.Camera.Value + 1, turn)
	local function finish()
		RunService:UnbindFromRenderStep(rotateName)
		humanoid.AutoRotate = autoRotate
		step:Disconnect()
		velocity:Destroy()
		attachment:Destroy()
	end
	step = RunService.Heartbeat:Connect(function()
		local u = (os.clock() - startedAt) / dodge.Duration
		if u >= 1 or not velocity.Parent then
			finish()
			return
		end
		local speed = peak * (1 - u * u)
		velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * speed
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
		if info.caster ~= player.Character then
			return
		end
		if info.kind == "Interrupted" then
			rollback(info.skillId)
		elseif info.kind == "Pushback" and activeCast then
			activeCast.fullAt = os.clock() + info.remaining
		end
	end)
	RunService.Heartbeat:Connect(function()
		local cast = activeCast
		local now = os.clock()
		if cast and not cast.full and now >= cast.fullAt then
			cast.full = true
			if not cast.hold then
				castFired(cast.skillId, CombatController.GetAim())
			elseif not cast.releasedAt then
				CombatController.DrawReady:Fire()
			end
		end
		-- The server cancels on its own; these only keep a lost message from locking the client for good.
		if
			cast
			and cast == activeCast
			and (
				(cast.releasedAt and now - cast.releasedAt > FIZZLE_CONFIRM)
				or now > cast.fullAt + Tuning.Combat.Cast.MaxHold + FIZZLE_CONFIRM
			)
		then
			rollback(cast.skillId)
		end
		local skillId = queued
		if not skillId then
			return
		end
		if os.clock() > queuedUntil or (waitFor(skillId) <= 0 and send(skillId, nil, queuedArg)) then
			queued = nil
		end
	end)
	ProfileController.Changed:Connect(rebuildHotbar)
	TextChatService.SendingMessage:Connect(function(message: TextChatMessage)
		CombatController.CastByName(message.Text)
	end)
	player.CharacterAdded:Connect(function()
		guarding = false
		if drawConnection then
			drawConnection:Disconnect()
			drawConnection = nil
		end
		drawStartedAt = nil
		drawSkill = nil
		activeCast = nil
		lockedUntil = 0
	end)
	GuardAnimations.Start()
	WeaponAnimations.Start()
	RunAnimations.Start()
	CameraController.Changed:Connect(function(on: boolean)
		syncCombatMode(on, true)
	end)
	-- A new character starts sheathed on the server: tell it the mode the camera is in.
	player.CharacterAdded:Connect(function()
		syncCombatMode(CameraController.InCombat(), false)
	end)
	if CameraController.InCombat() then
		syncCombatMode(true, false)
	end
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
