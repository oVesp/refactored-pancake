--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Classes = require(ReplicatedStorage.Content.Classes)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Logger = require(ReplicatedStorage.Shared.Logger)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Skills = require(ReplicatedStorage.Content.Skills)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type SkillDef = any

local PROJECTILE_RADIUS = 2.5
local ENTITY_RADIUS = 2
local OBJECT_PICK_RADIUS = 10
local CAST_ORIGIN_HEIGHT = 1.5
-- Aim is a direction hint; deliveries clamp to their own range. Farther aims are malformed.
local MAX_AIM_DISTANCE = 300

local log = Logger.new("SkillService")

local CombatService: any
local DataService: any
local EntityService: any
local StatService: any
local StatusService: any

local nextCastId = 0
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude

--[=[
	Resolves every skill use, for players (validated `UseSkill`) and NPCs (`Cast`), through one
	authoritative timeline (game-design.md 5.5): checks, cost, cooldown, windup/cast, then the
	delivery's hit test. Clients only predict visuals.
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

--[=[ Active skills a player may use: basic attacks, granted class actives and known spells. ]=]
function SkillService.KnownActives(profile: any): { string }
	local known = { Skills.Basic.Light, Skills.Basic.Heavy }
	for _, skillId in Formulas.GrantedSkills(profile.classes, Classes.ById) do
		local skill = Skills.ById[skillId]
		if skill and skill.kind == "Active" then
			table.insert(known, skillId)
		end
	end
	for _, spellId in profile.spells do
		table.insert(known, spellId)
	end
	return known
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

local function hitEnemy(caster: Entity, target: Entity, skill: SkillDef, bonus: number)
	if skill.damage then
		local dealt = CombatService.DealDamage(caster, target, skill.damage, skill.id, bonus)
		if dealt <= 0 and not CombatService.CanHarm(caster, target) then
			return
		end
	end
	CombatService.ApplyEffects(caster, target, skill.effects, caster.extras.StatusChance)
	if skill.knockback then
		CombatService.Knockback(target, caster.root.Position, skill.knockback)
	end
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

local function launchProjectile(caster: Entity, skill: SkillDef, aim: Vector3, bonus: number)
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
	})

	local travelled = 0
	local position = origin
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		local step = math.min(skill.speed * dt, skill.range - travelled)
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
				hitEnemy(caster, other, skill, bonus)
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
local function launchHoming(caster: Entity, skill: SkillDef, target: Entity, bonus: number)
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
			hitEnemy(caster, target, skill, bonus)
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
	local key = if skill.objectTag == "Kindleable" then "Kindled" else "Purified"
	best:SetAttribute(if key == "Kindled" then "Lit" else "Purified", true)
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

	local delivery = skill.delivery
	local origin = caster.root.Position
	local shownTarget: Model? = nil
	if delivery == "Melee" or delivery == "Cone" then
		for _, victim in arcTargets(caster, aim, skill.range, skill.angle) do
			hitEnemy(caster, victim, skill, bonus)
		end
	elseif delivery == "SelfArea" then
		for _, victim in areaTargets(caster, skill, origin, skill.radius) do
			if skill.targets == "Ally" then
				supportAlly(caster, victim, skill)
			else
				hitEnemy(caster, victim, skill, bonus)
			end
		end
	elseif delivery == "Ground" then
		local offset = flat(aim - origin)
		local center = if offset.Magnitude > skill.range then origin + offset.Unit * skill.range else aim
		for _, victim in areaTargets(caster, skill, center, skill.radius) do
			hitEnemy(caster, victim, skill, bonus)
		end
	elseif delivery == "Projectile" then
		launchProjectile(caster, skill, aim, bonus)
	elseif delivery == "Target" then
		if target and validEnemy(caster, target, skill) then
			launchHoming(caster, skill, target, bonus)
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
	elseif delivery == "Dash" then
		if target and validEnemy(caster, target, skill) then
			local away = flat(origin - target.root.Position)
			local offset = if away.Magnitude > 1e-3 then away.Unit * 3.5 else Vector3.new(0, 0, 3.5)
			teleport(caster, target.root.Position + offset, target.root.Position)
			hitEnemy(caster, target, skill, bonus)
		end
	elseif delivery == "Blink" then
		local offset = flat(aim - origin)
		local distance = math.min(offset.Magnitude, skill.range)
		if distance > 1 then
			local direction = offset.Unit
			local wall = workspace:Raycast(origin, direction * distance, worldParams)
			local travel = if wall then math.max(0, (wall.Position - origin).Magnitude - 2.5) else distance
			local destination = groundBelow(origin + direction * travel)
			teleport(
				caster,
				destination + Vector3.new(0, origin.Y - groundBelow(origin).Y, 0),
				origin + direction * 100
			)
		end
	elseif delivery == "Object" then
		useObject(caster, skill, aim)
	end
	if delivery ~= "Projectile" and delivery ~= "Target" then
		broadcast({
			kind = "Resolve",
			caster = caster.model,
			skillId = skill.id,
			origin = origin,
			aim = aim,
			target = shownTarget,
		})
	end

	for _, effect in (skill.selfEffects or {}) :: { any } do
		StatusService.Apply(caster, effect.status, effect.duration or 1, effect.magnitude, caster)
	end
end

local function castDuration(caster: Entity, skill: SkillDef): (number, boolean)
	if skill.castTime then
		local speed = 1 + (caster.stats.Agility or 0) * Tuning.Combat.CastSpeedPerAgility
		return skill.castTime / speed, true
	end
	if skill.windup then
		local windup = skill.windup
		if skill.id == Skills.Basic.Heavy then
			windup *= math.max(0.1, 1 - (caster.extras.HeavySpeed or 0))
		end
		return windup, false
	end
	return 0, false
end

--[=[
	Starts a skill for any entity after its checks have passed: pays nothing, sets the cooldown,
	broadcasts the cast or telegraph, waits out the windup/cast (interruptible by stun or
	knockback) and resolves it. `target` is the chosen enemy (Target, Dash) or ally (Ally); it is
	re-validated when the skill resolves. NPCs call this directly.
]=]
function SkillService.Cast(caster: Entity, skillId: string, aim: Vector3, target: Entity?)
	local skill = Skills.ById[skillId]
	if not skill or not caster.alive then
		return
	end
	local now = os.clock()
	caster.cooldowns[skillId] = now + (skill.cooldown or 0)

	local duration, isCast = castDuration(caster, skill)
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
	}
	local id = castId()
	broadcast({
		id = id,
		kind = if isCast then "Cast" else "Telegraph",
		caster = caster.model,
		skillId = skillId,
		origin = caster.root.Position,
		aim = aim,
		target = if target then target.model else nil,
		duration = duration,
	})
	caster.model:SetAttribute("Casting", skillId)

	task.delay(duration, function()
		local cast = caster.casting
		if not cast or cast.token ~= token then
			return
		end
		caster.casting = nil
		caster.model:SetAttribute("Casting", nil)
		if caster.alive and not StatusService.IsDisabled(caster) then
			resolve(caster, skill, aim, target)
		end
	end)
end

--[=[ Cancels a cast in progress. Returns true if one was cancelled. ]=]
function SkillService.Interrupt(caster: Entity): boolean
	local cast = caster.casting
	if not cast then
		return false
	end
	caster.casting = nil
	caster.model:SetAttribute("Casting", nil)
	impact(0, caster.root.Position, "interrupt")
	NetServer.FireAll("ShowCast", { kind = "Interrupted", caster = caster.model, skillId = cast.skillId })
	return true
end

--[=[ Seconds until a skill is ready for an entity. ]=]
function SkillService.CooldownRemaining(caster: Entity, skillId: string): number
	return math.max(0, (caster.cooldowns[skillId] or 0) - os.clock())
end

local function reject(player: Player, seq: number, reason: string)
	NetServer.Fire("RejectSkill", player, seq, reason)
end

local function handleUseSkill(player: Player, skillId: string, aim: Vector3, seq: number, targetModel: Model?)
	local caster = EntityService.ForPlayer(player)
	local profile = DataService.Get(player)
	if not caster or not profile or not caster.alive then
		reject(player, seq, "Dead")
		return
	end
	local skill = Skills.ById[skillId]
	if not skill or skill.kind ~= "Active" or not table.find(SkillService.KnownActives(profile), skillId) then
		reject(player, seq, "Unknown")
		return
	end
	if StatusService.IsDisabled(caster) then
		reject(player, seq, "Disabled")
		return
	end
	if caster.casting then
		reject(player, seq, "Busy")
		return
	end
	if SkillService.CooldownRemaining(caster, skillId) > 0.05 then
		reject(player, seq, "Cooldown")
		return
	end
	if (aim - caster.root.Position).Magnitude > MAX_AIM_DISTANCE then
		reject(player, seq, "Range")
		return
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
	else
		target = nil
	end
	if skill.cost then
		local amount = skill.cost.amount
		if skill.source == "Spell" and caster.statuses.overcharge then
			amount *= 1 + caster.extras.SpellCost
		end
		if not StatService.Spend(caster, skill.cost.resource, amount) then
			reject(player, seq, "Resource")
			return
		end
	end
	if caster.guardSince then
		caster.guardSince = nil
		caster.model:SetAttribute("Guarding", false)
	end
	SkillService.Cast(caster, skillId, aim, target)
end

local function withLatency(player: Player, fn: () -> ())
	local simulated = player:GetAttribute("SimLatencyMs")
	if RunService:IsStudio() and type(simulated) == "number" and simulated > 0 then
		task.delay(simulated / 1000, fn)
	else
		fn()
	end
end

local function handleGuard(player: Player, on: boolean)
	local entity = EntityService.ForPlayer(player)
	if not entity or not entity.alive then
		return
	end
	if on and (entity.casting or StatusService.IsDisabled(entity) or entity.stamina <= 0) then
		on = false
	end
	entity.guardSince = if on then os.clock() else nil
	entity.model:SetAttribute("Guarding", on)
end

local dodgeReadyAt: { [Player]: number } = {}

local function handleDodge(player: Player, direction: Vector3, seq: number)
	local entity = EntityService.ForPlayer(player)
	local dodge = Tuning.Combat.Dodge
	local now = os.clock()
	if not entity or not entity.alive or StatusService.IsImmobile(entity) or entity.casting then
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
end

function SkillService.Init(deps: { [string]: any })
	CombatService = deps.CombatService
	DataService = deps.DataService
	EntityService = deps.EntityService
	StatService = deps.StatService
	StatusService = deps.StatusService

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
	NetServer.Connect("Dodge", function(player: Player, direction: Vector3, seq: number)
		withLatency(player, function()
			handleDodge(player, direction, seq)
		end)
	end)
end

function SkillService.Start()
	StatusService.Interrupted:Connect(function(entity: Entity)
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
