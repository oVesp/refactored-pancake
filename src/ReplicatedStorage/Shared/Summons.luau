--!strict

local ChatCast = require(script.Parent.ChatCast)
local Types = require(script.Parent.Parent.Content.Types)

--[=[
	What a summon skill may raise (docs/systems/ai-and-spawning.md, Summons): the family's `base`
	plus each `pool` entry the player discovered. Pure, so the server decides and the client lists
	options with one rule.
]=]
local Summons = {}

type Family = Types.SummonFamily

--[=[ Ids the player may raise, base first, then discovered pool entries, without repeats. ]=]
function Summons.Options(family: Family, discoveries: { [string]: boolean }): { string }
	local options = table.clone(family.base)
	for _, id in family.pool do
		if discoveries[id] and not table.find(options, id) then
			table.insert(options, id)
		end
	end
	return options
end

--[=[
	The id a cast raises. `requested` (an id or a chat argument, in any case) must be an option, or
	the cast is refused with nil. With no request: `remembered` while it is still an option, else the
	first option.
]=]
function Summons.Choose(
	family: Family,
	discoveries: { [string]: boolean },
	requested: string?,
	remembered: string?
): string?
	local options = Summons.Options(family, discoveries)
	if requested then
		local wanted = ChatCast.Normalize(requested)
		for _, id in options do
			if ChatCast.Normalize(id) == wanted then
				return id
			end
		end
		return nil
	end
	if remembered and table.find(options, remembered) then
		return remembered
	end
	return options[1]
end

--[=[ Level a summon spawns at: the caster's plus the family's offset, never below 1. ]=]
function Summons.Level(family: Family, casterLevel: number): number
	return math.max(1, casterLevel + family.levelOffset)
end

--[=[ True when discovering `id` adds an option to any family (it is in a pool and not a base). ]=]
function Summons.Unlocks(families: { [string]: Family }, id: string): boolean
	for _, family in families do
		if table.find(family.pool, id) and not table.find(family.base, id) then
			return true
		end
	end
	return false
end

return table.freeze(Summons)
