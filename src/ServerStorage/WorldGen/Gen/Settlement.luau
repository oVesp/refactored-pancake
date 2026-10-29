--!strict

--[=[
	Settlement layout on the pads (docs/systems/world-generation.md): the village (houses and barns
	facing roads and the plaza, fixtures, perimeter fence, clutter), the farmland (crops in rows
	on the terraced plots, scarecrows, stone borders, fences), the orchard (fruit-tree grid) and the
	goblin camp (palisade ring with a gate, tents, fixtures, clutter).

	Pure data out (`Props.PropSpec`), seeded per site. Village-kit assets come from the manifest
	(`content/world/village.json`, metres) and are placed at `settlements.scale`; crops from the
	prop library. Everything keeps `clear` studs from the anchors (the Map's NPCs, spawners and
	dummies) and never overlaps another footprint.
]=]
local Field = require(script.Parent.Field)
local Hash = require(script.Parent.Hash)
local Props = require(script.Parent.Props)

export type Anchor = { x: number, z: number, r: number }

-- Oriented footprint on the ground plane.
export type Box = { x: number, z: number, hx: number, hz: number, yaw: number, wall: boolean? }

local Settlement = {}

local TAU = math.pi * 2

local function axes(yaw: number): (number, number, number, number)
	-- Local +X and +Z of `CFrame.Angles(0, yaw, 0)` on the ground plane.
	return math.cos(yaw), -math.sin(yaw), math.sin(yaw), math.cos(yaw)
end

local function corners(b: Box): { { number } }
	local ux, uz, vx, vz = axes(b.yaw)
	local out = {}
	for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		table.insert(out, { b.x + ux * b.hx * s[1] + vx * b.hz * s[2], b.z + uz * b.hx * s[1] + vz * b.hz * s[2] })
	end
	return out
end

-- Separating-axis test with `gap` studs of required clearance.
local function overlaps(a: Box, b: Box, gap: number): boolean
	local ca, cb = corners(a), corners(b)
	for _, box in { a, b } do
		local ux, uz, vx, vz = axes(box.yaw)
		for _, axis in { { ux, uz }, { vx, vz } } do
			local minA, maxA, minB, maxB = math.huge, -math.huge, math.huge, -math.huge
			for _, c in ca do
				local p = c[1] * axis[1] + c[2] * axis[2]
				minA, maxA = math.min(minA, p), math.max(maxA, p)
			end
			for _, c in cb do
				local p = c[1] * axis[1] + c[2] * axis[2]
				minB, maxB = math.min(minB, p), math.max(maxB, p)
			end
			if maxA + gap <= minB or maxB + gap <= minA then
				return false
			end
		end
	end
	return true
end

-- Distance from a point to a box (0 inside).
local function boxDistance(b: Box, x: number, z: number): number
	local ux, uz, vx, vz = axes(b.yaw)
	local dx, dz = x - b.x, z - b.z
	local lu = math.max(math.abs(dx * ux + dz * uz) - b.hx, 0)
	local lv = math.max(math.abs(dx * vx + dz * vz) - b.hz, 0)
	return math.sqrt(lu * lu + lv * lv)
end

local function segmentDistance(x: number, z: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local t = math.clamp(((x - ax) * dx + (z - az) * dz) / math.max(dx * dx + dz * dz, 1e-6), 0, 1)
	return math.sqrt((x - ax - dx * t) ^ 2 + (z - az - dz * t) ^ 2)
end

type Context = {
	field: Field.Field,
	realm: any,
	manifest: any,
	anchors: { Anchor },
	scale: number,
	clear: number,
	taken: { Box },
	out: { Props.PropSpec },
}

-- Yaw that turns an asset's front (the manifest's `front`, -Z or +Z) towards direction (dx, dz).
local function facing(ctx: Context, dx: number, dz: number): number
	if ctx.manifest.front == "-Z" then
		return math.atan2(-dx, -dz)
	end
	return math.atan2(dx, dz)
end

-- Footprint of a kit asset at `scale`, placed at (x, z) turned `yaw`, in studs.
local function footprint(ctx: Context, asset: string, x: number, z: number, yaw: number): Box
	local meta = ctx.manifest.assets[asset]
	assert(meta, `village kit has no asset {asset}`)
	local s = ctx.scale
	-- Bounds are about the asset origin; shift the box centre to the bounds centre.
	local cx = (meta.min[1] + meta.max[1]) / 2 * s
	local cz = (meta.min[3] + meta.max[3]) / 2 * s
	local ux, uz, vx, vz = axes(yaw)
	return {
		x = x + ux * cx + vx * cz,
		z = z + uz * cx + vz * cz,
		hx = (meta.max[1] - meta.min[1]) / 2 * s,
		hz = (meta.max[3] - meta.min[3]) / 2 * s,
		yaw = yaw,
	}
end

local function roadDistance(ctx: Context, x: number, z: number): number
	local best = math.huge
	for _, road in ctx.realm.roads do
		local pts = road.points
		for k = 1, #pts - 1 do
			local d = segmentDistance(x, z, pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]) - road.width / 2
			best = math.min(best, d)
		end
	end
	return best
end

-- True when the box is clear of anchors, roads (unless `onRoad`), the plaza and other footprints.
local function free(ctx: Context, b: Box, gap: number, roadClear: number?): boolean
	for _, a in ctx.anchors do
		if boxDistance(b, a.x, a.z) < a.r + ctx.clear then
			return false
		end
	end
	if roadClear then
		for _, c in corners(b) do
			if roadDistance(ctx, c[1], c[2]) < roadClear then
				return false
			end
		end
		if roadDistance(ctx, b.x, b.z) < roadClear then
			return false
		end
	end
	for _, other in ctx.taken do
		if overlaps(b, other, gap) then
			return false
		end
	end
	return true
end

local function inside(b: Box, pad: any, margin: number): boolean
	for _, c in corners(b) do
		if c[1] < pad.x0 + margin or c[1] > pad.x1 - margin or c[2] < pad.z0 + margin or c[2] > pad.z1 - margin then
			return false
		end
	end
	return true
end

-- Lowest ground under a box, so no corner floats.
local function groundUnder(ctx: Context, b: Box): number
	local low = ctx.field.height(b.x, b.z)
	for _, c in corners(b) do
		low = math.min(low, ctx.field.height(c[1], c[2]))
	end
	return low
end

local function put(ctx: Context, asset: string, x: number, z: number, yaw: number, box: Box?, y: number?)
	if box then
		table.insert(ctx.taken, box)
	end
	table.insert(ctx.out, {
		asset = asset,
		x = x,
		y = y or (if box then groundUnder(ctx, box) else ctx.field.height(x, z)),
		z = z,
		yaw = yaw,
		scale = 1,
	})
end

local function kitNames(ctx: Context, prefix: string): { string }
	local names = {}
	for name in ctx.manifest.assets do
		if string.match(name, "^" .. prefix .. "%d+$") then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

local function fixtures(ctx: Context, list: { any }?)
	if not list then
		return
	end
	for _, f in list do
		local yaw = math.rad(f.yaw)
		put(ctx, f.asset, f.x, f.z, yaw, footprint(ctx, f.asset, f.x, f.z, yaw))
	end
end

-- Fence segments along the named pad sides, with gaps where roads cross and where blocked.
local function fence(ctx: Context, pad: any, sides: { string }?)
	local meta = ctx.manifest.assets.Fence
	local length = (meta.max[1] - meta.min[1]) * ctx.scale
	local inset = 2
	local edges = {
		south = { pad.x0, pad.z1 - inset, pad.x1, pad.z1 - inset },
		north = { pad.x0, pad.z0 + inset, pad.x1, pad.z0 + inset },
		east = { pad.x1 - inset, pad.z0, pad.x1 - inset, pad.z1 },
		west = { pad.x0 + inset, pad.z0, pad.x0 + inset, pad.z1 },
	}
	if not sides then
		return
	end
	for _, side in sides do
		local e = edges[side]
		local dx, dz = e[3] - e[1], e[4] - e[2]
		local span = math.sqrt(dx * dx + dz * dz)
		local count = math.floor(span / length)
		local yaw = math.atan2(-dz, dx)
		for k = 0, count - 1 do
			local t = (k + 0.5) * length / span
			local x, z = e[1] + dx * t, e[2] + dz * t
			if roadDistance(ctx, x, z) < length / 2 + 2 then
				continue
			end
			local box = footprint(ctx, "Fence", x, z, yaw)
			box.wall = true
			if free(ctx, box, 0.5) then
				put(ctx, "Fence", x, z, yaw, box)
			end
		end
	end
end

-- Clutter (crates, wagons, hay) around existing footprints.
local function clutter(ctx: Context, rng: Hash.Rng, pad: any, counts: { [string]: number }?)
	if not counts then
		return
	end
	local names = {}
	for name in counts do
		table.insert(names, name)
	end
	table.sort(names)
	-- Clutter gathers by buildings, tents and fixtures, not along walls and fences.
	local hosts = {}
	for _, box in ctx.taken do
		if not box.wall then
			table.insert(hosts, box)
		end
	end
	for _, name in names do
		local placed = 0
		for _ = 1, 60 do
			if placed >= counts[name] or #hosts == 0 then
				break
			end
			local host = hosts[rng:int(1, #hosts)]
			local angle = rng:range(0, TAU)
			local reach = math.max(host.hx, host.hz) + rng:range(3, 7)
			local x, z = host.x + math.sin(angle) * reach, host.z + math.cos(angle) * reach
			local yaw = rng:range(0, TAU)
			local isKit = ctx.manifest.assets[name] ~= nil
			local box = if isKit
				then footprint(ctx, name, x, z, yaw)
				else { x = x, z = z, hx = 2.5, hz = 2.5, yaw = yaw }
			if inside(box, pad, 3) and free(ctx, box, 1, 1) then
				put(ctx, name, x, z, yaw, box)
				placed += 1
			end
		end
	end
end

local function village(ctx: Context, site: any, pad: any, seed: number)
	local rng = Hash.rng(Hash.named(seed, "village"))
	local plaza = site.plaza
	table.insert(ctx.taken, { x = plaza.x, z = plaza.z, hx = plaza.r * 0.72, hz = plaza.r * 0.72, yaw = math.rad(45) })
	fixtures(ctx, site.fixtures)

	-- Lots: points along each road inside the pad and around the plaza, each facing its road.
	type Lot = { x: number, z: number, nx: number, nz: number, key: number }
	local lots: { Lot } = {}
	for _, road in ctx.realm.roads do
		local pts = road.points
		for k = 1, #pts - 1 do
			local ax, az, bx, bz = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
			local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
			local tx, tz = (bx - ax) / len, (bz - az) / len
			for d = 0, len, 6 do
				local x, z = ax + tx * d, az + tz * d
				if x >= pad.x0 and x <= pad.x1 and z >= pad.z0 and z <= pad.z1 then
					for _, side in { 1, -1 } do
						local nx, nz = -tz * side, tx * side
						local edge = road.width / 2 + site.setback
						table.insert(lots, { x = x + nx * edge, z = z + nz * edge, nx = nx, nz = nz, key = 0 })
					end
				end
			end
		end
	end
	for deg = 0, 350, 10 do
		local a = math.rad(deg)
		local nx, nz = math.sin(a), math.cos(a)
		local edge = plaza.r + site.setback
		table.insert(lots, { x = plaza.x + nx * edge, z = plaza.z + nz * edge, nx = nx, nz = nz, key = 0 })
	end
	for k, lot in lots do
		lot.key = Hash.u32(seed, k, 7)
	end
	table.sort(lots, function(a, b)
		return a.key < b.key
	end)

	local houses, barns = kitNames(ctx, "House"), kitNames(ctx, "Barn")
	local placedHouses, placedBarns = 0, 0
	local used: { [string]: boolean } = {}
	for _, lot in lots do
		if placedHouses >= site.houses and placedBarns >= site.barns then
			break
		end
		-- Barns go on the outskirts, houses near the centre.
		local far = math.sqrt((lot.x - plaza.x) ^ 2 + (lot.z - plaza.z) ^ 2) > 60
		local pool = if far and placedBarns < site.barns then barns else houses
		if pool == houses and placedHouses >= site.houses then
			continue
		end
		local start = rng:int(1, #pool)
		for i = 0, #pool - 1 do
			local name = pool[(start + i - 1) % #pool + 1]
			if used[name] and i < #pool - 1 then
				continue
			end
			local meta = ctx.manifest.assets[name]
			-- The front faces the road: the house stands back by half its depth.
			local yaw = facing(ctx, -lot.nx, -lot.nz)
			local depth = (meta.max[3] - meta.min[3]) / 2 * ctx.scale
			local x, z = lot.x + lot.nx * depth, lot.z + lot.nz * depth
			local box = footprint(ctx, name, x, z, yaw)
			if inside(box, pad, 4) and free(ctx, box, site.gap, 1) then
				put(ctx, name, x, z, yaw, box)
				used[name] = true
				if pool == barns then
					placedBarns += 1
				else
					placedHouses += 1
				end
				break
			end
		end
	end
	fence(ctx, pad, site.fence)
	clutter(ctx, rng, pad, site.clutter)
end

local function fields(ctx: Context, site: any, pad: any, _seed: number)
	local crops = ctx.realm.props.crops
	local scarecrows = kitNames(ctx, "Scarecrow")
	for _, plot in ctx.field.plots do
		local rng = Hash.rng(plot.seed)
		local w, d = plot.x1 - plot.x0, plot.z1 - plot.z0
		local along = if plot.alongX then w else d
		local across = if plot.alongX then d else w
		local function at(u: number, v: number): (number, number)
			if plot.alongX then
				return plot.x0 + u, plot.z0 + v
			end
			return plot.x0 + v, plot.z0 + u
		end
		local function clearOfAnchors(x: number, z: number, r: number): boolean
			for _, a in ctx.anchors do
				if math.sqrt((x - a.x) ^ 2 + (z - a.z) ^ 2) < a.r + r then
					return false
				end
			end
			return true
		end
		if plot.crop == "wheat" or plot.crop == "sprout" then
			local def = crops[plot.crop]
			local spacing = if plot.crop == "wheat" then 4.6 else 4.2
			local period = site.rowSpacing
			-- Rows on the ridges (the second half of each furrow period).
			for v = period * 0.75, across - 2, period do
				for u = 3, along - 3, spacing do
					local x, z = at(u + rng:range(-0.6, 0.6), v + rng:range(-0.3, 0.3))
					table.insert(ctx.out, {
						asset = string.format("%s%02d", def.prefix, rng:int(1, def.variants)),
						x = x,
						y = ctx.field.height(x, z) - 0.2,
						z = z,
						yaw = rng:range(0, TAU),
						scale = rng:range(0.9, 1.15),
					})
				end
			end
		elseif plot.crop == "hay" then
			local def = crops.hay
			for _ = 1, rng:int(4, 8) do
				local x, z = at(rng:range(6, along - 6), rng:range(6, across - 6))
				local yaw = rng:range(0, TAU)
				local box = { x = x, z = z, hx = 4.5, hz = 4.5, yaw = yaw }
				if clearOfAnchors(x, z, 6) and free(ctx, box, 1) then
					put(ctx, string.format("%s%02d", def.prefix, rng:int(1, def.variants)), x, z, yaw, box)
				end
			end
		end
		if plot.crop == "wheat" and #scarecrows > 0 then
			for _ = 1, site.scarecrows do
				local x, z = at(rng:range(along * 0.3, along * 0.7), rng:range(across * 0.3, across * 0.7))
				local yaw = rng:range(0, TAU)
				local name = scarecrows[rng:int(1, #scarecrows)]
				local box = footprint(ctx, name, x, z, yaw)
				if clearOfAnchors(x, z, 4) and free(ctx, box, 1) then
					put(ctx, name, x, z, yaw, box)
				end
			end
		end
		-- Stone lip along the top of the plot's bank (3 studs in), open in the middle of each side.
		if plot.level > 0 then
			local lip = 3
			local meta = ctx.manifest.assets.Border
			local length = (meta.max[1] - meta.min[1]) * ctx.scale
			for _, e in
				{
					{ plot.x0 + lip, plot.z0 + lip, plot.x1 - lip, plot.z0 + lip },
					{ plot.x0 + lip, plot.z1 - lip, plot.x1 - lip, plot.z1 - lip },
					{ plot.x0 + lip, plot.z0 + lip, plot.x0 + lip, plot.z1 - lip },
					{ plot.x1 - lip, plot.z0 + lip, plot.x1 - lip, plot.z1 - lip },
				}
			do
				local dx, dz = e[3] - e[1], e[4] - e[2]
				local span = math.sqrt(dx * dx + dz * dz)
				local count = math.floor(span / length)
				local yaw = math.atan2(-dz, dx)
				for k = 0, count - 1 do
					if math.abs(k + 0.5 - count / 2) < 1 then
						continue
					end
					local t = (k + 0.5) * length / span
					local x, z = e[1] + dx * t, e[2] + dz * t
					put(ctx, "Border", x, z, yaw, nil, ctx.field.height(x, z) - 0.15)
				end
			end
		end
	end
	fence(ctx, pad, site.fence)
end

local function orchard(ctx: Context, site: any, pad: any, seed: number)
	local rng = Hash.rng(Hash.named(seed, "orchard"))
	local def = ctx.realm.props.crops.fruit
	local sx, sz = site.spacing[1], site.spacing[2]
	for z = pad.z0 + sz / 2, pad.z1 - sz / 2, sz do
		for x = pad.x0 + sx / 2, pad.x1 - sx / 2, sx do
			local px = x + rng:range(-site.jitter, site.jitter)
			local pz = z + rng:range(-site.jitter, site.jitter)
			local box = { x = px, z = pz, hx = 2, hz = 2, yaw = 0 }
			if roadDistance(ctx, px, pz) < site.aisle or not free(ctx, box, 2) then
				continue
			end
			put(ctx, string.format("%s%02d", def.prefix, rng:int(1, def.variants)), px, pz, rng:range(0, TAU), box)
		end
	end
	fence(ctx, pad, site.fence)
	clutter(ctx, rng, pad, site.clutter)
end

local function camp(ctx: Context, site: any, pad: any, seed: number)
	local rng = Hash.rng(Hash.named(seed, "camp"))
	local c = site.centre
	fixtures(ctx, site.fixtures)

	-- Palisade ring, the gate gap facing `gate` degrees from +Z.
	local segment = (ctx.manifest.assets.Palisade1.length or 4) * ctx.scale
	local count = math.floor(TAU * site.radius / segment)
	local step = TAU / count
	local gate = math.rad(site.gate)
	local walls = kitNames(ctx, "Palisade")
	for i = 0, count - 1 do
		local a = gate + (i + 0.5) * step
		if i < site.gateWidth / 2 or i >= count - site.gateWidth / 2 then
			continue
		end
		local x, z = c.x + math.sin(a) * site.radius, c.z + math.cos(a) * site.radius
		local name = walls[rng:int(1, #walls)]
		local box = footprint(ctx, name, x, z, a)
		box.wall = true
		put(ctx, name, x, z, a, box)
	end
	for _, side in { -1, 1 } do
		local a = gate + side * (site.gateWidth / 2) * step
		local x, z = c.x + math.sin(a) * site.radius, c.z + math.cos(a) * site.radius
		local box = footprint(ctx, "GateTower", x, z, a)
		box.wall = true
		put(ctx, "GateTower", x, z, a, box)
	end

	-- Tents on a ring, opening towards the centre, off the gate road.
	local tents = kitNames(ctx, "Tent")
	local placed = 0
	for _ = 1, 80 do
		if placed >= site.tents then
			break
		end
		local a = rng:range(0, TAU)
		local r = site.tentRing + rng:range(-8, 8)
		local x, z = c.x + math.sin(a) * r, c.z + math.cos(a) * r
		local yaw = facing(ctx, -math.sin(a), -math.cos(a))
		local name = tents[rng:int(1, #tents)]
		local box = footprint(ctx, name, x, z, yaw)
		if inside(box, pad, 4) and free(ctx, box, 3, 2) then
			put(ctx, name, x, z, yaw, box)
			placed += 1
		end
	end
	clutter(ctx, rng, pad, site.clutter)
end

--[=[ Ground footprint of a placed village-kit asset (studs), for checks outside the layout. ]=]
function Settlement.footprint(manifest: any, scale: number, spec: Props.PropSpec): Box?
	if not manifest.assets[spec.asset] then
		return nil
	end
	local ctx = { manifest = manifest, scale = scale } :: any
	return footprint(ctx, spec.asset, spec.x, spec.z, spec.yaw)
end

--[=[ True when two footprints come closer than `gap` studs. ]=]
function Settlement.overlaps(a: Box, b: Box, gap: number): boolean
	return overlaps(a, b, gap)
end

--[=[ Distance from a point to a footprint (0 inside). ]=]
function Settlement.distance(b: Box, x: number, z: number): number
	return boxDistance(b, x, z)
end

local SITES = { village = village, fields = fields, orchard = orchard, camp = camp }
local ORDER = { "village", "fields", "orchard", "camp" }

--[=[
	Placements for every settlement whose pad belongs to `zone` (a node id). `manifest` is the
	village-kit manifest; `anchors` are the Map's NPCs, spawners and dummies.
]=]
function Settlement.forZone(field: Field.Field, manifest: any, anchors: { Anchor }, zone: string): { Props.PropSpec }
	local realm = field.graph.realm
	local settlements = realm.settlements
	local out: { Props.PropSpec } = {}
	local ctx: Context = {
		field = field,
		realm = realm,
		manifest = manifest,
		anchors = anchors,
		scale = settlements.scale,
		clear = settlements.clear,
		taken = {},
		out = out,
	}
	for _, kind in ORDER do
		local site = settlements[kind]
		local pad
		for _, p in realm.pads do
			if p.name == site.pad then
				pad = p
			end
		end
		assert(pad, `settlements.{kind}: unknown pad {site.pad}`)
		if pad.zone == zone then
			SITES[kind](ctx, site, pad, Hash.named(field.graph.seed, "settlement:" .. kind))
		end
	end
	return out
end

return Settlement
