--!strict

-- Open-world population data (src/ServerStorage/ContentServerOnly/Population, docs/systems/open-world.md).
local Expect = require("../Expect")
local Loader = require("../Loader")

local NpcDefs = Loader.load("src/ReplicatedStorage/Shared/NpcDefs")
local Population = Loader.load("src/ServerStorage/ContentServerOnly/Population")

local function members(label: string, list: { any })
	Expect.truthy(#list > 0, `{label}: no members`)
	for _, member in list do
		local def = NpcDefs.Get(member.npc)
		Expect.truthy(def, `{label}: unknown npc {member.npc}`)
		Expect.truthy(member.count >= 1, `{label}: count`)
		if member.level then
			Expect.truthy(member.level[1] >= 1 and member.level[2] >= member.level[1], `{label}: level range`)
		end
	end
end

local function troops(): { any }
	local out = {}
	for _, kind in { "Patrols", "Caravans", "Travelers" } do
		for _, troop in Population[kind] do
			table.insert(out, troop)
		end
	end
	return out
end

return {
	["ids are unique"] = function()
		local seen: { [string]: boolean } = {}
		local function add(id: string)
			Expect.truthy(not seen[id], `duplicate id {id}`)
			seen[id] = true
		end
		for _, garrison in Population.Garrisons do
			add(garrison.id)
		end
		for _, troop in troops() do
			add(troop.id)
		end
		for _, group in Population.Residents do
			add(group.id)
		end
		for _, nest in Population.Nests do
			add(nest.id)
			for _, garrison in nest.stationed do
				add(nest.id .. "/" .. garrison.id)
			end
		end
	end,

	["every member resolves"] = function()
		for _, garrison in Population.Garrisons do
			members(garrison.id, garrison.members)
		end
		for _, troop in troops() do
			members(troop.id, troop.members)
			Expect.truthy(troop.max >= 1 and troop.interval > 0, `{troop.id}: max and interval`)
		end
		for _, group in Population.Residents do
			Expect.truthy(NpcDefs.Get(group.npc), `{group.id}: unknown npc`)
			Expect.truthy(group.night <= group.day, `{group.id}: fewer out at night`)
		end
		for _, nest in Population.Nests do
			Expect.truthy(#nest.squads > 0 or #nest.stationed > 0, `{nest.id}: empty nest`)
			for _, squad in nest.squads do
				members(nest.id, squad.members)
			end
			for _, garrison in nest.stationed do
				members(nest.id .. "/" .. garrison.id, garrison.members)
			end
		end
	end,
}
