--!strict

--[=[
	Pure threat rules (docs/systems/combat.md, Threat). No requires and no Roblox services: callers
	pass tables, content and tuning in. Every entity keeps `threat[source]`; CombatService adds to it
	and AIService picks its target with `Choose`. Class skills only supply data modifiers: a skill's
	`threat`, a status's `threatMultiplier` and the entity's own multiplier.
]=]
local Threat = {}

--[=[ A skill's threat modifiers (`SkillDef.threat`). ]=]
export type SkillThreat = { multiplier: number?, flat: number? }

--[=[ One valid target an NPC could fight. ]=]
export type Candidate = {
	key: any,
	threat: number,
	--[=[ Within the NPC's attack reach (plus slack). ]=]
	inReach: boolean,
	--[=[ Casting a heal: picked over closer targets. ]=]
	healing: boolean,
}

--[=[
	Multiplier on every threat an entity generates: its own `entityMultiplier` times the
	`threatMultiplier` of each status it carries (`statuses` is Content/Statuses ById). Missing
	values count as 1.
]=]
function Threat.SourceMultiplier(
	entityMultiplier: number,
	active: { [string]: any },
	statuses: { [string]: any }
): number
	local multiplier = entityMultiplier
	for id in active do
		local def = statuses[id]
		if def and def.threatMultiplier then
			multiplier *= def.threatMultiplier
		end
	end
	return multiplier
end

--[=[ Threat of a hit dealing `amount` damage: amount x the skill's multiplier x the source's multiplier. ]=]
function Threat.FromDamage(amount: number, skill: SkillThreat?, sourceMultiplier: number): number
	local multiplier = if skill and skill.multiplier then skill.multiplier else 1
	return amount * multiplier * sourceMultiplier
end

--[=[ Flat threat a skill adds to each enemy it hits, after the source's multiplier; 0 without one. ]=]
function Threat.Flat(skill: SkillThreat?, sourceMultiplier: number): number
	return if skill and skill.flat then skill.flat * sourceMultiplier else 0
end

--[=[
	Threat each of `enemies` gains when an ally they fight is healed or shielded for `amount`:
	`amount x healThreat`, split evenly. 0 when nobody fights the ally.
]=]
function Threat.HealShare(amount: number, healThreat: number, enemies: number): number
	if enemies <= 0 or amount <= 0 then
		return 0
	end
	return amount * healThreat / enemies
end

--[=[
	Adds `amount` threat for `source` to an NPC's table. A table with no entries yet also adds
	`pull`, so whoever engages an NPC first opens with a lead.
]=]
function Threat.Add(threat: { [any]: number }, source: any, amount: number, pull: number)
	if next(threat) == nil then
		amount += pull
	end
	threat[source] = (threat[source] or 0) + amount
end

--[=[ Threat left after `dt` seconds of decay at `perSecond` (a share per second); never below 0. ]=]
function Threat.Decay(value: number, dt: number, perSecond: number): number
	return value * math.max(0, 1 - perSecond * dt)
end

--[=[
	Picks a target among valid `candidates`. Candidates in reach are preferred over higher threat
	out of reach, except one casting a heal; with nobody in reach every candidate counts. The
	highest threat wins, but `current`, while it is still preferred, holds until a challenger's
	threat exceeds its own times `ratio`. Returns nil without candidates.
]=]
function Threat.Choose(candidates: { Candidate }, current: any?, ratio: number): any?
	local anyInReach = false
	for _, candidate in candidates do
		if candidate.inReach then
			anyInReach = true
			break
		end
	end
	local best: Candidate? = nil
	local held: Candidate? = nil
	for _, candidate in candidates do
		if anyInReach and not candidate.inReach and not candidate.healing then
			continue
		end
		if candidate.key == current then
			held = candidate
		end
		if not best or candidate.threat > best.threat then
			best = candidate
		end
	end
	if held and best and best.threat <= held.threat * ratio then
		return held.key
	end
	return if best then best.key else nil
end

return Threat
