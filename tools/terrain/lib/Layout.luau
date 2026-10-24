--!strict

-- Macro layout: the authored intent the generator fills in. Gameplay pads come from the greybox
-- (`src/Workspace/Map.rbxmx`, folder Ground), so the terrain always fits the current zones.
-- The lake and creek are authored shapes (vector primitives instead of painted masks).
local Noise = require("./Noise")

export type Rect = { name: string, cx: number, cz: number, hx: number, hz: number }
export type Point = { x: number, z: number }

export type Layout = {
	pads: { Rect }, -- flat ground at height 0 under the greybox slabs
	blockers: { Rect }, -- footprints of greybox props: no scatter
	lake: { cx: number, cz: number, radius: number },
	creek: { Point },
	padDistance: (x: number, z: number) -> number,
	blockerDistance: (x: number, z: number) -> number,
	creekDistance: (x: number, z: number) -> (number, number), -- distance, arc length at nearest point
	creekLength: number,
	lakeDistance: (x: number, z: number) -> number, -- signed: negative inside the shoreline
}

local Layout = {}

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

--[=[
	Builds the layout. `map` is the deserialized greybox Map model (or nil in tests, which pass
	their own pads).
]=]
function Layout.build(seed: number, map: any?, overridePads: { Rect }?): Layout
	local pads: { Rect } = overridePads or {}
	local blockers: { Rect } = {}
	if map then
		for _, part in map:FindFirstChild("Ground"):GetChildren() do
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

	local lake = { cx = 260, cz = 330, radius = 150 }
	local shore = Noise.fbm(Noise.layerSeed(seed, "lakeShore"), 180, 3, 2, 0.5)

	-- Creek from the north ridge down the west side, past the village to the lake. The control
	-- points are smoothed (Catmull-Rom) and meandered with noise that fades out at both ends.
	local control: { Point } = {
		{ x = -820, z = -1150 },
		{ x = -600, z = -820 },
		{ x = -420, z = -480 },
		{ x = -340, z = -150 },
		{ x = -320, z = 120 },
		{ x = -200, z = 260 },
		{ x = 0, z = 300 },
		{ x = 125, z = 320 },
	}
	local meander = Noise.fbm(Noise.layerSeed(seed, "creekMeander"), 260, 2, 2, 0.5)
	local creek: { Point } = {}
	for k = 1, #control - 1 do
		local p0 = control[math.max(k - 1, 1)]
		local p1, p2 = control[k], control[k + 1]
		local p3 = control[math.min(k + 2, #control)]
		local steps = 12
		for s = 0, steps - 1 do
			local t = s / steps
			local t2, t3 = t * t, t * t * t
			local function cr(a: number, b: number, c: number, d: number): number
				return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
			end
			table.insert(creek, { x = cr(p0.x, p1.x, p2.x, p3.x), z = cr(p0.z, p1.z, p2.z, p3.z) })
		end
	end
	table.insert(creek, control[#control])
	local raw = table.clone(creek)
	for k = 2, #creek - 1 do
		local a, b = raw[k - 1], raw[k + 1]
		local tx, tz = b.x - a.x, b.z - a.z
		local len = math.sqrt(tx * tx + tz * tz)
		local fade = math.min(k - 1, #creek - k, 12) / 12
		local off = meander(raw[k].x, raw[k].z) * 45 * fade
		creek[k] = { x = raw[k].x - tz / len * off, z = raw[k].z + tx / len * off }
	end
	local segStart: { number } = {}
	local total = 0
	for k = 1, #creek - 1 do
		segStart[k] = total
		local a, b = creek[k], creek[k + 1]
		total += math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	end

	local function creekDistance(x: number, z: number): (number, number)
		local best, bestT = math.huge, 0
		for k = 1, #creek - 1 do
			local a, b = creek[k], creek[k + 1]
			local abx, abz = b.x - a.x, b.z - a.z
			local len2 = abx * abx + abz * abz
			local t = math.clamp(((x - a.x) * abx + (z - a.z) * abz) / len2, 0, 1)
			local px, pz = a.x + abx * t, a.z + abz * t
			local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
			if d < best then
				best = d
				bestT = segStart[k] + t * math.sqrt(len2)
			end
		end
		return best, bestT
	end

	local function lakeDistance(x: number, z: number): number
		local dx, dz = x - lake.cx, z - lake.cz
		local r = lake.radius + shore(x, z) * 35
		return math.sqrt(dx * dx + dz * dz) - r
	end

	return {
		pads = pads,
		blockers = blockers,
		lake = lake,
		creek = creek,
		padDistance = function(x: number, z: number): number
			return nearest(pads, x, z)
		end,
		blockerDistance = function(x: number, z: number): number
			return nearest(blockers, x, z)
		end,
		creekDistance = creekDistance,
		creekLength = total,
		lakeDistance = lakeDistance,
	}
end

return Layout
