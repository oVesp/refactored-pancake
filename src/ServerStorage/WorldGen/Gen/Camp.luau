--!strict

--[=[
	Goblin camp layout (docs/systems/world-generation.md, region builds): a palisade ring with a
	gate between two towers, tents on an inner ring opening to the centre, the fire brazier, the
	chieftain's dais opposite the gate, and crates and a wagon by the tents.

	Pure data out. Assets are village-kit models (`content/world/village.json`, metres, front -Z),
	already scaled in `ServerStorage.VillageKit`, so every placement has scale 1.
]=]
local Hash = require(script.Parent.Hash)

export type PropSpec = { asset: string, x: number, y: number, z: number, yaw: number, scale: number }

export type Site = { x: number, z: number, y: number, gate: number, seed: number }

export type Config = {
	radius: number,
	gateWidth: number,
	tents: number,
	tentRing: number,
	clutter: { [string]: number },
}

local Camp = {}

local TAU = math.pi * 2

-- Radius of an asset's footprint on the ground, in studs.
local function reach(manifest: any, scale: number, asset: string): number
	local meta = manifest.assets[asset]
	assert(meta, `village kit has no asset {asset}`)
	return math.max(meta.max[1] - meta.min[1], meta.max[3] - meta.min[3]) / 2 * scale
end

local function kitNames(manifest: any, prefix: string): { string }
	local names = {}
	for name in manifest.assets do
		if string.match(name, "^" .. prefix .. "%d+$") then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

--[=[
	Lays out one camp. `site.gate` is the gate's direction in radians from +Z; `scale` is studs per
	kit metre.
]=]
function Camp.layout(manifest: any, scale: number, site: Site, config: Config): { PropSpec }
	local rng = Hash.rng(site.seed)
	local out: { PropSpec } = {}
	local taken: { { number } } = {} -- { x, z, r } of tents, fixtures and clutter

	local function put(asset: string, x: number, z: number, yaw: number)
		table.insert(out, { asset = asset, x = x, y = site.y, z = z, yaw = yaw, scale = 1 })
	end
	local function free(x: number, z: number, r: number): boolean
		for _, t in taken do
			if (t[1] - x) ^ 2 + (t[2] - z) ^ 2 < (t[3] + r) ^ 2 then
				return false
			end
		end
		return true
	end
	local function at(angle: number, r: number): (number, number)
		return site.x + math.sin(angle) * r, site.z + math.cos(angle) * r
	end

	-- Palisade ring; the gate gap faces `site.gate`.
	local segment = (manifest.assets.Palisade1.length or 4) * scale
	local count = math.floor(TAU * config.radius / segment)
	local step = TAU / count
	local walls = kitNames(manifest, "Palisade")
	for i = 0, count - 1 do
		if i < config.gateWidth / 2 or i >= count - config.gateWidth / 2 then
			continue
		end
		local a = site.gate + (i + 0.5) * step
		local x, z = at(a, config.radius)
		put(walls[rng:int(1, #walls)], x, z, a)
	end
	for _, side in { -1, 1 } do
		local a = site.gate + side * (config.gateWidth / 2) * step
		local x, z = at(a, config.radius)
		put("GateTower", x, z, a)
	end

	-- Fire in the middle, the dais at the back.
	put("Brazier", site.x, site.z, 0)
	table.insert(taken, { site.x, site.z, reach(manifest, scale, "Brazier") + 10 })
	local dx, dz = at(site.gate + math.pi, config.radius - 22)
	put("Dais", dx, dz, site.gate)
	table.insert(taken, { dx, dz, reach(manifest, scale, "Dais") })
	-- Keep the way from the gate to the fire open.
	for r = 10, config.radius, 10 do
		local x, z = at(site.gate, r)
		table.insert(taken, { x, z, 8 })
	end

	local tents = kitNames(manifest, "Tent")
	local placed = 0
	for _ = 1, 80 do
		if placed >= config.tents then
			break
		end
		local a = rng:range(0, TAU)
		local r = config.tentRing + rng:range(-8, 8)
		local name = tents[rng:int(1, #tents)]
		local size = reach(manifest, scale, name)
		local x, z = at(a, r)
		if free(x, z, size + 3) then
			-- Kit fronts face -Z, so yaw `a` turns the opening toward the centre.
			put(name, x, z, a)
			table.insert(taken, { x, z, size })
			placed += 1
		end
	end

	local names = {}
	for name in config.clutter do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local size = reach(manifest, scale, name)
		local done = 0
		for _ = 1, 60 do
			if done >= config.clutter[name] then
				break
			end
			local a = rng:range(0, TAU)
			local r = rng:range(16, config.radius - 12)
			local x, z = at(a, r)
			if free(x, z, size + 1) then
				put(name, x, z, rng:range(0, TAU))
				table.insert(taken, { x, z, size })
				done += 1
			end
		end
	end
	return out
end

return Camp
