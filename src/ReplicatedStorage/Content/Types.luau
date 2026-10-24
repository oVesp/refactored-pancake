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
	circle: number?,
	line: string?,
	delivery: Delivery?,
	targets: ("Enemy" | "Ally" | "Self")?,
	cost: { resource: "Mp" | "Stamina", amount: number }?,
	cooldown: number?,
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

export type EnemyDef = {
	id: string,
	name: string,
	tier: "Rabble" | "Warband" | "Training",
	levelMin: number,
	levelMax: number,
	behavior: "Melee" | "Ranged" | "Trapper" | "Brute" | "Caster" | "Healer" | "Rider" | "Leader" | "Boss" | "Dummy",
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
