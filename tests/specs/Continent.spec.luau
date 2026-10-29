--!strict

-- Continent generator (src/ServerStorage/WorldGen/Gen/Continent, docs/systems/world-generation.md).
local Expect = require("../Expect")
local Loader = require("../Loader")

local Continent = Loader.load("src/ServerStorage/WorldGen/Gen/Continent")
local Template = Loader.load("src/ServerStorage/WorldGen/Continent")

local RES = 128
local SEEDS = { Template.seed, 1, 2, 3, 7, 42, 1337, 90210 }

local cache: { [number]: any } = {}
local function map(seed: number): any
	if not cache[seed] then
		cache[seed] = Continent.generate(Template, seed, RES)
	end
	return cache[seed]
end

local function regionDef(id: string): any
	for _, region in Template.regions do
		if region.id == id then
			return region
		end
	end
	return nil
end

local SETTLEMENT = { capital = true, city = true, town = true, harbor = true }

return {
	["the same seed gives the same continent"] = function()
		local a = map(Template.seed)
		local b = Continent.generate(Template, Template.seed, RES)
		for k = 1, RES * RES do
			Expect.equal(a.region[k], b.region[k])
			Expect.equal(a.mountain[k], b.mountain[k])
		end
		Expect.equal(#a.sites, #b.sites)
		for n, site in a.sites do
			Expect.equal(site.cell, b.sites[n].cell)
		end
		Expect.equal(#a.roads, #b.roads)
	end,

	["different seeds give different continents"] = function()
		local a, b = map(1), map(2)
		local diff = 0
		for k = 1, RES * RES do
			if a.region[k] ~= b.region[k] then
				diff += 1
			end
		end
		Expect.truthy(diff > RES * RES * 0.02, `only {diff} cells differ`)
	end,

	["every region exists and holds together"] = function()
		for _, seed in SEEDS do
			local m = map(seed)
			for index, region in Template.regions do
				local cells: { [number]: boolean } = {}
				local count, first = 0, 0
				for k = 1, RES * RES do
					if m.region[k] == index then
						cells[k] = true
						count += 1
						first = if first == 0 then k else first
					end
				end
				Expect.truthy(count > 0, `seed {seed}: no {region.id}`)
				if not region.scatter then
					-- Largest 4-connected piece holds most of the region.
					local best = 0
					local seen: { [number]: boolean } = {}
					for start in cells do
						if not seen[start] then
							local size, stack = 0, { start }
							seen[start] = true
							while #stack > 0 do
								local k = table.remove(stack) :: number
								size += 1
								local i = (k - 1) % RES
								for _, n in
									{ if i > 0 then k - 1 else 0, if i < RES - 1 then k + 1 else 0, k - RES, k + RES }
								do
									if cells[n] and not seen[n] then
										seen[n] = true
										table.insert(stack, n)
									end
								end
							end
							best = math.max(best, size)
						end
					end
					Expect.truthy(best >= count * 0.8, `seed {seed}: {region.id} split ({best}/{count})`)
				end
			end
		end
	end,

	["adventurers hold exactly the central capital and the harbor"] = function()
		for _, seed in SEEDS do
			local m = map(seed)
			local capitals, harbors = {}, {}
			for _, site in m.sites do
				if site.owner == "Adventurers" then
					if site.kind == "capital" then
						table.insert(capitals, site)
					elseif site.kind == "harbor" then
						table.insert(harbors, site)
					else
						error(`seed {seed}: adventurer site {site.id} is a {site.kind}`)
					end
				end
			end
			Expect.equal(#capitals, 1)
			Expect.equal(#harbors, 1)
			local capital, harbor = capitals[1], harbors[1]
			Expect.truthy(
				capital.u > 0.3 and capital.u < 0.7 and capital.v > 0.25 and capital.v < 0.6,
				"capital not central"
			)
			Expect.truthy(harbor.u < 0.45 and harbor.v > 0.6, "harbor not in the south-west")
			Expect.truthy(m.coast[harbor.cell], `seed {seed}: harbor off the coast`)
		end
	end,

	["each empire has one capital inside its territory"] = function()
		for _, seed in SEEDS do
			local m = map(seed)
			for _, empire in { "HolyKingdom", "DragonEmpire" } do
				local found = 0
				for _, site in m.sites do
					if site.owner == empire and site.kind == "capital" then
						found += 1
						Expect.equal(regionDef(site.region).owner, empire)
					end
				end
				Expect.equal(found, 1)
			end
		end
	end,

	["sites stand on dry ground in their region"] = function()
		for _, seed in SEEDS do
			local m = map(seed)
			local ids: { [string]: boolean } = {}
			for _, site in m.sites do
				Expect.truthy(not ids[site.id], `seed {seed}: duplicate site {site.id}`)
				ids[site.id] = true
				local r = m.region[site.cell]
				Expect.truthy(r > 0, `seed {seed}: {site.id} in water`)
				Expect.equal(m.regionIds[r], site.region)
				if SETTLEMENT[site.kind] then
					Expect.truthy(not m.mountain[site.cell], `seed {seed}: {site.id} on a mountain`)
				end
			end
		end
	end,

	["roads reach every mainland settlement"] = function()
		for _, seed in SEEDS do
			local m = map(seed)
			local links: { [string]: { string } } = {}
			for _, road in m.roads do
				links[road.a] = links[road.a] or {}
				links[road.b] = links[road.b] or {}
				table.insert(links[road.a], road.b)
				table.insert(links[road.b], road.a)
			end
			local reached: { [string]: boolean } = { ["central-capital"] = true }
			local stack = { "central-capital" }
			while #stack > 0 do
				for _, other in links[table.remove(stack) :: string] or {} do
					if not reached[other] then
						reached[other] = true
						table.insert(stack, other)
					end
				end
			end
			for _, site in m.sites do
				if SETTLEMENT[site.kind] and m.mainland[site.cell] and not regionDef(site.region).sky then
					Expect.truthy(reached[site.id], `seed {seed}: no road to {site.id}`)
				end
			end
		end
	end,
}
