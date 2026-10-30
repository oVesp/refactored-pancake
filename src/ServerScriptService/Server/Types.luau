--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	cooldowns: { [string]: number },
	--[=[ os.clock() when the shared global cooldown is ready again. ]=]
	gcdReadyAt: number,
	--[=[ os.clock() when the animation lock of the last action ends. ]=]
	lockedUntil: number,
	casting: Cast?,
	castToken: number,
	guardSince: number?,
	--[=[ Last light chain hit this entity used and its os.clock() (Shared/Chain). ]=]
	chainLast: string?,
	chainAt: number,
	--[=[ os.clock() until which a melee swing keeps the player committed (slowed, no actions). ]=]
	commitUntil: number,
	invulnerableUntil: number,
	statuses: { [string]: StatusInstance },
	history: { Sample },
	threat: { [Entity]: number },
	tauntedBy: Entity?,
	lastHitBy: Entity?,
	--[=[ Combat traits from granted passives (players; empty for NPCs). ]=]
	traits: Formulas.Traits,
	--[=[ Weapon type (Content/Weapons) of the equipped weapon item, nil when unarmed. ]=]
	weaponFamily: string?,
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
