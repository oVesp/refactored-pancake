--!strict

-- Base heightfield (docs/systems/world-generation.md, phase F2): a low valley follows the
-- gameplay pads, rivers and lake; hills rise with distance and each region reshapes them
-- (snowy mountains north, highlands, flat swamp west, rolling plains east, sea south). Pads are
-- flattened to padHeight last.
local Grid = require("./Grid")
local Noise = require("./Noise")

local Heightfield = {}

export type Maps = {
	height: Grid.Grid,
	padDistance: Grid.Grid,
	creekDistance: Grid.Grid, -- shifted so every river's channel edge sits at water.creekWidth
	creekT: Grid.Grid, -- arc length along the nearest river
	creekRiver: Grid.Grid, -- index of the nearest river
	lakeDistance: Grid.Grid,
	mountain: Grid.Grid, -- region weights 0..1 (Layout.regions)
	highland: Grid.Grid,
	swamp: Grid.Grid,
	plains: Grid.Grid,
	coast: Grid.Grid,
}

--[=[ Squashes heights above `knee` so peaks stay within the terrain write budget. ]=]
local function softCap(h: number, knee: number): number
	return if h > knee then knee + (h - knee) * 0.5 else h
end

function Heightfield.generate(cfg: any, layout: any): Maps
	local n, cell = cfg.n, cfg.cell
	local hf = cfg.heightfield
	local w = cfg.world
	local seed = cfg.seed
	local hills = Noise.fbm(Noise.layerSeed(seed, "hills"), hf.hillWavelength, 3, 2, 0.5)
	local ridge = Noise.ridged(Noise.layerSeed(seed, "ridge"), 420, 5, 2, 0.5)
	local mountains = Noise.ridged(Noise.layerSeed(seed, "mountains"), w.mountains.wavelength, 5, 2, 0.5)
	local plainsRoll = Noise.fbm(Noise.layerSeed(seed, "plainsRoll"), 700, 3, 2, 0.5)
	local swampRoll = Noise.fbm(Noise.layerSeed(seed, "swampRoll"), 220, 3, 2, 0.5)
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
		creekRiver = Grid.new(n),
		lakeDistance = Grid.new(n),
		mountain = Grid.new(n),
		highland = Grid.new(n),
		swamp = Grid.new(n),
		plains = Grid.new(n),
		coast = Grid.new(n),
	}
	for j = 0, n - 1 do
		local z = cfg.originZ + (j + 0.5) * cell
		for i = 0, n - 1 do
			local x = cfg.originX + (i + 0.5) * cell
			local dp = layout.padDistance(x, z)
			local rawDc, tc, ri = layout.riverDistance(x, z)
			local dc = rawDc - (layout.rivers[ri].width - cfg.water.creekWidth)
			local dl = layout.lakeDistance(x, z)
			local reg = layout.regions(x, z)

			-- Start-valley shape: low ground along pads, rivers and the lake, hills farther out.
			local corridor = math.min(dp, dc + 50, math.max(dl, 0) + 40)
			local valley = Noise.smoothstep(hf.valleyNear, hf.valleyFar, corridor)
			local amp = hf.hillAmp + hf.hillAmpVariation * hills(x, z)
			local ampScale = 1 + (w.highlands.ampScale - 1) * reg.highland
			ampScale = ampScale * (1 - reg.swamp - reg.plains)
				+ w.swamp.ampScale * reg.swamp
				+ w.plains.ampScale * reg.plains
			local h = valley ^ hf.redistribution * amp * ampScale
			h += reg.plains * (w.plains.height + plainsRoll(x, z) * 18)
			h += reg.swamp * (w.swamp.height + swampRoll(x, z) * w.swamp.roll)
			h += reg.highland * 60

			-- North barrier ridge behind the goblin camp, open at both ends.
			local north = Noise.smoothstep(hf.ridgeStartZ, hf.ridgeFullZ, z)
				* Noise.smoothstep(hf.ridgeHalfWidth + 500, hf.ridgeHalfWidth, math.abs(x))
				* (1 - reg.mountain)
			h += north * (0.45 + 0.55 * ridge(x, z)) * hf.ridgeHeight
			h += reg.mountain * (0.35 + 0.65 * mountains(x, z)) * w.mountains.height

			-- North, east and west world edges lift; the south opens to the sea.
			local edge = math.min(i, j, n - 1 - i) * cell
			h += Noise.smoothstep(hf.borderWidth, 0, edge) * hf.borderHeight * (0.7 + 0.3 * hills(z, x))
			h += detail(x, z) * (3 + 28 * valley) * (1 - 0.8 * reg.swamp)
			h = softCap(h, 480)
			h = Noise.lerp(h, w.coast.seaFloor, reg.coast)

			local lakeTarget = cfg.waterLevel
				- cfg.water.lakeDepth * Noise.smoothstep(0, -80, dl)
				+ math.max(dl, 0) * 0.15
			h = Noise.lerp(h, lakeTarget, Noise.smoothstep(90, 0, dl))
			Grid.set(maps.height, i, j, h)
			Grid.set(maps.padDistance, i, j, dp)
			Grid.set(maps.creekDistance, i, j, dc)
			Grid.set(maps.creekT, i, j, tc)
			Grid.set(maps.creekRiver, i, j, ri)
			Grid.set(maps.lakeDistance, i, j, dl)
			Grid.set(maps.mountain, i, j, reg.mountain)
			Grid.set(maps.highland, i, j, reg.highland)
			Grid.set(maps.swamp, i, j, reg.swamp)
			Grid.set(maps.plains, i, j, reg.plains)
			Grid.set(maps.coast, i, j, reg.coast)
		end
	end
	return maps
end

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
