--!strict

-- Top-down preview of the continent (docs/systems/world-generation.md).
-- Run from the repo root: `lune run tools/worldgen/continent [seed]` (default: the template seed).
-- Writes build/continent-<seed>.png: biomes with hillshade, mountains, coast, lakes, territory
-- borders in faction colours, roads and sites, with labels for the named sites.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("../../tests/Loader")
local Png = require("./Png")
local Font = require("./Font")

local Continent = Loader.load("src/ServerStorage/WorldGen/Gen/Continent")
local template = Loader.load("src/ServerStorage/WorldGen/Continent")

local SCALE = 4

local seed = tonumber(process.args[1]) or template.seed
local started = os.clock()
local map = Continent.generate(template, seed)
print(
	string.format("generated seed %d in %.1fs: %d sites, %d roads", seed, os.clock() - started, #map.sites, #map.roads)
)

local res = map.res
local width = res * SCALE
local pixels = buffer.create(width * width * 3)

local function put(px: number, py: number, c: { number }, alpha: number?)
	if px < 0 or py < 0 or px >= width or py >= width then
		return
	end
	local o = (py * width + px) * 3
	local a = alpha or 1
	for n = 0, 2 do
		local old = buffer.readu8(pixels, o + n)
		buffer.writeu8(pixels, o + n, math.clamp(math.round(old * (1 - a) + c[n + 1] * a), 0, 255))
	end
end

local function regionAt(i: number, j: number): number
	if i < 0 or j < 0 or i >= res or j >= res then
		return Continent.SEA
	end
	return map.region[Continent.index(res, i, j)]
end

local biomes = template.biomes
local regionDefs = template.regions

-- Ground.
for j = 0, res - 1 do
	for i = 0, res - 1 do
		local k = Continent.index(res, i, j)
		local r = map.region[k]
		local color: { number }
		local shade = 1
		if r == Continent.SEA then
			color = biomes.sea.color
		elseif r == Continent.LAKE then
			color = biomes.lake.color
		else
			color = if map.mountain[k] then biomes.mountain.color else biomes[regionDefs[r].biome].color
			local west = if i > 0 then map.height[k - 1] else map.height[k]
			local north = if j > 0 then map.height[k - res] else map.height[k]
			shade = math.clamp(1 + (map.height[k] * 2 - west - north) * 12, 0.7, 1.25)
		end
		local c = { color[1] * shade, color[2] * shade, color[3] * shade }
		for sy = 0, SCALE - 1 do
			for sx = 0, SCALE - 1 do
				put(i * SCALE + sx, j * SCALE + sy, c)
			end
		end
	end
end

-- Coast and region borders (thin), territory borders (faction colour).
local function ownerOf(r: number): string?
	return if r > 0 then regionDefs[r].owner else nil
end
for j = 0, res - 1 do
	for i = 0, res - 1 do
		local r = regionAt(i, j)
		if r ~= Continent.SEA then
			for _, d in { { 1, 0 }, { 0, 1 } } do
				local o = regionAt(i + d[1], j + d[2])
				if o ~= r then
					local px, py = i * SCALE, j * SCALE
					local line: { number } = { 20, 30, 34 }
					local alpha = 0.5
					local owner = ownerOf(r)
					if o == Continent.SEA then
						alpha = 0.8
					elseif owner ~= ownerOf(o) and owner and template.factionColors[owner] then
						line = template.factionColors[owner]
						alpha = 0.9
					end
					for n = 0, SCALE - 1 do
						if d[1] == 1 then
							put(px + SCALE - 1, py + n, line, alpha)
						else
							put(px + n, py + SCALE - 1, line, alpha)
						end
					end
				end
			end
		end
	end
end

-- Roads.
local ROAD = { 92, 64, 40 }
for _, road in map.roads do
	for n = 2, #road.cells do
		local u0, v0 = Continent.center(res, road.cells[n - 1])
		local u1, v1 = Continent.center(res, road.cells[n])
		for t = 0, SCALE - 1 do
			local f = t / SCALE
			local px = math.floor((u0 + (u1 - u0) * f) * width)
			local py = math.floor((v0 + (v1 - v0) * f) * width)
			put(px, py, ROAD, 0.9)
			put(px - 1, py, ROAD, 0.9)
		end
	end
end

-- Sites: square for settlements, diamond for dungeons, triangle-ish dot for points of interest.
local MARK: { [string]: { size: number, color: { number } } } = {
	capital = { size = 6, color = { 255, 214, 64 } },
	city = { size = 5, color = { 255, 255, 255 } },
	harbor = { size = 6, color = { 255, 214, 64 } },
	town = { size = 3, color = { 240, 240, 240 } },
	poi = { size = 2, color = { 60, 200, 230 } },
	dungeon = { size = 3, color = { 200, 40, 40 } },
	portal = { size = 6, color = { 190, 90, 255 } },
}
for _, site in map.sites do
	local mark = MARK[site.kind]
	local cx, cy = math.floor(site.u * width), math.floor(site.v * width)
	local s = mark.size
	for dy = -s - 1, s + 1 do
		for dx = -s - 1, s + 1 do
			local diamond = site.kind == "dungeon" or site.kind == "portal"
			local inside = if diamond
				then math.abs(dx) + math.abs(dy) <= s
				else math.max(math.abs(dx), math.abs(dy)) <= s
			local edge = if diamond
				then math.abs(dx) + math.abs(dy) <= s + 1
				else math.max(math.abs(dx), math.abs(dy)) <= s + 1
			if inside then
				put(cx + dx, cy + dy, mark.color)
			elseif edge then
				put(cx + dx, cy + dy, { 0, 0, 0 })
			end
		end
	end
	if site.name ~= "" then
		Font.label(put, string.lower(site.name), cx, cy + s + 4, { 255, 244, 200 })
	end
end

-- Region names at the centroid of their cells.
for index, region in regionDefs do
	local su, sv, n = 0, 0, 0
	for k = 1, res * res do
		if map.region[k] == index then
			local u, v = Continent.center(res, k)
			su += u
			sv += v
			n += 1
		end
	end
	if n > 0 then
		Font.label(put, string.lower(region.name), math.floor(su / n * width), math.floor(sv / n * width) - 14, {
			20,
			20,
			24,
		})
	end
end

fs.writeDir("build")
local path = `build/continent-{seed}.png`
fs.writeFile(path, Png.encode(width, width, pixels))
print(`wrote {path}`)
