--!strict

--[=[
	Keep-out anchors for the settlement layout, read from the Map (trainers and the vendor, training
	dummies, dev spawn pads and the respawn point) and from the open-world population (garrison
	posts and nest lairs with their wander radius, docs/systems/open-world.md). Works on Studio
	instances and on `@lune/roblox` instances (positions come from CFrame, which both provide).
]=]
export type Anchor = { x: number, z: number, r: number }

local Anchors = {}

local function position(part: any): (number, number)
	local p = part.CFrame.Position
	return p.X, p.Z
end

local POST_CLEAR = 6 -- studs kept around a garrison post beyond its wander radius
local NEST_CLEAR = 10

-- Garrison posts and nests from `ContentServerOnly/Population`.
local function fromPopulation(population: any, out: { Anchor })
	local function post(garrison: any)
		table.insert(out, { x = garrison.at[1], z = garrison.at[2], r = garrison.wander + POST_CLEAR })
	end
	for _, garrison in population.Garrisons do
		post(garrison)
	end
	for _, nest in population.Nests do
		table.insert(out, { x = nest.at[1], z = nest.at[2], r = NEST_CLEAR })
		for _, garrison in nest.stationed do
			post(garrison)
		end
	end
end

--[=[
	Anchors from a Map model (Workspace.Map in Studio, src/Workspace/Map.rbxmx in Lune) and the
	population data.
]=]
function Anchors.fromMap(map: any, population: any): { Anchor }
	local out: { Anchor } = {}
	fromPopulation(population, out)
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			if d:HasTag("Trainer") or d:HasTag("DevSpawnPad") or d:HasTag("RespawnPoint") then
				local x, z = position(d)
				table.insert(out, { x = x, z = z, r = math.max(d.Size.X, d.Size.Z) / 2 + 3 })
			end
		elseif d:IsA("Model") and d:HasTag("TrainingDummy") then
			for _, p in d:GetDescendants() do
				if p:IsA("BasePart") then
					local x, z = position(p)
					table.insert(out, { x = x, z = z, r = 3 })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.z < b.z
	end)
	return out
end

return Anchors
