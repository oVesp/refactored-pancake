--!strict

-- Features (phase F6): flat sites for future points of interest, scored by flatness and view,
-- and trails found with A* on a slope-penalised grid, smoothed, then cut into the terrain.
local Grid = require("./Grid")
local Noise = require("./Noise")

local Paths = {}

export type Poi = { name: string, x: number, z: number, y: number }
export type Trail = { name: string, points: { { number } } } -- {x, z, y}

local function toCell(cfg: any, x: number, z: number): (number, number)
	return math.floor((x - cfg.originX) / cfg.cell), math.floor((z - cfg.originZ) / cfg.cell)
end

local function toWorld(cfg: any, i: number, j: number): (number, number)
	return cfg.originX + (i + 0.5) * cfg.cell, cfg.originZ + (j + 0.5) * cfg.cell
end

local function isWet(maps: any, water: any, i: number, j: number): boolean
	return Grid.get(water.surface, i, j) > Grid.get(maps.height, i, j)
end

--[=[ Picks the flattest high site on each side of the valley and levels it. ]=]
function Paths.pickPois(cfg: any, maps: any, water: any): { Poi }
	local n = cfg.n
	local r = math.ceil(cfg.paths.poiRadius / cfg.cell)
	local best: { [string]: { score: number, i: number, j: number } } = {}
	for j = r + 2, n - r - 3, 4 do
		for i = r + 2, n - r - 3, 4 do
			local x, z = toWorld(cfg, i, j)
			local h = Grid.get(maps.height, i, j)
			local ok = Grid.get(maps.padDistance, i, j) > 250
				and Grid.get(maps.lakeDistance, i, j) > 60
				and Grid.get(maps.creekDistance, i, j) > 60
				and h > 25
				and h < 170
				and z > -1000
				and math.min(i, j, n - 1 - i, n - 1 - j) * cfg.cell > 280
			if ok then
				local lo, hi = math.huge, -math.huge
				for dj = -r, r, 2 do
					for di = -r, r, 2 do
						local v = Grid.get(maps.height, i + di, j + dj)
						lo = math.min(lo, v)
						hi = math.max(hi, v)
					end
				end
				local score = -(hi - lo) * 2 + h * 0.08
				local side = if x < -300 then "West" elseif x > 300 then "East" else nil
				if side and (best[side] == nil or score > best[side].score) then
					best[side] = { score = score, i = i, j = j }
				end
			end
		end
	end

	local pois: { Poi } = {}
	for _, side in { "West", "East" } do
		local b = best[side]
		if b then
			local x, z = toWorld(cfg, b.i, b.j)
			local heights = {}
			for dj = -r, r do
				for di = -r, r do
					table.insert(heights, Grid.get(maps.height, b.i + di, b.j + dj))
				end
			end
			table.sort(heights)
			local y = heights[#heights // 2 + 1]
			local outer = r + 4
			for dj = -outer, outer do
				for di = -outer, outer do
					local d = math.sqrt(di * di + dj * dj) * cfg.cell
					local w = Noise.smoothstep(cfg.paths.poiRadius + 16, cfg.paths.poiRadius, d)
					if w > 0 and not isWet(maps, water, b.i + di, b.j + dj) then
						local h = Grid.get(maps.height, b.i + di, b.j + dj)
						Grid.set(maps.height, b.i + di, b.j + dj, Noise.lerp(h, y, w))
					end
				end
			end
			table.insert(pois, { name = `Lookout{side}`, x = x, z = z, y = y })
		end
	end
	return pois
end

--[=[ A* over columns. Steep steps cost more and steps above the grade limit are near-forbidden. ]=]
function Paths.findPath(
	cfg: any,
	maps: any,
	water: any,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): { { number } }
	local n = cfg.n
	local p = cfg.paths
	local si, sj = toCell(cfg, fromX, fromZ)
	local gi, gj = toCell(cfg, toX, toZ)
	local start = si + sj * n
	local goal = gi + gj * n
	local maxGrade = math.tan(math.rad(p.maxGradeDeg))
	local gScore: { [number]: number } = { [start] = 0 }
	local came: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	local heapF: { number } = {}
	local heapK: { number } = {}
	local size = 0

	local function push(f: number, k: number)
		size += 1
		local c = size
		heapF[c], heapK[c] = f, k
		while c > 1 do
			local q = c // 2
			if heapF[q] <= heapF[c] then
				break
			end
			heapF[q], heapF[c] = heapF[c], heapF[q]
			heapK[q], heapK[c] = heapK[c], heapK[q]
			c = q
		end
	end
	local function pop(): number
		local k = heapK[1]
		heapF[1], heapK[1] = heapF[size], heapK[size]
		heapF[size], heapK[size] = nil :: any, nil :: any
		size -= 1
		local c = 1
		while true do
			local l, r = c * 2, c * 2 + 1
			local m = c
			if l <= size and heapF[l] < heapF[m] then
				m = l
			end
			if r <= size and heapF[r] < heapF[m] then
				m = r
			end
			if m == c then
				break
			end
			heapF[m], heapF[c] = heapF[c], heapF[m]
			heapK[m], heapK[c] = heapK[c], heapK[m]
			c = m
		end
		return k
	end

	local function heuristic(k: number): number
		local i, j = k % n, k // n
		return math.sqrt((i - gi) ^ 2 + (j - gj) ^ 2) * cfg.cell
	end

	push(heuristic(start), start)
	local moves = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
	while size > 0 do
		local k = pop()
		if k == goal then
			break
		end
		if not closed[k] then
			closed[k] = true
			local i, j = k % n, k // n
			local h = Grid.get(maps.height, i, j)
			for _, m in moves do
				local ni, nj = i + m[1], j + m[2]
				if ni > 0 and nj > 0 and ni < n - 1 and nj < n - 1 then
					local nk = ni + nj * n
					if not closed[nk] then
						local len = math.sqrt(m[1] * m[1] + m[2] * m[2]) * cfg.cell
						local grade = math.abs(Grid.get(maps.height, ni, nj) - h) / len
						local cost = len * (1 + p.slopeCost * grade * grade)
						if grade > maxGrade then
							cost *= 50
						end
						if isWet(maps, water, ni, nj) then
							cost += p.waterCost
						end
						if Grid.get(maps.padDistance, ni, nj) <= 0 then
							cost *= 3
						end
						local g = gScore[k] + cost
						if gScore[nk] == nil or g < gScore[nk] then
							gScore[nk] = g
							came[nk] = k
							push(g + heuristic(nk), nk)
						end
					end
				end
			end
		end
	end
	assert(came[goal], "trail has no route")

	local cells: { number } = {}
	local k = goal
	while k do
		table.insert(cells, 1, k)
		k = came[k]
	end
	local pts: { { number } } = {}
	for idx = 1, #cells, 3 do
		local x, z = toWorld(cfg, cells[idx] % n, cells[idx] // n)
		table.insert(pts, { x, z })
	end
	local lx, lz = toWorld(cfg, gi, gj)
	table.insert(pts, { lx, lz })
	-- Chaikin corner cutting, endpoints kept.
	for _ = 1, 2 do
		local out = { pts[1] }
		for idx = 1, #pts - 1 do
			local a, b = pts[idx], pts[idx + 1]
			table.insert(out, { a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25 })
			table.insert(out, { a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75 })
		end
		table.insert(out, pts[#pts])
		pts = out
	end
	return pts
end

--[=[ Cuts a trail into the terrain along smoothed heights and marks its cells in `mask`. ]=]
function Paths.carve(cfg: any, maps: any, water: any, pts: { { number } }, mask: Grid.Grid): { { number } }
	local n = cfg.n
	local p = cfg.paths
	local raw: { number } = {}
	for idx, pt in pts do
		local fi = (pt[1] - cfg.originX) / cfg.cell - 0.5
		local fj = (pt[2] - cfg.originZ) / cfg.cell - 0.5
		raw[idx] = Grid.sample(maps.height, fi, fj)
	end
	local trail: { { number } } = {}
	for idx, pt in pts do
		local sum, count = 0, 0
		for o = -3, 3 do
			local v = raw[math.clamp(idx + o, 1, #raw)]
			sum += v
			count += 1
		end
		trail[idx] = { pt[1], pt[2], sum / count }
	end

	local reach = p.halfWidth + p.feather
	local best = Grid.new(n, math.huge)
	local target = Grid.new(n)
	for idx = 1, #trail - 1 do
		local a, b = trail[idx], trail[idx + 1]
		local i0, j0 = toCell(cfg, math.min(a[1], b[1]) - reach, math.min(a[2], b[2]) - reach)
		local i1, j1 = toCell(cfg, math.max(a[1], b[1]) + reach, math.max(a[2], b[2]) + reach)
		local abx, abz = b[1] - a[1], b[2] - a[2]
		local len2 = math.max(abx * abx + abz * abz, 1e-6)
		for j = math.max(j0, 0), math.min(j1, n - 1) do
			for i = math.max(i0, 0), math.min(i1, n - 1) do
				local x, z = toWorld(cfg, i, j)
				local t = math.clamp(((x - a[1]) * abx + (z - a[2]) * abz) / len2, 0, 1)
				local d = math.sqrt((x - a[1] - abx * t) ^ 2 + (z - a[2] - abz * t) ^ 2)
				if d < Grid.get(best, i, j) then
					Grid.set(best, i, j, d)
					Grid.set(target, i, j, Noise.lerp(a[3], b[3], t))
				end
			end
		end
	end
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local d = Grid.get(best, i, j)
			if d < reach and not isWet(maps, water, i, j) and Grid.get(maps.padDistance, i, j) > 2 then
				local w = Noise.smoothstep(reach, p.halfWidth, d)
				Grid.set(maps.height, i, j, Noise.lerp(Grid.get(maps.height, i, j), Grid.get(target, i, j), w))
			end
			if d < p.halfWidth + 1 then
				Grid.set(mask, i, j, 1)
			end
		end
	end
	return trail
end

--[=[ Nearest dry column whose lake distance falls in [lo, hi], closest to (x, z). ]=]
function Paths.shorePoint(cfg: any, maps: any, x: number, z: number, lo: number, hi: number): (number, number)
	local bestD, bx, bz = math.huge, x, z
	for j = 0, cfg.n - 1, 2 do
		for i = 0, cfg.n - 1, 2 do
			local dl = Grid.get(maps.lakeDistance, i, j)
			if dl >= lo and dl <= hi then
				local wx, wz = toWorld(cfg, i, j)
				local d = (wx - x) ^ 2 + (wz - z) ^ 2
				if d < bestD then
					bestD, bx, bz = d, wx, wz
				end
			end
		end
	end
	return bx, bz
end

return Paths
