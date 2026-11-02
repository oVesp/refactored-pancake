--!strict

-- Biomes and terrain materials (phase F4). Roblox terrain holds one material per voxel, so the
-- weighted masks collapse to the first matching rule; a per-column hash dithers rule edges.
local Grid = require("./Grid")
local Noise = require("./Noise")

local Materials = {}

export type Surface = { biome: buffer, material: buffer }

function Materials.classify(cfg: any, layout: any, maps: any, water: any, extra: any): Surface
	local n = cfg.n
	local seed = Noise.layerSeed(cfg.seed, "biome")
	local jitterAt = Noise.fbm(seed, 160, 3, 2, 0.5)
	local patchAt = Noise.fbm(Noise.layerSeed(cfg.seed, "groundPatch"), 48, 2, 2, 0.5)
	local index: { [string]: number } = {}
	for k, name in cfg.materials do
		index[name] = k
	end
	local biome = buffer.create(n * n)
	local material = buffer.create(n * n)
	local threshold = cfg.water.riverThreshold
	local world = cfg.world
	local roadHalfWidth = 0
	for _, r in cfg.roads do
		roadHalfWidth = math.max(roadHalfWidth, r[5])
	end
	local edgeAt = Noise.fbm(Noise.layerSeed(cfg.seed, "roadEdge"), 24, 2, 2, 0.5)
	local function roadWidth(x: number, z: number): number
		return roadHalfWidth + edgeAt(x, z) * 2.5
	end
	local margin = cfg.scatter.padMargin

	for j = 0, n - 1 do
		local z = cfg.originZ + (j + 0.5) * cfg.cell
		for i = 0, n - 1 do
			local x = cfg.originX + (i + 0.5) * cfg.cell
			local k = i + j * n
			local h = Grid.get(maps.height, i, j)
			local slope = Grid.slopeDeg(maps.height, i, j, cfg.cell)
			local dp = Grid.get(maps.padDistance, i, j)
			local dc = Grid.get(maps.creekDistance, i, j)
			local dl = Grid.get(maps.lakeDistance, i, j)
			local ws = Grid.get(water.surface, i, j)
			local wet = ws > h
			local flow = Grid.get(water.flow, i, j)
			local wear = Grid.get(extra.wear, i, j)
			local onPath = Grid.get(extra.pathMask, i, j) > 0
			local poi = Grid.get(extra.poiMask, i, j)
			local jit = jitterAt(x, z)
			local dither = Noise.hash01(seed, i, j) - 0.5
			local road = layout.roadDistance(x, z) - roadWidth(x, z) - dither * 2
			-- Pad materials end on a ragged line so zones do not read as rectangles.
			local pad = if dp <= margin
				then layout.padAt(x + edgeAt(x, z + 300) * 14, z + edgeAt(x + 300, z) * 14)
				else nil

			local mountain = Grid.get(maps.mountain, i, j)
			local upland = mountain + Grid.get(maps.highland, i, j)
			local swamp = Grid.get(maps.swamp, i, j)
			local plains = Grid.get(maps.plains, i, j)
			local coast = Grid.get(maps.coast, i, j)
			local snowLine = world.snowLine + jit * 40

			local b
			if dp <= margin or wet or onPath or poi > 0 or road < margin then
				b = 0
			elseif h > snowLine - 40 then
				b = 11
			elseif slope + dither * 6 > 32 + 4 * jit or (h > 200 + 20 * jit and upland < 0.3) then
				b = 7
			elseif coast > 0.35 and h < 14 + 6 * jit then
				b = 12
			elseif swamp > 0.5 + 0.15 * jit then
				b = if h < 3 and dither > 0 then 6 else 9
			elseif plains > 0.5 + 0.15 * jit then
				b = if dc < 70 + 20 * jit then 5 else 8
			elseif upland > 0.5 + 0.15 * jit then
				b = if h > 150 + 30 * jit then 10 else 4
			elseif
				h < 6
				and slope < 6
				and dp > 90
				and ((dl < 60 + 25 * jit and x < layout.lake.cx) or flow > threshold * 3)
			then
				b = 6
			elseif (dc < 60 + 20 * jit or dl < 90 + 25 * jit) and dp > 120 then
				b = 5
			elseif h > 105 + 25 * jit or z < -880 + 60 * jit then
				b = 4
			elseif dp < 90 + 40 * jit then
				b = 1
			else
				b = 3
			end
			buffer.writeu8(biome, k, b)

			local m
			if onPath or road < 0 then
				m = "Ground"
			elseif pad and cfg.padMaterials[pad] then
				m = cfg.padMaterials[pad]
			elseif poi > 0 then
				m = if poi > 1 then "Pavement" else "Ground"
			elseif wet then
				if dc < cfg.water.creekWidth then
					m = "Ground"
				elseif coast > 0.3 then
					m = "Sand"
				elseif swamp > 0.3 then
					m = "Mud"
				else
					m = if dl > -30 + dither * 10 then "Sand" else "Mud"
				end
			elseif h > world.glacierLine + dither * 30 and slope < 35 then
				m = "Glacier"
			elseif h > snowLine + dither * 20 and slope < 40 + dither * 8 then
				m = "Snow"
			elseif slope + dither * 5 > 42 then
				if coast > 0.3 then
					m = "Sandstone"
				else
					m = if h > 150 or z < -900 then "Rock" else "Slate"
				end
			elseif slope + dither * 6 > 30 and (wear > 0.4 or dither > 0.1) then
				m = if dither > 0.3 then "Rock" else "Ground"
			elseif (dl < 8 + dither * 6 or coast > 0.2) and h < cfg.waterLevel + 3 + dither * 2 then
				m = "Sand"
			elseif dc < cfg.water.creekWidth + 5 + dither * 4 then
				m = "Mud"
			elseif b == 6 then
				m = if dither > 0.2 then "Grass" else "Mud"
			elseif b == 9 then
				m = if h < 3.5 and dither > -0.25 then "Mud" elseif patchAt(x, z) > 0.4 then "Ground" else "LeafyGrass"
			elseif b == 12 then
				m = if dither > 0.35 then "Ground" else "Sand"
			elseif b == 10 then
				local patch = patchAt(x, z)
				m = if patch > 0.3 then "Ground" elseif dither > 0.4 then "Slate" else "Grass"
			elseif b == 11 then
				m = if dither > 0.1 then "Rock" else "Ground"
			elseif b == 3 or b == 4 or b == 5 then
				m = if b == 4 and patchAt(x, z) > 0.35 then "Ground" else "LeafyGrass"
			elseif b == 7 then
				m = if dither > 0.25 then "Rock" else "Ground"
			else
				m = "Grass"
			end
			buffer.writeu8(material, k, index[m])
		end
	end
	return { biome = biome, material = material }
end

return Materials
