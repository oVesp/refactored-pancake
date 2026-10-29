--!strict

-- Region report (docs/systems/world-generation.md, region builds).
-- Run from the repo root: `lune run tools/worldgen/region <region>`. Prints the build bounds, prop
-- count, site markers and the approval fingerprint, and writes build/region-<region>.png: a
-- top-down view at 8 studs per pixel with ground, water, roads, props and sites.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("../../tests/Loader")
local Png = require("./Png")

local Continent = Loader.load("src/ServerStorage/WorldGen/Gen/Continent")
local Region = Loader.load("src/ServerStorage/WorldGen/Gen/Region")
local template = Loader.load("src/ServerStorage/WorldGen/Continent")

local id = process.args[1] or "verdant"
local started = os.clock()
local ctx = Region.context(template)
local index = Region.index(ctx, id)
local bounds = Region.bounds(ctx, id)
print(string.format("context %.1fs; bounds %d %d %d %d", os.clock() - started, table.unpack(bounds)))

started = os.clock()
local props = Region.props(ctx, id)
print(string.format("%d props in %.1fs", #props, os.clock() - started))
for _, marker in Region.markers(ctx, id) do
	print(string.format("  %-8s %-22s x %6d z %6d y %5.1f", marker.kind, marker.id, marker.x, marker.z, marker.y))
end
started = os.clock()
print(string.format("fingerprint %s in %.1fs", Region.fingerprint(ctx, id), os.clock() - started))

local STEP = 8
local nx = math.floor((bounds[3] - bounds[1]) / STEP)
local nz = math.floor((bounds[4] - bounds[2]) / STEP)
local pixels = buffer.create(nx * nz * 3)
local function put(px: number, py: number, c: { number })
	if px >= 0 and py >= 0 and px < nx and py < nz then
		local o = (py * nx + px) * 3
		for n = 0, 2 do
			buffer.writeu8(pixels, o + n, math.clamp(math.round(c[n + 1]), 0, 255))
		end
	end
end
local COLORS: { [string]: { number } } = {}
for name, rgb in template.materialColors do
	COLORS[name] = rgb
end
started = os.clock()
local previous: { number } = {}
for j = 0, nz - 1 do
	for i = 0, nx - 1 do
		local x, z = bounds[1] + i * STEP, bounds[2] + j * STEP
		local p = ctx.sample(Continent.toUnit(template, x, z))
		local column = Region.column(ctx, index, x, z, p, math.abs(p.height - (previous[i] or p.height)) / 2)
		previous[i] = p.height
		local c = COLORS[column.material] or { 128, 128, 128 }
		local shade = math.clamp(0.75 + column.height / 400, 0.6, 1.3)
		local rgb = { c[1] * shade, c[2] * shade, c[3] * shade }
		if column.water then
			local depth = math.clamp((column.water - column.height) / 40, 0, 1)
			rgb = { 60 - 30 * depth, 110 - 40 * depth, 130 - 30 * depth }
		end
		if not column.owned then
			rgb = { rgb[1] * 0.4, rgb[2] * 0.4, rgb[3] * 0.4 }
		end
		put(i, j, rgb)
	end
end
for _, prop in props do
	local px, py = math.floor((prop.x - bounds[1]) / STEP), math.floor((prop.z - bounds[2]) / STEP)
	put(px, py, if string.find(prop.asset, "Boulder") then { 150, 150, 150 } else { 30, 70, 40 })
end
for _, marker in Region.markers(ctx, id) do
	local px, py = math.floor((marker.x - bounds[1]) / STEP), math.floor((marker.z - bounds[2]) / STEP)
	for dy = -4, 4 do
		for dx = -4, 4 do
			put(px + dx, py + dy, { 255, 214, 64 })
		end
	end
end
print(string.format("image %.1fs", os.clock() - started))
fs.writeDir("build")
fs.writeFile(`build/region-{id}.png`, Png.encode(nx, nz, pixels))
print(`wrote build/region-{id}.png`)
