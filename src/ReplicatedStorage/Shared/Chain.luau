--!strict

--[=[
	Light attack chain (docs/systems/combat.md, Timing): pure rules shared by CombatController and
	SkillService. A chain starts at its entry skill and follows `SkillDef.chainNext`; each hit may
	only follow the previous one within `window` seconds and once the previous hit's cooldown is
	over. Anything else starts the chain again at the entry.
]=]
local Chain = {}

-- Skills.ById; only `chainNext` is read.
type SkillMap = { [string]: any }

--[=[ The chain's skill ids in order, starting at `entry`. Errors on a loop. ]=]
function Chain.Members(skills: SkillMap, entry: string): { string }
	local members = {}
	local id: string? = entry
	while id do
		assert(not table.find(members, id), `Chain loops at {id}`)
		table.insert(members, id)
		local skill = skills[id]
		id = skill and skill.chainNext
	end
	return members
end

--[=[ True when `skillId` belongs to the chain that starts at `entry`. ]=]
function Chain.Contains(skills: SkillMap, entry: string, skillId: string): boolean
	return table.find(Chain.Members(skills, entry), skillId) ~= nil
end

--[=[
	The hit a light attack press uses now: the last hit's `chainNext` while the press is within
	`window` seconds of it, else `entry`.
]=]
function Chain.Next(skills: SkillMap, entry: string, last: string?, lastAt: number, now: number, window: number): string
	if last and now - lastAt <= window then
		local skill = skills[last]
		if skill and skill.chainNext then
			return skill.chainNext
		end
	end
	return entry
end

--[=[
	True when `skillId` may follow `last` (used at `lastAt`): the entry always may, any other hit
	only as `last`'s `chainNext` within `window` seconds. Cooldowns are checked by the caller.
]=]
function Chain.Allowed(
	skills: SkillMap,
	entry: string,
	last: string?,
	lastAt: number,
	skillId: string,
	now: number,
	window: number
): boolean
	if skillId == entry then
		return true
	end
	local skill = if last then skills[last] else nil
	return skill ~= nil and skill.chainNext == skillId and now - lastAt <= window
end

return table.freeze(Chain)
