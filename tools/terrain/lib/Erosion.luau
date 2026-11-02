--!strict

-- Erosion (phase F3): droplet hydraulic erosion after Beyer (2015) as implemented by Sebastian
-- Lague, then thermal talus passes. Runs on a normalized copy so the published droplet constants
-- keep their meaning. `mask` (0..1) scales erosion; 0 protects pads, lake and creek.
local Grid = require("./Grid")
local Noise = require("./Noise")

local Erosion = {}

export type Result = { wear: Grid.Grid, deposit: Grid.Grid }

local function heightAndGradient(map: buffer, n: number, px: number, pz: number): (number, number, number)
	local cx = math.floor(px)
	local cz = math.floor(pz)
	local u = px - cx
	local v = pz - cz
	local k = (cx + cz * n) * 4
	local nw = buffer.readf32(map, k)
	local ne = buffer.readf32(map, k + 4)
	local sw = buffer.readf32(map, k + n * 4)
	local se = buffer.readf32(map, k + n * 4 + 4)
	local gx = (ne - nw) * (1 - v) + (se - sw) * v
	local gz = (sw - nw) * (1 - u) + (se - ne) * u
	local h = nw * (1 - u) * (1 - v) + ne * u * (1 - v) + sw * (1 - u) * v + se * u * v
	return h, gx, gz
end

function Erosion.hydraulic(cfg: any, height: Grid.Grid, mask: Grid.Grid): Result
	local e = cfg.erosion
	local n = height.n
	local scale = e.heightScale
	local map = buffer.create(n * n * 4)
	local original = Grid.copy(height)
	-- Droplets never dig below zero, so heights are shifted to start at zero (the sea floor and
	-- lake beds are negative).
	local lo = Grid.range(height)
	for k = 0, n * n - 1 do
		buffer.writef32(map, k * 4, (buffer.readf32(height.data, k * 4) - lo) / scale)
	end

	local brush: { { number } } = {}
	local weightSum = 0
	for dz = -e.radius, e.radius do
		for dx = -e.radius, e.radius do
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= e.radius then
				local w = 1 - d / e.radius
				weightSum += w
				table.insert(brush, { dx, dz, w })
			end
		end
	end
	for _, b in brush do
		b[3] /= weightSum
	end

	local rand = Noise.rng(Noise.layerSeed(cfg.seed, "erosion"))
	local droplets = math.floor(n * n * e.dropletsPerCell)
	local maskData = mask.data
	for _ = 1, droplets do
		local px = rand() * (n - 2)
		local pz = rand() * (n - 2)
		local dirX, dirZ, speed, water, sediment = 0, 0, 1, 1, 0
		for _ = 1, e.lifetime do
			local cx = math.floor(px)
			local cz = math.floor(pz)
			local u = px - cx
			local v = pz - cz
			local h, gx, gz = heightAndGradient(map, n, px, pz)
			dirX = dirX * e.inertia - gx * (1 - e.inertia)
			dirZ = dirZ * e.inertia - gz * (1 - e.inertia)
			local len = math.sqrt(dirX * dirX + dirZ * dirZ)
			if len < 1e-9 then
				break
			end
			dirX /= len
			dirZ /= len
			px += dirX
			pz += dirZ
			if px < 0 or pz < 0 or px >= n - 2 or pz >= n - 2 then
				break
			end
			local newH = heightAndGradient(map, n, px, pz)
			local dh = newH - h
			local capacity = math.max(-dh * speed * water * e.capacity, e.minSlope)
			local k = (cx + cz * n) * 4
			if sediment > capacity or dh > 0 then
				local amount = if dh > 0 then math.min(dh, sediment) else (sediment - capacity) * e.depositSpeed
				sediment -= amount
				buffer.writef32(map, k, buffer.readf32(map, k) + amount * (1 - u) * (1 - v))
				buffer.writef32(map, k + 4, buffer.readf32(map, k + 4) + amount * u * (1 - v))
				buffer.writef32(map, k + n * 4, buffer.readf32(map, k + n * 4) + amount * (1 - u) * v)
				buffer.writef32(map, k + n * 4 + 4, buffer.readf32(map, k + n * 4 + 4) + amount * u * v)
			else
				local m = buffer.readf32(maskData, k)
				local amount = math.min((capacity - sediment) * e.erodeSpeed, -dh) * m
				if amount > 0 then
					for _, b in brush do
						local bx, bz = cx + b[1], cz + b[2]
						if bx >= 0 and bz >= 0 and bx < n and bz < n then
							local bk = (bx + bz * n) * 4
							local cur = buffer.readf32(map, bk)
							local take = math.min(cur, amount * b[3])
							buffer.writef32(map, bk, cur - take)
							sediment += take
						end
					end
				end
			end
			speed = math.sqrt(math.max(0, speed * speed + dh * e.gravity))
			water *= 1 - e.evaporate
		end
	end

	local wear = Grid.new(n)
	local deposit = Grid.new(n)
	for k = 0, n * n - 1 do
		local before = buffer.readf32(original.data, k * 4)
		local after = buffer.readf32(map, k * 4) * scale + lo
		if before > e.baseLevel then
			after = math.max(after, e.baseLevel)
		end
		-- Protected cells keep their exact shape, including deposits from neighbouring droplets.
		local m = buffer.readf32(maskData, k * 4)
		after = before + (after - before) * m
		buffer.writef32(height.data, k * 4, after)
		local delta = after - before
		buffer.writef32(wear.data, k * 4, math.max(-delta, 0))
		buffer.writef32(deposit.data, k * 4, math.max(delta, 0))
	end
	return { wear = wear, deposit = deposit }
end

--[=[ Moves material downhill wherever the slope to a neighbour exceeds the talus angle. ]=]
function Erosion.thermal(cfg: any, height: Grid.Grid, mask: Grid.Grid)
	local e = cfg.erosion
	local n = height.n
	local talus = math.tan(math.rad(e.talusDeg)) * cfg.cell
	local data = height.data
	local neighbours = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for _ = 1, e.thermalPasses do
		for j = 1, n - 2 do
			for i = 1, n - 2 do
				local k = (i + j * n) * 4
				local m = buffer.readf32(mask.data, k)
				if m > 0 then
					local h = buffer.readf32(data, k)
					local bestD, bestK = 0, -1
					for _, o in neighbours do
						local nk = ((i + o[1]) + (j + o[2]) * n) * 4
						local d = h - buffer.readf32(data, nk)
						if d > bestD then
							bestD = d
							bestK = nk
						end
					end
					if bestK >= 0 and bestD > talus then
						local move = (bestD - talus) * 0.25 * m
						buffer.writef32(data, k, h - move)
						buffer.writef32(data, bestK, buffer.readf32(data, bestK) + move)
					end
				end
			end
		end
	end
end

return Erosion
