--!strict

--[=[
	Dev skills (`source = "Dev"`, docs/systems/dev-tools.md): debug tools every developer knows
	without learning them. The server decides who is a developer; this only builds the list.
]=]
local DevSkills = {}

--[=[ Ids of every dev skill, sorted. ]=]
function DevSkills.Ids(skillsById: { [string]: any }): { string }
	local ids = {}
	for id, skill in skillsById do
		if skill.source == "Dev" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

--[=[ `known` plus every dev skill when `isDev`; otherwise `known` unchanged. Mutates `known`. ]=]
function DevSkills.Grant(known: { string }, isDev: boolean, skillsById: { [string]: any }): { string }
	if isDev then
		for _, id in DevSkills.Ids(skillsById) do
			if not table.find(known, id) then
				table.insert(known, id)
			end
		end
	end
	return known
end

return table.freeze(DevSkills)
