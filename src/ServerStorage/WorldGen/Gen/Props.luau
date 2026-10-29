--!strict

--[=[
	Prop scatter for one zone: trees in groves with a few loners outside, bushes around trees and
	cliff feet, boulders. Pure data; every placement names a variant of the low-poly library
	(`Realm.props`), so all copies of a variant render as one instanced batch.

	Groves come from a realm-wide noise mask thresholded per biome, so a grove may run across an
	open border. Inside a grove trees are Poisson-disc spaced for the biome's density.
]=]
local Field = require(script.Parent.Field)
local Grid = require(script.Parent.Grid)
local Hash = require(script.Parent.Hash)

export type PropSpec = {
	asset: string,
	x: number,
	y: number,
	z: number,
	yaw: number,
	scale: number,
}

local Props = {}

local LONE_SHARE = 0.08 -- density of lone trees outside groves, as a share of grove density
local MAX_SLOPE = 3.5 -- studs of rise across one 4-stud sample under a prop

-- Ground under a footprint: flat enough and dry, with the lowest height for the base.
local function footing(grid: Grid.Grid, x: number, z: number, radius: number): number?
	local low, high = math.huge, -math.huge
	for _, o in { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local h = Grid.heightAt(grid, x + o[1] * radius, z + o[2] * radius)
		low, high = math.min(low, h), math.max(high, h)
	end
	if high - low > MAX_SLOPE * math.max(radius / 4, 1) then
		return nil
	end
	return low
end

local function sampleAt(grid: Grid.Grid, x: number, z: number): number
	return Grid.index(grid, math.round((x - grid.x0) / grid.step), math.round((z - grid.z0) / grid.step))
end

local function pick(weights: { [string]: number }, roll: number): string
	local names = {}
	local total = 0
	for name, w in weights do
		table.insert(names, name)
		total += w
	end
	table.sort(names)
	local acc = 0
	for _, name in names do
		acc += weights[name] / total
		if roll < acc then
			return name
		end
	end
	return names[#names]
end

--[=[
	Placements for `zone`. `grid` is the zone's sample grid (with margin). Deterministic per zone
	seed and independent of every other zone.
]=]
function Props.scatter(field: Field.Field, grid: Grid.Grid, zone: number): { PropSpec }
	local graph = field.graph
	local realm = graph.realm
	local library = realm.props
	local node = graph.nodes[zone]
	local biome = realm.biomes[node.biome]
	local out: { PropSpec } = {}
	if biome.trees <= 0 and biome.boulders <= 0 then
		return out
	end
	local groveNoise = Hash.fbm(Hash.named(graph.seed, "groves"), library.groveScale, 3)
	-- Grove threshold: the quantile of the mask over this zone's ground that leaves `groves` of it
	-- covered, so the share holds whatever the noise does locally.
	local threshold = math.huge
	if biome.groves > 0 then
		local values = {}
		for j = 0, grid.nz - 1, 4 do
			for i = 0, grid.nx - 1, 4 do
				local k = Grid.index(grid, i, j)
				if grid.owner[k] == zone then
					table.insert(values, groveNoise(grid.x0 + i * grid.step, grid.z0 + j * grid.step))
				end
			end
		end
		table.sort(values)
		if #values > 0 then
			threshold = values[math.clamp(math.floor(#values * (1 - biome.groves)) + 1, 1, #values)]
		end
	end
	local spacing = math.sqrt(10000 / math.max(biome.trees, 1e-3))
	local rng = Hash.rng(Hash.named(node.seed, "props"))

	local function usable(x: number, z: number, keepOff: number): boolean
		local k = sampleAt(grid, x, z)
		if grid.assign[k] ~= zone or grid.owner[k] ~= zone then
			return false
		end
		if grid.water[k] ~= 0 or grid.corridor[k] then
			return false
		end
		-- Away from corridors and water by `keepOff`.
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local q = sampleAt(grid, x + o[1] * keepOff, z + o[2] * keepOff)
			if grid.corridor[q] or grid.water[q] ~= 0 then
				return false
			end
		end
		return true
	end

	-- Poisson-disc (Bridson) over the zone's grid rectangle; acceptance by grove mask.
	local x0, z0 = grid.x0, grid.z0
	local x1, z1 = grid.x0 + (grid.nx - 1) * grid.step, grid.z0 + (grid.nz - 1) * grid.step
	local cell = spacing / math.sqrt(2)
	local cols = math.ceil((x1 - x0) / cell) + 1
	local rows = math.ceil((z1 - z0) / cell) + 1
	local occupied: { [number]: { number } } = {}
	local active: { { number } } = {}
	local placedOrder: { { number } } = {}
	local function slot(x: number, z: number): number
		return math.floor((x - x0) / cell) + math.floor((z - z0) / cell) * cols
	end
	local function far(x: number, z: number): boolean
		local ci, cj = math.floor((x - x0) / cell), math.floor((z - z0) / cell)
		for dj = -2, 2 do
			for di = -2, 2 do
				local i, j = ci + di, cj + dj
				if i >= 0 and j >= 0 and i < cols and j < rows then
					local p = occupied[i + j * cols]
					if p and (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < spacing * spacing then
						return false
					end
				end
			end
		end
		return true
	end
	local function add(x: number, z: number)
		local p = { x, z }
		occupied[slot(x, z)] = p
		table.insert(active, p)
		table.insert(placedOrder, p)
	end

	local trees: { { number } } = {}
	if biome.trees > 0 then
		-- Seeds on a coarse lattice so every grove gets a start, then grow by Bridson.
		local seedStep = spacing * 2
		for sz = z0, z1, seedStep do
			for sx = x0, x1, seedStep do
				local x, z = sx + rng:range(0, seedStep), sz + rng:range(0, seedStep)
				if x <= x1 and z <= z1 and far(x, z) then
					add(x, z)
				end
			end
		end
		while #active > 0 do
			local idx = rng:int(1, #active)
			local p = active[idx]
			local placed = false
			for _ = 1, 20 do
				local angle = rng:range(0, math.pi * 2)
				local d = rng:range(spacing, spacing * 2)
				local x, z = p[1] + math.cos(angle) * d, p[2] + math.sin(angle) * d
				if x >= x0 and x <= x1 and z >= z0 and z <= z1 and far(x, z) then
					add(x, z)
					placed = true
					break
				end
			end
			if not placed then
				active[idx] = active[#active]
				active[#active] = nil
			end
		end
		for _, p in placedOrder do
			local x, z = p[1], p[2]
			local inGrove = groveNoise(x, z) > threshold
			if not inGrove and rng:next() > LONE_SHARE then
				continue
			end
			if not usable(x, z, 10) then
				continue
			end
			local k = sampleAt(grid, x, z)
			if grid.padDistance[k] < 14 then
				continue
			end
			local base = footing(grid, x, z, 6)
			if not base then
				continue
			end
			local species = pick(biome.species, rng:next())
			local def = library.species[species]
			local variant = rng:int(1, def.variants)
			table.insert(trees, { x, z })
			table.insert(out, {
				asset = string.format("%s%02d", def.prefix, variant),
				x = x,
				y = base - 0.5,
				z = z,
				yaw = rng:range(0, math.pi * 2),
				scale = rng:range(def.scale[1], def.scale[2]) * (if inGrove then 1 else 1.15),
			})
		end
	end

	-- Bushes: a few around each tree, and along cliff feet.
	local bushes = library.bushes
	for _, t in trees do
		local n = rng:int(0, bushes.perTree)
		for _ = 1, n do
			local angle = rng:range(0, math.pi * 2)
			local d = rng:range(8, 22)
			local x, z = t[1] + math.cos(angle) * d, t[2] + math.sin(angle) * d
			if usable(x, z, 6) then
				local base = footing(grid, x, z, 3)
				if base then
					table.insert(out, {
						asset = string.format("%s%02d", bushes.prefix, rng:int(1, bushes.variants)),
						x = x,
						y = base - 0.3,
						z = z,
						yaw = rng:range(0, math.pi * 2),
						scale = rng:range(bushes.scale[1], bushes.scale[2]),
					})
				end
			end
		end
	end

	-- Boulders on open ground, on a jittered lattice.
	local boulders = library.boulders
	local lattice = 60
	local chance = biome.boulders * lattice * lattice / 100000
	for gz = math.floor(z0 / lattice), math.floor(z1 / lattice) do
		for gx = math.floor(x0 / lattice), math.floor(x1 / lattice) do
			if Hash.unit(node.seed, gx, gz, 21) >= chance then
				continue
			end
			local x = (gx + Hash.unit(node.seed, gx, gz, 22)) * lattice
			local z = (gz + Hash.unit(node.seed, gx, gz, 23)) * lattice
			if x < x0 or x > x1 or z < z0 or z > z1 or not usable(x, z, 8) then
				continue
			end
			local k = sampleAt(grid, x, z)
			if grid.padDistance[k] < 10 then
				continue
			end
			local base = footing(grid, x, z, 4)
			if base then
				table.insert(out, {
					asset = string.format(
						"%s%02d",
						boulders.prefix,
						1 + Hash.u32(node.seed, gx, gz, 24) % boulders.variants
					),
					x = x,
					y = base - 1.5,
					z = z,
					yaw = Hash.unit(node.seed, gx, gz, 25) * math.pi * 2,
					scale = boulders.scale[1]
						+ (boulders.scale[2] - boulders.scale[1]) * Hash.unit(node.seed, gx, gz, 26),
				})
			end
		end
	end
	return out
end

return Props
