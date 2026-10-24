--!strict

-- Prop scatter (phase F7), in priority layers like the UE5 PCG Biome Core and the Wildlands
-- cascade: path tiles, canopy trees (Poisson disk), rock clusters, understory as tree children,
-- ground-cover patches, pebbles. Every random choice is a hash of (layer seed, position), so a
-- change in one layer never reshuffles another.
local Grid = require("./Grid")
local Noise = require("./Noise")

local Scatter = {}

export type Placement = {
	group: string,
	asset: string,
	x: number,
	y: number,
	z: number,
	yaw: number,
	ux: number, -- ground-aligned up vector, X and Z parts
	uz: number,
	scale: number,
}

type Circle = { x: number, z: number, r: number }

local BUCKET = 32

local function spatial()
	local buckets: { [number]: { Circle } } = {}
	local function key(bx: number, bz: number): number
		return (bx + 1000) * 4000 + (bz + 1000)
	end
	local self = {}
	function self.add(c: Circle)
		local k = key(c.x // BUCKET, c.z // BUCKET)
		local list = buckets[k]
		if not list then
			list = {}
			buckets[k] = list
		end
		table.insert(list, c)
	end
	--[=[ True when a circle of radius r at (x, z) overlaps any stored circle, scaled by `spread`. ]=]
	function self.hits(x: number, z: number, r: number, spread: number): boolean
		local bx, bz = x // BUCKET, z // BUCKET
		for dz = -2, 2 do
			for dx = -2, 2 do
				local list = buckets[key(bx + dx, bz + dz)]
				if list then
					for _, c in list do
						local min = (c.r + r) * spread
						if (c.x - x) ^ 2 + (c.z - z) ^ 2 < min * min then
							return true
						end
					end
				end
			end
		end
		return false
	end
	return self
end

--[=[ Bridson Poisson-disk samples over the tile (k = 30 candidates per active point). ]=]
function Scatter.poisson(cfg: any, radius: number, seed: number): { { number } }
	local rand = Noise.rng(seed)
	local size = cfg.n * cfg.cell
	local cellSize = radius / math.sqrt(2)
	local gn = math.ceil(size / cellSize)
	local grid: { [number]: number } = {}
	local points: { { number } } = {}
	local active: { number } = {}
	local function add(x: number, z: number)
		table.insert(points, { x, z })
		grid[math.floor(x / cellSize) + math.floor(z / cellSize) * gn] = #points
		table.insert(active, #points)
	end
	add(rand() * size, rand() * size)
	while #active > 0 do
		local slot = math.floor(rand() * #active) + 1
		local p = points[active[slot]]
		local found = false
		for _ = 1, 30 do
			local a = rand() * math.pi * 2
			local d = radius * (1 + rand())
			local x, z = p[1] + math.cos(a) * d, p[2] + math.sin(a) * d
			if x >= 0 and z >= 0 and x < size and z < size then
				local ci, cj = math.floor(x / cellSize), math.floor(z / cellSize)
				local ok = true
				for dj = -2, 2 do
					for di = -2, 2 do
						local idx = grid[(ci + di) + (cj + dj) * gn]
						if idx and ci + di >= 0 and ci + di < gn then
							local q = points[idx]
							if (q[1] - x) ^ 2 + (q[2] - z) ^ 2 < radius * radius then
								ok = false
							end
						end
					end
				end
				if ok then
					add(x, z)
					found = true
					break
				end
			end
		end
		if not found then
			active[slot] = active[#active]
			table.remove(active)
		end
	end
	for _, p in points do
		p[1] += cfg.originX
		p[2] += cfg.originZ
	end
	return points
end

local function pickWeighted(weights: { [string]: number }, roll: number): string
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

function Scatter.run(cfg: any, layout: any, maps: any, water: any, surface: any, trails: { any }): { Placement }
	local n, cell = cfg.n, cfg.cell
	local sc = cfg.scatter
	local biomes = cfg.biomes
	local placements: { Placement } = {}
	local size = n * cell

	local blocked = buffer.create(n * n)
	for _, r in layout.blockers do
		local m = sc.padMargin
		local i0 = math.floor((r.cx - r.hx - m - cfg.originX) / cell)
		local i1 = math.floor((r.cx + r.hx + m - cfg.originX) / cell)
		local j0 = math.floor((r.cz - r.hz - m - cfg.originZ) / cell)
		local j1 = math.floor((r.cz + r.hz + m - cfg.originZ) / cell)
		for j = math.max(j0, 0), math.min(j1, n - 1) do
			for i = math.max(i0, 0), math.min(i1, n - 1) do
				buffer.writeu8(blocked, i + j * n, 1)
			end
		end
	end

	local function cellOf(x: number, z: number): (number, number)
		return math.floor((x - cfg.originX) / cell), math.floor((z - cfg.originZ) / cell)
	end
	local function inside(x: number, z: number): boolean
		return x > cfg.originX + 8 and z > cfg.originZ + 8 and x < cfg.originX + size - 8 and z < cfg.originZ + size - 8
	end
	local function biomeAt(x: number, z: number): number
		local i, j = cellOf(x, z)
		if i < 0 or j < 0 or i >= n or j >= n or buffer.readu8(blocked, i + j * n) == 1 then
			return 0
		end
		return buffer.readu8(surface.biome, i + j * n)
	end
	local function dry(x: number, z: number): boolean
		local i, j = cellOf(x, z)
		return Grid.get(water.surface, i, j) < Grid.get(maps.height, i, j) - 0.5
	end
	local function slopeAt(x: number, z: number): number
		local i, j = cellOf(x, z)
		return Grid.slopeDeg(maps.height, i, j, cell)
	end
	local function assetOf(group: string, roll: number): any
		local list = cfg.groups[group].assets
		return list[math.floor(roll * #list) + 1]
	end
	local function place(group: string, asset: any, x: number, z: number, yaw: number, scale: number)
		table.insert(placements, {
			group = group,
			asset = asset.name,
			x = x,
			y = 0,
			z = z,
			yaw = yaw,
			ux = 0,
			uz = 0,
			scale = scale,
		})
	end
	local function scaleOf(asset: any, roll: number): number
		return asset.scale[1] + (asset.scale[2] - asset.scale[1]) * roll
	end

	local solid = spatial() -- trunks and rocks
	local shrubs = spatial()

	-- Path tiles along trails.
	local tileSeed = Noise.layerSeed(cfg.seed, "pathTiles")
	for t, trail in trails do
		local pts = trail.points
		local carry = 0
		for idx = 1, #pts - 1 do
			local a, b = pts[idx], pts[idx + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(dx * dx + dz * dz)
			local d = carry
			while d < len do
				local x, z = a[1] + dx * d / len, a[2] + dz * d / len
				local h = Noise.hash32(tileSeed, t, idx, math.floor(d * 10))
				local r1 = Noise.hash01(h, 1)
				local side = (Noise.hash01(h, 2) - 0.5) * 2.4
				x += -dz / len * side
				z += dx / len * side
				local i, j = cellOf(x, z)
				if dry(x, z) and Grid.get(maps.padDistance, i, j) > 4 and inside(x, z) then
					local asset = assetOf("PathTile", r1)
					local yaw = math.deg(math.atan2(dx, dz)) + (Noise.hash01(h, 3) - 0.5) * 30
					place("PathTile", asset, x, z, yaw, scaleOf(asset, Noise.hash01(h, 4)))
				end
				d += cfg.paths.tileSpacing
			end
			carry = d - len
		end
	end

	-- Canopy trees.
	local treeSeed = Noise.layerSeed(cfg.seed, "trees")
	local clump = Noise.fbm(Noise.layerSeed(cfg.seed, "treeClump"), 220, 3, 2, 0.5)
	local samples = Scatter.poisson(cfg, sc.treeSampleRadius, treeSeed)
	local areaPer = size * size / #samples
	local trees: { { x: number, z: number, r: number, b: number } } = {}
	for s, p in samples do
		local x, z = p[1], p[2]
		local b = biomeAt(x, z)
		if b > 0 and inside(x, z) and dry(x, z) then
			local def = biomes[b]
			local i, j = cellOf(x, z)
			local edge = Noise.smoothstep(sc.padMargin, sc.padMargin + 40, Grid.get(maps.padDistance, i, j))
			local density = def.trees / 1000 * areaPer * math.clamp(1 + clump(x, z) * 0.9, 0.15, 1.9) * edge
			if Noise.hash01(treeSeed, s, 1) < density then
				local group = pickWeighted(def.treeWeights, Noise.hash01(treeSeed, s, 2))
				local asset = assetOf(group, Noise.hash01(treeSeed, s, 3))
				local scale = scaleOf(asset, Noise.hash01(treeSeed, s, 4))
				local r = asset.radius * scale
				if slopeAt(x, z) <= asset.maxSlope and not solid.hits(x, z, r, sc.canopyOverlap) then
					solid.add({ x = x, z = z, r = r })
					table.insert(trees, { x = x, z = z, r = r, b = b })
					place(group, asset, x, z, Noise.hash01(treeSeed, s, 5) * 360, scale)
				end
			end
		end
	end

	-- Rock clusters: one parent, smaller rocks and pebbles around it. Denser on 20-45° slopes and
	-- along the creek.
	local rockSeed = Noise.layerSeed(cfg.seed, "rocks")
	local rockSamples = Scatter.poisson(cfg, sc.rockSampleRadius, rockSeed)
	local rockArea = size * size / #rockSamples
	for s, p in rockSamples do
		local x, z = p[1], p[2]
		local b = biomeAt(x, z)
		if b > 0 and inside(x, z) and dry(x, z) then
			local i, j = cellOf(x, z)
			local slope = slopeAt(x, z)
			local boost = 1 + 2 * Noise.smoothstep(15, 30, slope)
			if Grid.get(maps.creekDistance, i, j) < cfg.water.creekBank + 12 then
				boost *= 4
			end
			local density = biomes[b].rocks / 1000 * rockArea * boost
			if Noise.hash01(rockSeed, s, 1) < density then
				local asset = assetOf("Rock", Noise.hash01(rockSeed, s, 2))
				local scale = scaleOf(asset, Noise.hash01(rockSeed, s, 3))
				local r = asset.radius * scale
				if slope <= asset.maxSlope and not solid.hits(x, z, r, sc.canopyOverlap) then
					solid.add({ x = x, z = z, r = r })
					place("Rock", asset, x, z, Noise.hash01(rockSeed, s, 4) * 360, scale)
					local children = 2 + math.floor(Noise.hash01(rockSeed, s, 5) * 3)
					for c = 1, children do
						local a = Noise.hash01(rockSeed, s, 10 + c) * math.pi * 2
						local d = r + 2 + Noise.hash01(rockSeed, s, 20 + c) * 6
						local cx, cz = x + math.cos(a) * d, z + math.sin(a) * d
						if biomeAt(cx, cz) > 0 and dry(cx, cz) and inside(cx, cz) then
							if c <= 1 then
								local small = assetOf("Rock", Noise.hash01(rockSeed, s, 30 + c))
								local ss = scale * (0.35 + 0.25 * Noise.hash01(rockSeed, s, 40 + c))
								if not solid.hits(cx, cz, small.radius * ss, sc.canopyOverlap) then
									solid.add({ x = cx, z = cz, r = small.radius * ss })
									place("Rock", small, cx, cz, Noise.hash01(rockSeed, s, 50 + c) * 360, ss)
								end
							else
								local peb = assetOf("Pebble", Noise.hash01(rockSeed, s, 30 + c))
								place(
									"Pebble",
									peb,
									cx,
									cz,
									Noise.hash01(rockSeed, s, 50 + c) * 360,
									scaleOf(peb, Noise.hash01(rockSeed, s, 60 + c))
								)
							end
						end
					end
				end
			end
		end
	end

	-- Understory as children of trees, in a ring around the canopy.
	local underSeed = Noise.layerSeed(cfg.seed, "understory")
	for t, tree in trees do
		local def = biomes[tree.b]
		local lo, hi = def.understory[1], def.understory[2]
		local count = lo + math.floor(Noise.hash01(underSeed, t, 1) * (hi - lo + 1))
		for c = 1, count do
			local a = Noise.hash01(underSeed, t, 10 + c) * math.pi * 2
			local d = tree.r * (0.6 + 0.9 * Noise.hash01(underSeed, t, 20 + c))
			local x, z = tree.x + math.cos(a) * d, tree.z + math.sin(a) * d
			if biomeAt(x, z) > 0 and dry(x, z) and inside(x, z) then
				local group = pickWeighted(def.understoryWeights, Noise.hash01(underSeed, t, 30 + c))
				local asset = assetOf(group, Noise.hash01(underSeed, t, 40 + c))
				local scale = scaleOf(asset, Noise.hash01(underSeed, t, 50 + c))
				local r = asset.radius * scale
				if
					slopeAt(x, z) <= asset.maxSlope
					and not shrubs.hits(x, z, r, 0.8)
					and not solid.hits(x, z, 1, sc.trunkClearance)
				then
					shrubs.add({ x = x, z = z, r = r })
					place(group, asset, x, z, Noise.hash01(underSeed, t, 60 + c) * 360, scale)
				end
			end
		end
	end

	-- Ground cover in noise patches on a jittered grid (flowers only inside strong meadow patches).
	local coverSeed = Noise.layerSeed(cfg.seed, "cover")
	local patches = Noise.fbm(Noise.layerSeed(cfg.seed, "coverPatch"), 60, 3, 2, 0.5)
	local cover: { Placement } = {}
	local cells = math.floor(size / sc.coverCell)
	for cj = 0, cells - 1 do
		for ci = 0, cells - 1 do
			local x = cfg.originX + (ci + Noise.hash01(coverSeed, ci, cj, 1)) * sc.coverCell
			local z = cfg.originZ + (cj + Noise.hash01(coverSeed, ci, cj, 2)) * sc.coverCell
			local b = biomeAt(x, z)
			if b > 0 and inside(x, z) and dry(x, z) then
				local patch = patches(x, z)
				local strength = Noise.smoothstep(0.05, 0.45, patch)
				local def = biomes[b]
				if strength > 0 and Noise.hash01(coverSeed, ci, cj, 3) < def.cover * strength * 4 then
					local weights = def.coverWeights
					local group = pickWeighted(weights, Noise.hash01(coverSeed, ci, cj, 4))
					if group == "Flower" and patch < 0.35 then
						group = "Grass"
					end
					local asset = assetOf(group, Noise.hash01(coverSeed, ci, cj, 5))
					if slopeAt(x, z) <= asset.maxSlope and not solid.hits(x, z, 0.5, sc.trunkClearance) then
						table.insert(cover, {
							group = group,
							asset = asset.name,
							x = x,
							y = 0,
							z = z,
							yaw = Noise.hash01(coverSeed, ci, cj, 6) * 360,
							ux = 0,
							uz = 0,
							scale = scaleOf(asset, Noise.hash01(coverSeed, ci, cj, 7)),
						})
					end
				end
			end
		end
	end
	if #cover > sc.maxCover then
		-- Deterministic thinning keeps the spatial spread of the patches.
		local keep = sc.maxCover / #cover
		for idx, p in cover do
			if Noise.hash01(coverSeed, idx, 99) < keep then
				table.insert(placements, p)
			end
		end
	else
		for _, p in cover do
			table.insert(placements, p)
		end
	end

	-- Pebbles along creek banks.
	local pebSeed = Noise.layerSeed(cfg.seed, "creekPebbles")
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local dc = Grid.get(maps.creekDistance, i, j)
			local w = cfg.water.creekWidth
			if dc > w - 1 and dc < w + 6 and Noise.hash01(pebSeed, i, j) < 0.12 then
				local x = cfg.originX + (i + Noise.hash01(pebSeed, i, j, 1)) * cell
				local z = cfg.originZ + (j + Noise.hash01(pebSeed, i, j, 2)) * cell
				if dry(x, z) and biomeAt(x, z) > 0 and inside(x, z) then
					local asset = assetOf("Pebble", Noise.hash01(pebSeed, i, j, 3))
					place(
						"Pebble",
						asset,
						x,
						z,
						Noise.hash01(pebSeed, i, j, 4) * 360,
						scaleOf(asset, Noise.hash01(pebSeed, i, j, 5))
					)
				end
			end
		end
	end

	-- Final heights and ground alignment from the finished heightfield.
	for _, p in placements do
		local fi = (p.x - cfg.originX) / cell - 0.5
		local fj = (p.z - cfg.originZ) / cell - 0.5
		p.y = Grid.sample(maps.height, fi, fj)
		local i, j = math.floor(fi + 0.5), math.floor(fj + 0.5)
		local gx, gz = Grid.gradient(maps.height, i, j, cell)
		local nx, ny, nz = -gx, 1, -gz
		local len = math.sqrt(nx * nx + ny * ny + nz * nz)
		local align = 0
		for _, a in cfg.groups[p.group].assets do
			if a.name == p.asset then
				align = a.align
				break
			end
		end
		local ux, uy, uz = nx / len * align, 1 + (ny / len - 1) * align, nz / len * align
		local ul = math.sqrt(ux * ux + uy * uy + uz * uz)
		p.ux, p.uz = ux / ul, uz / ul
	end
	return placements
end

return Scatter
