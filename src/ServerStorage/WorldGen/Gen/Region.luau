--!strict

--[=[
	One region of the continent at stud scale (docs/systems/world-generation.md, region builds).
	Pure: the Studio builder (`WorldGen/Regions`) writes what this returns, and the approval
	fingerprint in tests reads the same data, so an approved region cannot drift unnoticed.

	A region owns every column whose sample names it as `owner`: its land, its lakes and the sea
	out to `template.offshore`. Region by region the seams meet, since every builder samples the
	same point query.
]=]

local Camp = require(script.Parent.Camp)
local Continent = require(script.Parent.Continent)
local Hash = require(script.Parent.Hash)

type Template = typeof(require(script.Parent.Parent.Continent))

export type Context = {
	template: Template,
	seed: number,
	map: Continent.Map,
	sample: Continent.Sampler,
	roads: { { { number } } }, -- smoothed polylines in studs
	buckets: { [number]: { { number } } }, -- road segments { x0, z0, x1, z1 } by bucket
	patches: Hash.Fbm, -- bare-ground patches
	camps: { CampSite }, -- every goblin camp on the continent, in studs
	manifest: any?, -- village kit manifest (content/world/village.json); nil: camps are not dressed
}

export type CampSite = { id: string, region: string, x: number, z: number, y: number, gate: number }

export type Column = {
	height: number, -- ground in studs
	water: number?, -- water surface in studs
	material: string,
	owned: boolean,
}

export type PropSpec = { asset: string, x: number, y: number, z: number, yaw: number, scale: number }

export type Marker = { id: string, name: string, kind: string, x: number, y: number, z: number }

local Region = {}

local BUCKET = 128
local ROAD_HALF = 7 -- studs either side of a road's centre line
local SNOW_LINE = 250

local function bucketKey(bx: number, bz: number): number
	return (bx + 4096) * 8192 + (bz + 4096)
end

-- Chaikin corner cutting: rounds the grid steps of an A* path into a curve.
local function chaikin(points: { { number } }, passes: number): { { number } }
	local out = points
	for _ = 1, passes do
		local next: { { number } } = { out[1] }
		for i = 1, #out - 1 do
			local a, b = out[i], out[i + 1]
			table.insert(next, { a[1] * 0.75 + b[1] * 0.25, a[2] * 0.75 + b[2] * 0.25 })
			table.insert(next, { a[1] * 0.25 + b[1] * 0.75, a[2] * 0.25 + b[2] * 0.75 })
		end
		table.insert(next, out[#out])
		out = next
	end
	return out
end

--[=[
	Generates the continent once and prepares the stud-scale lookups. `manifest` is the village kit
	manifest; without it camps flatten their ground but are not dressed.
]=]
function Region.context(template: Template, seed: number?, manifest: any?): Context
	local s = seed or template.seed
	local map = Continent.generate(template, s)
	local sample = Continent.sampler(template, s)
	-- Camps: ground height at the centre; the gate faces the nearest settlement.
	local camps: { CampSite } = {}
	for _, site in map.sites do
		if site.kind == "camp" then
			local x, z = Continent.toStuds(template, site.u, site.v)
			local best, gate = math.huge, 0
			for _, other in map.sites do
				if
					other.kind == "town"
					or other.kind == "harbor"
					or other.kind == "capital"
					or other.kind == "city"
				then
					local ox, oz = Continent.toStuds(template, other.u, other.v)
					local d = (ox - x) ^ 2 + (oz - z) ^ 2
					if d < best then
						best, gate = d, math.atan2(ox - x, oz - z)
					end
				end
			end
			table.insert(
				camps,
				{ id = site.id, region = site.region, x = x, z = z, y = sample(site.u, site.v).height, gate = gate }
			)
		end
	end
	local roads: { { { number } } } = {}
	local buckets: { [number]: { { number } } } = {}
	for _, road in map.roads do
		local points: { { number } } = {}
		for _, k in road.cells do
			local u, v = Continent.center(map.res, k)
			local x, z = Continent.toStuds(template, u, v)
			table.insert(points, { x, z })
		end
		local line = chaikin(points, 3)
		table.insert(roads, line)
		for i = 1, #line - 1 do
			local a, b = line[i], line[i + 1]
			local segment = { a[1], a[2], b[1], b[2] }
			local bx0 = math.floor((math.min(a[1], b[1]) - ROAD_HALF) / BUCKET)
			local bx1 = math.floor((math.max(a[1], b[1]) + ROAD_HALF) / BUCKET)
			local bz0 = math.floor((math.min(a[2], b[2]) - ROAD_HALF) / BUCKET)
			local bz1 = math.floor((math.max(a[2], b[2]) + ROAD_HALF) / BUCKET)
			for bx = bx0, bx1 do
				for bz = bz0, bz1 do
					local key = bucketKey(bx, bz)
					local list = buckets[key]
					if not list then
						list = {}
						buckets[key] = list
					end
					table.insert(list, segment)
				end
			end
		end
	end
	return {
		template = template,
		seed = s,
		map = map,
		sample = sample,
		roads = roads,
		buckets = buckets,
		patches = Hash.fbm(Hash.named(s, "patches"), 320, 3),
		camps = camps,
		manifest = manifest,
	}
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

--[=[
	The continent sample at studs `x`, `z` with the camp grounds levelled, and how far inside a camp
	the point is (1 inside the palisade, easing to 0 over `camp.flatten`).
]=]
function Region.point(ctx: Context, x: number, z: number): (Continent.Sample, number)
	local p = ctx.sample(Continent.toUnit(ctx.template, x, z))
	local config = ctx.template.camp
	local inner = config.radius + 12
	local weight = 0
	for _, camp in ctx.camps do
		local d = math.sqrt((camp.x - x) ^ 2 + (camp.z - z) ^ 2)
		if d < inner + config.flatten then
			local w = 1 - smooth((d - inner) / config.flatten)
			if w > weight and not p.water then
				weight = w
				p = table.clone(p)
				p.height = p.height + (camp.y - p.height) * w
			end
		end
	end
	return p, weight
end

--[=[ Index of a region id in the template. ]=]
function Region.index(ctx: Context, id: string): number
	for index, region in ctx.template.regions do
		if region.id == id then
			return index
		end
	end
	error(`unknown region {id}`)
end

--[=[ Distance in studs from a point to the nearest road centre line, capped at `BUCKET`. ]=]
function Region.roadDistance(ctx: Context, x: number, z: number): number
	local list = ctx.buckets[bucketKey(math.floor(x / BUCKET), math.floor(z / BUCKET))]
	local best = BUCKET
	if list then
		for _, s in list do
			local dx, dz = s[3] - s[1], s[4] - s[2]
			local len2 = dx * dx + dz * dz
			local t = if len2 > 0 then math.clamp(((x - s[1]) * dx + (z - s[2]) * dz) / len2, 0, 1) else 0
			local px, pz = s[1] + dx * t - x, s[2] + dz * t - z
			best = math.min(best, math.sqrt(px * px + pz * pz))
		end
	end
	return best
end

--[=[
	Stud bounds of a region's build: its grid cells plus a margin for the offshore sea, as
	{ x0, z0, x1, z1 }.
]=]
function Region.bounds(ctx: Context, id: string): { number }
	local index = Region.index(ctx, id)
	local map = ctx.map
	local u0, v0, u1, v1 = math.huge, math.huge, -math.huge, -math.huge
	for k = 1, map.res * map.res do
		if map.region[k] == index then
			local u, v = Continent.center(map.res, k)
			u0, v0 = math.min(u0, u), math.min(v0, v)
			u1, v1 = math.max(u1, u), math.max(v1, v)
		end
	end
	assert(u0 < math.huge, `region {id} has no ground`)
	local x0, z0 = Continent.toStuds(ctx.template, u0, v0)
	local x1, z1 = Continent.toStuds(ctx.template, u1, v1)
	local pad = ctx.template.offshoreMargin
	return { x0 - pad, z0 - pad, x1 + pad, z1 + pad }
end

--[=[
	The column at studs `x`, `z` for region `index`. `slope` is the steepest rise in studs to a
	neighbouring column 4 studs away (from the caller's samples); steep ground turns to rock.
]=]
function Region.column(
	ctx: Context,
	index: number,
	x: number,
	z: number,
	point: Continent.Sample,
	slope: number,
	camp: number?
): Column
	local template = ctx.template
	local owned = point.owner == index and (point.region ~= Continent.SEA or point.offshore < template.offshore)
	local regionDef = template.regions[point.owner]
	local biome = template.biomes[regionDef.biome]
	local material = biome.grass
	if point.water and point.region == Continent.SEA then
		material = if point.offshore < 0.06 then biome.sand else "Mud"
	elseif point.water or (camp or 0) > 0.6 then
		-- Lake beds, and trodden camp grounds.
		material = "Mud"
	elseif point.shore < 0.12 and point.pad < 0.5 then
		material = biome.sand
	elseif point.mountain > 0.55 or slope > 4.5 then
		material = if point.height > SNOW_LINE then "Snow" else biome.rock
	elseif Region.roadDistance(ctx, x, z) < ROAD_HALF or ctx.patches(x, z) > 0.55 then
		material = biome.ground
	end
	return { height = point.height, water = point.water, material = material, owned = owned }
end

--[=[
	Prop placements for a region: trees in groves from a noise mask, a few loners, bushes around
	trees, boulders on a jittered lattice. Kept off water, beaches, mountains, roads and the Map pads.
]=]
function Region.props(ctx: Context, id: string): { PropSpec }
	local template = ctx.template
	local index = Region.index(ctx, id)
	local regionDef = template.regions[index]
	local biome = template.biomes[regionDef.biome]
	local bounds = Region.bounds(ctx, id)
	local seed = Hash.named(ctx.seed, "props:" .. id)
	local grove = Hash.fbm(Hash.named(seed, "grove"), template.props.groveScale, 3)
	-- Grove mask threshold so groves cover about `groves` of the ground (the mask is mostly -0.5..0.5).
	local threshold = 0.5 - biome.groves
	local out: { PropSpec } = {}

	local function ground(x: number, z: number): number?
		local p, camp = Region.point(ctx, x, z)
		if p.owner ~= index or p.water or p.shore < 0.3 or p.mountain > 0.3 or p.pad > 0.02 or camp > 0 then
			return nil
		end
		if Region.roadDistance(ctx, x, z) < ROAD_HALF + 6 then
			return nil
		end
		-- Flat enough under the trunk.
		local low, high = p.height, p.height
		for _, o in { { 6, 0 }, { -6, 0 }, { 0, 6 }, { 0, -6 } } do
			local q = Region.point(ctx, x + o[1], z + o[2])
			low, high = math.min(low, q.height), math.max(high, q.height)
		end
		if high - low > 6 then
			return nil
		end
		return low
	end

	local function pick(weights: { [string]: number }, r: number): string?
		local total = 0
		for _, w in weights do
			total += w
		end
		local acc = 0
		local names = {}
		for name in weights do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			acc += weights[name] / total
			if r <= acc then
				return name
			end
		end
		return names[#names]
	end

	local function place(prefix: string, variants: number, scale: { number }, x: number, z: number, n: number): boolean
		local y = ground(x, z)
		if not y then
			return false
		end
		local variant = 1 + Hash.u32(seed, n, 1) % variants
		table.insert(out, {
			asset = string.format("%s%02d", prefix, variant),
			x = x,
			y = y - 0.5,
			z = z,
			yaw = Hash.range(seed, 0, 2 * math.pi, n, 2),
			scale = Hash.range(seed, scale[1], scale[2], n, 3),
		})
		return true
	end

	-- Trees: a jittered lattice at the grove density; outside groves a few loners.
	if biome.trees > 0 then
		local cell = math.sqrt(10000 / biome.trees)
		local n = 0
		for gx = math.floor(bounds[1] / cell), math.floor(bounds[3] / cell) do
			for gz = math.floor(bounds[2] / cell), math.floor(bounds[4] / cell) do
				n += 1
				local x = (gx + Hash.unit(seed, gx, gz, 1)) * cell
				local z = (gz + Hash.unit(seed, gx, gz, 2)) * cell
				local inGrove = grove(x, z) > threshold
				if inGrove or Hash.unit(seed, gx, gz, 3) < 0.02 then
					local name = pick(biome.species, Hash.unit(seed, gx, gz, 4))
					local species = name and (template.props.species :: any)[name]
					if species and place(species.prefix, species.variants, species.scale, x, z, n * 8) then
						local bushes = template.props.bushes
						for b = 1, math.floor(bushes.perTree + Hash.unit(seed, gx, gz, 5)) do
							local angle = Hash.range(seed, 0, 2 * math.pi, n, b, 6)
							local dist = Hash.range(seed, 8, 20, n, b, 7)
							place(
								bushes.prefix,
								bushes.variants,
								bushes.scale,
								x + math.cos(angle) * dist,
								z + math.sin(angle) * dist,
								n * 8 + b
							)
						end
					end
				end
			end
		end
	end

	if biome.boulders > 0 then
		local cell = math.sqrt(100000 / biome.boulders)
		local boulders = template.props.boulders
		local n = 0
		for gx = math.floor(bounds[1] / cell), math.floor(bounds[3] / cell) do
			for gz = math.floor(bounds[2] / cell), math.floor(bounds[4] / cell) do
				n += 1
				local x = (gx + Hash.unit(seed, gx, gz, 11)) * cell
				local z = (gz + Hash.unit(seed, gx, gz, 12)) * cell
				place(boulders.prefix, boulders.variants, boulders.scale, x, z, 1000000 + n)
			end
		end
	end
	return out
end

--[=[ Placeholder markers for the region's sites, until settlements are dressed. ]=]
function Region.markers(ctx: Context, id: string): { Marker }
	local out: { Marker } = {}
	for _, site in ctx.map.sites do
		if site.region == id and site.kind ~= "camp" then
			local x, z = Continent.toStuds(ctx.template, site.u, site.v)
			local p = ctx.sample(site.u, site.v)
			table.insert(out, { id = site.id, name = site.name, kind = site.kind, x = x, y = p.height, z = z })
		end
	end
	return out
end

--[=[ Village-kit placements for the region's goblin camps (empty without a manifest). ]=]
function Region.camps(ctx: Context, id: string): { PropSpec }
	local out: { PropSpec } = {}
	if not ctx.manifest then
		return out
	end
	for _, camp in ctx.camps do
		if camp.region == id then
			local site = { x = camp.x, z = camp.z, y = camp.y, gate = camp.gate, seed = Hash.named(ctx.seed, camp.id) }
			for _, spec in Camp.layout(ctx.manifest, ctx.template.kitScale, site, ctx.template.camp) do
				table.insert(out, spec)
			end
		end
	end
	return out
end

--[=[
	Hash of a region's build: ground and water on a 32-stud lattice over its owned columns, the
	material of each, its props and its markers. `template.approved[id]` stores it once the owner
	signs a region off; a test fails when a change would alter an approved region.
]=]
function Region.fingerprint(ctx: Context, id: string): string
	local index = Region.index(ctx, id)
	local bounds = Region.bounds(ctx, id)
	local h = Hash.named(ctx.seed, "fingerprint:" .. id)
	local step = 32
	for x = math.floor(bounds[1] / step) * step, bounds[3], step do
		for z = math.floor(bounds[2] / step) * step, bounds[4], step do
			local point, camp = Region.point(ctx, x, z)
			local column = Region.column(ctx, index, x, z, point, 0, camp)
			if column.owned then
				h = Hash.u32(h, math.round(column.height * 2), math.round((column.water or -999) * 2))
				h = Hash.named(h, column.material)
			end
		end
	end
	for _, prop in Region.props(ctx, id) do
		h = Hash.u32(
			Hash.named(h, prop.asset),
			math.round(prop.x * 10),
			math.round(prop.z * 10),
			math.round(prop.y * 10)
		)
	end
	for _, marker in Region.markers(ctx, id) do
		h = Hash.u32(Hash.named(h, marker.id), math.round(marker.x), math.round(marker.z))
	end
	for _, spec in Region.camps(ctx, id) do
		h = Hash.u32(
			Hash.named(h, spec.asset),
			math.round(spec.x * 10),
			math.round(spec.z * 10),
			math.round(spec.yaw * 100)
		)
	end
	return string.format("%08x", h)
end

return Region
