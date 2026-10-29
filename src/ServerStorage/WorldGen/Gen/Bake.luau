--!strict

--[=[
	One zone's build result (terrain columns, parts, props), generated from the field or decoded
	from a bake. A locked zone is baked by `lune run tools/worldgen/bake` into `WorldGen/Baked`, so
	later changes to the generator code or to other zones can never alter it.
]=]
local Cliffs = require(script.Parent.Cliffs)
local Field = require(script.Parent.Field)
local Graph = require(script.Parent.Graph)
local Grid = require(script.Parent.Grid)
local Props = require(script.Parent.Props)
local Settlement = require(script.Parent.Settlement)

export type Columns = {
	x0: number,
	z0: number,
	nx: number,
	nz: number,
	height: { number },
	material: { string },
	assign: { number },
	water: { number },
}

export type Result = {
	columns: Columns,
	parts: { Cliffs.PartSpec },
	props: { Props.PropSpec },
}

export type Extent = { x0: number, z0: number, x1: number, z1: number }

-- What the settlement layout needs beyond the field: the village-kit manifest and the Map anchors.
export type SettlementInput = { manifest: any, anchors: { Settlement.Anchor } }

local Bake = {}

local STEP = 4 -- terrain column spacing (one voxel)
local COARSE = 16 -- studs between samples when finding zone extents
local VERSION = 1

--[=[ World-space extent of the ground each node builds, from a coarse scan of the sections. ]=]
function Bake.extents(field: Field.Field): { [number]: Extent }
	local out: { [number]: Extent } = {}
	for _, s in field.graph.realm.sections do
		for z = s.z0, s.z1, COARSE do
			for x = s.x0, s.x1, COARSE do
				local a, b = field.owner(x, z)
				local assign = if a ~= 0 then a else b
				if assign ~= 0 then
					local e = out[assign]
					if not e then
						out[assign] = { x0 = x, z0 = z, x1 = x, z1 = z }
					else
						e.x0, e.z0 = math.min(e.x0, x), math.min(e.z0, z)
						e.x1, e.z1 = math.max(e.x1, x), math.max(e.z1, z)
					end
				end
			end
		end
	end
	for _, e in out do
		-- One coarse step of slack, snapped to the voxel grid.
		e.x0 = math.floor((e.x0 - COARSE) / STEP) * STEP
		e.z0 = math.floor((e.z0 - COARSE) / STEP) * STEP
		e.x1 = math.ceil((e.x1 + COARSE) / STEP) * STEP
		e.z1 = math.ceil((e.z1 + COARSE) / STEP) * STEP
	end
	return out
end

--[=[
	Zones whose ground lies within `reach` studs of each other's, from a coarse scan of the
	sections. A zone's cliffs and terrain read the ground this close across its border, so these are
	the zones to rebuild together after a border moves (graph edges miss rim and cliff neighbours).
]=]
function Bake.neighbours(field: Field.Field, reach: number): { [number]: { [number]: boolean } }
	local out: { [number]: { [number]: boolean } } = {}
	local steps = math.max(1, math.ceil(reach / COARSE))
	for _, s in field.graph.realm.sections do
		local cols = math.floor((s.x1 - s.x0) / COARSE) + 1
		local rows = math.floor((s.z1 - s.z0) / COARSE) + 1
		local assign = table.create(cols * rows, 0)
		for j = 0, rows - 1 do
			for i = 0, cols - 1 do
				local a, b = field.owner(s.x0 + i * COARSE, s.z0 + j * COARSE)
				assign[i + j * cols + 1] = if a ~= 0 then a else b
			end
		end
		for j = 0, rows - 1 do
			for i = 0, cols - 1 do
				local here = assign[i + j * cols + 1]
				for d = 1, steps do
					for _, o in { { d, 0 }, { 0, d } } do
						local ni, nj = i + o[1], j + o[2]
						if ni < cols and nj < rows then
							local there = assign[ni + nj * cols + 1]
							if here ~= 0 and there ~= 0 and here ~= there then
								out[here] = out[here] or {}
								out[there] = out[there] or {}
								out[here][there] = true
								out[there][here] = true
							end
						end
					end
				end
			end
		end
	end
	return out
end

--[=[ Index of the column at world (x, z), or nil outside the table. ]=]
function Bake.columnIndex(columns: Columns, x: number, z: number): number?
	local i = (x - columns.x0) / STEP
	local j = (z - columns.z0) / STEP
	if i < 0 or j < 0 or i >= columns.nx or j >= columns.nz then
		return nil
	end
	return math.floor(i) + math.floor(j) * columns.nx + 1
end

--[=[
	Generates a zone: samples its extent plus `margin`, paints cliff faces with the rock material,
	and builds its parts and props. With `settlement`, the zone's settlements (village, farmland,
	orchard, camp) join its props.
]=]
function Bake.generate(
	field: Field.Field,
	node: Graph.Node,
	extent: Extent,
	margin: number,
	settlement: SettlementInput?
): Result
	local realm = field.graph.realm
	local x0, z0 = extent.x0 - margin, extent.z0 - margin
	local nx = math.floor((extent.x1 - extent.x0 + margin * 2) / STEP) + 1
	local nz = math.floor((extent.z1 - extent.z0 + margin * 2) / STEP) + 1
	local grid = Grid.sample(field, x0, z0, nx, nz, STEP)

	-- Faces steeper than a cliff step show rock where no column covers them.
	local material = table.clone(grid.material)
	local step = realm.cliff.step
	for j = 0, nz - 1 do
		for i = 0, nx - 1 do
			local k = Grid.index(grid, i, j)
			local h = grid.height[k]
			local rise = math.max(
				math.abs(grid.height[Grid.index(grid, i + 1, j)] - h),
				math.abs(grid.height[Grid.index(grid, i - 1, j)] - h),
				math.abs(grid.height[Grid.index(grid, i, j + 1)] - h),
				math.abs(grid.height[Grid.index(grid, i, j - 1)] - h)
			)
			if rise > step then
				local owner = grid.owner[k]
				material[k] = if owner ~= 0 then realm.biomes[field.graph.nodes[owner].biome].rock else "Slate"
			end
		end
	end

	local props = Props.scatter(field, grid, node.index)
	if settlement then
		for _, spec in Settlement.forZone(field, settlement.manifest, settlement.anchors, node.id) do
			table.insert(props, spec)
		end
	end

	return {
		columns = {
			x0 = x0,
			z0 = z0,
			nx = nx,
			nz = nz,
			height = grid.height,
			material = material,
			assign = grid.assign,
			water = grid.water,
		},
		parts = Cliffs.build(field, grid, node.index),
		props = props,
	}
end

-- Base64 ------------------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE: { [number]: number } = {}
for k = 1, #ALPHABET do
	DECODE[string.byte(ALPHABET, k)] = k - 1
end

local function encode64(data: buffer): string
	local len = buffer.len(data)
	local out = table.create(math.ceil(len / 3))
	for o = 0, len - 1, 3 do
		local a = buffer.readu8(data, o)
		local b = if o + 1 < len then buffer.readu8(data, o + 1) else 0
		local c = if o + 2 < len then buffer.readu8(data, o + 2) else 0
		local v = a * 65536 + b * 256 + c
		local s1 = bit32.rshift(v, 18) + 1
		local s2 = bit32.band(bit32.rshift(v, 12), 63) + 1
		local s3 = bit32.band(bit32.rshift(v, 6), 63) + 1
		local s4 = bit32.band(v, 63) + 1
		table.insert(
			out,
			string.sub(ALPHABET, s1, s1)
				.. string.sub(ALPHABET, s2, s2)
				.. (if o + 1 < len then string.sub(ALPHABET, s3, s3) else "=")
				.. (if o + 2 < len then string.sub(ALPHABET, s4, s4) else "=")
		)
	end
	return table.concat(out)
end

local function decode64(text: string, size: number): buffer
	local out = buffer.create(size)
	local o = 0
	for k = 1, #text, 4 do
		local a, b, c, d = string.byte(text, k, k + 3)
		local v = DECODE[a] * 262144 + DECODE[b] * 4096
		if c ~= 61 then
			v += DECODE[c] * 64
		end
		if d ~= 61 then
			v += DECODE[d]
		end
		for shift = 16, 0, -8 do
			if o < size then
				buffer.writeu8(out, o, bit32.band(bit32.rshift(v, shift), 0xFF))
				o += 1
			end
		end
	end
	return out
end

local function encodeHeight(h: number): number
	return math.clamp(math.round((h + 128) * 16), 1, 65535)
end

local function decodeHeight(v: number): number
	return v / 16 - 128
end

--[=[ Luau module source for a zone's bake. Columns the zone does not own are stored as unowned. ]=]
function Bake.encode(node: Graph.Node, result: Result): string
	local columns = result.columns
	local count = columns.nx * columns.nz
	local palette: { string } = {}
	local paletteIndex: { [string]: number } = {}
	local data = buffer.create(count * 5)
	for k = 1, count do
		local name = columns.material[k]
		local index = paletteIndex[name]
		if not index then
			table.insert(palette, name)
			index = #palette
			paletteIndex[name] = index
		end
		assert(index < 128, "too many terrain materials in one zone")
		local o = (k - 1) * 5
		buffer.writeu16(data, o, encodeHeight(columns.height[k]))
		buffer.writeu8(data, o + 2, index + (if columns.assign[k] == node.index then 128 else 0))
		buffer.writeu16(data, o + 3, if columns.water[k] ~= 0 then encodeHeight(columns.water[k]) else 0)
	end

	local parts = table.create(#result.parts)
	for _, p in result.parts do
		table.insert(
			parts,
			string.format(
				"%s %s %d %d %d %.2f %.2f %.2f %.4f %.4f %.4f %.2f %.2f %.2f",
				p.kind,
				p.material,
				p.color[1],
				p.color[2],
				p.color[3],
				p.x,
				p.y,
				p.z,
				p.yaw,
				p.pitch,
				p.roll,
				p.sx,
				p.sy,
				p.sz
			)
		)
	end
	local props = table.create(#result.props)
	for _, p in result.props do
		table.insert(props, string.format("%s %.2f %.2f %.2f %.4f %.3f", p.asset, p.x, p.y, p.z, p.yaw, p.scale))
	end
	local quoted = {}
	for _, name in palette do
		table.insert(quoted, `"{name}"`)
	end
	return table.concat({
		"-- Generated by tools/worldgen/bake.luau. Do not edit.",
		"return {",
		`\tversion = {VERSION},`,
		`\tzone = "{node.id}",`,
		`\tx0 = {columns.x0},`,
		`\tz0 = {columns.z0},`,
		`\tnx = {columns.nx},`,
		`\tnz = {columns.nz},`,
		`\tmaterials = \{ {table.concat(quoted, ", ")} },`,
		`\tcolumns = "{encode64(data)}",`,
		"\tparts = [[",
		table.concat(parts, "\n"),
		"]],",
		"\tprops = [[",
		table.concat(props, "\n"),
		"]],",
		"}",
		"",
	}, "\n")
end

--[=[ Result from a baked module's table; owned columns get `zoneIndex`. ]=]
function Bake.decode(data: any, zoneIndex: number): Result
	assert(data.version == VERSION, `bake version {data.version} is not {VERSION}; rebake`)
	local count = data.nx * data.nz
	local raw = decode64(data.columns, count * 5)
	local columns: Columns = {
		x0 = data.x0,
		z0 = data.z0,
		nx = data.nx,
		nz = data.nz,
		height = table.create(count, 0),
		material = table.create(count, ""),
		assign = table.create(count, 0),
		water = table.create(count, 0),
	}
	for k = 1, count do
		local o = (k - 1) * 5
		columns.height[k] = decodeHeight(buffer.readu16(raw, o))
		local m = buffer.readu8(raw, o + 2)
		columns.material[k] = data.materials[bit32.band(m, 127)]
		columns.assign[k] = if m >= 128 then zoneIndex else 0
		local w = buffer.readu16(raw, o + 3)
		columns.water[k] = if w ~= 0 then decodeHeight(w) else 0
	end
	local parts: { Cliffs.PartSpec } = {}
	for line in string.gmatch(data.parts, "[^\n]+") do
		local f = string.split(line, " ")
		table.insert(parts, {
			kind = f[1],
			material = f[2],
			color = { tonumber(f[3]) :: number, tonumber(f[4]) :: number, tonumber(f[5]) :: number },
			x = tonumber(f[6]) :: number,
			y = tonumber(f[7]) :: number,
			z = tonumber(f[8]) :: number,
			yaw = tonumber(f[9]) :: number,
			pitch = tonumber(f[10]) :: number,
			roll = tonumber(f[11]) :: number,
			sx = tonumber(f[12]) :: number,
			sy = tonumber(f[13]) :: number,
			sz = tonumber(f[14]) :: number,
		})
	end
	local props: { Props.PropSpec } = {}
	for line in string.gmatch(data.props, "[^\n]+") do
		local f = string.split(line, " ")
		table.insert(props, {
			asset = f[1],
			x = tonumber(f[2]) :: number,
			y = tonumber(f[3]) :: number,
			z = tonumber(f[4]) :: number,
			yaw = tonumber(f[5]) :: number,
			scale = tonumber(f[6]) :: number,
		})
	end
	return { columns = columns, parts = parts, props = props }
end

return Bake
