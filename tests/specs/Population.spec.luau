--!strict

-- Open-world population data (src/ServerStorage/ContentServerOnly/Population, docs/systems/open-world.md).
local Expect = require("../Expect")
local Loader = require("../Loader")

local Field = Loader.load("src/ServerStorage/WorldGen/Gen/Field")
local Graph = Loader.load("src/ServerStorage/WorldGen/Gen/Graph")
local Realm = Loader.load("src/ServerStorage/WorldGen/Midgard")
local NpcDefs = Loader.load("src/ReplicatedStorage/Shared/NpcDefs")
local Population = Loader.load("src/ServerStorage/ContentServerOnly/Population")

-- Most rise between ground samples 4 studs apart that a walker takes off a corridor; terrace
-- steps and cliff faces are larger.
local STEP = 5
local SAMPLE = 4

local field: any = nil
local function world(): any
	if not field then
		field = Field.new(Graph.build(Realm))
	end
	return field
end

local function walkable(label: string, points: { { number } })
	local f = world()
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local length = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local steps = math.max(1, math.ceil(length / SAMPLE))
		local previous = f.height(a[1], a[2])
		for k = 1, steps do
			local t = k / steps
			local x, z = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
			local height = f.height(x, z)
			Expect.truthy(
				math.abs(height - previous) <= STEP or f.sample(x, z).corridor ~= nil,
				`{label} leg {i - 1}: step of {math.floor(math.abs(height - previous))} at ({math.floor(x)}, {math.floor(
					z
				)})`
			)
			previous = height
		end
	end
end

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

	["routes and territories stay on walkable ground"] = function()
		for _, troop in troops() do
			Expect.truthy(#troop.route.points >= 2, `{troop.id}: route`)
			walkable(troop.id, troop.route.points)
			for index in troop.route.stops or {} do
				Expect.truthy(troop.route.points[index], `{troop.id}: stop {index} is not a point`)
			end
		end
		for _, nest in Population.Nests do
			if #nest.squads > 0 then
				Expect.truthy(#nest.territory >= 3, `{nest.id}: territory loop`)
				walkable(nest.id, nest.territory)
				local first, last = nest.territory[1], nest.territory[#nest.territory]
				Expect.truthy(first[1] == last[1] and first[2] == last[2], `{nest.id}: territory closes`)
			end
		end
	end,
}
