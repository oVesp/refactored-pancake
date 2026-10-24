--!strict

-- Water (phase F5): the authored creek is carved along its spline with a water surface that only
-- falls downstream; the lake fills its basin to the water level. Flow accumulation comes from a
-- Priority-Flood (Barnes et al. 2014) whose pop order doubles as the drainage order.
local Grid = require("./Grid")
local Noise = require("./Noise")

local Water = {}

export type WaterMaps = {
	surface: Grid.Grid, -- water surface height per column, or NONE
	flow: Grid.Grid, -- share of all cells that drain through each column (0..1)
	creekSurface: (t: number) -> number,
}

Water.NONE = -1e6

--[=[ Water surface along the creek at arc length `t`, monotonic from source to lake. ]=]
local function creekProfile(cfg: any, maps: any, layout: any): (number) -> number
	local step = cfg.cell
	local samples: { number } = {}
	local creek = layout.creek
	local t = 0
	local k = 1
	local running = math.huge
	local count = math.floor(layout.creekLength / step) + 1
	for s = 0, count - 1 do
		local target = s * step
		while k < #creek - 1 do
			local a, b = creek[k], creek[k + 1]
			local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
			if target <= t + len then
				break
			end
			t += len
			k += 1
		end
		local a, b = creek[k], creek[k + 1]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local f = math.clamp((target - t) / len, 0, 1)
		local x, z = a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
		local fi = (x - cfg.originX) / cfg.cell - 0.5
		local fj = (z - cfg.originZ) / cfg.cell - 0.5
		local ground = Grid.sample(maps.height, fi, fj)
		running = math.min(running, ground - 1.5)
		samples[s + 1] = math.max(running, cfg.waterLevel)
	end
	-- The last stretch eases into the lake surface.
	local tail = math.min(#samples, 30)
	for s = #samples - tail + 1, #samples do
		local w = (s - (#samples - tail)) / tail
		samples[s] = Noise.lerp(samples[s], cfg.waterLevel, w)
	end
	return function(at: number): number
		local idx = math.clamp(at / step, 0, #samples - 1)
		local lo = math.floor(idx)
		local hi = math.min(lo + 1, #samples - 1)
		return Noise.lerp(samples[lo + 1], samples[hi + 1], idx - lo)
	end
end

function Water.carve(cfg: any, maps: any, layout: any): WaterMaps
	local n = cfg.n
	local w = cfg.water
	local surface = Grid.new(n, Water.NONE)
	local profile = creekProfile(cfg, maps, layout)
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local h = Grid.get(maps.height, i, j)
			local dc = Grid.get(maps.creekDistance, i, j)
			if dc < w.creekBank then
				local ws = profile(Grid.get(maps.creekT, i, j))
				if dc < w.creekWidth then
					local r = dc / w.creekWidth
					h = math.min(h, ws - w.creekDepth * (1 - r * r) - 0.5)
					Grid.set(surface, i, j, ws)
				else
					local s = Noise.smoothstep(w.creekWidth, w.creekBank, dc)
					h = math.min(h, Noise.lerp(ws + 0.6, h, s))
				end
			end
			local dl = Grid.get(maps.lakeDistance, i, j)
			if dl < 20 and h < cfg.waterLevel then
				Grid.set(surface, i, j, math.max(Grid.get(surface, i, j), cfg.waterLevel))
			end
			Grid.set(maps.height, i, j, h)
		end
	end
	return { surface = surface, flow = Water.flow(maps.height), creekSurface = profile }
end

--[=[
	Flow accumulation. Priority-Flood from the tile border fills depressions with a tiny epsilon
	gradient; every cell drains to the neighbour that flooded it, so reversing the pop order
	accumulates flow without a sort.
]=]
function Water.flow(height: Grid.Grid): Grid.Grid
	local n = height.n
	local total = n * n
	local filled = buffer.create(total * 4)
	local parent = buffer.create(total * 4)
	local closed = buffer.create(total)
	local order = buffer.create(total * 4)
	local heapH: { number } = {}
	local heapK: { number } = {}
	local size = 0

	local function push(h: number, k: number)
		size += 1
		local c = size
		heapH[c] = h
		heapK[c] = k
		while c > 1 do
			local p = c // 2
			if heapH[p] <= heapH[c] then
				break
			end
			heapH[p], heapH[c] = heapH[c], heapH[p]
			heapK[p], heapK[c] = heapK[c], heapK[p]
			c = p
		end
	end

	local function pop(): (number, number)
		local h, k = heapH[1], heapK[1]
		heapH[1], heapK[1] = heapH[size], heapK[size]
		heapH[size], heapK[size] = nil :: any, nil :: any
		size -= 1
		local c = 1
		while true do
			local l, r = c * 2, c * 2 + 1
			local m = c
			if l <= size and heapH[l] < heapH[m] then
				m = l
			end
			if r <= size and heapH[r] < heapH[m] then
				m = r
			end
			if m == c then
				break
			end
			heapH[m], heapH[c] = heapH[c], heapH[m]
			heapK[m], heapK[c] = heapK[c], heapK[m]
			c = m
		end
		return h, k
	end

	for j = 0, n - 1 do
		for i = 0, n - 1 do
			if i == 0 or j == 0 or i == n - 1 or j == n - 1 then
				local k = i + j * n
				local h = buffer.readf32(height.data, k * 4)
				buffer.writeu8(closed, k, 1)
				buffer.writef32(filled, k * 4, h)
				buffer.writei32(parent, k * 4, -1)
				push(h, k)
			end
		end
	end

	local popped = 0
	local offsets = { 1, -1, n, -n, n + 1, n - 1, -n + 1, -n - 1 }
	while size > 0 do
		local h, k = pop()
		buffer.writei32(order, popped * 4, k)
		popped += 1
		local i = k % n
		for _, o in offsets do
			local nk = k + o
			local ni = nk % n
			if nk >= 0 and nk < total and math.abs(ni - i) <= 1 and buffer.readu8(closed, nk) == 0 then
				buffer.writeu8(closed, nk, 1)
				local nh = math.max(buffer.readf32(height.data, nk * 4), h + 1e-3)
				buffer.writef32(filled, nk * 4, nh)
				buffer.writei32(parent, nk * 4, k)
				push(nh, nk)
			end
		end
	end

	-- Each cell drains to its steepest lower neighbour on the filled surface (D8); flats and
	-- filled pits fall back to the cell that flooded them.
	local acc = Grid.new(n, 1)
	local diag = math.sqrt(2)
	for p = popped - 1, 0, -1 do
		local k = buffer.readi32(order, p * 4)
		local i = k % n
		local h = buffer.readf32(filled, k * 4)
		local receiver = buffer.readi32(parent, k * 4)
		local best = 0
		for idx, o in offsets do
			local nk = k + o
			local ni = nk % n
			if nk >= 0 and nk < total and math.abs(ni - i) <= 1 then
				local drop = (h - buffer.readf32(filled, nk * 4)) / (if idx > 4 then diag else 1)
				if drop > best then
					best = drop
					receiver = nk
				end
			end
		end
		if receiver >= 0 then
			buffer.writef32(
				acc.data,
				receiver * 4,
				buffer.readf32(acc.data, receiver * 4) + buffer.readf32(acc.data, k * 4)
			)
		end
	end
	for k = 0, total - 1 do
		buffer.writef32(acc.data, k * 4, buffer.readf32(acc.data, k * 4) / total)
	end
	return acc
end

return Water
