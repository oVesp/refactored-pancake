--!strict

-- Generates the Midgard terrain tile and prop scatter (docs/systems/world-generation.md).
-- Run from the repo root: `lune run tools/terrain/build`. Output is deterministic; commit it.
-- Writes src/ServerStorage/WorldGen/Data/* for the Studio applier and a preview image to build/.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Config = require("./lib/Config")
local Encode = require("./lib/Encode")
local Erosion = require("./lib/Erosion")
local Grid = require("./lib/Grid")
local Heightfield = require("./lib/Heightfield")
local Layout = require("./lib/Layout")
local Materials = require("./lib/Materials")
local Noise = require("./lib/Noise")
local Paths = require("./lib/Paths")
local Scatter = require("./lib/Scatter")
local Water = require("./lib/Water")

local OUT = "src/ServerStorage/WorldGen/Data"
local CHUNK_ROWS = 32
local SCATTER_BAND = 2048

local started = os.clock()
local function step(label: string)
	print(string.format("%6.1fs  %s", os.clock() - started, label))
end

local cfg = Config
local n = cfg.n
local map = roblox.deserializeModel(fs.readFile("src/Workspace/Map.rbxmx"))[1]
local layout = Layout.build(cfg, map)
step(`layout: {#layout.pads} pads, {#layout.blockers} blockers`)

local maps = Heightfield.generate(cfg, layout)
step("heightfield")

local mask = Grid.new(n)
for j = 0, n - 1 do
	for i = 0, n - 1 do
		local protect = math.max(
			1 - math.clamp((Grid.get(maps.padDistance, i, j) - 30) / 50, 0, 1),
			1 - math.clamp(Grid.get(maps.lakeDistance, i, j) / 40, 0, 1),
			1 - math.clamp((Grid.get(maps.creekDistance, i, j) - cfg.water.creekBank) / 20, 0, 1),
			Noise.smoothstep(0.3, 0.6, Grid.get(maps.coast, i, j)),
			-- Keep the swamp flat: droplets would fill its pools with sediment.
			0.8 * Grid.get(maps.swamp, i, j)
		)
		Grid.set(mask, i, j, 1 - protect)
	end
end
local erosion = Erosion.hydraulic(cfg, maps.height, mask)
local deepest, moved = 0, 0
for k = 0, n * n - 1 do
	local cut = buffer.readf32(erosion.wear.data, k * 4)
	deepest = math.max(deepest, cut)
	moved += cut
end
step(string.format("hydraulic erosion: deepest cut %.1f studs, mean %.2f", deepest, moved / (n * n)))
Erosion.thermal(cfg, maps.height, mask)
step("thermal erosion")

local water = Water.carve(cfg, maps, layout)
step("creek, lake and flow")
Heightfield.flattenPads(cfg, maps)

local pois = Paths.pickPois(cfg, maps, water)
local sites = Paths.pickSites(cfg, maps, water)
local poiMask = Grid.new(n)
local function markSite(poi: any, radius: number, inner: number)
	local ci = math.floor((poi.x - cfg.originX) / cfg.cell)
	local cj = math.floor((poi.z - cfg.originZ) / cfg.cell)
	local r = math.ceil((radius + 6) / cfg.cell)
	for dj = -r, r do
		for di = -r, r do
			local d = math.sqrt(di * di + dj * dj) * cfg.cell
			if d <= radius + 6 then
				Grid.set(poiMask, ci + di, cj + dj, if d < inner then 2 else 1)
			end
		end
	end
end
for _, poi in pois do
	markSite(poi, cfg.paths.poiRadius, 8)
end
for _, site in sites do
	markSite(site, cfg.paths.siteRadius, 0)
end
step(`points of interest: {#pois} lookouts, {#sites} region sites`)

-- Trails in the start valley (village to the lake shore, to the west lookout across the creek,
-- orchard to the east lookout), then wider roads out to each region site.
local pathMask = Grid.new(n)
local shoreX, shoreZ = Paths.shorePoint(cfg, maps, 60, 120, 10, 18)
local poiByName: { [string]: any } = {}
for _, poi in pois do
	poiByName[poi.name] = poi
end
for _, site in sites do
	poiByName[site.name] = site
end
local trail, road = cfg.paths.halfWidth, cfg.paths.roadHalfWidth
type Route = { name: string, from: string | { number }, to: string | { number }, width: number, tiles: boolean }
local routes: { Route } = {
	{ name = "LakeTrail", from = { -94, 96 }, to = { shoreX, shoreZ }, width = trail, tiles = true },
	{ name = "WestTrail", from = { -94, 96 }, to = "LookoutWest", width = trail, tiles = true },
	{ name = "EastTrail", from = { 118, -440 }, to = "LookoutEast", width = trail, tiles = true },
	{ name = "NorthRoad", from = { 0, -790 }, to = "SiteHighlands", width = road, tiles = false },
	{ name = "PassRoad", from = "SiteHighlands", to = "SiteMountains", width = road, tiles = false },
	{ name = "WestRoad", from = { -260, 0 }, to = "SiteSwamp", width = road, tiles = false },
	{ name = "EastRoad", from = { 130, -300 }, to = "SitePlains", width = road, tiles = false },
	{ name = "SouthRoad", from = { 0, 110 }, to = "SiteCoast", width = road, tiles = false },
}
local function resolve(target: string | { number }): { number }?
	if typeof(target) == "string" then
		local poi = poiByName[target]
		return if poi then { poi.x, poi.z } else nil
	end
	return target
end
local trails, startTrails = {}, {}
for _, route in routes do
	local from, to = resolve(route.from), resolve(route.to)
	if from and to then
		local pts = Paths.findPath(cfg, maps, water, from[1], from[2], to[1], to[2])
		local carved = Paths.carve(cfg, maps, water, pts, pathMask, route.width)
		table.insert(trails, { name = route.name, points = carved })
		if route.tiles then
			table.insert(startTrails, { name = route.name, points = carved })
		end
	end
end
step(`trails and roads: {#trails}`)

local surface = Materials.classify(cfg, layout, maps, water, {
	wear = erosion.wear,
	pathMask = pathMask,
	poiMask = poiMask,
})
step("biomes and materials")

local placements = Scatter.run(cfg, layout, maps, water, surface, startTrails)
step(`scatter: {#placements} props`)

-- Terrain columns: height u16, material u8, water surface u16 (0 = dry).
if fs.isDir(OUT) then
	fs.removeDir(OUT)
end
fs.writeDir(OUT)
local chunks = n // CHUNK_ROWS
local lo, hi = Grid.range(maps.height)
for c = 0, chunks - 1 do
	local data = buffer.create(CHUNK_ROWS * n * 5)
	local o = 0
	for j = c * CHUNK_ROWS, (c + 1) * CHUNK_ROWS - 1 do
		for i = 0, n - 1 do
			local h = Grid.get(maps.height, i, j)
			local ws = Grid.get(water.surface, i, j)
			buffer.writeu16(data, o, Encode.height(h))
			buffer.writeu8(data, o + 2, buffer.readu8(surface.material, i + j * n))
			buffer.writeu16(data, o + 3, if ws > h then Encode.height(ws) else 0)
			o += 5
		end
	end
	fs.writeFile(string.format("%s/Terrain%02d.luau", OUT, c + 1), Encode.stringModule(Encode.base64(data)))
end

-- Props, one module per layer. Line: asset index, x, y, z, yaw, up.x, up.z, scale.
local assets: { any } = {}
local assetIndex: { [string]: number } = {}
local groupNames = {}
for name in cfg.groups do
	table.insert(groupNames, name)
end
table.sort(groupNames)
for _, groupName in groupNames do
	local group = cfg.groups[groupName]
	for _, a in group.assets do
		table.insert(assets, {
			name = a.name,
			group = groupName,
			layer = group.layer,
			collide = group.collide,
			shadow = group.shadow,
			sink = a.sink,
		})
		assetIndex[a.name] = #assets
	end
end
local layerOrder = { "Paths", "Trees", "Rocks", "Understory", "Cover", "Pebbles" }
-- Each layer is split into bands of SCATTER_BAND studs along Z so no module grows past a few
-- hundred kilobytes.
local bands = math.ceil(n * cfg.cell / SCATTER_BAND)
local byLayer: { [string]: { { string } } } = {}
for _, layer in layerOrder do
	byLayer[layer] = {}
	for band = 1, bands do
		byLayer[layer][band] = {}
	end
end
for _, p in placements do
	local layer = cfg.groups[p.group].layer
	local band = math.clamp(math.floor((p.z - cfg.originZ) / SCATTER_BAND) + 1, 1, bands)
	table.insert(
		byLayer[layer][band],
		string.format(
			"%d %.1f %.2f %.1f %.0f %.3f %.3f %.2f",
			assetIndex[p.asset],
			p.x,
			p.y,
			p.z,
			p.yaw % 360,
			p.ux,
			p.uz,
			p.scale
		)
	)
end
local layers = {}
for _, layer in layerOrder do
	local modules, count = {}, 0
	for band, lines in byLayer[layer] do
		if #lines > 0 then
			local name = `Scatter{layer}{band}`
			fs.writeFile(`{OUT}/{name}.luau`, Encode.linesModule(lines))
			table.insert(modules, name)
			count += #lines
		end
	end
	table.insert(layers, { name = layer, modules = modules, count = count })
end

local colors = {}
for name, rgb in cfg.materialColors do
	colors[name] = rgb
end
local poiList = {}
for _, poi in table.move(sites, 1, #sites, #pois + 1, table.clone(pois)) do
	table.insert(
		poiList,
		{ name = poi.name, x = math.floor(poi.x), y = math.floor(poi.y * 10) / 10, z = math.floor(poi.z) }
	)
end
fs.writeFile(
	`{OUT}/Meta.luau`,
	Encode.tableModule({
		version = 1,
		seed = cfg.seed,
		originX = cfg.originX,
		originZ = cfg.originZ,
		n = n,
		cell = cfg.cell,
		floorY = cfg.floorY,
		minHeight = math.floor(lo),
		maxHeight = math.ceil(hi),
		chunkRows = CHUNK_ROWS,
		chunks = chunks,
		materials = cfg.materials,
		materialColors = colors,
		assets = assets,
		layers = layers,
		pois = poiList,
	})
)
step(`wrote {OUT}`)

-- Preview: shaded relief tinted by material, water blue, trees dark dots (build/, not committed).
local palette = {
	Grass = { 96, 128, 68 },
	LeafyGrass = { 66, 96, 50 },
	Ground = { 120, 100, 76 },
	Mud = { 84, 70, 54 },
	Sand = { 180, 168, 132 },
	Rock = { 128, 128, 124 },
	Slate = { 96, 100, 104 },
	Pavement = { 150, 144, 132 },
	Snow = { 236, 240, 244 },
	Glacier = { 180, 208, 226 },
	Sandstone = { 160, 136, 104 },
}
local img = buffer.create(n * n * 3)
for j = 0, n - 1 do
	for i = 0, n - 1 do
		local k = i + j * n
		local m = cfg.materials[buffer.readu8(surface.material, k)]
		local c = palette[m]
		local gx, gz = Grid.gradient(maps.height, i, j, cfg.cell)
		local shade = math.clamp(0.85 - (gx * 0.6 + gz * 0.6), 0.45, 1.25)
		local r, g, b = c[1] * shade, c[2] * shade, c[3] * shade
		local h = Grid.get(maps.height, i, j)
		local ws = Grid.get(water.surface, i, j)
		if ws > h then
			local depth = math.clamp((ws - h) / 20, 0, 1)
			r, g, b = 70 - depth * 40, 110 - depth * 40, 150 - depth * 30
		end
		buffer.writeu8(img, k * 3, math.clamp(math.floor(r), 0, 255))
		buffer.writeu8(img, k * 3 + 1, math.clamp(math.floor(g), 0, 255))
		buffer.writeu8(img, k * 3 + 2, math.clamp(math.floor(b), 0, 255))
	end
end
local dotColors = { Trees = { 20, 50, 20 }, Rocks = { 200, 200, 200 }, Paths = { 230, 210, 160 } }
for _, p in placements do
	local dot = dotColors[cfg.groups[p.group].layer]
	if dot then
		local i = math.floor((p.x - cfg.originX) / cfg.cell)
		local j = math.floor((p.z - cfg.originZ) / cfg.cell)
		local k = i + j * n
		buffer.writeu8(img, k * 3, dot[1])
		buffer.writeu8(img, k * 3 + 1, dot[2])
		buffer.writeu8(img, k * 3 + 2, dot[3])
	end
end
fs.writeDir("build")
fs.writeFile("build/terrain-preview.ppm", `P6\n{n} {n}\n255\n` .. buffer.tostring(img))
step("preview written to build/terrain-preview.ppm")
