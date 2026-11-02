--!strict

--[=[
	Pure poise, parry and cast-pushback rules (docs/systems/combat.md, Poise and parry). No requires
	and no Roblox services: callers pass levels, content and tuning in. AIService keeps each enemy's
	pool, CombatService decides parries and SkillService pushes player casts back.
]=]
local Poise = {}

export type ParryClass = "Normal" | "Heavy" | "None"

export type ParrySettings = {
	LevelStep: number,
	MinScale: number,
	MaxScale: number,
	HeavyWindowShare: number,
}

export type CastSettings = {
	CastPoise: number,
	Pushback: number,
	PushbackMax: number,
}

local PARRIED_DELIVERIES = { Melee = true, Cone = true, Dash = true }

--[=[ Poise pool at the current max HP: `poiseMax` is set at the base max HP and grows with it. ]=]
function Poise.Pool(poiseMax: number, baseMaxHp: number, maxHp: number): number
	return poiseMax * maxHp / math.max(baseMaxHp, 1)
end

--[=[ Poise damage of a hit dealing `amount`: amount x the skill's `poiseDamage`, else `defaultFactor`. ]=]
function Poise.Damage(amount: number, factor: number?, defaultFactor: number): number
	return amount * (if factor then factor else defaultFactor)
end

--[=[
	Takes `amount` from a pool holding `poise`, last hit at `lastAt`. A pool left alone for more
	than `refillDelay` seconds is full again first. Returns the poise left and true when it broke;
	a broken pool comes back full.
]=]
function Poise.Hit(
	poise: number,
	lastAt: number,
	amount: number,
	max: number,
	refillDelay: number,
	now: number
): (number, boolean)
	if now - lastAt > refillDelay then
		poise = max
	end
	poise -= amount
	if poise <= 1e-6 then
		return max, true
	end
	return poise, false
end

--[=[ A skill's parry class: its `parry` field, else Normal for Melee, Cone and Dash and None otherwise. ]=]
function Poise.ParryClass(skill: any): ParryClass
	if skill.parry then
		return skill.parry
	end
	return if PARRIED_DELIVERIES[skill.delivery] then "Normal" else "None"
end

--[=[ Level gap scale on parry poise: clamp(1 + LevelStep x (defender - attacker), MinScale, MaxScale). ]=]
function Poise.LevelScale(defenderLevel: number, attackerLevel: number, settings: ParrySettings): number
	return math.clamp(1 + settings.LevelStep * (defenderLevel - attackerLevel), settings.MinScale, settings.MaxScale)
end

--[=[
	True when a guard raised `sinceGuard` seconds ago parries a hit of `class`: Normal inside
	`window`, Heavy inside the first HeavyWindowShare of it unless the defender is the higher level,
	None never.
]=]
function Poise.Parries(
	class: ParryClass,
	sinceGuard: number,
	window: number,
	defenderLevel: number,
	attackerLevel: number,
	settings: ParrySettings
): boolean
	if class == "None" or sinceGuard > window then
		return false
	end
	if class == "Heavy" and defenderLevel <= attackerLevel then
		return sinceGuard <= window * settings.HeavyWindowShare
	end
	return true
end

--[=[ Poise one parry takes from an attacker whose full pool is `pool`: pool x `share` x the level scale. ]=]
function Poise.ParryDamage(
	pool: number,
	share: number,
	defenderLevel: number,
	attackerLevel: number,
	settings: ParrySettings
): number
	return pool * share * Poise.LevelScale(defenderLevel, attackerLevel, settings)
end

--[=[
	What a hit of `poise` damage does to a player's cast: "Interrupt" at or above CastPoise x
	`maxHp`; otherwise "Pushback" with the seconds to add, while the cast has been pushed back less
	than PushbackMax so far (`pushed`), else "None".
]=]
function Poise.CastHit(
	poise: number,
	maxHp: number,
	pushed: number,
	settings: CastSettings
): ("Interrupt" | "Pushback" | "None", number)
	if poise >= settings.CastPoise * maxHp then
		return "Interrupt", 0
	end
	local seconds = math.min(settings.Pushback, settings.PushbackMax - pushed)
	if seconds <= 0 then
		return "None", 0
	end
	return "Pushback", seconds
end

return Poise
