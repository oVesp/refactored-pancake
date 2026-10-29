--!strict

--[=[
	Part geometry for one zone: rock columns on every cliff face, spires on the mountain rim,
	stairs, and the slabs that roof caves and pockets. Pure data (`PartSpec`); the Studio builder
	turns it into Parts.

	Cliff faces are found from the height samples, not from the graph: wherever the ground rises
	more than `cliff.step` between neighbouring samples there is a face, whether it is a tier
	border, the rim, a ridge, a ramp side or a tunnel wall. Each face point on this zone's ground
	becomes a candidate; candidates are thinned to `cliff.spacing` and each grows a column of
	stacked, jittered blocks from below the low ground to the top of the high ground.
]=]
local Field = require(script.Parent.Field)
local Graph = require(script.Parent.Graph)
local Grid = require(script.Parent.Grid)
local Hash = require(script.Parent.Hash)

export type PartSpec = {
	kind: string, -- "Cliff", "Cap", "Spire", "Outcrop", "Stair", "Roof"
	x: number,
	y: number,
	z: number,
	yaw: number, -- radians
	pitch: number,
	roll: number,
	sx: number,
	sy: number,
	sz: number,
	material: string,
	color: { number },
}

local Cliffs = {}

local CAP = 1.6 -- grass cap thickness
local CAP_LIP = 1.4 -- how far a cap reaches past its block
local ROOM = 34 -- clear height inside a roofed pocket
local BURY = 10 -- columns start this far below the low ground

local function shade(color: { number }, f: number): { number }
	return {
		math.clamp(math.round(color[1] * f), 0, 255),
		math.clamp(math.round(color[2] * f), 0, 255),
		math.clamp(math.round(color[3] * f), 0, 255),
	}
end

local function biomeOf(field: Field.Field, index: number): any
	local graph = field.graph
	return graph.realm.biomes[graph.nodes[index].biome]
end

--[=[
	Stacks blocks from `top` down to `bottom` at (x, z) with outward normal (nx, nz). The top block
	stays level so its grass cap sits flat; lower blocks lean and wander a little.
]=]
local function column(
	out: { PartSpec },
	rng: Hash.Rng,
	cfg: any,
	x: number,
	z: number,
	nx: number,
	nz: number,
	width: number,
	depth: number,
	top: number,
	bottom: number,
	material: string,
	color: { number },
	cap: { number }?,
	kind: string
)
	local tx, tz = -nz, nx
	local yaw = math.atan2(-nx, -nz)
	local total = top - bottom
	local scale = 1 + total / 320
	local y = top
	local k = 0
	while y > bottom + 1 do
		k += 1
		local bh = rng:range(cfg.block[1], cfg.block[2]) * scale
		if y - bh < bottom + cfg.block[1] * 0.5 then
			bh = y - bottom
		end
		local grow = 1 + 0.06 * (k - 1)
		local w = width * rng:range(0.88, 1.08) * grow
		local d = depth * rng:range(0.9, 1.12) * grow
		local off = if k == 1 then 0 else rng:range(-3, 2)
		local side = rng:range(-3, 3)
		local cx = x + nx * off + tx * side
		local cz = z + nz * off + tz * side
		local tilt = math.rad(cfg.tilt)
		table.insert(out, {
			kind = kind,
			x = cx,
			y = y - bh / 2,
			z = cz,
			yaw = yaw + math.rad(rng:range(-cfg.yaw, cfg.yaw)),
			pitch = if k == 1 then 0 else rng:range(-tilt, tilt),
			roll = if k == 1 then 0 else rng:range(-tilt, tilt),
			sx = w,
			sy = bh + 2,
			sz = d,
			material = material,
			color = shade(color, rng:range(0.92, 1.06)),
		})
		if k == 1 and cap then
			table.insert(out, {
				kind = "Cap",
				x = cx,
				y = top + CAP / 2 - 0.4,
				z = cz,
				yaw = out[#out].yaw,
				pitch = 0,
				roll = 0,
				sx = w + CAP_LIP * 2,
				sy = CAP,
				sz = d + CAP_LIP * 2,
				material = "Grass",
				color = shade(cap, rng:range(0.95, 1.05)),
			})
		end
		y -= bh
	end
end

-- Candidate face points on this zone's ground, each with a downhill normal.
type Candidate = { i: number, j: number, nx: number, nz: number, rise: number, key: number }

local function candidates(grid: Grid.Grid, zone: number, step: number, margin: number): { Candidate }
	local list: { Candidate } = {}
	local h = grid.height
	for j = margin, grid.nz - 1 - margin do
		for i = margin, grid.nx - 1 - margin do
			local k = Grid.index(grid, i, j)
			if grid.assign[k] ~= zone then
				continue
			end
			local here = h[k]
			local rise = 0
			local gx, gz = 0, 0
			for dj = -1, 1 do
				for di = -1, 1 do
					if di ~= 0 or dj ~= 0 then
						local up = h[Grid.index(grid, i + di, j + dj)] - here
						if up > 0 then
							local w = up / math.sqrt(di * di + dj * dj)
							gx -= di * w
							gz -= dj * w
							if di == 0 or dj == 0 then
								rise = math.max(rise, up)
							end
						end
					end
				end
			end
			if rise > step then
				local len = math.sqrt(gx * gx + gz * gz)
				if len > 1e-6 then
					table.insert(list, { i = i, j = j, nx = gx / len, nz = gz / len, rise = rise, key = 0 })
				end
			end
		end
	end
	return list
end

-- Height of the ground at the top of this face: walk uphill until the climb levels out, so a
-- face between two ledges stops at the lower ledge instead of reaching the cliff behind it.
local function topBehind(grid: Grid.Grid, x: number, z: number, nx: number, nz: number, reach: number): number
	local previous = Grid.heightAt(grid, x - nx * 4, z - nz * 4)
	local climbed = previous - Grid.heightAt(grid, x, z)
	for d = 8, reach, 4 do
		local h = Grid.heightAt(grid, x - nx * d, z - nz * d)
		local rise = h - previous
		if rise < 1 and climbed > 2 then
			break
		end
		climbed += rise
		previous = math.max(previous, h)
	end
	return previous
end

local function corridorAt(grid: Grid.Grid, x: number, z: number): Field.Corridor?
	local i = math.round((x - grid.x0) / grid.step)
	local j = math.round((z - grid.z0) / grid.step)
	return grid.corridor[Grid.index(grid, i, j)]
end

-- Points across the walkable width of every corridor, with the floor height there. A column
-- may not stand over any of them unless its top is below that floor.
type Walk = { x: number, z: number, h: number }
type Walks = { [number]: { Walk } } -- bucketed by WALK_CELL

local WALK_STEP = 3
local EMPTY_WALKS: { Walk } = {}
local EMPTY_POINTS: { { number } } = {}
local WALK_CELL = 32

local function walkKey(x: number, z: number): number
	return math.floor(x / WALK_CELL) * 65536 + math.floor(z / WALK_CELL)
end

local function walkways(field: Field.Field): Walks
	local out: Walks = {}
	for _, c in field.corridors do
		local pts = c.points
		local lateral = math.max(c.half - 1, 0)
		for k = 1, #pts - 1 do
			local p, q = pts[k], pts[k + 1]
			local dx, dz = q.x - p.x, q.z - p.z
			local len = math.sqrt(dx * dx + dz * dz)
			if len < 1e-3 then
				continue
			end
			local sx, sz = -dz / len, dx / len
			local steps = math.max(1, math.ceil(len / WALK_STEP))
			for s = 0, steps do
				local t = s / steps
				local x, z, h = p.x + dx * t, p.z + dz * t, p.h + (q.h - p.h) * t
				for _, o in { -lateral, 0, lateral } do
					local w = { x = x + sx * o, z = z + sz * o, h = h }
					local key = walkKey(w.x, w.z)
					local bucket = out[key]
					if not bucket then
						bucket = {}
						out[key] = bucket
					end
					table.insert(bucket, w)
				end
			end
		end
	end
	return out
end

--[=[
	True when a column at (cx, cz), facing (nx, nz), `width` x `depth` and reaching `top`, covers
	walkable corridor ground below its top. Lower blocks grow and wander, so the footprint is
	inflated to match.
]=]
local function blocksWalk(
	walks: Walks,
	cx: number,
	cz: number,
	nx: number,
	nz: number,
	width: number,
	depth: number,
	top: number
): boolean
	local tx, tz = -nz, nx
	local hw, hd = width * 0.65 + 3, depth * 0.65 + 3
	local reach = math.max(hw, hd) * 1.5
	for bx = math.floor((cx - reach) / WALK_CELL), math.floor((cx + reach) / WALK_CELL) do
		for bz = math.floor((cz - reach) / WALK_CELL), math.floor((cz + reach) / WALK_CELL) do
			for _, w in walks[bx * 65536 + bz] or EMPTY_WALKS do
				if w.h < top - 2 then
					local dx, dz = w.x - cx, w.z - cz
					if math.abs(dx * tx + dz * tz) < hw and math.abs(dx * nx + dz * nz) < hd then
						return true
					end
				end
			end
		end
	end
	return false
end

local function cliffColumns(out: { PartSpec }, field: Field.Field, grid: Grid.Grid, zone: number, walks: Walks)
	local graph = field.graph
	local realm = graph.realm
	local cfg = realm.cliff
	local node = graph.nodes[zone]
	local biome = biomeOf(field, zone)
	local list = candidates(grid, zone, cfg.step, 2)
	for _, c in list do
		c.key = Hash.u32(node.seed, c.i + math.floor(grid.x0 / grid.step), c.j + math.floor(grid.z0 / grid.step))
	end
	table.sort(list, function(a, b)
		return a.key < b.key
	end)

	-- Poisson thinning with a bucket grid.
	local spacing = cfg.spacing
	local buckets: { [number]: { { number } } } = {}
	local function bucketKey(bx: number, bz: number): number
		return bx * 100003 + bz
	end
	local function free(x: number, z: number): boolean
		local bx, bz = math.floor(x / spacing), math.floor(z / spacing)
		for dz = -1, 1 do
			for dx = -1, 1 do
				for _, p in buckets[bucketKey(bx + dx, bz + dz)] or EMPTY_POINTS do
					if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < spacing * spacing then
						return false
					end
				end
			end
		end
		return true
	end

	for _, c in list do
		local px = grid.x0 + c.i * grid.step
		local pz = grid.z0 + c.j * grid.step
		if not free(px, pz) then
			continue
		end
		local rng = Hash.rng(c.key)
		local nx, nz = c.nx, c.nz
		local low = grid.height[Grid.index(grid, c.i, c.j)]
		local top = topBehind(grid, px, pz, nx, nz, 32)
		if top - low < cfg.step then
			continue
		end
		local width = rng:range(cfg.width[1], cfg.width[2])
		local depth = rng:range(cfg.depth[1], cfg.depth[2])

		-- Inside a corridor (tunnel or path wall) the face must not narrow the way.
		local inCorridor = corridorAt(grid, px, pz) ~= nil
		local outset = if inCorridor then -1 else cfg.outset
		local cx = px + nx * (outset - depth / 2)
		local cz = pz + nz * (outset - depth / 2)

		-- Shrink the column until its footprint keeps off walkable corridor ground below its top.
		local fits = false
		for _ = 1, 4 do
			if not blocksWalk(walks, cx, cz, nx, nz, width, depth, top) then
				fits = true
				break
			end
			width *= 0.7
			depth *= 0.8
			cx = px + nx * (outset - depth / 2)
			cz = pz + nz * (outset - depth / 2)
		end
		if not fits then
			continue
		end

		local bx, bz = math.floor(px / spacing), math.floor(pz / spacing)
		local key = bucketKey(bx, bz)
		buckets[key] = buckets[key] or {}
		table.insert(buckets[key], { px, pz })

		-- The rim and ridges take their colour from the zone below; plateaus from their own biome.
		local behind = field.owner(px - nx * 20, pz - nz * 20)
		local rockBiome = if behind ~= 0 then biomeOf(field, behind) else biome
		local material = rockBiome.rock
		local isRim = behind == 0
		local cap = rockBiome.capColor
		column(
			out,
			rng,
			cfg,
			cx,
			cz,
			nx,
			nz,
			width,
			depth,
			top,
			low - BURY,
			material,
			rockBiome.rockColor,
			cap,
			"Cliff"
		)
		if
			isRim
			and rng:next() < cfg.spires
			and not blocksWalk(
				walks,
				cx - nx * depth * 0.4,
				cz - nz * depth * 0.4,
				nx,
				nz,
				width * 0.6,
				depth * 0.7,
				math.huge
			)
		then
			local rise = rng:range(cfg.spireHeight[1], cfg.spireHeight[2])
			local sx = cx - nx * depth * 0.4
			local sz = cz - nz * depth * 0.4
			column(
				out,
				rng,
				cfg,
				sx,
				sz,
				nx,
				nz,
				width * 0.6,
				depth * 0.7,
				top + rise,
				top - 6,
				material,
				shade(rockBiome.rockColor, 1.04),
				nil,
				"Spire"
			)
		end
	end
end

--[=[
	Standalone rock pillars on a zone's floor, on a jittered lattice so the count follows the
	zone's area. Kept off pads, corridors, water and borders so they never block a way through.
]=]
local function outcrops(out: { PartSpec }, field: Field.Field, grid: Grid.Grid, zone: number, walks: Walks)
	local graph = field.graph
	local node = graph.nodes[zone]
	local biome = biomeOf(field, zone)
	if biome.outcrops <= 0 then
		return
	end
	local cfg = graph.realm.cliff
	local lattice = 40
	local chance = biome.outcrops * lattice * lattice / 100000
	local i0 = math.floor(grid.x0 / lattice)
	local j0 = math.floor(grid.z0 / lattice)
	local i1 = math.floor((grid.x0 + grid.nx * grid.step) / lattice)
	local j1 = math.floor((grid.z0 + grid.nz * grid.step) / lattice)
	for j = j0, j1 do
		for i = i0, i1 do
			if Hash.unit(node.seed, i, j, 1) >= chance then
				continue
			end
			local x = (i + Hash.unit(node.seed, i, j, 2)) * lattice
			local z = (j + Hash.unit(node.seed, i, j, 3)) * lattice
			local a, _, margin = field.owner(x, z)
			if a ~= zone or margin < 30 then
				continue
			end
			local s = field.sample(x, z)
			if s.padDistance < 50 or s.water or s.corridor then
				continue
			end
			local clear = true
			for k = 0, 5 do
				local angle = k * math.pi / 3
				local ring = field.sample(x + math.cos(angle) * 24, z + math.sin(angle) * 24)
				if ring.corridor or ring.water or math.abs(ring.height - s.height) > cfg.step * 2 then
					clear = false
					break
				end
			end
			if not clear then
				continue
			end
			local rng = Hash.rng(Hash.u32(node.seed, i, j, 4))
			local rise = rng:range(28, 140)
			local width = rng:range(14, 34) * (if rise > 90 then 0.8 else 1)
			local angle = rng:range(0, math.pi * 2)
			if blocksWalk(walks, x, z, math.cos(angle), math.sin(angle), width, width * 1.2, s.height + rise) then
				continue
			end
			column(
				out,
				rng,
				cfg,
				x,
				z,
				math.cos(angle),
				math.sin(angle),
				width,
				width * rng:range(0.8, 1.2),
				s.height + rise,
				s.height - BURY,
				biome.rock,
				shade(biome.rockColor, rng:range(0.95, 1.08)),
				if rng:next() < 0.6 then biome.capColor else nil,
				"Outcrop"
			)
		end
	end
end

local function stairs(out: { PartSpec }, field: Field.Field, corridor: Field.Corridor)
	local realm = field.graph.realm
	local slope = realm.corridor.stairsSlope
	local rise = 2
	local run = rise / slope
	local biome = biomeOf(field, corridor.edge.a)
	local pts = corridor.points
	local rng = Hash.rng(corridor.edge.seed)
	for k = 1, #pts - 1 do
		local p, q = pts[k], pts[k + 1]
		local dx, dz = q.x - p.x, q.z - p.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-3 or math.abs(q.h - p.h) < 0.5 then
			continue
		end
		local yaw = math.atan2(-dx / len, -dz / len)
		local count = math.max(1, math.floor(len / run))
		for s = 0, count - 1 do
			local t = (s + 0.5) / count
			local h = p.h + (q.h - p.h) * t
			local stepTop = math.ceil(h / rise) * rise + 0.5
			table.insert(out, {
				kind = "Stair",
				x = p.x + dx * t,
				y = stepTop - 4,
				z = p.z + dz * t,
				yaw = yaw + math.rad(rng:range(-2, 2)),
				pitch = 0,
				roll = 0,
				sx = corridor.half * 2 - 2,
				sy = 8,
				sz = len / count + 0.6,
				material = biome.rock,
				color = shade(biome.rockColor, rng:range(1.02, 1.12)),
			})
		end
	end
end

-- Slabs over a tunnel: from the tunnel ceiling up to the ground it was cut through.
local function caveRoof(out: { PartSpec }, field: Field.Field, corridor: Field.Corridor, skip: number?)
	local realm = field.graph.realm
	local caveHeight = realm.corridor.caveHeight
	local biome = biomeOf(field, corridor.edge.a)
	local rng = Hash.rng(corridor.edge.seed + 7)
	local pts = corridor.points
	local spacingAlong = 14
	for k = 1, #pts - 1 do
		local p, q = pts[k], pts[k + 1]
		local dx, dz = q.x - p.x, q.z - p.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-3 then
			continue
		end
		local yaw = math.atan2(-dx / len, -dz / len)
		local count = math.max(1, math.ceil(len / spacingAlong))
		for s = 0, count - 1 do
			local t = (s + 0.5) / count
			local x, z = p.x + dx * t, p.z + dz * t
			if skip and field.owner(x, z) == skip then
				continue
			end
			local floor = p.h + (q.h - p.h) * t
			local ceiling = floor + caveHeight
			local ground = field.baseHeight(x, z)
			if ground - ceiling < 4 then
				continue
			end
			table.insert(out, {
				kind = "Roof",
				x = x,
				y = (ceiling + ground) / 2,
				z = z,
				yaw = yaw + math.rad(rng:range(-4, 4)),
				pitch = 0,
				roll = 0,
				sx = corridor.half * 2 + 12,
				sy = ground - ceiling,
				sz = len / count + 2,
				material = biome.rock,
				color = shade(biome.rockColor, rng:range(0.9, 1.0)),
			})
			table.insert(out, {
				kind = "Cap",
				x = x,
				y = ground + CAP / 2 - 0.4,
				z = z,
				yaw = out[#out].yaw,
				pitch = 0,
				roll = 0,
				sx = corridor.half * 2 + 12 + CAP_LIP * 2,
				sy = CAP,
				sz = len / count + 2,
				material = "Grass",
				color = biome.capColor,
			})
		end
	end
end

-- Slabs over a roofed pocket, matching the ground the pocket was cut out of.
local function pocketRoof(out: { PartSpec }, field: Field.Field, node: Graph.Node)
	local cell = 20
	local rng = Hash.rng(node.seed + 11)
	local reach = node.r * 1.6
	for gz = node.z - reach, node.z + reach, cell do
		for gx = node.x - reach, node.x + reach, cell do
			local x, z = gx + cell / 2, gz + cell / 2
			if field.owner(x, z) ~= node.index then
				continue
			end
			local ground = field.baseHeight(x, z, node.index)
			local ceiling = node.floor + ROOM
			if ground - ceiling < 4 then
				continue
			end
			local outer = field.owner(x, z, node.index)
			local biome = if outer ~= 0 then biomeOf(field, outer) else biomeOf(field, node.index)
			table.insert(out, {
				kind = "Roof",
				x = x,
				y = (ceiling + ground) / 2,
				z = z,
				yaw = math.rad(rng:range(-3, 3)),
				pitch = 0,
				roll = 0,
				sx = cell + 4,
				sy = ground - ceiling,
				sz = cell + 4,
				material = biome.rock,
				color = shade(biome.rockColor, rng:range(0.88, 1.0)),
			})
			table.insert(out, {
				kind = "Cap",
				x = x,
				y = ground + CAP / 2 - 0.4,
				z = z,
				yaw = out[#out].yaw,
				pitch = 0,
				roll = 0,
				sx = cell + 4 + CAP_LIP,
				sy = CAP,
				sz = cell + 4 + CAP_LIP,
				material = "Grass",
				color = biome.capColor,
			})
		end
	end
end

--[=[ Point halfway along a corridor's length. ]=]
function Cliffs.midpoint(corridor: Field.Corridor): (number, number)
	local pts = corridor.points
	local total = 0
	for k = 1, #pts - 1 do
		total += math.sqrt((pts[k + 1].x - pts[k].x) ^ 2 + (pts[k + 1].z - pts[k].z) ^ 2)
	end
	local half = total / 2
	for k = 1, #pts - 1 do
		local p, q = pts[k], pts[k + 1]
		local len = math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2)
		if half <= len and len > 0 then
			return p.x + (q.x - p.x) * half / len, p.z + (q.z - p.z) * half / len
		end
		half -= len
	end
	local last = pts[#pts]
	return last.x, last.z
end

--[=[
	Every part one zone builds. `grid` must cover the zone plus a margin of a few samples. A
	corridor's stairs and roof belong to the zone that owns the corridor's midpoint.
]=]
function Cliffs.build(field: Field.Field, grid: Grid.Grid, zone: number): { PartSpec }
	local out: { PartSpec } = {}
	local walks = walkways(field)
	cliffColumns(out, field, grid, zone, walks)
	outcrops(out, field, grid, zone, walks)
	for _, corridor in field.corridors do
		local mx, mz = Cliffs.midpoint(corridor)
		local a, b = field.owner(mx, mz)
		local owner = if a ~= 0 then a else b
		if owner ~= zone then
			continue
		end
		if corridor.kind == "stairs" then
			stairs(out, field, corridor)
		elseif corridor.kind == "cave" then
			local target = field.graph.nodes[corridor.edge.b]
			caveRoof(out, field, corridor, if target.roof then target.index else nil)
		end
	end
	local node = field.graph.nodes[zone]
	if node.roof then
		pocketRoof(out, field, node)
	end
	return out
end

return Cliffs
