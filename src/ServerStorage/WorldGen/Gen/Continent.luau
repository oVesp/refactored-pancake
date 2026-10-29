--!strict

--[=[
	Continent generator (docs/systems/world-generation.md). A pure function of the template and a
	seed, so it runs the same in Lune (preview, tests) and Studio. Works on a `res` x `res` grid of
	unit map coordinates (`u` east, `v` south).

	Stages:
	1. Land and regions: every region has anchors; a cell belongs to the region whose anchor is
	   nearest by distance / reach, measured on domain-warped coordinates so borders curve. A cell
	   is land while that distance stays under a noisy `coast.reach` (1 for scattered islets), which
	   draws the coastline and closes the gaps between neighbouring anchors.
	2. Height, mountains and lakes: base height plus noise per region; borders listed in `ridges`
	   become mountain bands; template lakes are carved.
	3. Sites: named sites at their template spot (jittered, moved to the coast when `coastal`), then
	   each region's towns, points of interest and dungeons at random, kept apart by `spacing`.
	4. Roads: a minimum spanning tree over the mainland settlements plus a few short extra links,
	   each routed by A* over a cost grid that avoids water and mountains and prefers existing road.
]=]

local Hash = require(script.Parent.Hash)

type Template = typeof(require(script.Parent.Parent.Continent))

export type PlacedSite = {
	id: string,
	name: string,
	kind: string,
	region: string,
	owner: string?,
	u: number,
	v: number,
	cell: number,
}

export type Road = { a: string, b: string, cells: { number } }

export type Map = {
	res: number,
	size: number,
	seed: number,
	regionIds: { string }, -- region index to id
	region: { number }, -- per cell: region index, 0 sea, -1 lake
	height: { number }, -- per cell, 0..1
	mountain: { boolean },
	coast: { boolean }, -- land cell next to the sea
	mainland: { boolean }, -- in the largest land mass
	road: { boolean },
	sites: { PlacedSite },
	roads: { Road },
}

local Continent = {}

Continent.SEA = 0
Continent.LAKE = -1

local SETTLEMENT = { capital = true, city = true, town = true, harbor = true }

--[=[ Cell index of grid coordinates (0-based). ]=]
function Continent.index(res: number, i: number, j: number): number
	return j * res + i + 1
end

--[=[ Unit coordinates of a cell's centre. ]=]
function Continent.center(res: number, k: number): (number, number)
	local i = (k - 1) % res
	local j = (k - 1) // res
	return (i + 0.5) / res, (j + 0.5) / res
end

--[=[ Studs from unit coordinates: X east, Z south, the map centre at the origin. ]=]
function Continent.toStuds(map: Map, u: number, v: number): (number, number)
	return (u - 0.5) * map.size, (v - 0.5) * map.size
end

type AnchorPoint = { u: number, v: number, r: number, region: number }

local function anchorsOf(template: Template, seed: number): { AnchorPoint }
	local out: { AnchorPoint } = {}
	for index, region in template.regions do
		local rng = Hash.rng(Hash.named(seed, region.id))
		for _, a in region.anchors do
			local u = a[1] + rng:range(-0.012, 0.012)
			local v = a[2] + rng:range(-0.012, 0.012)
			table.insert(out, { u = u, v = v, r = a[3], region = index })
		end
		local scatter = region.scatter
		if scatter then
			local centre = region.anchors[1]
			for _ = 1, scatter.count do
				local angle = rng:range(0, 2 * math.pi)
				local dist = scatter.spread * math.sqrt(rng:next())
				table.insert(out, {
					u = centre[1] + math.cos(angle) * dist,
					v = centre[2] + math.sin(angle) * dist,
					r = rng:range(scatter.r[1], scatter.r[2]),
					region = index,
				})
			end
		end
	end
	return out
end

local function ridgeSet(template: Template, indexOf: { [string]: number }): { [number]: boolean }
	local set: { [number]: boolean } = {}
	for _, pair in template.ridges do
		local a, b = indexOf[pair[1]], indexOf[pair[2]]
		assert(a and b, `ridge names an unknown region: {pair[1]}/{pair[2]}`)
		set[a * 1000 + b] = true
		set[b * 1000 + a] = true
	end
	return set
end

local function terrain(template: Template, seed: number, res: number, map: Map)
	local indexOf: { [string]: number } = {}
	for index, region in template.regions do
		indexOf[region.id] = index
	end
	local anchors = anchorsOf(template, seed)
	local ridges = ridgeSet(template, indexOf)
	local warpU = Hash.fbm(Hash.named(seed, "warpU"), template.warp.scale, 3)
	local warpV = Hash.fbm(Hash.named(seed, "warpV"), template.warp.scale, 3)
	local coastNoise = Hash.fbm(Hash.named(seed, "coast"), template.coast.scale, template.coast.octaves)
	local heightNoise = Hash.fbm(Hash.named(seed, "height"), 0.08, 4)
	local ridgeNoise = Hash.fbm(Hash.named(seed, "ridge"), 0.05, 3)
	local margin = template.margin
	local regionCount = #template.regions
	local best = table.create(regionCount, math.huge)

	for k = 1, res * res do
		local u, v = Continent.center(res, k)
		local wu = u + template.warp.amp * warpU(u, v)
		local wv = v + template.warp.amp * warpV(u, v)
		table.clear(best)
		for _, a in anchors do
			local d = math.sqrt((wu - a.u) ^ 2 + (wv - a.v) ^ 2) / a.r
			if d < (best[a.region] or math.huge) then
				best[a.region] = d
			end
		end
		local r1, d1, r2, d2 = 0, math.huge, 0, math.huge
		for index, d in best do
			if d < d1 then
				r2, d2 = r1, d1
				r1, d1 = index, d
			elseif d < d2 then
				r2, d2 = index, d
			end
		end

		local inside = u > margin and u < 1 - margin and v > margin and v < 1 - margin
		local land = if template.regions[r1].scatter then 1 else template.coast.reach
		local reach = land + template.coast.amp * coastNoise(u, v)
		if not inside or d1 >= reach then
			map.region[k] = Continent.SEA
			map.height[k] = 0
			map.mountain[k] = false
			continue
		end

		local region = template.regions[r1]
		local shore = math.clamp((reach - d1) / 0.25, 0, 1)
		local h = (region.height + region.relief * (heightNoise(u, v) * 0.5 + 0.5)) * (0.4 + 0.6 * shore)
		local mountain = false
		if r2 ~= 0 and ridges[r1 * 1000 + r2] then
			local width = template.ridge.width * (1 + template.ridge.noise * ridgeNoise(u, v))
			if d2 - d1 < width / region.anchors[1][3] then
				mountain = true
				h = math.max(h, 0.75 + 0.2 * (ridgeNoise(v, u) * 0.5 + 0.5))
			end
		end
		map.region[k] = r1
		map.height[k] = math.clamp(h, 0, 1)
		map.mountain[k] = mountain

		for _, lake in template.lakes do
			local d = math.sqrt((u - lake[1]) ^ 2 + (v - lake[2]) ^ 2) / lake[3]
			if d + 0.3 * coastNoise(v, u) < 1 then
				map.region[k] = Continent.LAKE
				map.mountain[k] = false
			end
		end
	end
end

local function neighbours(res: number, k: number): { number }
	local i = (k - 1) % res
	local j = (k - 1) // res
	local out = {}
	if i > 0 then
		table.insert(out, k - 1)
	end
	if i < res - 1 then
		table.insert(out, k + 1)
	end
	if j > 0 then
		table.insert(out, k - res)
	end
	if j < res - 1 then
		table.insert(out, k + res)
	end
	return out
end

local function shoreAndMainland(res: number, map: Map)
	local component = table.create(res * res, 0)
	local sizes: { number } = {}
	for k = 1, res * res do
		map.coast[k] = false
		if map.region[k] > 0 then
			for _, n in neighbours(res, k) do
				if map.region[n] == Continent.SEA then
					map.coast[k] = true
				end
			end
		end
	end
	for start = 1, res * res do
		if map.region[start] > 0 and component[start] == 0 then
			local id = #sizes + 1
			local stack = { start }
			component[start] = id
			local count = 0
			while #stack > 0 do
				local k = table.remove(stack) :: number
				count += 1
				for _, n in neighbours(res, k) do
					if map.region[n] > 0 and component[n] == 0 then
						component[n] = id
						table.insert(stack, n)
					end
				end
			end
			sizes[id] = count
		end
	end
	local biggest, biggestSize = 0, 0
	for id, size in sizes do
		if size > biggestSize then
			biggest, biggestSize = id, size
		end
	end
	for k = 1, res * res do
		map.mainland[k] = component[k] == biggest and biggest ~= 0
	end
end

local function placeSites(template: Template, seed: number, res: number, map: Map)
	local indexOf: { [string]: number } = {}
	for index, region in template.regions do
		indexOf[region.id] = index
	end
	local rng = Hash.rng(Hash.named(seed, "sites"))

	local function clearOf(u: number, v: number, spacing: number): boolean
		for _, s in map.sites do
			if (s.u - u) ^ 2 + (s.v - v) ^ 2 < spacing * spacing then
				return false
			end
		end
		return true
	end

	for _, site in template.sites do
		local regionIndex = indexOf[site.region]
		assert(regionIndex, `site {site.id} names an unknown region {site.region}`)
		local tu = site.at[1] + rng:range(-0.015, 0.015)
		local tv = site.at[2] + rng:range(-0.015, 0.015)
		local bestK, bestD = 0, math.huge
		for k = 1, res * res do
			if map.region[k] == regionIndex and not map.mountain[k] and (map.coast[k] or not site.coastal) then
				local u, v = Continent.center(res, k)
				local d = (u - tu) ^ 2 + (v - tv) ^ 2
				if d < bestD and clearOf(u, v, 0.02) then
					bestK, bestD = k, d
				end
			end
		end
		assert(bestK > 0, `site {site.id} has no ground in {site.region}`)
		local u, v = Continent.center(res, bestK)
		table.insert(map.sites, {
			id = site.id,
			name = site.name,
			kind = site.kind :: string,
			region = site.region,
			owner = site.owner,
			u = u,
			v = v,
			cell = bestK,
		})
	end

	for index, region in template.regions do
		local open: { number } = {}
		local any: { number } = {}
		for k = 1, res * res do
			if map.region[k] == index then
				table.insert(any, k)
				if not map.mountain[k] then
					table.insert(open, k)
				end
			end
		end
		for _, kind in { "town", "poi", "dungeon" } do
			local want = (region :: any)[kind .. "s"] :: number
			local pool = if kind == "dungeon" then any else open
			local spacing = (template.spacing :: any)[kind] :: number
			local placed = 0
			for _ = 1, 300 do
				if placed >= want or #pool == 0 then
					break
				end
				local k = pool[rng:int(1, #pool)]
				local u, v = Continent.center(res, k)
				if clearOf(u, v, spacing) then
					placed += 1
					table.insert(map.sites, {
						id = `{region.id}-{kind}-{placed}`,
						name = "",
						kind = kind,
						region = region.id,
						owner = if kind == "town" then region.owner else nil,
						u = u,
						v = v,
						cell = k,
					})
				end
			end
		end
	end
end

-- Binary min-heap of cells keyed by priority.
local function heapPush(heap: { number }, prio: { [number]: number }, k: number)
	table.insert(heap, k)
	local i = #heap
	while i > 1 do
		local p = i // 2
		if prio[heap[p]] <= prio[heap[i]] then
			break
		end
		heap[p], heap[i] = heap[i], heap[p]
		i = p
	end
end

local function heapPop(heap: { number }, prio: { [number]: number }): number
	local top = heap[1]
	local last = table.remove(heap) :: number
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local l, r, m = i * 2, i * 2 + 1, i
			if l <= #heap and prio[heap[l]] < prio[heap[m]] then
				m = l
			end
			if r <= #heap and prio[heap[r]] < prio[heap[m]] then
				m = r
			end
			if m == i then
				break
			end
			heap[m], heap[i] = heap[i], heap[m]
			i = m
		end
	end
	return top
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function route(template: Template, res: number, map: Map, from: number, to: number): { number }?
	local tuning = template.roads
	local ti, tj = (to - 1) % res, (to - 1) // res
	local g: { [number]: number } = { [from] = 0 }
	local f: { [number]: number } = {}
	local came: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	local heap: { number } = {}
	local function h(k: number): number
		local i, j = (k - 1) % res, (k - 1) // res
		return math.sqrt((i - ti) ^ 2 + (j - tj) ^ 2) * tuning.reuse
	end
	f[from] = h(from)
	heapPush(heap, f, from)
	while #heap > 0 do
		local k = heapPop(heap, f)
		if k == to then
			local path = { k }
			while came[k] do
				k = came[k]
				table.insert(path, 1, k)
			end
			return path
		end
		if not closed[k] then
			closed[k] = true
			local i, j = (k - 1) % res, (k - 1) // res
			for _, d in DIRS do
				local ni, nj = i + d[1], j + d[2]
				if ni >= 0 and nj >= 0 and ni < res and nj < res then
					local n = Continent.index(res, ni, nj)
					if map.mainland[n] and not closed[n] then
						local step = if d[1] ~= 0 and d[2] ~= 0 then 1.414 else 1
						local cost = step * (1 + tuning.slope * math.abs(map.height[n] - map.height[k]) * res / 64)
						if map.mountain[n] then
							cost *= tuning.mountain
						end
						if map.road[n] then
							cost *= tuning.reuse
						end
						local score = g[k] + cost
						if score < (g[n] or math.huge) then
							g[n] = score
							came[n] = k
							f[n] = score + h(n)
							heapPush(heap, f, n)
						end
					end
				end
			end
		end
	end
	return nil
end

local function buildRoads(template: Template, res: number, map: Map)
	local skyRegions: { [string]: boolean } = {}
	for _, region in template.regions do
		if region.sky then
			skyRegions[region.id] = true
		end
	end
	local nodes: { PlacedSite } = {}
	for _, s in map.sites do
		if SETTLEMENT[s.kind] and map.mainland[s.cell] and not skyRegions[s.region] then
			table.insert(nodes, s)
		end
	end
	local function dist(a: PlacedSite, b: PlacedSite): number
		return math.sqrt((a.u - b.u) ^ 2 + (a.v - b.v) ^ 2)
	end

	-- Prim's minimum spanning tree.
	local edges: { { PlacedSite } } = {}
	local linked: { [string]: boolean } = {}
	local inTree: { [number]: boolean } = { [1] = true }
	for _ = 2, #nodes do
		local bestA, bestB, bestD = 0, 0, math.huge
		for a in inTree do
			for b = 1, #nodes do
				if not inTree[b] then
					local d = dist(nodes[a], nodes[b])
					if d < bestD then
						bestA, bestB, bestD = a, b, d
					end
				end
			end
		end
		if bestB == 0 then
			break
		end
		inTree[bestB] = true
		table.insert(edges, { nodes[bestA], nodes[bestB] })
		linked[nodes[bestA].id .. "|" .. nodes[bestB].id] = true
		linked[nodes[bestB].id .. "|" .. nodes[bestA].id] = true
	end
	-- Extra links: a node's second-nearest neighbour when it is not much farther than the nearest.
	for _, a in nodes do
		local order = table.clone(nodes)
		table.sort(order, function(x, y)
			return dist(a, x) < dist(a, y)
		end)
		local nearest, second = order[2], order[3]
		if nearest and second and dist(a, second) < template.roads.extra * dist(a, nearest) then
			if not linked[a.id .. "|" .. second.id] then
				table.insert(edges, { a, second })
				linked[a.id .. "|" .. second.id] = true
				linked[second.id .. "|" .. a.id] = true
			end
		end
	end

	table.sort(edges, function(x, y)
		return dist(x[1], x[2]) < dist(y[1], y[2])
	end)
	for _, edge in edges do
		local path = route(template, res, map, edge[1].cell, edge[2].cell)
		if path then
			for _, k in path do
				map.road[k] = true
			end
			table.insert(map.roads, { a = edge[1].id, b = edge[2].id, cells = path })
		end
	end
end

--[=[
	Generates a continent from `template` (WorldGen/Continent). `seed` defaults to the template's
	and `res` to `template.res`; tests use a lower `res`.
]=]
function Continent.generate(template: Template, seed: number?, res: number?): Map
	local s = seed or template.seed
	local n = res or template.res
	local regionIds = {}
	for index, region in template.regions do
		regionIds[index] = region.id
	end
	local map: Map = {
		res = n,
		size = template.size,
		seed = s,
		regionIds = regionIds,
		region = table.create(n * n, 0),
		height = table.create(n * n, 0),
		mountain = table.create(n * n, false),
		coast = table.create(n * n, false),
		mainland = table.create(n * n, false),
		road = table.create(n * n, false),
		sites = {},
		roads = {},
	}
	terrain(template, s, n, map)
	shoreAndMainland(n, map)
	placeSites(template, s, n, map)
	buildRoads(template, n, map)
	return map
end

return Continent
