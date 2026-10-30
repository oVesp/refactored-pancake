--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Archery = require(ReplicatedStorage.Shared.Archery)
local Chain = require(ReplicatedStorage.Shared.Chain)
local Classes = require(ReplicatedStorage.Content.Classes)
local DevSkills = require(ReplicatedStorage.Shared.DevSkills)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Items = require(ReplicatedStorage.Content.Items)
local Loadout = require(ReplicatedStorage.Shared.Loadout)
local Logger = require(ReplicatedStorage.Shared.Logger)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Skills = require(ReplicatedStorage.Content.Skills)
local Statuses = require(ReplicatedStorage.Content.Statuses)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Weapons = require(ReplicatedStorage.Content.Weapons)
local DevService = require(script.Parent.DevService)
local DevSkillEffects = require(script.Parent.Parent.DevSkillEffects)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type SkillDef = any

local PROJECTILE_RADIUS = 2.5
local ENTITY_RADIUS = 2
local OBJECT_PICK_RADIUS = 10
local CAST_ORIGIN_HEIGHT = 1.5
-- Aim is a direction hint; deliveries clamp to their own range. Farther aims are malformed.
local MAX_AIM_DISTANCE = 300
-- Seconds a use may arrive early for its cooldown, GCD or lock (network jitter).
local LATENCY_SLACK = 0.05
-- Seconds a chain hit may arrive past Tuning.Combat.Chain.Window (network jitter).
local CHAIN_SLACK = 0.15

local log = Logger.new("SkillService")

local CombatService: any
local DataService: any
local EntityService: any
local StatService: any
local StatusService: any

local nextCastId = 0
-- Chat argument of a dev skill use, read when it resolves (Gate's destination).
local devArgs: { [Entity]: string } = {}
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude

--[=[
	Resolves every skill use, for players (validated `UseSkill`) and NPCs (`Cast`), through one
	authoritative timeline (game-design.md 5.5): checks, GCD/cooldown/animation lock, windup or
	cast (cancelled by moving before the slidecast window), cost, then the delivery's hit test.
	Clients only predict visuals and timers.
]=]
local SkillService = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function castId(): number
	nextCastId += 1
	return nextCastId
end

local function broadcast(info: { [string]: any })
	NetServer.FireAll("ShowCast", info)
end

local function impact(id: number, position: Vector3, kind: string)
	NetServer.FireAll("ShowImpact", id, position, kind)
end

local function refreshWorldFilter()
	local exclude: { Instance } = {}
	for model in EntityService.All() do
		table.insert(exclude, model)
	end
	worldParams.FilterDescendantsInstances = exclude
end

--[=[
	Active skills a player may use: the equipped weapon's basic attacks (plus the shield bash),
	granted class actives, known spells and, for developers, the dev skills.
]=]
function SkillService.KnownActives(profile: any, isDev: boolean?): { string }
	local held = Loadout.Of(profile, Items.ById, Weapons.ById, Weapons.Default)
	local known = Loadout.Basics(Skills.ById, held.weapon, held.shield ~= nil, Weapons.ShieldBash)
	for _, skillId in Formulas.GrantedSkills(profile.classes, Classes.ById) do
		local skill = Skills.ById[skillId]
		if skill and skill.kind == "Active" then
			table.insert(known, skillId)
		end
	end
	for _, spellId in profile.spells do
		table.insert(known, spellId)
	end
	return DevSkills.Grant(known, isDev == true, Skills.ById)
end

local function enemiesOf(caster: Entity): { Entity }
	local list = {}
	for _, other in EntityService.All() do
		if other.alive and EntityService.AreEnemies(caster, other) then
			table.insert(list, other)
		end
	end
	return list
end

local function alliesOf(caster: Entity): { Entity }
	local list = {}
	for _, other in EntityService.All() do
		if other.alive and other.team == caster.team then
			table.insert(list, other)
		end
	end
	return list
end

local function rewindFor(caster: Entity): number
	return EntityService.RewindFor(caster.player)
end

local function spellBonus(caster: Entity, skill: SkillDef): number
	if skill.source == "Spell" and caster.statuses.overcharge then
		return caster.extras.SpellDamage
	end
	return 0
end

local function hitEnemy(caster: Entity, target: Entity, skill: SkillDef, bonus: number, mods: any?)
	if skill.rearBonus then
		local look = target.root.CFrame.LookVector
		if Archery.FromBehind(target.root.Position, look, caster.root.Position, Tuning.Combat.Bow.RearArc) then
			bonus += skill.rearBonus
		end
	end
	if skill.damage then
		local dealt = CombatService.DealDamage(caster, target, skill.damage, skill.id, bonus, mods)
		if dealt <= 0 and not CombatService.CanHarm(caster, target) then
			return
		end
	end
	CombatService.ApplyEffects(caster, target, skill.effects, caster.extras.StatusChance)
	if skill.knockback then
		CombatService.Knockback(target, caster.root.Position, skill.knockback)
	end
end

--[=[ Self effects of a skill for this caster, after upgrade passives (Formulas.CollectTraits). ]=]
local function selfEffectsOf(caster: Entity, skill: SkillDef): { any }
	local upgrade = caster.traits.upgrades[skill.id]
	return (upgrade and upgrade.selfEffects) or skill.selfEffects or {}
end

local function chargesOf(caster: Entity, skill: SkillDef): number
	local upgrade = caster.traits.upgrades[skill.id]
	return (upgrade and upgrade.charges) or skill.charges or 1
end

local function applySelfEffects(caster: Entity, skill: SkillDef)
	for _, effect in selfEffectsOf(caster, skill) do
		StatusService.Apply(caster, effect.status, effect.duration or 1, effect.magnitude, caster)
	end
end

-- Spends the caster's next-hit statuses (Gather Strength, Disengage) on a damaging skill.
-- Returns the outgoing bonus and crit mods every hit of this use shares.
local function spendNextHit(caster: Entity, skill: SkillDef): (number, any?)
	if not skill.damage then
		return 0, if skill.critChance then { critChance = skill.critChance } else nil
	end
	local bonus = 0
	local mods = { critChance = skill.critChance, forceCrit = false }
	for id, status in table.clone(caster.statuses) do
		local def = Statuses.ById[id]
		local nextHit = def and def.nextHit
		if nextHit then
			if nextHit.damage then
				bonus += status.magnitude
			end
			if nextHit.crit then
				mods.forceCrit = true
			end
			StatusService.Consume(caster, id)
		end
	end
	return bonus, mods
end

local function supportAlly(caster: Entity, target: Entity, skill: SkillDef)
	local healingBonus = caster.extras.HealingDone or 0
	if skill.heal then
		local amount =
			Formulas.ResolveHeal(skill.heal.base, caster.stats[skill.heal.stat] or 0, skill.heal.ratio, healingBonus)
		CombatService.Heal(caster, target, amount)
	end
	if skill.shield then
		local amount = Formulas.ResolveHeal(
			skill.shield.base,
			caster.stats[skill.shield.stat] or 0,
			skill.shield.ratio,
			healingBonus
		)
		CombatService.Shield(target, amount)
	end
	CombatService.ApplyEffects(caster, target, skill.effects, 0)
end

local function areaTargets(caster: Entity, skill: SkillDef, center: Vector3, radius: number): { Entity }
	local rewind = rewindFor(caster)
	local pool: { Entity } = if skill.targets == "Ally" then alliesOf(caster) else enemiesOf(caster)
	local hits = {}
	for _, other in pool do
		local position = EntityService.PositionAt(other, rewind)
		if (flat(position) - flat(center)).Magnitude <= radius + ENTITY_RADIUS then
			table.insert(hits, other)
		end
	end
	return hits
end

local function arcTargets(caster: Entity, aim: Vector3, range: number, angle: number): { Entity }
	local rewind = rewindFor(caster)
	local origin = caster.root.Position
	local facing = flat(aim - origin)
	if facing.Magnitude < 1e-3 then
		facing = flat(caster.root.CFrame.LookVector)
	end
	local hits = {}
	for _, other in enemiesOf(caster) do
		local p = EntityService.PositionAt(other, rewind)
		if Formulas.InArc(origin.X, origin.Z, facing.X, facing.Z, p.X, p.Z, range + ENTITY_RADIUS, angle) then
			if math.abs(p.Y - origin.Y) < 12 then
				table.insert(hits, other)
			end
		end
	end
	return hits
end

local function inRange(caster: Entity, target: Entity, range: number): boolean
	local position = EntityService.PositionAt(target, rewindFor(caster))
	return (position - caster.root.Position).Magnitude <= range + Tuning.Combat.RangeTolerance
end

--[=[ True when a skill needs an enemy target chosen by the caster (no target, no cast). ]=]
local function needsEnemyTarget(skill: SkillDef): boolean
	return skill.delivery == "Target" or skill.delivery == "Dash"
end

local function validEnemy(caster: Entity, target: Entity?, skill: SkillDef): boolean
	return target ~= nil
		and target.alive
		and EntityService.AreEnemies(caster, target)
		and inRange(caster, target, skill.range or 0)
end

local function validAlly(caster: Entity, target: Entity?, skill: SkillDef): boolean
	return target ~= nil and target.alive and target.team == caster.team and inRange(caster, target, skill.range or 0)
end

local function groundBelow(position: Vector3): Vector3
	local result = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), worldParams)
	return if result then result.Position else position
end

local function teleport(caster: Entity, destination: Vector3, faceToward: Vector3?)
	local look = if faceToward then flat(faceToward - destination) else flat(caster.root.CFrame.LookVector)
	local cframe = if look.Magnitude > 1e-3
		then CFrame.lookAt(destination, destination + look)
		else CFrame.new(destination)
	if caster.player then
		EntityService.NoteTeleport(caster.player)
	end
	caster.model:PivotTo(cframe)
end

-- Moves the caster up to `distance` studs along flat `direction`, stopping short of walls, and
-- faces it along `facing` (Blink forward, Leap backward).
local function travelAlong(caster: Entity, direction: Vector3, distance: number, facing: Vector3)
	if distance <= 1 then
		return
	end
	local origin = caster.root.Position
	local wall = workspace:Raycast(origin, direction * distance, worldParams)
	local travel = if wall then math.max(0, (wall.Position - origin).Magnitude - 2.5) else distance
	local destination = groundBelow(origin + direction * travel)
	teleport(caster, destination + Vector3.new(0, origin.Y - groundBelow(origin).Y, 0), destination + facing * 100)
end

local function launchProjectile(caster: Entity, skill: SkillDef, aim: Vector3, bonus: number, mods: any?)
	local origin = caster.root.Position + Vector3.new(0, CAST_ORIGIN_HEIGHT, 0)
	local toAim = aim - origin
	local direction = if toAim.Magnitude > 1e-3 then toAim.Unit else caster.root.CFrame.LookVector
	local id = castId()
	broadcast({
		id = id,
		kind = "Projectile",
		caster = caster.model,
		skillId = skill.id,
		origin = origin,
		direction = direction,
		speed = skill.speed,
		range = skill.range,
		gravity = skill.gravity,
	})

	-- Arrows fall (`gravity`); the path length still ends at `range`.
	local velocity = direction * skill.speed
	local fall = Vector3.new(0, -(skill.gravity or 0), 0)
	local travelled = 0
	local position = origin
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		velocity += fall * dt
		direction = velocity.Unit
		local step = math.min(velocity.Magnitude * dt, skill.range - travelled)
		local nextPosition = position + direction * step

		local wall = workspace:Raycast(position, direction * step, worldParams)
		local segmentEnd = if wall then wall.Position else nextPosition

		for _, other in enemiesOf(caster) do
			local p = other.root.Position
			local along = math.clamp((p - position):Dot(direction), 0, (segmentEnd - position).Magnitude)
			local closest = position + direction * along
			if (p - closest).Magnitude <= PROJECTILE_RADIUS + ENTITY_RADIUS then
				connection:Disconnect()
				impact(id, closest, "hit")
				hitEnemy(caster, other, skill, bonus, mods)
				return
			end
		end

		travelled += step
		position = segmentEnd
		if wall or travelled >= skill.range then
			connection:Disconnect()
			impact(id, position, "miss")
		end
	end)
end

-- Homing spell: chases one target, cannot hit anyone else, stops on walls and gives up after
-- HomingRangeFactor x range (Tuning.Targeting).
local function launchHoming(caster: Entity, skill: SkillDef, target: Entity, bonus: number, mods: any?)
	local origin = caster.root.Position + Vector3.new(0, CAST_ORIGIN_HEIGHT, 0)
	local toTarget = target.root.Position - origin
	local id = castId()
	broadcast({
		id = id,
		kind = "Projectile",
		caster = caster.model,
		skillId = skill.id,
		origin = origin,
		direction = if toTarget.Magnitude > 1e-3 then toTarget.Unit else caster.root.CFrame.LookVector,
		speed = skill.speed,
		range = skill.range * Tuning.Targeting.HomingRangeFactor,
		homing = target.model,
	})

	local maxTravel = skill.range * Tuning.Targeting.HomingRangeFactor
	local travelled = 0
	local position = origin
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not target.alive or not target.root.Parent then
			connection:Disconnect()
			impact(id, position, "miss")
			return
		end
		local offset = target.root.Position - position
		local step = math.min(skill.speed * dt, maxTravel - travelled)
		if offset.Magnitude <= step + PROJECTILE_RADIUS + ENTITY_RADIUS then
			connection:Disconnect()
			impact(id, target.root.Position, "hit")
			hitEnemy(caster, target, skill, bonus, mods)
			return
		end
		local direction = offset.Unit
		local wall = workspace:Raycast(position, direction * step, worldParams)
		travelled += step
		position = if wall then wall.Position else position + direction * step
		if wall or travelled >= maxTravel then
			connection:Disconnect()
			impact(id, position, "miss")
		end
	end)
end

local function useObject(caster: Entity, skill: SkillDef, aim: Vector3)
	local best: BasePart?, bestDistance = nil, OBJECT_PICK_RADIUS
	for _, instance in CollectionService:GetTagged(skill.objectTag) do
		if instance:IsA("BasePart") then
			local distance = (instance.Position - aim).Magnitude
			if distance <= bestDistance and (instance.Position - caster.root.Position).Magnitude <= skill.range + 6 then
				best, bestDistance = instance, distance
			end
		end
	end
	if not best then
		return
	end
	for _, child in best:GetChildren() do
		if child:IsA("Fire") or child:IsA("Light") or child:IsA("ParticleEmitter") then
			(child :: any).Enabled = true
		end
	end
	local key = skill.objectNotice or (if skill.objectTag == "Kindleable" then "Kindled" else "Purified")
	best:SetAttribute(skill.objectAttribute or (if key == "Kindled" then "Lit" else "Purified"), true)
	if caster.player then
		NetServer.Fire("Notify", caster.player, key, {})
	end
end

local function resolve(caster: Entity, skill: SkillDef, aim: Vector3, target: Entity?)
	if not caster.alive then
		return
	end
	local bonus = spellBonus(caster, skill)
	if bonus > 0 then
		StatusService.Consume(caster, "overcharge")
	end
	local nextBonus, mods = spendNextHit(caster, skill)
	bonus += nextBonus
	if skill.drawn then
		bonus += caster.drawBonus
		caster.drawBonus = 0
	end

	local delivery = skill.delivery
	local origin = caster.root.Position
	local shownTarget: Model? = nil
	if delivery == "Melee" or delivery == "Cone" then
		local victims = arcTargets(caster, aim, skill.range, skill.angle)
		if skill.maxTargets and #victims > skill.maxTargets then
			table.sort(victims, function(a, b)
				return (a.root.Position - origin).Magnitude < (b.root.Position - origin).Magnitude
			end)
			victims = table.move(victims, 1, skill.maxTargets, 1, {})
		end
		for _, victim in victims do
			hitEnemy(caster, victim, skill, bonus, mods)
		end
	elseif delivery == "SelfArea" then
		for _, victim in areaTargets(caster, skill, origin, skill.radius) do
			if skill.targets == "Ally" then
				supportAlly(caster, victim, skill)
			else
				hitEnemy(caster, victim, skill, bonus, mods)
			end
		end
	elseif delivery == "Ground" then
		local offset = flat(aim - origin)
		local center = if offset.Magnitude > skill.range then origin + offset.Unit * skill.range else aim
		for _, victim in areaTargets(caster, skill, center, skill.radius) do
			hitEnemy(caster, victim, skill, bonus, mods)
		end
	elseif delivery == "Projectile" then
		launchProjectile(caster, skill, aim, bonus, mods)
	elseif delivery == "Target" then
		if target and validEnemy(caster, target, skill) then
			launchHoming(caster, skill, target, bonus, mods)
		else
			impact(0, origin, "miss")
		end
	elseif delivery == "Ally" then
		local ally = if target and validAlly(caster, target, skill) then target else caster
		shownTarget = ally.model
		supportAlly(caster, ally, skill)
	elseif delivery == "Self" then
		if skill.shield then
			supportAlly(caster, caster, skill)
		end
		local restore = skill.restore
		if restore and restore.Hp then
			CombatService.Heal(caster, caster, caster.stats.MaxHp * restore.Hp)
		end
		if restore and restore.Stamina then
			StatService.Restore(caster, "Stamina", caster.maxStamina * restore.Stamina)
		end
	elseif delivery == "Dash" then
		if target and validEnemy(caster, target, skill) then
			local away = flat(origin - target.root.Position)
			local offset = if away.Magnitude > 1e-3 then away.Unit * 3.5 else Vector3.new(0, 0, 3.5)
			teleport(caster, target.root.Position + offset, target.root.Position)
			hitEnemy(caster, target, skill, bonus, mods)
		end
	elseif delivery == "Blink" then
		local offset = flat(aim - origin)
		if offset.Magnitude > 1 then
			travelAlong(caster, offset.Unit, math.min(offset.Magnitude, skill.range), offset.Unit)
		end
	elseif delivery == "Leap" then
		local forward = flat(aim - origin)
		if forward.Magnitude < 1e-3 then
			forward = flat(caster.root.CFrame.LookVector)
		end
		if forward.Magnitude > 1e-3 then
			travelAlong(caster, -forward.Unit, skill.range, forward.Unit)
		end
	elseif delivery == "Object" then
		useObject(caster, skill, aim)
	elseif delivery == "Dev" then
		local arg = devArgs[caster]
		devArgs[caster] = nil
		DevSkillEffects.Resolve(caster, skill, target, arg)
	end
	if delivery ~= "Projectile" and delivery ~= "Target" and delivery ~= "Dev" then
		broadcast({
			kind = "Resolve",
			caster = caster.model,
			skillId = skill.id,
			origin = origin,
			aim = aim,
			target = shownTarget,
		})
	end

	applySelfEffects(caster, skill)
end

local function hasted(caster: Entity, seconds: number): number
	return Formulas.Hasted(seconds, caster.extras.Haste or 0, Tuning.Combat.Gcd.MaxHaste)
end

local function endCommit(caster: Entity)
	if caster.commitUntil > 0 then
		caster.commitUntil = 0
		StatService.Recompute(caster)
	end
end

local function castDuration(caster: Entity, skill: SkillDef): (number, boolean)
	if skill.castTime then
		return hasted(caster, skill.castTime), true
	end
	if skill.windup then
		local windup = skill.windup
		if skill.heavy then
			windup *= math.max(0.1, 1 - (caster.extras.HeavySpeed or 0))
		end
		return windup, false
	end
	return 0, false
end

-- Slows the caster until `endsAt` (a melee swing and its recovery) and restores speed after.
local function commit(caster: Entity, endsAt: number)
	caster.commitUntil = endsAt
	StatService.Recompute(caster)
	task.delay(endsAt - os.clock(), function()
		if caster.commitUntil == endsAt then
			endCommit(caster)
		end
	end)
end

-- Cancels the cast when the caster drifts more than MoveTolerance before the slidecast window.
local function watchMovement(caster: Entity, token: number, slideAt: number)
	local start = flat(caster.root.Position)
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local cast = caster.casting
		if not cast or cast.token ~= token or os.clock() >= slideAt then
			connection:Disconnect()
			return
		end
		if (flat(caster.root.Position) - start).Magnitude > Tuning.Combat.Gcd.MoveTolerance then
			connection:Disconnect()
			SkillService.Interrupt(caster)
		end
	end)
end

--[=[
	Starts a skill for any entity after its checks have passed. Sets the skill's own cooldown, the
	GCD (`gcd` skills) and the animation lock (non-basic player actions), broadcasts the cast or
	telegraph, waits out the windup/cast and resolves it. A cast is cancelled by stun, knockback,
	dodging or moving before the slidecast window (players and interruptible NPC casts); `cost`,
	when given, is paid only if the cast completes. `target` is the chosen enemy (Target, Dash) or
	ally (Ally); it is re-validated when the skill resolves. NPCs call this directly.
]=]
function SkillService.Cast(
	caster: Entity,
	skillId: string,
	aim: Vector3,
	target: Entity?,
	cost: { resource: "Mp" | "Stamina", amount: number }?
)
	local skill = Skills.ById[skillId]
	if not skill or not caster.alive then
		return
	end
	local now = os.clock()
	local timing = Tuning.Combat.Gcd
	if skill.cooldown then
		caster.cooldowns[skillId] = Formulas.ChargeSpend(caster.cooldowns[skillId] or 0, now, skill.cooldown)
	end
	if skill.gcd then
		caster.gcdReadyAt = now + hasted(caster, timing.Base)
	end

	local duration, isCast = castDuration(caster, skill)
	if caster.player and skill.recovery then
		-- A melee swing commits the player until its recovery ends: no actions, slowed.
		local endsAt = now + duration + skill.recovery
		caster.lockedUntil = endsAt
		commit(caster, endsAt)
	elseif caster.player and skill.source ~= "Basic" then
		caster.lockedUntil = now + math.max(duration, timing.AnimationLock)
	end
	if duration <= 0 then
		resolve(caster, skill, aim, target)
		return
	end

	caster.castToken += 1
	local token = caster.castToken
	caster.casting = {
		skillId = skillId,
		endsAt = now + duration,
		aim = aim,
		target = target,
		interruptible = true,
		token = token,
		cost = cost,
	}
	if skill.telegraph ~= false then
		broadcast({
			id = castId(),
			kind = if isCast then "Cast" else "Telegraph",
			caster = caster.model,
			skillId = skillId,
			origin = caster.root.Position,
			aim = aim,
			target = if target then target.model else nil,
			duration = duration,
		})
		caster.model:SetAttribute("Casting", skillId)
	end
	if isCast and (caster.player or skill.interruptible) then
		watchMovement(caster, token, now + duration - timing.SlidecastWindow)
	end

	task.delay(duration, function()
		local cast = caster.casting
		if not cast or cast.token ~= token then
			return
		end
		if not caster.alive or StatusService.IsDisabled(caster) then
			SkillService.Interrupt(caster)
			return
		end
		if cast.cost and not StatService.Spend(caster, cast.cost.resource, cast.cost.amount) then
			SkillService.Interrupt(caster)
			if caster.player then
				NetServer.Fire("Notify", caster.player, "CastNoResource", {})
			end
			return
		end
		caster.casting = nil
		caster.model:SetAttribute("Casting", nil)
		resolve(caster, skill, aim, target)
	end)
end

--[=[
	Cancels a cast in progress and gives back its GCD, cooldown and lock, so the caster can act
	at once (nothing was paid yet). Returns true if one was cancelled.
]=]
function SkillService.Interrupt(caster: Entity): boolean
	local cast = caster.casting
	if not cast then
		return false
	end
	local skill = Skills.ById[cast.skillId]
	local now = os.clock()
	caster.casting = nil
	caster.lockedUntil = now
	endCommit(caster)
	if skill and skill.gcd then
		caster.gcdReadyAt = now
	end
	if skill and skill.cooldown then
		caster.cooldowns[cast.skillId] = math.max(now, (caster.cooldowns[cast.skillId] or now) - skill.cooldown)
	end
	caster.model:SetAttribute("Casting", nil)
	impact(0, caster.root.Position, "interrupt")
	NetServer.FireAll("ShowCast", { kind = "Interrupted", caster = caster.model, skillId = cast.skillId })
	return true
end

--[=[ Seconds until a skill is ready for an entity: its own cooldown and, for `gcd` skills, the GCD. ]=]
function SkillService.CooldownRemaining(caster: Entity, skillId: string): number
	local now = os.clock()
	local skill = Skills.ById[skillId]
	local remaining = (caster.cooldowns[skillId] or 0) - now
	if skill and skill.cooldown then
		remaining =
			Formulas.ChargeReadyIn(caster.cooldowns[skillId] or 0, now, skill.cooldown, chargesOf(caster, skill))
	end
	if skill and skill.gcd then
		remaining = math.max(remaining, caster.gcdReadyAt - now)
	end
	return math.max(0, remaining)
end

local function reject(player: Player, seq: number, reason: string)
	NetServer.Fire("RejectSkill", player, seq, reason)
end

-- Ends a bow draw (shot, cancel, guard, dodge or interrupt) and restores walk speed.
local function stopDraw(entity: Entity)
	if entity.drawSince then
		entity.drawSince = nil
		entity.model:SetAttribute("Drawing", nil)
		StatService.Recompute(entity)
	end
end

local function handleUseSkill(
	player: Player,
	skillId: string,
	aim: Vector3,
	seq: number,
	targetModel: Model?,
	arg: string?
)
	local caster = EntityService.ForPlayer(player)
	local profile = DataService.Get(player)
	if not caster or not profile or not caster.alive then
		reject(player, seq, "Dead")
		return
	end
	local skill = Skills.ById[skillId]
	if
		not skill
		or skill.kind ~= "Active"
		or not table.find(SkillService.KnownActives(profile, DevService.IsDev(player)), skillId)
	then
		reject(player, seq, "Unknown")
		return
	end
	if StatusService.IsDisabled(caster) then
		reject(player, seq, "Disabled")
		return
	end
	if caster.casting or caster.lockedUntil - os.clock() > LATENCY_SLACK then
		reject(player, seq, "Busy")
		return
	end
	if SkillService.CooldownRemaining(caster, skillId) > LATENCY_SLACK then
		reject(player, seq, "Cooldown")
		return
	end
	-- Light chain: each hit waits out the previous hit's cooldown and must follow it in order.
	local weapon = Weapons.ById[caster.weapon] or Weapons.ById[Weapons.Default]
	local chained = Chain.Contains(Skills.ById, weapon.light, skillId)
	if chained then
		local last = caster.chainLast
		if last and SkillService.CooldownRemaining(caster, last) > LATENCY_SLACK then
			reject(player, seq, "Cooldown")
			return
		end
		local window = Tuning.Combat.Chain.Window + CHAIN_SLACK
		if not Chain.Allowed(Skills.ById, weapon.light, last, caster.chainAt, skillId, os.clock(), window) then
			reject(player, seq, "Chain")
			return
		end
	end
	if (aim - caster.root.Position).Magnitude > MAX_AIM_DISTANCE then
		reject(player, seq, "Range")
		return
	end
	-- Bow: the shot needs a draw long enough to fire; its strength comes from the draw time.
	local drawBonus = 0
	if skill.drawn then
		local scale = Archery.DrawScale(os.clock() - (caster.drawSince or math.huge), Tuning.Combat.Bow)
		if scale <= 0 then
			stopDraw(caster)
			reject(player, seq, "Draw")
			return
		end
		drawBonus = scale - 1
	end
	-- The client's target is a suggestion: it must still be alive, on the right side and in range.
	local target = if targetModel then EntityService.Get(targetModel) else nil
	if needsEnemyTarget(skill) then
		if not target or not target.alive or not EntityService.AreEnemies(caster, target) then
			reject(player, seq, "NoTarget")
			return
		end
		if not inRange(caster, target, skill.range or 0) then
			reject(player, seq, "Range")
			return
		end
	elseif skill.delivery == "Ally" then
		if not validAlly(caster, target, skill) then
			target = nil
		end
	elseif skill.delivery == "Dev" then
		-- Dev skills inspect any living entity, at any range.
		if target and not target.alive then
			target = nil
		end
	else
		target = nil
	end
	-- Instant actions pay now; casts check now and pay when they complete.
	local cost: { resource: "Mp" | "Stamina", amount: number }? = nil
	if skill.cost then
		local amount = skill.cost.amount
		if skill.source == "Spell" and caster.statuses.overcharge then
			amount *= 1 + caster.extras.SpellCost
		end
		local resource: "Mp" | "Stamina" = skill.cost.resource
		if resource == "Stamina" then
			amount *= math.max(0, 1 + caster.extras.StaminaCost)
		end
		local available = if resource == "Mp" then caster.mp else caster.stamina
		if available < amount then
			reject(player, seq, "Resource")
			return
		end
		if skill.castTime then
			cost = { resource = resource, amount = amount }
		else
			StatService.Spend(caster, resource, amount)
		end
	end
	if caster.guardSince then
		caster.guardSince = nil
		caster.model:SetAttribute("Guarding", false)
	end
	stopDraw(caster)
	if skill.drawn then
		caster.drawBonus = drawBonus
	end
	if chained then
		caster.chainLast = skillId
		caster.chainAt = os.clock()
	end
	if skill.delivery == "Dev" and arg then
		devArgs[caster] = arg
	end
	SkillService.Cast(caster, skillId, aim, target, cost)
end

local function withLatency(player: Player, fn: () -> ())
	local simulated = player:GetAttribute("SimLatencyMs")
	if RunService:IsStudio() and type(simulated) == "number" and simulated > 0 then
		task.delay(simulated / 1000, fn)
	else
		fn()
	end
end

--[=[
	Runs a player's skill use through the same checks as `UseSkill` (chat casting uses it).
	`arg` is a dev skill's chat argument.
]=]
function SkillService.Use(player: Player, skillId: string, aim: Vector3, seq: number, target: Model?, arg: string?)
	withLatency(player, function()
		handleUseSkill(player, skillId, aim, seq, target, arg)
	end)
end

local function handleGuard(player: Player, on: boolean)
	local entity = EntityService.ForPlayer(player)
	if not entity or not entity.alive then
		return
	end
	if on and (entity.casting or StatusService.IsDisabled(entity) or entity.stamina <= 0) then
		on = false
	end
	local weapon = Weapons.ById[entity.weapon] or Weapons.ById[Weapons.Default]
	if on and not Loadout.CanGuard(weapon, entity.shieldGuard ~= nil) then
		on = false
	end
	if on then
		stopDraw(entity)
	end
	entity.guardSince = if on then os.clock() else nil
	entity.model:SetAttribute("Guarding", on)
end

-- Starts or cancels a bow draw. Only a drawn weapon draws, and not while busy or guarding.
local function handleDraw(player: Player, on: boolean)
	local entity = EntityService.ForPlayer(player)
	if not entity or not entity.alive then
		return
	end
	local weapon = Weapons.ById[entity.weapon]
	local busy = entity.casting ~= nil
		or entity.guardSince ~= nil
		or entity.lockedUntil - os.clock() > LATENCY_SLACK
		or StatusService.IsDisabled(entity)
	if not on or not weapon or not weapon.drawn or busy then
		stopDraw(entity)
		return
	end
	if not entity.drawSince then
		entity.drawSince = os.clock()
		entity.model:SetAttribute("Drawing", true)
		StatService.Recompute(entity)
	end
end

local dodgeReadyAt: { [Player]: number } = {}

local function handleDodge(player: Player, direction: Vector3, seq: number)
	local entity = EntityService.ForPlayer(player)
	local dodge = Tuning.Combat.Dodge
	local now = os.clock()
	if not entity or not entity.alive or StatusService.IsImmobile(entity) then
		reject(player, seq, "Dodge")
		return
	end
	if now < (dodgeReadyAt[player] or 0) or flat(direction).Magnitude < 0.5 then
		reject(player, seq, "Dodge")
		return
	end
	if not StatService.Spend(entity, "Stamina", dodge.StaminaCost) then
		reject(player, seq, "Dodge")
		return
	end
	dodgeReadyAt[player] = now + dodge.Cooldown
	entity.invulnerableUntil = now + dodge.Invulnerable
	-- Dodge cancels a swing in its windup (Interrupt) or recovery, and a bow draw.
	stopDraw(entity)
	SkillService.Interrupt(entity)
	entity.lockedUntil = now
	endCommit(entity)
end

function SkillService.Init(deps: { [string]: any })
	CombatService = deps.CombatService
	DataService = deps.DataService
	EntityService = deps.EntityService
	StatService = deps.StatService
	StatusService = deps.StatusService
	DevSkillEffects.Init(deps)

	NetServer.Connect("UseSkill", function(player: Player, skillId: string, aim: Vector3, seq: number, target: Model?)
		withLatency(player, function()
			handleUseSkill(player, skillId, aim, seq, target)
		end)
	end)
	NetServer.Connect("SetGuard", function(player: Player, on: boolean)
		withLatency(player, function()
			handleGuard(player, on)
		end)
	end)
	NetServer.Connect("SetDraw", function(player: Player, on: boolean)
		withLatency(player, function()
			handleDraw(player, on)
		end)
	end)
	NetServer.Connect("Dodge", function(player: Player, direction: Vector3, seq: number)
		withLatency(player, function()
			handleDodge(player, direction, seq)
		end)
	end)
end

function SkillService.Start()
	StatusService.Expired:Connect(function(entity: Entity, statusId: string)
		local def = Statuses.ById[statusId]
		local skill = def and def.expireSkill and Skills.ById[def.expireSkill]
		if skill and entity.alive then
			applySelfEffects(entity, skill)
		end
	end)
	StatusService.Interrupted:Connect(function(entity: Entity)
		stopDraw(entity)
		if SkillService.Interrupt(entity) then
			log:Debug("Interrupted %s", entity.name)
		end
	end)
	EntityService.Added:Connect(refreshWorldFilter)
	EntityService.Removing:Connect(function()
		task.defer(refreshWorldFilter)
	end)
	Players.PlayerRemoving:Connect(function(player)
		dodgeReadyAt[player] = nil
	end)
	refreshWorldFilter()
end

return SkillService
