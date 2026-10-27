--!strict

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

--[=[ Server-side combat entity: a player character, a goblin or a training dummy. ]=]
export type Entity = {
	model: Model,
	humanoid: Humanoid?,
	root: BasePart,
	kind: "Player" | "Npc" | "Dummy",
	player: Player?,
	team: "Players" | "Goblins" | "Undead" | "Neutral",
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
	invulnerableUntil: number,
	statuses: { [string]: StatusInstance },
	history: { Sample },
	threat: { [Entity]: number },
	tauntedBy: Entity?,
	lastHitBy: Entity?,
}

return nil
