--!strict

--[=[
	Pure hunger and thirst math (docs/systems/stats-and-hud.md, Hunger and thirst). Values run from
	0 to `config.Max`; NeedsService owns the state and applies the results.
]=]
local Needs = {}

export type Kind = "Hunger" | "Thirst"

export type Config = {
	Max: number,
	SecondsToEmpty: { [string]: number },
	LowThreshold: number,
	LowRegenScale: number,
	StarvingHpPerSecond: number,
	FloorHp: number,
}

local KINDS: { Kind } = { "Hunger", "Thirst" }
Needs.Kinds = table.freeze(KINDS)

--[=[ Value of a need after `dt` seconds of decay, never below 0. ]=]
function Needs.Decay(value: number, kind: Kind, dt: number, config: Config): number
	local rate = config.Max / config.SecondsToEmpty[kind]
	return math.max(0, value - rate * dt)
end

--[=[ Value of a need after restoring `amount`, clamped to [0, Max]. ]=]
function Needs.Restore(value: number, amount: number, config: Config): number
	return math.clamp(value + amount, 0, config.Max)
end

--[=[
	HP and MP regen scale for one need: 1 at or above the low threshold, `LowRegenScale` below
	it, 0 when empty.
]=]
function Needs.RegenScale(value: number, config: Config): number
	if value <= 0 then
		return 0
	elseif value < config.Max * config.LowThreshold then
		return config.LowRegenScale
	end
	return 1
end

--[=[ Combined regen scale: the product of every need's scale. ]=]
function Needs.CombinedRegenScale(values: { [string]: number }, config: Config): number
	local scale = 1
	for _, kind in Needs.Kinds do
		scale *= Needs.RegenScale(values[kind], config)
	end
	return scale
end

--[=[ HP lost per second: `StarvingHpPerSecond` for each empty need. ]=]
function Needs.DrainRate(values: { [string]: number }, config: Config): number
	local empty = 0
	for _, kind in Needs.Kinds do
		if values[kind] <= 0 then
			empty += 1
		end
	end
	return empty * config.StarvingHpPerSecond
end

--[=[ HP after draining `amount`; never takes HP below `FloorHp` and never raises it. ]=]
function Needs.DrainHp(hp: number, amount: number, config: Config): number
	if hp <= config.FloorHp then
		return hp
	end
	return math.max(config.FloorHp, hp - amount)
end

--[=[
	One starvation tick. HP moves in whole points, so the fraction owed carries over between ticks.
	Returns the new `owed` and the new HP, or nil when HP does not change. Nothing is owed while
	nothing drains, in god mode or at the floor.
]=]
function Needs.Starve(
	owed: number,
	hp: number,
	rate: number,
	dt: number,
	god: boolean,
	config: Config
): (number, number?)
	if rate <= 0 or god or hp <= config.FloorHp then
		return 0, nil
	end
	local total = owed + rate * dt
	local whole = math.floor(total)
	if whole < 1 then
		return total, nil
	end
	return total - whole, Needs.DrainHp(hp, whole, config)
end

return Needs
