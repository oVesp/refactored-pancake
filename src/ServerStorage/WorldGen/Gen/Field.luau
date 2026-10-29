--!strict

--[=[
	The world as a pure function of position: which node owns a point, the ground height, the
	surface material and water. Terrain columns, cliff columns and props all sample this, so they
	agree with each other and come out identical in Studio and Lune.

	Ownership is a multiplicatively weighted Voronoi diagram on domain-warped coordinates: a point
	belongs to the node with the smallest distance / r. Past r from every site, or outside every
	section rectangle, the point is mountain rim (owner 0). Inside a zone, terraces raise parts of
	the floor by one or two steps so the floor itself has levels.
]=]
local Graph = require(script.Parent.Graph)
local Hash = require(script.Parent.Hash)

type Graph = Graph.Graph
type Node = Graph.Node

export type Corridor = {
	edge: Graph.Edge,
	kind: string,
	points: { { x: number, z: number, h: number } },
	half: number,
	feather: number,
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
}

export type Sample = {
	height: number,
	material: string,
	owner: number, -- 0 = rim
	assign: number, -- node that builds this point: the owner, or the nearest node for rim
	water: number?, -- water surface height
	corridor: Corridor?,
	padDistance: number, -- studs to the nearest pad of the same floor (math.huge if none)
}

export type Field = {
	graph: Graph,
	corridors: { Corridor },
	owner: (x: number, z: number, skip: number?) -> (number, number, number),
	baseHeight: (x: number, z: number, skip: number?) -> number,
	sample: (x: number, z: number) -> Sample,
	height: (x: number, z: number) -> number,
	-- Unit vector pointing out of node `index`'s cell, across its nearest border.
	outward: (x: number, z: number, index: number) -> (number, number),
	roofHeight: (node: Node) -> number,
}

local Field = {}

local MARCH = 4
local FOLLOW_STEP = 8
local PAD_FEATHER = 24
local TERRACE_CLEAR = 60 -- no terraces this close to a pad
local OPEN_CLEAR = 50 -- nor this close to an open border

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--[=[ Builds the field for a graph; precomputes corridors for every edge with geometry. ]=]
function Field.new(graph: Graph): Field
	local realm = graph.realm
	local nodes = graph.nodes
	local count = #nodes
	local warpLargeX = Hash.fbm(Hash.named(graph.seed, "warpLX"), realm.warp.large.scale, 3)
	local warpLargeZ = Hash.fbm(Hash.named(graph.seed, "warpLZ"), realm.warp.large.scale, 3)
	local warpSmallX = Hash.fbm(Hash.named(graph.seed, "warpSX"), realm.warp.small.scale, 2)
	local warpSmallZ = Hash.fbm(Hash.named(graph.seed, "warpSZ"), realm.warp.small.scale, 2)
	local largeAmp, smallAmp = realm.warp.large.amp, realm.warp.small.amp
	local rimNoise = Hash.fbm(Hash.named(graph.seed, "rim"), realm.rim.scale, 4)
	local ridgeNoise = Hash.fbm(Hash.named(graph.seed, "ridge"), 120, 3)
	local edgeNoise = Hash.fbm(Hash.named(graph.seed, "edge"), 40, 2)
	local terraceNoise = Hash.fbm(Hash.named(graph.seed, "terrace"), realm.terraces.scale, 3)
	local floorNoise: { Hash.Fbm } = {}
	local terraceSteps: { { number } } = {}
	for i, node in nodes do
		floorNoise[i] = Hash.fbm(Hash.named(node.seed, "floor"), 180, 3)
		local steps = realm.terraces.step
		terraceSteps[i] = {
			Hash.range(node.seed, steps[1], steps[2], 1),
			Hash.range(node.seed, steps[1], steps[2], 2),
		}
	end
	local sections = {}
	for _, rect in realm.sections do
		table.insert(sections, rect)
	end
	local pads = realm.pads
	local lakes = realm.lakes
	local ridge = realm.ridge

	local self = {} :: Field
	self.graph = graph
	self.corridors = {}

	local function inSection(x: number, z: number): boolean
		for _, s in sections do
			if x >= s.x0 and x <= s.x1 and z >= s.z0 and z <= s.z1 then
				return true
			end
		end
		return false
	end

	local function warp(x: number, z: number): (number, number)
		return x + warpLargeX(x, z) * largeAmp + warpSmallX(x, z) * smallAmp,
			z + warpLargeZ(x, z) * largeAmp + warpSmallZ(x, z) * smallAmp
	end

	--[=[
		Owner, runner-up and margin in studs (about the distance to their border). With `skip`, that
		node is left out, which gives the ground a pocket replaced.
	]=]
	function self.owner(x: number, z: number, skip: number?): (number, number, number)
		if not inSection(x, z) then
			return 0, 0, 0
		end
		local wx, wz = warp(x, z)
		local best, second = 0, 0
		local bestRatio, secondRatio = math.huge, math.huge
		for i = 1, count do
			if i ~= skip then
				local node = nodes[i]
				local dx, dz = wx - node.x, wz - node.z
				local ratio = math.sqrt(dx * dx + dz * dz) / node.r
				if ratio < bestRatio then
					second, secondRatio = best, bestRatio
					best, bestRatio = i, ratio
				elseif ratio < secondRatio then
					second, secondRatio = i, ratio
				end
			end
		end
		if best == 0 then
			return 0, 0, 0
		end
		local rb = nodes[best].r
		if bestRatio > 1 then
			return 0, best, (bestRatio - 1) * rb
		end
		if second == 0 or secondRatio > 1 then
			return best, 0, (1 - bestRatio) * rb
		end
		local rs = nodes[second].r
		return best, second, (secondRatio - bestRatio) * rb * rs / (rb + rs)
	end

	local function isRidge(a: number, b: number): boolean
		if a == 0 or b == 0 or nodes[a].floor ~= nodes[b].floor then
			return false
		end
		local edge = Graph.edgeBetween(graph, a, b)
		return edge == nil or edge.kind ~= "open"
	end

	local function isOpen(a: number, b: number): boolean
		if a == 0 or b == 0 then
			return false
		end
		local edge = Graph.edgeBetween(graph, a, b)
		return edge ~= nil and (edge.kind == "open" or edge.kind == "pass")
	end

	-- Distance to the nearest pad on the same floor as node `a`.
	local function padDistance(x: number, z: number, a: number): (number, any)
		local best, which = math.huge, nil
		local floor = nodes[a].floor
		for _, pad in pads do
			if graph.byId[pad.zone].floor == floor then
				local dx = math.max(pad.x0 - x, 0, x - pad.x1)
				local dz = math.max(pad.z0 - z, 0, z - pad.z1)
				local d = math.sqrt(dx * dx + dz * dz)
				if d < best then
					best, which = d, pad
				end
			end
		end
		return best, which
	end

	local function lakeDistance(x: number, z: number, a: number): number
		local best = math.huge
		for _, lake in lakes do
			if graph.byId[lake.zone].index == a then
				best = math.min(best, math.sqrt((x - lake.x) ^ 2 + (z - lake.z) ^ 2) - lake.r)
			end
		end
		return best
	end

	local rimHeight: (x: number, z: number, skip: number?) -> number
	local rim = realm.rim
	local stepRise = Hash.fbm(Hash.named(graph.seed, "rimRise"), rim.ledgeScale, 2)
	local stepWidth = Hash.fbm(Hash.named(graph.seed, "rimWidth"), rim.ledgeScale, 2)

	local function outsideSections(x: number, z: number): number
		local best = math.huge
		for _, s in sections do
			local dx = math.max(s.x0 - x, 0, x - s.x1)
			local dz = math.max(s.z0 - z, 0, z - s.z1)
			best = math.min(best, math.sqrt(dx * dx + dz * dz))
		end
		return best
	end

	-- Height of the stepped rim `m` studs out from a cell: ledges `stepWidth` deep, each
	-- `stepRise` higher. Rise and depth vary smoothly along the border, so ledges run on.
	local function ledges(m: number, x: number, z: number): number
		local h, edge = 0, 0
		for k = 1, 16 do
			if m < edge then
				break
			end
			local t = 0.5 + 0.5 * stepRise(x + k * 137.3, z - k * 71.9)
			h += rim.rise[1] + (rim.rise[2] - rim.rise[1]) * math.clamp(t, 0, 1)
			local u = 0.5 + 0.5 * stepWidth(x - k * 53.1, z + k * 97.7)
			edge += rim.ledge[1] + (rim.ledge[2] - rim.ledge[1]) * math.clamp(u, 0, 1)
		end
		return h
	end

	--[=[
		Mountain rim: from every nearby cell the ground climbs in ledges; the rim takes the lowest
		of those climbs, so between two zones it rises from both sides to a crest. Capped by the
		rim's noisy ceiling.
	]=]
	function rimHeight(x: number, z: number, skip: number?): number
		local ceiling = rim.floor + rim.relief * rimNoise(x, z)
		local outside = outsideSections(x, z)
		local wx, wz = warp(x, z)
		local best = ceiling
		for i = 1, count do
			local node = nodes[i]
			if i ~= skip and node.kind == "zone" then
				local ratio = math.sqrt((wx - node.x) ^ 2 + (wz - node.z) ^ 2) / node.r
				local m = math.max((ratio - 1) * node.r, outside, 0)
				if m < 400 then
					best = math.min(best, node.floor + ledges(m, x, z))
				end
			end
		end
		return best
	end

	--[=[ Ground height from cells and terraces: no corridors, pads or lakes. ]=]
	local function cellHeight(x: number, z: number, skip: number?): (number, number, number, number)
		local a, b, margin = self.owner(x, z, skip)
		if a == 0 then
			return rimHeight(x, z, skip), a, b, margin
		end
		local node = nodes[a]
		local biome = realm.biomes[node.biome]
		local h = node.floor + biome.floorNoise * floorNoise[a](x, z)
		if isRidge(a, b) then
			local half = ridge.half * (1 + 0.35 * ridgeNoise(x + 911, z))
			if margin < half then
				return node.floor + ridge.height + ridge.relief * ridgeNoise(x, z), a, b, margin
			end
		end
		local terrace = biome.terrace
		if terrace then
			-- Terraces fade out (their threshold rises) near pads, lakes and open borders, so they
			-- never wall off the way between connected zones.
			local clear = math.min(
				smoothstep(TERRACE_CLEAR, TERRACE_CLEAR + 50, (padDistance(x, z, a))),
				smoothstep(20, 70, lakeDistance(x, z, a)),
				if isOpen(a, b) then smoothstep(OPEN_CLEAR, OPEN_CLEAR + 40, margin) else 1
			)
			local n = terraceNoise(x, z) + (1 - clear) * 2
			if n > terrace[2] then
				h += terraceSteps[a][1] + terraceSteps[a][2]
			elseif n > terrace[1] then
				h += terraceSteps[a][1]
			end
		end
		return h, a, b, margin
	end

	function self.baseHeight(x: number, z: number, skip: number?): number
		return (cellHeight(x, z, skip))
	end

	--[=[ Outward unit normal of a node's cell, from the gradient of its warped distance ratio. ]=]
	function self.outward(x: number, z: number, index: number): (number, number)
		local node = nodes[index]
		local function ratio(px: number, pz: number): number
			local wx, wz = warp(px, pz)
			return math.sqrt((wx - node.x) ^ 2 + (wz - node.z) ^ 2) / node.r
		end
		local e = 2
		local gx = ratio(x + e, z) - ratio(x - e, z)
		local gz = ratio(x, z + e) - ratio(x, z - e)
		local len = math.sqrt(gx * gx + gz * gz)
		if len < 1e-9 then
			return 1, 0
		end
		return gx / len, gz / len
	end

	-- Corridors -------------------------------------------------------------------------------

	local corridorCfg = realm.corridor

	-- Walks the straight line between two sites; returns the last point owned by `a` and the
	-- first point owned by `b` after leaving `a`.
	local function crossing(a: Node, b: Node): (number, number, number, number)
		local dx, dz = b.x - a.x, b.z - a.z
		local len = math.sqrt(dx * dx + dz * dz)
		local steps = math.ceil(len / MARCH)
		local exitX, exitZ
		for s = 1, steps do
			local t = s / steps
			local x, z = a.x + dx * t, a.z + dz * t
			local o = self.owner(x, z)
			if exitX == nil and o ~= a.index then
				local tp = (s - 1) / steps
				exitX, exitZ = a.x + dx * tp, a.z + dz * tp
			end
			if exitX ~= nil and o == b.index then
				return exitX, exitZ, x, z
			end
		end
		error(`no crossing from {a.id} to {b.id}: the line between their sites never enters {b.id}`)
	end

	local function finish(edge: Graph.Edge, kind: string, points: { any }, feather: number): Corridor
		local half = edge.width / 2
		local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
		for _, p in points do
			minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
			minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
		end
		local reach = half + feather
		return {
			edge = edge,
			kind = kind,
			points = points,
			half = half,
			feather = feather,
			minX = minX - reach,
			minZ = minZ - reach,
			maxX = maxX + reach,
			maxZ = maxZ + reach,
		}
	end

	--[=[
		Walks inside node `lo` along its border, `offset` studs in, for up to `length` studs. Returns
		the points with distance travelled, how far it got, and the closest it came to a pad.
	]=]
	local function follow(sx: number, sz: number, lo: Node, sign: number, length: number, offset: number)
		local ox, oz = self.outward(sx, sz, lo.index)
		local _, _, startMargin = self.owner(sx, sz)
		local x, z = sx - ox * (offset - startMargin), sz - oz * (offset - startMargin)
		local points = { { x = x, z = z, d = 0 } }
		local travelled = 0
		local clearance = (padDistance(x, z, lo.index))
		while travelled < length do
			ox, oz = self.outward(x, z, lo.index)
			local nx, nz = x + oz * sign * FOLLOW_STEP, z - ox * sign * FOLLOW_STEP
			local a, _, margin = self.owner(nx, nz)
			if a ~= lo.index then
				break
			end
			-- Pull back to the wanted distance from the border.
			nx, nz = nx + ox * (margin - offset), nz + oz * (margin - offset)
			if self.owner(nx, nz) ~= lo.index then
				break
			end
			travelled += math.sqrt((nx - x) ^ 2 + (nz - z) ^ 2)
			x, z = nx, nz
			clearance = math.min(clearance, (padDistance(x, z, lo.index)))
			table.insert(points, { x = x, z = z, d = travelled })
		end
		return points, travelled, clearance
	end

	local function slopeCorridor(edge: Graph.Edge)
		local a, b = nodes[edge.a], nodes[edge.b]
		local hi, lo = a, b
		if lo.floor > hi.floor then
			hi, lo = lo, hi
		end
		local inset = corridorCfg.inset
		local slope = if edge.kind == "stairs" then corridorCfg.stairsSlope else corridorCfg.rampSlope
		local need = (hi.floor - lo.floor) / slope
		local ex, ez, lx, lz = crossing(hi, lo)
		local dx, dz = lx - ex, lz - ez
		local gap = math.sqrt(dx * dx + dz * dz)
		local ux, uz = (lo.x - hi.x), (lo.z - hi.z)
		local ul = math.sqrt(ux * ux + uz * uz)
		ux, uz = ux / ul, uz / ul

		local points = { { x = ex - ux * inset, z = ez - uz * inset, h = hi.floor }, { x = ex, z = ez, h = hi.floor } }
		if not edge.along then
			local run = math.max(gap, need)
			table.insert(points, { x = ex + ux * run, z = ez + uz * run, h = lo.floor })
			table.insert(points, { x = ex + ux * (run + inset), z = ez + uz * (run + inset), h = lo.floor })
			return finish(edge, edge.kind, points, 2)
		end

		-- Along the cliff: a level causeway across any gap, then a path inside `lo` that hugs its
		-- border while it descends. The side that keeps farther from pads wins.
		local offset = edge.width / 2 + 3
		local best, bestLength, bestClear = nil, 0, -math.huge
		for _, sign in { 1, -1 } do
			local path, length, clearance = follow(lx, lz, lo, sign, need, offset)
			local score = math.min(length, need) * 4 + math.min(clearance, 200)
			if best == nil or score > math.min(bestLength, need) * 4 + math.min(bestClear, 200) then
				best, bestLength, bestClear = path, length, clearance
			end
		end
		assert(best, "follow returned no path")
		if bestLength < need * 0.6 then
			error(
				`{hi.id}-{lo.id}: the path along {lo.id}'s border is {math.floor(bestLength)} of {math.floor(need)} studs`
			)
		end
		for _, p in best do
			table.insert(points, { x = p.x, z = p.z, h = lerp(hi.floor, lo.floor, math.min(p.d / bestLength, 1)) })
		end
		local last, before = points[#points], points[#points - 1]
		local tx, tz = last.x - before.x, last.z - before.z
		local tl = math.max(math.sqrt(tx * tx + tz * tz), 1e-3)
		table.insert(points, { x = last.x + tx / tl * inset, z = last.z + tz / tl * inset, h = lo.floor })
		return finish(edge, edge.kind, points, 2)
	end

	for _, edge in graph.edges do
		if edge.kind == "open" or edge.kind == "drop" then
			continue
		end
		if edge.kind == "ramp" or edge.kind == "stairs" then
			table.insert(self.corridors, slopeCorridor(edge))
			continue
		end
		local a, b = nodes[edge.a], nodes[edge.b]
		local inset = corridorCfg.inset
		local ex, ez, bx, bz = crossing(a, b)
		local dx, dz = bx - ex, bz - ez
		local dl = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
		dx, dz = dx / dl, dz / dl
		table.insert(
			self.corridors,
			finish(edge, edge.kind, {
				{ x = ex - dx * inset, z = ez - dz * inset, h = a.floor },
				{ x = ex, z = ez, h = a.floor },
				{ x = bx, z = bz, h = b.floor },
				{ x = bx + dx * inset, z = bz + dz * inset, h = b.floor },
			}, if edge.kind == "pass" then 6 else 1)
		)
	end

	-- Nearest point on a corridor: distance and the height there.
	local function onCorridor(c: Corridor, x: number, z: number): (number, number)
		local best, height = math.huge, 0
		local pts = c.points
		for k = 1, #pts - 1 do
			local p, q = pts[k], pts[k + 1]
			local abx, abz = q.x - p.x, q.z - p.z
			local len2 = math.max(abx * abx + abz * abz, 1e-6)
			local t = math.clamp(((x - p.x) * abx + (z - p.z) * abz) / len2, 0, 1)
			local d = math.sqrt((x - p.x - abx * t) ^ 2 + (z - p.z - abz * t) ^ 2)
			if d < best then
				best, height = d, lerp(p.h, q.h, t)
			end
		end
		return best, height
	end

	function self.sample(x: number, z: number): Sample
		local h, a, b = cellHeight(x, z)
		local assign = if a ~= 0 then a else b
		local material = realm.biomes[nodes[if a ~= 0 then a elseif b ~= 0 then b else 1].biome].grass
		local water: number? = nil
		local nearestPad = math.huge

		if a ~= 0 then
			local d, pad = padDistance(x, z, a)
			nearestPad = d
			if pad and d < PAD_FEATHER then
				h = lerp(h, realm.padHeight, smoothstep(PAD_FEATHER, 0, d))
				if d < 3 + 4 * edgeNoise(x, z) then
					material = pad.material
				end
			end
			for _, lake in lakes do
				if graph.byId[lake.zone].index == a then
					local dl = math.sqrt((x - lake.x) ^ 2 + (z - lake.z) ^ 2) + 10 * edgeNoise(x + 300, z)
					if dl < lake.r then
						local s = dl / lake.r
						h = math.min(h, lake.level - lake.depth * (1 - s * s))
						water = lake.level
						material = "Mud"
					else
						h = math.min(h, lake.level + (dl - lake.r) * 0.35)
						if dl < lake.r + 8 then
							material = "Sand"
						end
					end
				end
			end
		end

		local inside: Corridor? = nil
		for _, c in self.corridors do
			if x >= c.minX and x <= c.maxX and z >= c.minZ and z <= c.maxZ then
				local d, hc = onCorridor(c, x, z)
				if d < c.half + c.feather then
					local w = if d <= c.half then 1 else smoothstep(c.half + c.feather, c.half, d)
					h = lerp(h, hc, w)
					if d <= c.half then
						inside = c
						material = realm.biomes[nodes[c.edge.a].biome].ground
					end
				end
			end
		end

		return {
			height = h,
			material = material,
			owner = a,
			assign = assign,
			water = water,
			corridor = inside,
			padDistance = nearestPad,
		}
	end

	function self.height(x: number, z: number): number
		return self.sample(x, z).height
	end

	--[=[ Height a roofed pocket's roof matches: the ground the pocket was cut out of. ]=]
	function self.roofHeight(node: Node): number
		return self.baseHeight(node.x, node.z, node.index)
	end

	return self
end

return Field
