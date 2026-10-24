--!strict

-- Base heightfield (docs/systems/world-generation.md, phase F2): a low valley follows the
-- gameplay pads, creek and lake; hills rise with distance, a ridged barrier closes the north and
-- the tile edges lift so the world reads enclosed. Pads are flattened to height 0 last.
local Grid = require("./Grid")
local Noise = require("./Noise")

local Heightfield = {}

export type Maps = {
	height: Grid.Grid,
	padDistance: Grid.Grid,
	creekDistance: Grid.Grid,
	creekT: Grid.Grid,
	lakeDistance: Grid.Grid,
}

function Heightfield.generate(cfg: any, layout: any): Maps
	local n, cell = cfg.n, cfg.cell
	local hf = cfg.heightfield
	local seed = cfg.seed
	local hills = Noise.fbm(Noise.layerSeed(seed, "hills"), hf.hillWavelength, 3, 2, 0.5)
	local ridge = Noise.ridged(Noise.layerSeed(seed, "ridge"), 420, 5, 2, 0.5)
	local detail = Noise.warp(
		Noise.layerSeed(seed, "warp"),
		Noise.fbm(Noise.layerSeed(seed, "detail"), hf.detailWavelength, hf.detailOctaves, 2, 0.5),
		hf.detailWavelength,
		hf.warpStrength
	)
	local maps: Maps = {
		height = Grid.new(n),
		padDistance = Grid.new(n),
		creekDistance = Grid.new(n),
		creekT = Grid.new(n),
		lakeDistance = Grid.new(n),
	}

	for j = 0, n - 1 do
		local z = cfg.originZ + (j + 0.5) * cell
		for i = 0, n - 1 do
			local x = cfg.originX + (i + 0.5) * cell
			local dp = layout.padDistance(x, z)
			local dc, tc = layout.creekDistance(x, z)
			local dl = layout.lakeDistance(x, z)

			local corridor = math.min(dp, dc + 50, math.max(dl, 0) + 40)
			local valley = Noise.smoothstep(hf.valleyNear, hf.valleyFar, corridor)
			local amp = hf.hillAmp + hf.hillAmpVariation * hills(x, z)
			local h = valley ^ hf.redistribution * amp

			local north = Noise.smoothstep(hf.ridgeStartZ, hf.ridgeFullZ, z)
			h += north * (0.45 + 0.55 * ridge(x, z)) * hf.ridgeHeight

			local edge = math.min(i, j, n - 1 - i, n - 1 - j) * cell
			h += Noise.smoothstep(hf.borderWidth, 0, edge) * hf.borderHeight * (0.7 + 0.3 * hills(z, x))

			h += detail(x, z) * (3 + 28 * valley)

			-- Lake basin: the shoreline sits at the water level and the bed sinks inward.
			local lakeTarget = cfg.waterLevel
				- cfg.water.lakeDepth * Noise.smoothstep(0, -80, dl)
				+ math.max(dl, 0) * 0.15
			h = Noise.lerp(h, lakeTarget, Noise.smoothstep(90, 0, dl))

			Grid.set(maps.height, i, j, h)
			Grid.set(maps.padDistance, i, j, dp)
			Grid.set(maps.creekDistance, i, j, dc)
			Grid.set(maps.creekT, i, j, tc)
			Grid.set(maps.lakeDistance, i, j, dl)
		end
	end
	return maps
end

--[=[ Blends terrain to height 0 over the gameplay pads and their feather. ]=]
function Heightfield.flattenPads(cfg: any, maps: Maps)
	local n = cfg.n
	local feather = cfg.heightfield.padFeather
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local dp = Grid.get(maps.padDistance, i, j)
			if dp < feather then
				local w = Noise.smoothstep(feather, 4, dp)
				Grid.set(maps.height, i, j, Noise.lerp(Grid.get(maps.height, i, j), cfg.padHeight, w))
			end
		end
	end
end

return Heightfield
