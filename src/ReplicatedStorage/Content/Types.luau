--!strict

local Factions = require(script.Parent.Factions)

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

export type DamageType =
	"physical"
	| "force"
	| "fire"
	| "cold"
	| "water"
	| "lightning"
	| "acid"
	| "holy"
	| "negative"
	| "poison"
	| "mental"

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
	| "Dev"
	| "Leap"

export type SkillDef = {
	id: string,
	name: string,
	kind: "Active" | "Passive",
	source: "Basic" | "Class" | "Spell" | "Enemy" | "Dev",
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
	--[=[ Seconds from the press to the hit; the swing commits the player (Tuning.Combat.Commit). ]=]
	windup: number?,
	--[=[ Seconds after the hit during which the player stays committed: no actions, slowed. Players only. ]=]
	recovery: number?,
	--[=[ Studs the owner's client steps toward the aim when the swing starts. ]=]
	lunge: number?,
	--[=[ false: no ground telegraph; the owner's client predicts the swing at the clip `Hit` marker. ]=]
	telegraph: boolean?,
	range: number?,
	radius: number?,
	angle: number?,
	speed: number?,
	--[=[ Projectiles only: size multiplier of the client's bolt visual (a chain's closing bolt is larger). ]=]
	projectileScale: number?,
	damage: (Amount & { type: string })?,
	heal: Amount?,
	shield: Amount?,
	effects: { Effect }?,
	selfEffects: { Effect }?,
	knockback: number?,
	objectTag: string?,
	--[=[ Object spells: attribute set true on the object and the `Strings` notice sent to the caster. ]=]
	objectAttribute: string?,
	objectNotice: string?,
	modifiers: StatBlock?,
	--[=[ Key in `Assets.Animations` for the caster's clip; markers `Windup`/`Hit` are cosmetic cues. ]=]
	animation: string?,
	--[=[
		Basic chain only: the hit a light attack press uses next when it comes within
		Tuning.Combat.Chain.Window of this one (Shared/Chain).
	]=]
	chainNext: string?,
	--[=[ Weapon heavy attack: `HeavySpeed` shortens its windup. ]=]
	heavy: boolean?,
	--[=[ Bow shot: needs a draw (`SetDraw`) and scales with it (Shared/Archery, Tuning.Combat.Bow). ]=]
	drawn: boolean?,
	--[=[ Projectile only: downward acceleration in studs/s², so long shots must be aimed high. ]=]
	gravity: number?,
	--[=[ Extra outgoing damage multiplier when the hit lands on the target's back (Shared/Archery). ]=]
	rearBonus: number?,
	--[=[ Melee only: hits at most this many enemies in the arc, nearest first. ]=]
	maxTargets: number?,
	--[=[ Added to the caster's crit chance for this skill's hits. ]=]
	critChance: number?,
	--[=[
		The skill attacks with the equipped weapon: it takes on the weapon's light attack with damage
		times `scale` (Loadout.Attack), so it needs no delivery or damage of its own. `type` and `stat`
		replace the light attack's damage type and scaling stat, whatever the weapon.
	]=]
	weaponAttack: { scale: number, type: string?, stat: string? }?,
	--[=[ Set by Loadout.Attack: the light attack whose visuals a `weaponAttack` use shows. ]=]
	shownAs: string?,
	--[=[ Self only: restores these fractions of max HP and Stamina. ]=]
	restore: { Hp: number?, Stamina: number? }?,
	--[=[ Uses of the cooldown held at once; each recharges in `cooldown` seconds. Default 1. ]=]
	charges: number?,
	--[=[
		Passive: damage bonus (and crit damage bonus) with the chosen weapon family. Tiers override:
		the highest granted tier counts (Formulas.CollectTraits).
	]=]
	proficiency: { damage: number, critDamage: number? }?,
	--[=[ Passive: each hit within `window` seconds of the last adds `perStack` damage, up to `maxStacks`. ]=]
	rhythm: { window: number, perStack: number, maxStacks: number }?,
	--[=[ Passive: statuses the owner's crits apply to the target. ]=]
	critEffects: { Effect }?,
	--[=[ Passive: overrides `charges` and `selfEffects` of another skill (`skill`) while granted. ]=]
	upgrade: { skill: string, charges: number?, selfEffects: { Effect }? }?,
	--[=[ Dev skills only (delivery `Dev`): the server-side debug effect it runs (Server/DevSkillEffects). ]=]
	devEffect: ("Fly" | "LifeEssence" | "ManaEssence" | "DiscernEnemy" | "DetectLife" | "Gate")?,
	--[=[ Chat casting may follow the name with an argument (Gate: the destination). ]=]
	chatArg: boolean?,
	description: string,
}

export type ClassDef = {
	id: string,
	name: string,
	cap: number,
	--[=[ Category tags (docs/systems/classes.md, Unlock requirements), e.g. "Martial". ]=]
	categories: { string }?,
	line: string?,
	growth: StatBlock,
	grants: { string },
	spellList: { string },
	--[=[ Weapon types (Content/Weapons) the class may equip; any one class allowing it is enough (Loadout.CanEquip). ]=]
	weapons: { string },
}

export type StatusDef = {
	id: string,
	name: string,
	kind: "Dot" | "Hot" | "Move" | "Stun" | "Root" | "Taunt" | "Shield" | "Stats" | "Light" | "Ward",
	harmful: boolean,
	damageType: string?,
	tickInterval: number?,
	modifiers: StatBlock?,
	--[=[ Stats only: the instance magnitude is added to this modifier key (e.g. AgilityPct). ]=]
	magnitudeStat: string?,
	--[=[
		Spent by the owner's next damaging skill: `damage` adds the magnitude as outgoing bonus,
		`crit` makes its hits crit.
	]=]
	nextHit: { damage: boolean?, crit: boolean? }?,
	--[=[ The bearer takes +magnitude damage of this type from the status's source. ]=]
	exposure: string?,
	--[=[ Applying it fills the bearer's Battle Rhythm stacks. ]=]
	fillsRhythm: boolean?,
	--[=[ When it runs out (not when cleared), the bearer gets that skill's self effects for free. ]=]
	expireSkill: string?,
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
	--[=[ Share of max HP taken quickly that staggers the enemy. Default Tuning.Swarm.Stagger.DefaultPoise. ]=]
	poise: number?,
	--[=[ Adds spawned once the enemy's HP falls below `belowHp` (fraction), with optional self effects. ]=]
	summons: { Summon }?,
}

--[=[ One step of an NPC's task cascade (Shared/Tasks); `tag` and `radius` are for Guard. ]=]
export type TaskDef = {
	kind: "FollowLeader" | "Guard" | "Patrol" | "Wander" | "Idle",
	tag: string?,
	radius: number?,
}

export type EnemyDef = {
	id: string,
	name: string,
	tier: "Rabble" | "Warband" | "Training" | "Civilian",
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
	--[=[ Human template only: `Appearance` outfit ids, one picked per spawn. ]=]
	outfits: { string }?,
	-- ServerStorage.Templates model to clone; defaults to "Goblin".
	template: string?,
	-- Faction (Content/Factions); defaults to "Goblins". Allies call each other for help.
	team: Factions.FactionId?,
	combat: CombatDef?,
	--[=[ "Hostile" attacks players on sight; "Neutral" ignores them until attacked. Default by faction. ]=]
	stance: ("Hostile" | "Neutral")?,
	--[=[ Out-of-combat tasks, highest priority first. Default Shared/Tasks.Default. ]=]
	tasks: { TaskDef }?,
}

--[=[
	A weapon type (Content/Weapons, docs/systems/weapons.md): which basic attacks the light and
	heavy attack buttons use while it is equipped, how many hands it takes and whether it can guard
	without a shield.
]=]
export type WeaponDef = {
	id: string,
	name: string,
	hands: "One" | "Two",
	--[=[ Entry of the light attack chain (`chainNext`). ]=]
	light: string,
	--[=[ Held attack; absent for weapons whose light attack is held (bow draw). ]=]
	heavy: string?,
	--[=[ The light attack is held to draw and released to shoot (`SkillDef.drawn`). ]=]
	drawn: boolean?,
	--[=[ Can guard (F) without a shield. ]=]
	guard: boolean,
	--[=[ Child of ReplicatedStorage.Weapons welded to the character; none for fists. ]=]
	model: string?,
	--[=[ Hand the model is held in. ]=]
	hand: ("Right" | "Left")?,
}

--[=[ Guard values a shield uses in place of `Tuning.Combat.Guard` (docs/systems/weapons.md). ]=]
export type ShieldDef = {
	--[=[ Share of a blocked hit's damage that still lands (0 = full block). ]=]
	damageMultiplier: number,
	parryWindow: number,
	staminaPerHit: number,
	--[=[ Full width of the blocking arc in degrees. ]=]
	arc: number,
	model: string,
}

export type ItemDef = {
	id: string,
	name: string,
	kind: "Weapon" | "Shield" | "Armor" | "Consumable" | "Material",
	--[=[ Weapons only: the weapon type (Content/Weapons). ]=]
	weapon: string?,
	--[=[ Shields only. ]=]
	shield: ShieldDef?,
	grade: number,
	capacity: number,
	modifiers: StatBlock?,
	--[=[ What using a Consumable restores: HP, MP, hunger and thirst (0-100 scale). ]=]
	use: { hp: number?, mp: number?, hunger: number?, thirst: number? }?,
	stack: number,
	description: string,
}

return nil
