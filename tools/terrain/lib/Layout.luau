--!strict

-- Macro layout: the authored intent the generator fills in. Gameplay pads come from the Map zones
-- (`src/Workspace/Map.rbxmx`, folder Zones), so the terrain always fits the current areas.
-- Lakes, rivers, roads and the world regions are authored shapes (vector primitives instead of
-- painted masks).
local Noise = require("./Noise")

export type Rect = { name: string, cx: number, cz: number, hx: number, hz: number }
export type Point = { x: number, z: number }
export type River = {
	name: string,
	width: number, -- half-width of the wet channel
	depth: number,
	bank: number, -- half-width of the carved valley around the channel
	points: { Point },
	segStart: { number },
	length: number,
}
export type Regions = {
	mountain: number,
	highland: number,
	swamp: number,
	plains: number,
	coast: number,
}

export type Layout = {
	pads: { Rect }, -- flat gameplay ground (the Map zones), terrain held at padHeight
	blockers: { Rect }, -- footprints of Map props: no scatter
	lake: { cx: number, cz: number, radius: number },
	rivers: { River },
	padDistance: (x: number, z: number) -> number,
	padAt: (x: number, z: number) -> string?, -- name of the pad containing the point
	roadDistance: (x: number, z: number) -> number,
	blockerDistance: (x: number, z: number) -> number,
	-- Distance to the nearest river centreline, arc length along it, and its index. Points farther
	-- than RIVER_REACH return RIVER_REACH.
	riverDistance: (x: number, z: number) -> (number, number, number),
	lakeDistance: (x: number, z: number) -> number, -- signed: negative inside the shoreline
	regions: (x: number, z: number) -> Regions, -- region weights 0..1 (see Config.world)
}

local Layout = {}

local RIVER_REACH = 2000
local BUCKET = 256

local function rectDistance(r: Rect, x: number, z: number): number
	local dx = math.max(math.abs(x - r.cx) - r.hx, 0)
	local dz = math.max(math.abs(z - r.cz) - r.hz, 0)
	return math.sqrt(dx * dx + dz * dz)
end

local function nearest(rects: { Rect }, x: number, z: number): number
	local best = math.huge
	for _, r in rects do
		best = math.min(best, rectDistance(r, x, z))
	end
	return best
end

local function segmentDistance(x: number, z: number, ax: number, az: number, bx: number, bz: number): number
	local abx, abz = bx - ax, bz - az
	local len2 = math.max(abx * abx + abz * abz, 1e-6)
	local t = math.clamp(((x - ax) * abx + (z - az) * abz) / len2, 0, 1)
	return math.sqrt((x - ax - abx * t) ^ 2 + (z - az - abz * t) ^ 2)
end

--[=[
	Smooths control points with Catmull-Rom (about one point per 20 studs) and meanders them with
	noise that fades out at both ends.
]=]
local function spline(seed: number, name: string, control: { Point }, meanderStuds: number): { Point }
	local pts: { Point } = {}
	for k = 1, #control - 1 do
		local p0 = control[math.max(k - 1, 1)]
		local p1, p2 = control[k], control[k + 1]
		local p3 = control[math.min(k + 2, #control)]
		local steps = math.max(12, math.ceil(math.sqrt((p2.x - p1.x) ^ 2 + (p2.z - p1.z) ^ 2) / 20))
		for s = 0, steps - 1 do
			local t = s / steps
			local t2, t3 = t * t, t * t * t
			local function cr(a: number, b: number, c: number, d: number): number
				return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
			end
			table.insert(pts, { x = cr(p0.x, p1.x, p2.x, p3.x), z = cr(p0.z, p1.z, p2.z, p3.z) })
		end
	end
	table.insert(pts, control[#control])
	local meander = Noise.fbm(Noise.layerSeed(seed, name .. "Meander"), 260, 2, 2, 0.5)
	local raw = table.clone(pts)
	for k = 2, #pts - 1 do
		local a, b = raw[k - 1], raw[k + 1]
		local tx, tz = b.x - a.x, b.z - a.z
		local len = math.sqrt(tx * tx + tz * tz)
		local fade = math.min(k - 1, #pts - k, 12) / 12
		local off = meander(raw[k].x, raw[k].z) * meanderStuds * fade
		pts[k] = { x = raw[k].x - tz / len * off, z = raw[k].z + tx / len * off }
	end
	return pts
end

--[=[
	Builds the layout from Config. `map` is the deserialized Map model (or nil in tests, which
	pass their own pads).
]=]
function Layout.build(cfg: any, map: any?, overridePads: { Rect }?): Layout
	local seed = cfg.seed
	local pads: { Rect } = overridePads or {}
	local blockers: { Rect } = {}
	if map then
		for _, part in map:FindFirstChild("Zones"):GetChildren() do
			local p = part.CFrame.Position
			table.insert(pads, { name = part.Name, cx = p.X, cz = p.Z, hx = part.Size.X / 2, hz = part.Size.Z / 2 })
		end
		for _, folderName in { "Props", "Npcs", "Spawners" } do
			for _, d in map:FindFirstChild(folderName):GetDescendants() do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					-- Axis-aligned bound of the rotated footprint, generous enough for fences and walls.
					local h = math.max(d.Size.X, d.Size.Z) / 2
					table.insert(blockers, { name = d.Name, cx = p.X, cz = p.Z, hx = h, hz = h })
				end
			end
		end
	end

	local lake = cfg.water.lake
	local shore = Noise.fbm(Noise.layerSeed(seed, "lakeShore"), 180, 3, 2, 0.5)

	local rivers: { River } = {}
	local buckets: { [number]: { { number } } } = {} -- river index, segment index
	local function bucketKey(bx: number, bz: number): number
		return (bx + 500) * 1000 + (bz + 500)
	end
	for r, def in cfg.water.rivers do
		local control: { Point } = {}
		for _, p in def.points do
			table.insert(control, { x = p[1], z = p[2] })
		end
		-- The first river keeps the original layer name so its meander does not change.
		local pts = spline(seed, if r == 1 then "creek" else def.name, control, def.meander)
		local segStart: { number } = {}
		local total = 0
		for k = 1, #pts - 1 do
			segStart[k] = total
			local a, b = pts[k], pts[k + 1]
			total += math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
			local bx0, bx1 = math.min(a.x, b.x) // BUCKET, math.max(a.x, b.x) // BUCKET
			local bz0, bz1 = math.min(a.z, b.z) // BUCKET, math.max(a.z, b.z) // BUCKET
			for bz = bz0, bz1 do
				for bx = bx0, bx1 do
					local key = bucketKey(bx, bz)
					local list = buckets[key]
					if not list then
						list = {}
						buckets[key] = list
					end
					table.insert(list, { r, k })
				end
			end
		end
		table.insert(rivers, {
			name = def.name,
			width = def.width,
			depth = def.depth,
			bank = def.bank,
			points = pts,
			segStart = segStart,
			length = total,
		})
	end

	local reachBuckets = math.ceil(RIVER_REACH / BUCKET)
	local function riverDistance(x: number, z: number): (number, number, number)
		local best, bestT, bestR = RIVER_REACH, 0, 1
		local cx, cz = x // BUCKET, z // BUCKET
		-- Search rings outward; stop once the ring is farther than the best hit.
		for ring = 0, reachBuckets do
			if (ring - 1) * BUCKET > best then
				break
			end
			for bz = cz - ring, cz + ring do
				for bx = cx - ring, cx + ring do
					if math.max(math.abs(bx - cx), math.abs(bz - cz)) == ring then
						local list = buckets[bucketKey(bx, bz)]
						if list then
							for _, ref in list do
								local river = rivers[ref[1]]
								local k = ref[2]
								local a, b = river.points[k], river.points[k + 1]
								local abx, abz = b.x - a.x, b.z - a.z
								local len2 = math.max(abx * abx + abz * abz, 1e-6)
								local t = math.clamp(((x - a.x) * abx + (z - a.z) * abz) / len2, 0, 1)
								local d = math.sqrt((x - a.x - abx * t) ^ 2 + (z - a.z - abz * t) ^ 2)
								if d < best then
									best = d
									bestT = river.segStart[k] + t * math.sqrt(len2)
									bestR = ref[1]
								end
							end
						end
					end
				end
			end
		end
		return best, bestT, bestR
	end

	local function lakeDistance(x: number, z: number): number
		local dx, dz = x - lake.cx, z - lake.cz
		local r = lake.radius + shore(x, z) * 35
		return math.sqrt(dx * dx + dz * dz) - r
	end

	local w = cfg.world
	local warpX = Noise.fbm(Noise.layerSeed(seed, "regionWarpX"), w.warpWavelength, 3, 2, 0.5)
	local warpZ = Noise.fbm(Noise.layerSeed(seed, "regionWarpZ"), w.warpWavelength, 3, 2, 0.5)
	local function regions(x: number, z: number): Regions
		local wx = x + warpX(x, z) * w.warpStrength
		local wz = z + warpZ(x, z) * w.warpStrength
		local mountain = Noise.smoothstep(w.mountains.fromZ, w.mountains.toZ, wz)
		local coast = Noise.smoothstep(w.coast.fromZ, w.coast.toZ, wz)
		local open = (1 - mountain) * (1 - coast)
		local highland = Noise.smoothstep(w.highlands.fromZ, w.highlands.toZ, wz) * (1 - mountain)
		local lowland = open * (1 - highland)
		return {
			mountain = mountain,
			highland = highland,
			swamp = Noise.smoothstep(w.swamp.fromX, w.swamp.toX, wx) * lowland,
			plains = Noise.smoothstep(w.plains.fromX, w.plains.toX, wx) * lowland,
			coast = coast,
		}
	end

	return {
		pads = pads,
		blockers = blockers,
		lake = lake,
		rivers = rivers,
		padDistance = function(x: number, z: number): number
			return nearest(pads, x, z)
		end,
		padAt = function(x: number, z: number): string?
			for _, r in pads do
				if math.abs(x - r.cx) <= r.hx and math.abs(z - r.cz) <= r.hz then
					return r.name
				end
			end
			return nil
		end,
		roadDistance = function(x: number, z: number): number
			local best = math.huge
			for _, r in cfg.roads do
				best = math.min(best, segmentDistance(x, z, r[1], r[2], r[3], r[4]))
			end
			return best
		end,
		blockerDistance = function(x: number, z: number): number
			return nearest(blockers, x, z)
		end,
		riverDistance = riverDistance,
		lakeDistance = lakeDistance,
		regions = regions,
	}
end

return Layout
