--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContentTypes = require(ReplicatedStorage.Content.Types)
local Factions = require(ReplicatedStorage.Content.Factions)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Swarm = require(ReplicatedStorage.Shared.Swarm)

export type Tags = {
	resist: { string }?,
	immune: { string }?,
	vulnerable: { string }?,
}

export type Cast = {
	skillId: string,
	endsAt: number,
	aim: Vector3,
	target: Entity?,
	interruptible: boolean,
	token: number,
	--[=[ Resource paid when a cast completes; a cancelled cast costs nothing. ]=]
	cost: { resource: "Mp" | "Stamina", amount: number }?,
}

export type StatusInstance = {
	id: string,
	expiresAt: number,
	magnitude: number,
	nextTick: number,
	source: Entity?,
}

export type Sample = {
	time: number,
	position: Vector3,
}

--[=[ Server-side combat entity: a player character, an NPC of any faction or a training dummy. ]=]
export type Entity = {
	model: Model,
	humanoid: Humanoid?,
	root: BasePart,
	kind: "Player" | "Npc" | "Dummy",
	player: Player?,
	team: Factions.FactionId,
	defId: string,
	name: string,
	level: number,
	tags: Tags,
	stats: { [string]: number },
	extras: { [string]: number },
	hp: number,
	mp: number,
	stamina: number,
	maxStamina: number,
	shield: number,
	alive: boolean,
	god: boolean,
	lastCombatAt: number,
	--[=[ HP and MP regen multiplier from hunger and thirst (NeedsService); 1 when fed. ]=]
	regenScale: number,
	cooldowns: { [string]: number },
	--[=[ os.clock() when the shared global cooldown is ready again. ]=]
	gcdReadyAt: number,
	--[=[ os.clock() when the animation lock of the last action ends. ]=]
	lockedUntil: number,
	casting: Cast?,
	castToken: number,
	guardSince: number?,
	--[=[ Equipped weapon type (Content/Weapons); NPCs keep the default. Set by StatService.Recompute. ]=]
	weapon: string,
	--[=[ Guard values of the equipped shield, replacing Tuning.Combat.Guard. ]=]
	shieldGuard: ContentTypes.ShieldDef?,
	--[=[ os.clock() when the current bow draw started (`SetDraw`). ]=]
	drawSince: number?,
	--[=[ Outgoing damage bonus of the arrow being released, consumed when it resolves. ]=]
	drawBonus: number,
	--[=[ Walk speed multiplier from gait: a running player, a patrolling NPC. ]=]
	pace: number,
	--[=[ Last light chain hit this entity used and its os.clock() (Shared/Chain). ]=]
	chainLast: string?,
	chainAt: number,
	--[=[ os.clock() until which a melee swing keeps the player committed (slowed, no actions). ]=]
	commitUntil: number,
	invulnerableUntil: number,
	statuses: { [string]: StatusInstance },
	history: { Sample },
	threat: { [Entity]: number },
	--[=[ Entities this one fights although their factions are not Hostile: who attacked it. ]=]
	grudges: { [Entity]: true },
	tauntedBy: Entity?,
	lastHitBy: Entity?,
	--[=[ Combat traits from granted passives (players; empty for NPCs). ]=]
	traits: Formulas.Traits,
	--[=[ Weapon type Weapon Proficiency applies to. ]=]
	proficiencyFamily: string?,
	--[=[ Battle Rhythm stacks and os.clock() of the last hit that counted. ]=]
	rhythmStacks: number,
	rhythmAt: number,
}

--[=[ An enemy's place in group combat, owned by SquadService and held by its AI brain. ]=]
export type SquadMember = {
	entity: Entity,
	profile: Swarm.Profile,
	target: Entity?,
	--[=[ Creation order; breaks ties in slot assignment. ]=]
	seq: number,
	--[=[ Distance from the target where the enemy fights; AIService keeps it current. ]=]
	reach: number,
	--[=[ Engagement slot index in the member's ring, from the last tactical update. ]=]
	slot: number?,
	--[=[ Squad role from the last tactical update. ]=]
	role: Swarm.Role,
	--[=[ Stored morale without leader or rally bonuses; unused when the profile has none. ]=]
	morale: number,
	fleeing: boolean,
	--[=[ os.clock() of the last morale update. ]=]
	moraleAt: number,
	--[=[ os.clock() of the last morale loss; regeneration waits Morale.RegenDelay after it. ]=]
	moraleLostAt: number,
}

return nil
