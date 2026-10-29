--!strict

--[=[
	Field plots for a farmland site: the pad is split by binary space partition into rectangular
	plots with paths between them, each plot with a terrace level, a crop and a furrow direction.
	Pure and seeded per site, so the terrain (`Field`) and the crop placement (`Settlement`) read
	the same plots.
]=]
local Hash = require(script.Parent.Hash)

export type Plot = {
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	level: number, -- studs above the pad
	crop: string, -- key of the site's `crops` weights
	alongX: boolean, -- furrows run along X
	seed: number,
}

local Plots = {}

local function pick(weights: { [string]: number }, roll: number): string
	local names = {}
	local total = 0
	for name, w in weights do
		table.insert(names, name)
		total += w
	end
	table.sort(names)
	local acc = 0
	for _, name in names do
		acc += weights[name] / total
		if roll < acc then
			return name
		end
	end
	return names[#names]
end

--[=[
	Plots for `site` (a `settlements.fields` entry) on `pad`. Areas the site keeps clear (its
	`roads` half-widths along X, as `{ x, half }`) split the pad first; each part is divided until
	plots are under `plotMax` on both sides.
]=]
function Plots.layout(seed: number, site: any, pad: any): { Plot }
	local out: { Plot } = {}
	local margin = site.margin
	local path = site.path
	local rng = Hash.rng(Hash.named(seed, "plots:" .. pad.name))

	-- Columns left between the roads that cross the pad along Z.
	local cuts = { { pad.x0 + margin, pad.x1 - margin } }
	for _, road in site.roads do
		local nextCuts = {}
		for _, c in cuts do
			if road.x - road.half > c[1] and road.x + road.half < c[2] then
				table.insert(nextCuts, { c[1], road.x - road.half - path / 2 })
				table.insert(nextCuts, { road.x + road.half + path / 2, c[2] })
			else
				table.insert(nextCuts, c)
			end
		end
		cuts = nextCuts
	end

	local function split(x0: number, z0: number, x1: number, z1: number, depth: number)
		local w, d = x1 - x0, z1 - z0
		if (w <= site.plotMax and d <= site.plotMax) or depth > 8 then
			local plotSeed = Hash.u32(seed, math.floor(x0), math.floor(z0), depth)
			table.insert(out, {
				x0 = x0,
				z0 = z0,
				x1 = x1,
				z1 = z1,
				level = site.levels[1 + Hash.u32(plotSeed, 1) % #site.levels],
				crop = pick(site.crops, Hash.unit(plotSeed, 2)),
				alongX = w > d,
				seed = plotSeed,
			})
			return
		end
		local alongX = w >= d
		local span = if alongX then w else d
		local cut = span * rng:range(0.38, 0.62)
		if cut - path / 2 < site.plotMin or span - cut - path / 2 < site.plotMin then
			cut = span / 2
		end
		if alongX then
			split(x0, z0, x0 + cut - path / 2, z1, depth + 1)
			split(x0 + cut + path / 2, z0, x1, z1, depth + 1)
		else
			split(x0, z0, x1, z0 + cut - path / 2, depth + 1)
			split(x0, z0 + cut + path / 2, x1, z1, depth + 1)
		end
	end
	for _, c in cuts do
		split(c[1], pad.z0 + margin, c[2], pad.z1 - margin, 0)
	end
	return out
end

--[=[ The plot containing (x, z), or nil on a path or outside. ]=]
function Plots.at(plots: { Plot }, x: number, z: number): Plot?
	for _, p in plots do
		if x >= p.x0 and x <= p.x1 and z >= p.z0 and z <= p.z1 then
			return p
		end
	end
	return nil
end

--[=[ Distance from (x, z) inside a plot to its nearest edge. ]=]
function Plots.inset(p: Plot, x: number, z: number): number
	return math.min(x - p.x0, p.x1 - x, z - p.z0, p.z1 - z)
end

return Plots
