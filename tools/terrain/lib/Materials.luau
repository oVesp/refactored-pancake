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

			local b
			if dp <= margin or wet or onPath or poi > 0 then
				b = 0
			elseif slope + dither * 6 > 32 + 4 * jit or h > 200 + 20 * jit then
				b = 7
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
			elseif dp < 170 + 50 * jit then
				b = 1
			else
				b = 3
			end
			buffer.writeu8(biome, k, b)

			local m
			if onPath then
				m = "Ground"
			elseif poi > 0 then
				m = if poi > 1 then "Pavement" else "Ground"
			elseif wet then
				if dc < cfg.water.creekWidth then
					m = "Ground"
				else
					m = if dl > -30 + dither * 10 then "Sand" else "Mud"
				end
			elseif slope + dither * 5 > 42 then
				m = if h > 150 or z < -900 then "Rock" else "Slate"
			elseif slope + dither * 6 > 30 and (wear > 0.4 or dither > 0.1) then
				m = if dither > 0.3 then "Rock" else "Ground"
			elseif dl < 8 + dither * 6 and h < cfg.waterLevel + 3 then
				m = "Sand"
			elseif dc < cfg.water.creekWidth + 5 + dither * 4 then
				m = "Mud"
			elseif b == 6 then
				m = if dither > 0.2 then "Grass" else "Mud"
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
