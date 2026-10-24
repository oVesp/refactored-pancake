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
local ALLY_PICK_RADIUS = 8
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

local function nearestTo(pool: { Entity }, point: Vector3, within: number, rewind: number): Entity?
	local best, bestDistance = nil, within
	for _, other in pool do
		local distance = (EntityService.PositionAt(other, rewind) - point).Magnitude
		if distance <= bestDistance then
			best, bestDistance = other, distance
		end
	end
	return best
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

local function resolve(caster: Entity, skill: SkillDef, aim: Vector3)
	if not caster.alive then
		return
	end
	local bonus = spellBonus(caster, skill)
	if bonus > 0 then
		StatusService.Consume(caster, "overcharge")
	end

	local delivery = skill.delivery
	local origin = caster.root.Position
	if delivery == "Melee" or delivery == "Cone" then
		for _, target in arcTargets(caster, aim, skill.range, skill.angle) do
			hitEnemy(caster, target, skill, bonus)
		end
	elseif delivery == "SelfArea" then
		for _, target in areaTargets(caster, skill, origin, skill.radius) do
			if skill.targets == "Ally" then
				supportAlly(caster, target, skill)
			else
				hitEnemy(caster, target, skill, bonus)
			end
		end
	elseif delivery == "Ground" then
		local offset = flat(aim - origin)
		local center = if offset.Magnitude > skill.range then origin + offset.Unit * skill.range else aim
		for _, target in areaTargets(caster, skill, center, skill.radius) do
			hitEnemy(caster, target, skill, bonus)
		end
	elseif delivery == "Projectile" then
		launchProjectile(caster, skill, aim, bonus)
	elseif delivery == "Ally" then
		local target = nearestTo(alliesOf(caster), aim, ALLY_PICK_RADIUS, rewindFor(caster))
		if not target or (target.root.Position - origin).Magnitude > skill.range + Tuning.Combat.RangeTolerance then
			target = caster
		end
		supportAlly(caster, target :: Entity, skill)
	elseif delivery == "Self" then
		if skill.shield then
			supportAlly(caster, caster, skill)
		end
	elseif delivery == "Dash" then
		local target = nearestTo(enemiesOf(caster), aim, ALLY_PICK_RADIUS, rewindFor(caster))
		if target and (target.root.Position - origin).Magnitude <= skill.range + Tuning.Combat.RangeTolerance then
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
	knockback) and resolves it. NPCs call this directly.
]=]
function SkillService.Cast(caster: Entity, skillId: string, aim: Vector3)
	local skill = Skills.ById[skillId]
	if not skill or not caster.alive then
		return
	end
	local now = os.clock()
	caster.cooldowns[skillId] = now + (skill.cooldown or 0)

	local duration, isCast = castDuration(caster, skill)
	if duration <= 0 then
		resolve(caster, skill, aim)
		return
	end

	caster.castToken += 1
	local token = caster.castToken
	caster.casting = {
		skillId = skillId,
		endsAt = now + duration,
		aim = aim,
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
			resolve(caster, skill, aim)
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

local function handleUseSkill(player: Player, skillId: string, aim: Vector3, seq: number)
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
	SkillService.Cast(caster, skillId, aim)
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

	NetServer.Connect("UseSkill", function(player: Player, skillId: string, aim: Vector3, seq: number)
		withLatency(player, function()
			handleUseSkill(player, skillId, aim, seq)
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
