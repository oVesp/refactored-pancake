--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Relations = require(ReplicatedStorage.Shared.Relations)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Statuses = require(ReplicatedStorage.Content.Statuses)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type Effect = { status: string, duration: number?, magnitude: number?, chance: number? }

local SHOW_RADIUS = 90
local PARRY_STAGGER = 0.6
local SHIELD_SECONDS = 15
local KNOCKBACK_SECONDS = 0.25

local EntityService: any
local StatService: any
local StatusService: any
local ZoneService: any

local random = Random.new()

--[=[
	The single path for HP changes (game-design.md 5.5): damage with type, tags, level gap, crit,
	guard, shields and safe-zone rules; healing; shields; death.
]=]
local CombatService = {}

--[=[ Fires `(target, amount, damageType, source, crit, skillId)` after damage lands. ]=]
CombatService.Damaged = Signal.new() :: Signal.Signal<Entity, number, string, Entity?, boolean, string?>
--[=[ Fires `(victim, killer)` once when an entity dies. ]=]
CombatService.Died = Signal.new() :: Signal.Signal<Entity, Entity?>

local function show(target: Entity, amount: number, kind: string, crit: boolean, skillId: string?, source: Entity?)
	local position = target.root.Position
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= SHOW_RADIUS then
			NetServer.Fire("ShowDamage", player, target.model, amount, kind, crit, skillId, source and source.model)
		end
	end
end

local function inFront(defender: Entity, attacker: Entity, arc: number): boolean
	local look = defender.root.CFrame.LookVector
	local p = attacker.root.Position
	local o = defender.root.Position
	return Formulas.InArc(o.X, o.Z, look.X, look.Z, p.X, p.Z, math.huge, arc)
end

--[=[
	True when `source` may aim at or hit `target`: enemies (factions or grudges), and a player
	against any NPC outside safe zones. NPCs inside a safe zone only fight hostile factions.
]=]
function CombatService.MayAttack(source: Entity, target: Entity): boolean
	if source.kind == "Player" and target.kind == "Npc" and not Relations.Hostile(source.team, target.team) then
		return not ZoneService.IsSafe(target.root.Position)
	end
	return EntityService.AreEnemies(source, target)
end

--[=[ True when `target` can currently be damaged by `source`. ]=]
function CombatService.CanHarm(source: Entity?, target: Entity): boolean
	if not target.alive or target.god then
		return false
	end
	if source and not CombatService.MayAttack(source, target) then
		return false
	end
	if target.kind == "Player" and ZoneService.IsSafe(target.root.Position) then
		return false
	end
	return true
end

local function die(target: Entity, killer: Entity?)
	if not target.alive then
		return
	end
	target.alive = false
	target.hp = 0
	target.casting = nil
	StatusService.Clear(target)
	StatService.SetHp(target, 0)
	if target.humanoid then
		target.humanoid.Health = 0
	end
	CombatService.Died:Fire(target, killer)
end

--[=[ Kills an entity outright (falls, dev commands). ]=]
function CombatService.Kill(target: Entity, killer: Entity?)
	die(target, killer)
end

local function landDamage(
	target: Entity,
	amount: number,
	damageType: string,
	source: Entity?,
	crit: boolean,
	skillId: string?,
	blocked: boolean?
)
	local now = os.clock()
	target.lastCombatAt = now
	if source then
		source.lastCombatAt = now
		target.lastHitBy = source
		target.threat[source] = (target.threat[source] or 0) + amount
	end

	local remaining = amount
	if target.shield > 0 then
		local absorbed = math.min(target.shield, remaining)
		target.shield -= absorbed
		remaining -= absorbed
		if target.shield <= 0 then
			StatusService.Remove(target, "shield")
		end
	end

	StatService.SetHp(target, target.hp - remaining)
	if target.statuses.sleep then
		StatusService.Remove(target, "sleep")
	end
	local kind = if blocked then "blocked" elseif remaining < amount then "shielded" else "damage"
	show(target, amount, kind, crit, skillId, source)
	CombatService.Damaged:Fire(target, amount, damageType, source, crit, skillId)
	if target.hp <= 0 then
		die(target, source)
	end
end

--[=[
	Applies hit effects (statuses) with their chance; `chanceBonus` adds to effects that have a
	chance. `cleanse` removes cleansable statuses.
]=]
function CombatService.ApplyEffects(source: Entity?, target: Entity, effects: { Effect }?, chanceBonus: number?)
	for _, effect in (effects or {}) :: { Effect } do
		if effect.status == "cleanse" then
			StatusService.Cleanse(target)
			continue
		end
		local chance = if effect.chance then math.min(1, effect.chance + (chanceBonus or 0)) else 1
		if random:NextNumber() < chance then
			StatusService.Apply(target, effect.status, effect.duration or 1, effect.magnitude, source)
		end
	end
end

export type DamageSpec = {
	type: string,
	base: number,
	stat: string,
	ratio: number,
}

--[=[ Evil creatures are the ones holy damage hurts more (undead, demons); Anti-Evil Protection keys on it. ]=]
function CombatService.IsEvil(entity: Entity): boolean
	return Formulas.TypeMultiplier("holy", entity.tags, Tuning.Combat.TypeMultiplier) > 1
end

--[=[ Per-hit crit adjustments from the skill and the attacker's next-hit statuses. ]=]
export type HitMods = {
	critChance: number?,
	forceCrit: boolean?,
}

-- Extra damage the target takes of this type from `source` (Exposed).
local function exposureFrom(source: Entity, target: Entity, damageType: string): number
	local total = 0
	for id, status in target.statuses do
		local def = Statuses.ById[id]
		if def and def.exposure == damageType and status.source == source then
			total += status.magnitude
		end
	end
	return total
end

--[=[
	Resolves and lands one hit. `bonus` is an additive outgoing multiplier (e.g. Overcharge);
	Weapon Proficiency, Battle Rhythm, Finishing Instinct and Exposed add to it (Formulas.HitBonus).
	Guarding defenders facing the attacker take reduced damage, or none inside the parry window
	(the attacker is staggered). A crit applies the attacker's crit effects. Returns the damage dealt.
]=]
function CombatService.DealDamage(
	source: Entity,
	target: Entity,
	spec: DamageSpec,
	skillId: string?,
	bonus: number?,
	mods: HitMods?
): number
	if not CombatService.CanHarm(source, target) then
		return 0
	end
	local now = os.clock()
	if now < target.invulnerableUntil then
		show(target, 0, "dodged", false)
		return 0
	end

	local traits = source.traits
	local proficient = traits.proficiency ~= nil
		and spec.type == "physical"
		and source.weapon == source.proficiencyFamily
	local proficiency = if proficient and traits.proficiency then traits.proficiency else nil
	local rhythm = traits.rhythm
	local stacks = 0
	if rhythm then
		stacks = Formulas.RhythmStacks(source.rhythmStacks, source.rhythmAt, now, rhythm.window, rhythm.maxStacks)
	end
	local critChance =
		Formulas.CritChance(source.stats.Agility or 0, Tuning.Combat.BaseCrit, Tuning.Combat.CritPerAgility)
	critChance = if mods and mods.forceCrit then 1 else math.min(1, critChance + (mods and mods.critChance or 0))

	local defense = if spec.type == "physical" then target.stats.PhysDef else target.stats.MagDef
	local amount, crit = Formulas.ResolveDamage({
		base = spec.base,
		attackStat = source.stats[spec.stat] or 0,
		ratio = spec.ratio,
		damageType = spec.type,
		attackerLevel = source.level,
		targetLevel = target.level,
		defense = defense or 0,
		tags = target.tags,
		critChance = critChance,
		roll = random:NextNumber(),
		bonus = Formulas.HitBonus({
			base = (source.extras.DamageDone or 0) + (bonus or 0),
			proficiency = if proficiency then proficiency.damage else 0,
			rhythmStacks = stacks,
			perStack = if rhythm then rhythm.perStack else 0,
			execute = source.extras.ExecuteDamage or 0,
			targetHpFraction = target.hp / math.max(target.stats.MaxHp or 1, 1),
			executeBelow = Tuning.Combat.ExecuteBelow,
			exposure = exposureFrom(source, target, spec.type),
		}),
		critDamage = if proficiency then proficiency.critDamage else nil,
	}, Tuning.Combat)

	if amount == 0 then
		show(target, 0, "immune", false)
		return 0
	end

	-- A shield replaces the bare guard's values (docs/systems/weapons.md, Shields).
	local guard = Tuning.Combat.Guard
	local shield = target.shieldGuard
	local arc = if shield then shield.arc else guard.Arc
	local parryWindow = if shield then shield.parryWindow else guard.ParryWindow
	local staminaPerHit = if shield then shield.staminaPerHit else guard.StaminaPerHit
	local damageMultiplier = if shield then shield.damageMultiplier else guard.DamageMultiplier
	local blocked = false
	if target.guardSince and inFront(target, source, arc) then
		if now - target.guardSince <= parryWindow then
			show(target, 0, "parried", false)
			NetServer.FireAll("ShowParry", target.model, source.model)
			StatusService.Apply(source, "stun", PARRY_STAGGER, nil, target)
			return 0
		end
		if StatService.Spend(target, "Stamina", staminaPerHit) then
			amount = math.floor(amount * damageMultiplier + 0.5)
			blocked = true
		else
			target.guardSince = nil
			target.model:SetAttribute("Guarding", false)
		end
	end

	local ward = target.statuses.anti_evil
	if ward and CombatService.IsEvil(source) then
		amount = math.max(1, math.floor(amount * (1 - ward.magnitude) + 0.5))
	end

	if rhythm then
		source.rhythmStacks = stacks
		source.rhythmAt = now
	end
	landDamage(target, amount, spec.type, source, crit, skillId, blocked)
	if crit and #traits.critEffects > 0 then
		CombatService.ApplyEffects(source, target, traits.critEffects)
	end
	return amount
end

--[=[ Lands a damage-over-time tick: type multiplier applies, defense does not. ]=]
function CombatService.DealTick(target: Entity, amount: number, damageType: string, source: Entity?)
	if not CombatService.CanHarm(source, target) then
		return
	end
	local scaled = amount * Formulas.TypeMultiplier(damageType, target.tags, Tuning.Combat.TypeMultiplier)
	if scaled <= 0 then
		return
	end
	landDamage(target, math.max(1, math.floor(scaled + 0.5)), damageType, source, false, nil)
end

--[=[ Heals a living target. Returns the amount restored. ]=]
function CombatService.Heal(source: Entity?, target: Entity, amount: number): number
	if not target.alive or amount <= 0 then
		return 0
	end
	local before = target.hp
	StatService.SetHp(target, target.hp + amount)
	local restored = target.hp - before
	if source then
		source.lastCombatAt = math.max(source.lastCombatAt, target.lastCombatAt)
	end
	show(target, restored, "heal", false)
	return restored
end

--[=[ Grants an absorb shield that lasts SHIELD_SECONDS; a stronger shield replaces a weaker one. ]=]
function CombatService.Shield(target: Entity, amount: number)
	if not target.alive then
		return
	end
	StatusService.Apply(target, "shield", SHIELD_SECONDS, nil, nil)
	StatService.SetShield(target, math.max(target.shield, amount))
	show(target, amount, "shield", false)
end

--[=[ Pushes a server-owned entity away from `origin`. Player characters are not pushed. ]=]
function CombatService.Knockback(target: Entity, origin: Vector3, force: number)
	if target.kind ~= "Npc" or not target.alive then
		return
	end
	local flat = target.root.Position - origin
	flat = Vector3.new(flat.X, 0, flat.Z)
	local direction = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, 1)
	-- A Humanoid overrides a raw velocity write on the next step, so drive it with a short constraint.
	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "Knockback"
	velocity.Attachment0 = attachment
	velocity.MaxForce = 1e6
	velocity.VectorVelocity = direction * force + Vector3.new(0, force * 0.25, 0)
	attachment.Parent = target.root
	velocity.Parent = target.root
	task.delay(KNOCKBACK_SECONDS, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
	StatusService.Interrupted:Fire(target, "knockback")
end

function CombatService.Init(deps: { [string]: any })
	EntityService = deps.EntityService
	StatService = deps.StatService
	StatusService = deps.StatusService
	ZoneService = deps.ZoneService
end

function CombatService.Start()
	StatusService.Ticked:Connect(function(entity: Entity, statusId: string, magnitude: number, source: Entity?)
		local def = Statuses.ById[statusId]
		if not def then
			return
		end
		if def.kind == "Dot" then
			CombatService.DealTick(entity, magnitude, def.damageType or "physical", source)
		elseif def.kind == "Hot" then
			CombatService.Heal(source, entity, magnitude)
		end
	end)

	EntityService.Added:Connect(function(entity: Entity)
		local humanoid = entity.humanoid
		if humanoid then
			humanoid.Died:Connect(function()
				if entity.alive then
					die(entity, entity.lastHitBy)
				end
			end)
		end
	end)
end

return CombatService
