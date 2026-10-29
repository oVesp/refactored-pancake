--!strict

-- Top-down preview of a realm section (docs/systems/world-generation.md, section loop).
-- Run from the repo root: `lune run tools/worldgen/map [section]` (default `centre`).
-- Writes build/worldgen-<section>.png: shaded ground, water, zone borders, corridors, pads,
-- cliff parts and node labels. Two pixels per terrain column (4 studs).
local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("../../tests/Loader")
local Png = require("./Png")

local Graph = Loader.load("src/ServerStorage/WorldGen/Gen/Graph")
local Field = Loader.load("src/ServerStorage/WorldGen/Gen/Field")
local Grid = Loader.load("src/ServerStorage/WorldGen/Gen/Grid")
local Cliffs = Loader.load("src/ServerStorage/WorldGen/Gen/Cliffs")
local realm = Loader.load("src/ServerStorage/WorldGen/Midgard")

local STEP = 4
local SCALE = 2

local sectionName = process.args[1] or "centre"
local section = realm.sections[sectionName]
assert(section, `unknown section {sectionName}`)

local started = os.clock()
local graph = Graph.build(realm)
local field = Field.new(graph)
local nx = math.floor((section.x1 - section.x0) / STEP)
local nz = math.floor((section.z1 - section.z0) / STEP)
local grid = Grid.sample(field, section.x0, section.z0, nx, nz, STEP)
print(string.format("sampled %d x %d in %.1fs", nx, nz, os.clock() - started))

local width, height = nx * SCALE, nz * SCALE
local pixels = buffer.create(width * height * 3)

local function put(px: number, py: number, r: number, g: number, b: number)
	if px < 0 or py < 0 or px >= width or py >= height then
		return
	end
	local o = (py * width + px) * 3
	buffer.writeu8(pixels, o, math.clamp(math.round(r), 0, 255))
	buffer.writeu8(pixels, o + 1, math.clamp(math.round(g), 0, 255))
	buffer.writeu8(pixels, o + 2, math.clamp(math.round(b), 0, 255))
end

local function toPixel(x: number, z: number): (number, number)
	return math.floor((x - section.x0) / STEP * SCALE), math.floor((z - section.z0) / STEP * SCALE)
end

-- Ground: material colour, hillshade from the north-west, darker with depth.
local colors = realm.materialColors
for j = 0, nz - 1 do
	for i = 0, nx - 1 do
		local k = Grid.index(grid, i, j)
		local h = grid.height[k]
		local dx = grid.height[Grid.index(grid, i + 1, j)] - grid.height[Grid.index(grid, i - 1, j)]
		local dz = grid.height[Grid.index(grid, i, j + 1)] - grid.height[Grid.index(grid, i, j - 1)]
		local light = math.clamp(1 - (dx + dz) * 0.04, 0.45, 1.4)
		local tone = math.clamp(0.75 + h / 900, 0.5, 1.3)
		local c = colors[grid.material[k]] or { 200, 0, 200 }
		local r, g, b = c[1] * light * tone, c[2] * light * tone, c[3] * light * tone
		if grid.water[k] ~= 0 and grid.water[k] > h then
			r, g, b = 60, 110, 150
		end
		local o = grid.owner[k]
		if o ~= grid.owner[Grid.index(grid, i + 1, j)] or o ~= grid.owner[Grid.index(grid, i, j + 1)] then
			r, g, b = r * 0.55, g * 0.55, b * 0.55
		end
		if grid.corridor[k] then
			r, g, b = r * 0.6 + 230 * 0.4, g * 0.6 + 150 * 0.4, b * 0.6 + 60 * 0.4
		end
		for sy = 0, SCALE - 1 do
			for sx = 0, SCALE - 1 do
				put(i * SCALE + sx, j * SCALE + sy, r, g, b)
			end
		end
	end
end

-- Cliff parts as footprints.
local partCount = 0
for _, node in graph.nodes do
	local parts = Cliffs.build(field, grid, node.index)
	partCount += #parts
	for _, p in parts do
		if p.kind == "Cap" then
			continue
		end
		local shadeColor = if p.kind == "Stair"
			then { 230, 210, 160 }
			elseif p.kind == "Roof" then { 90, 70, 110 }
			elseif p.kind == "Spire" then { 230, 230, 240 }
			elseif p.kind == "Outcrop" then { 200, 120, 90 }
			else { 70, 76, 86 }
		local cy, sy = math.cos(p.yaw), math.sin(p.yaw)
		local reach = math.max(p.sx, p.sz) * 0.75
		local x0, z0 = toPixel(p.x - reach, p.z - reach)
		local x1, z1 = toPixel(p.x + reach, p.z + reach)
		for py = z0, z1 do
			for px = x0, x1 do
				local wx = section.x0 + (px + 0.5) / SCALE * STEP - p.x
				local wz = section.z0 + (py + 0.5) / SCALE * STEP - p.z
				-- Part local axes: yaw turns X towards -Z.
				local lx = wx * cy - wz * sy
				local lz = wx * sy + wz * cy
				local ax, az = math.abs(lx) - p.sx / 2, math.abs(lz) - p.sz / 2
				if ax <= 0 and az <= 0 then
					if ax > -1.5 or az > -1.5 then
						put(px, py, 25, 25, 30)
					else
						put(px, py, shadeColor[1], shadeColor[2], shadeColor[3])
					end
				end
			end
		end
	end
end

-- Pads.
for _, pad in realm.pads do
	local x0, z0 = toPixel(pad.x0, pad.z0)
	local x1, z1 = toPixel(pad.x1, pad.z1)
	for px = x0, x1 do
		put(px, z0, 255, 255, 255)
		put(px, z1, 255, 255, 255)
	end
	for py = z0, z1 do
		put(x0, py, 255, 255, 255)
		put(x1, py, 255, 255, 255)
	end
end

-- 3 x 5 bitmap font for labels.
local GLYPHS: { [string]: string } = {
	a = "010101111101101",
	b = "110101110101110",
	c = "011100100100011",
	d = "110101101101110",
	e = "111100110100111",
	f = "111100110100100",
	g = "011100101101011",
	h = "101101111101101",
	i = "111010010010111",
	j = "001001001101010",
	k = "101101110101101",
	l = "100100100100111",
	m = "101111111101101",
	n = "110101101101101",
	o = "010101101101010",
	p = "110101110100100",
	q = "010101101110011",
	r = "110101110101101",
	s = "011100010001110",
	t = "111010010010010",
	u = "101101101101111",
	v = "101101101101010",
	w = "101101111111101",
	x = "101101010101101",
	y = "101101010010010",
	z = "111001010100111",
	["-"] = "000000111000000",
	["0"] = "111101101101111",
	["1"] = "010110010010111",
	["2"] = "110001010100111",
	["3"] = "110001010001110",
	["4"] = "101101111001001",
	["5"] = "111100110001110",
	["6"] = "011100111101111",
	["7"] = "111001010010010",
	["8"] = "111101111101111",
	["9"] = "111101111001110",
	["+"] = "000010111010000",
}

local function label(text: string, cx: number, cy: number)
	local size = 2
	local w = #text * 4 * size
	local x = cx - w // 2
	for n = 1, #text do
		local glyph = GLYPHS[string.sub(text, n, n)]
		if glyph then
			for gy = 0, 4 do
				for gx = 0, 2 do
					if string.sub(glyph, gy * 3 + gx + 1, gy * 3 + gx + 1) == "1" then
						for sy = 0, size - 1 do
							for sx = 0, size - 1 do
								put(x + gx * size + sx, cy + gy * size + sy, 255, 240, 120)
							end
						end
					end
				end
			end
		end
		x += 4 * size
	end
end

for _, node in graph.nodes do
	local px, py = toPixel(node.x, node.z)
	for dy = -3, 3 do
		for dx = -3, 3 do
			put(px + dx, py + dy, 255, 60, 60)
		end
	end
	label(`{node.id} {math.floor(node.floor)}`, px, py + 6)
end

fs.writeDir("build")
local out = `build/worldgen-{sectionName}.png`
fs.writeFile(out, Png.encode(width, height, pixels))
print(string.format("%s: %d parts, %.1fs", out, partCount, os.clock() - started))
