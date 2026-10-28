--!strict

--[=[ Shared types for content tables. Content modules hold data only, never logic. ]=]

export type StatName =
	"MaxHp"
	| "MaxMp"
	| "PhysAtk"
	| "PhysDef"
	| "Agility"
	| "MagAtk"
	| "MagDef"
	| "Resistance"
	| "Special"

export type StatBlock = { [string]: number }

export type DamageType = "physical" | "fire" | "cold" | "lightning" | "acid" | "holy" | "negative" | "poison" | "mental"

export type Tags = {
	resist: { string }?,
	immune: { string }?,
	vulnerable: { string }?,
}

export type Effect = {
	status: string,
	duration: number?,
	magnitude: number?,
	chance: number?,
}

export type Amount = {
	base: number,
	stat: string,
	ratio: number,
}

export type Delivery =
	"Melee"
	| "Projectile"
	| "Target"
	| "Cone"
	| "Ground"
	| "Self"
	| "SelfArea"
	| "Ally"
	| "Dash"
	| "Blink"
	| "Object"

export type SkillDef = {
	id: string,
	name: string,
	kind: "Active" | "Passive",
	source: "Basic" | "Class" | "Spell" | "Enemy",
	tier: number?,
	--[=[ Spells only: fixed entry number in the spellbook, unique across all spells. ]=]
	number: number?,
	line: string?,
	delivery: Delivery?,
	targets: ("Enemy" | "Ally" | "Self")?,
	cost: { resource: "Mp" | "Stamina", amount: number }?,
	--[=[ Weaponskill or spell on the shared global cooldown (Tuning.Combat.Gcd); otherwise off-GCD. ]=]
	gcd: boolean?,
	--[=[ Seconds between uses of this skill; a GCD skill may add its own on top of the GCD. ]=]
	cooldown: number?,
	--[=[ Seconds of casting; moving before the slidecast window cancels it. ]=]
	castTime: number?,
	interruptible: boolean?,
	windup: number?,
	range: number?,
	radius: number?,
	angle: number?,
	speed: number?,
	damage: (Amount & { type: string })?,
	heal: Amount?,
	shield: Amount?,
	effects: { Effect }?,
	selfEffects: { Effect }?,
	knockback: number?,
	objectTag: string?,
	modifiers: StatBlock?,
	--[=[ Key in `Assets.Animations` for the caster's clip; markers `Windup`/`Hit` are cosmetic cues. ]=]
	animation: string?,
	description: string,
}

export type ClassDef = {
	id: string,
	name: string,
	cap: number,
	line: string?,
	growth: StatBlock,
	grants: { string },
	spellList: { string },
}

export type StatusDef = {
	id: string,
	name: string,
	kind: "Dot" | "Hot" | "Move" | "Stun" | "Root" | "Taunt" | "Shield" | "Stats" | "Light",
	harmful: boolean,
	damageType: string?,
	tickInterval: number?,
	modifiers: StatBlock?,
}

export type Summon = {
	belowHp: number,
	enemy: string,
	count: number,
	level: number,
	selfEffects: { Effect }?,
}

--[=[ Group-combat data for an enemy (docs/systems/ai-and-spawning.md, Group combat). ]=]
export type CombatDef = {
	--[=[ Ring and stand-off distance the enemy uses; "None" never waits for a token. Default Melee. ]=]
	slot: ("Melee" | "Ranged" | "Support" | "None")?,
	--[=[ Share of the target's attack budget one attack takes. Default Tuning.Swarm.TokenCost. ]=]
	tokenCost: number?,
	--[=[
		Preferred squad roles with weights (Pressure, Flanker, Opportunist, Disruptor, Support,
		Reserve). Disruptor needs a telegraphed stun skill. Default { Pressure = 1 }.
	]=]
	roles: { [string]: number }?,
	--[=[
		Morale that drops with damage and nearby deaths; below `fleeBelow` the enemy flees or
		regroups on its leader. `false` never flees (undead, bosses). Default Tuning.Swarm.Morale.Default.
	]=]
	morale: ({ base: number, fleeBelow: number } | false)?,
	--[=[ Gives nearby allies of its team a morale bonus; its death costs them morale. ]=]
	leader: boolean?,
	--[=[ Adds spawned once the enemy's HP falls below `belowHp` (fraction), with optional self effects. ]=]
	summons: { Summon }?,
}

export type EnemyDef = {
	id: string,
	name: string,
	tier: "Rabble" | "Warband" | "Training",
	levelMin: number,
	levelMax: number,
	--[=[
		Special cases only: "Dummy" never thinks; "Boss" labels an encounter boss. Group combat
		comes from `combat`.
	]=]
	behavior: ("Boss" | "Dummy")?,
	base: StatBlock,
	growth: StatBlock,
	tags: Tags,
	skills: { string },
	aggroRadius: number,
	leashRadius: number,
	keepDistance: number?,
	moveSpeed: number,
	xp: number,
	scale: number,
	color: Color3,
	elite: boolean?,
	-- ServerStorage.Templates model to clone; defaults to "Goblin".
	template: string?,
	-- Defaults to "Goblins". Enemies of one team call each other for help.
	team: ("Goblins" | "Undead")?,
	combat: CombatDef?,
}

export type ItemDef = {
	id: string,
	name: string,
	kind: "Weapon" | "Armor" | "Consumable" | "Material",
	grade: number,
	capacity: number,
	modifiers: StatBlock?,
	use: { hp: number?, mp: number? }?,
	stack: number,
	description: string,
}

return nil
