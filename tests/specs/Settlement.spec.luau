--!strict

-- Settlement layout (src/ServerStorage/WorldGen/Gen/Settlement.luau, Plots.luau) and the Map it
-- dresses (docs/systems/world-generation.md).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Expect = require("../Expect")
local Loader = require("../Loader")

local Anchors = Loader.load("src/ServerStorage/WorldGen/Gen/Anchors")
local Field = Loader.load("src/ServerStorage/WorldGen/Gen/Field")
local Graph = Loader.load("src/ServerStorage/WorldGen/Gen/Graph")
local Plots = Loader.load("src/ServerStorage/WorldGen/Gen/Plots")
local Settlement = Loader.load("src/ServerStorage/WorldGen/Gen/Settlement")
local Realm = Loader.load("src/ServerStorage/WorldGen/Midgard")

local ZONES = { "village", "fields", "orchard", "goblin-camp" }

local cached: any = nil
local function world(): any
	if not cached then
		local field = Field.new(Graph.build(Realm))
		local manifest = serde.decode("json", fs.readFile("content/world/village.json"))
		local map = roblox.deserializeModel(fs.readFile("src/Workspace/Map.rbxmx"))[1]
		local anchors = Anchors.fromMap(map, Loader.load("src/ServerStorage/ContentServerOnly/Population"))
		local byZone = {}
		for _, zone in ZONES do
			byZone[zone] = Settlement.forZone(field, manifest, anchors, zone)
		end
		cached = { field = field, manifest = manifest, map = map, anchors = anchors, byZone = byZone }
	end
	return cached
end

local function isFixture(spec: any): boolean
	for _, kind in { "village", "camp" } do
		for _, f in Realm.settlements[kind].fixtures do
			if f.asset == spec.asset and math.abs(f.x - spec.x) < 0.01 and math.abs(f.z - spec.z) < 0.01 then
				return true
			end
		end
	end
	return false
end

local function padNamed(name: string): any
	for _, pad in Realm.pads do
		if pad.name == name then
			return pad
		end
	end
	error(`no pad {name}`)
end

return {
	["plots stay on the pad, apart, off the road and at a listed level"] = function()
		local w = world()
		local site = Realm.settlements.fields
		local pad = padNamed(site.pad)
		Expect.truthy(#w.field.plots >= 8, `{#w.field.plots} plots`)
		for i, p in w.field.plots do
			Expect.truthy(p.x0 >= pad.x0 and p.x1 <= pad.x1 and p.z0 >= pad.z0 and p.z1 <= pad.z1, "inside the pad")
			Expect.truthy(table.find(site.levels, p.level) ~= nil, `level {p.level}`)
			for _, road in site.roads do
				Expect.truthy(p.x1 <= road.x - road.half or p.x0 >= road.x + road.half, "off the road")
			end
			for j, q in w.field.plots do
				if i ~= j then
					local apart = p.x1 <= q.x0 or q.x1 <= p.x0 or p.z1 <= q.z0 or q.z1 <= p.z0
					Expect.truthy(apart, "plots do not overlap")
				end
			end
		end
	end,

	["raised plots lift the terrain to their level, paths stay at the pad"] = function()
		local w = world()
		for _, p in w.field.plots do
			local cx, cz = (p.x0 + p.x1) / 2, (p.z0 + p.z1) / 2
			Expect.truthy(math.abs(w.field.height(cx, cz) - (Realm.padHeight + p.level)) < 0.01, "plot centre")
			local path = w.field.height(p.x1 + Realm.settlements.fields.path / 2, cz)
			if not Plots.at(w.field.plots, p.x1 + Realm.settlements.fields.path / 2, cz) then
				Expect.truthy(math.abs(path - Realm.padHeight) < 0.01, `path height {path}`)
			end
		end
	end,

	["kit footprints never overlap"] = function()
		local w = world()
		local scale = Realm.settlements.scale
		for _, zone in ZONES do
			local boxes = {}
			for _, spec in w.byZone[zone] do
				if spec.asset ~= "Border" then
					local box = Settlement.footprint(w.manifest, scale, spec)
					if box then
						table.insert(boxes, { box = box, name = spec.asset })
					end
				end
			end
			-- The palisade ring and its gate towers interlock on purpose to make one wall.
			local function wall(name: string): boolean
				return string.match(name, "^Palisade") ~= nil or name == "GateTower"
			end
			for i = 1, #boxes do
				for j = i + 1, #boxes do
					if wall(boxes[i].name) and wall(boxes[j].name) then
						continue
					end
					Expect.truthy(
						not Settlement.overlaps(boxes[i].box, boxes[j].box, -0.5),
						`{zone}: {boxes[i].name} overlaps {boxes[j].name}`
					)
				end
			end
		end
	end,

	["generated pieces keep clear of NPCs, spawners and dummies"] = function()
		local w = world()
		local scale = Realm.settlements.scale
		for _, zone in ZONES do
			for _, spec in w.byZone[zone] do
				local box = Settlement.footprint(w.manifest, scale, spec)
				if box and spec.asset ~= "Border" and not isFixture(spec) then
					for _, a in w.anchors do
						Expect.truthy(
							Settlement.distance(box, a.x, a.z) >= a.r + Realm.settlements.clear - 0.01,
							`{zone}: {spec.asset} at ({math.floor(spec.x)}, {math.floor(spec.z)}) crowds an anchor`
						)
					end
				end
			end
		end
	end,

	["the well and braziers stand at their authored spots"] = function()
		local w = world()
		local function count(zone: string, asset: string): number
			local n = 0
			for _, spec in w.byZone[zone] do
				if spec.asset == asset and isFixture(spec) then
					n += 1
				end
			end
			return n
		end
		Expect.equal(count("village", "Well"), 1, "village well")
		Expect.equal(count("village", "Brazier"), 2, "village braziers")
		Expect.equal(count("goblin-camp", "Brazier"), 1, "camp fire")
		Expect.equal(count("goblin-camp", "Dais"), 1, "chieftain dais")
	end,

	["houses face a road or the plaza"] = function()
		local w = world()
		local scale = Realm.settlements.scale
		local plaza = Realm.settlements.village.plaza
		local houses = 0
		for _, spec in w.byZone.village do
			local meta = w.manifest.assets[spec.asset]
			if meta and meta.kind == "building" then
				houses += 1
				-- A point just in front of the door side.
				local sign = if w.manifest.front == "-Z" then -1 else 1
				local reach = (if sign < 0 then -meta.min[3] else meta.max[3]) * scale
					+ Realm.settlements.village.setback
					+ 2
				local fx = spec.x + math.sin(spec.yaw) * reach * sign
				local fz = spec.z + math.cos(spec.yaw) * reach * sign
				local onPlaza = math.sqrt((fx - plaza.x) ^ 2 + (fz - plaza.z) ^ 2) < plaza.r + 2
				Expect.truthy(
					onPlaza or w.field.roadDistance(fx, fz) < 2,
					`{spec.asset} at ({math.floor(spec.x)}, {math.floor(spec.z)}) faces away`
				)
			end
		end
		Expect.truthy(houses >= Realm.settlements.village.houses - 2, `{houses} houses placed`)
	end,

	["crops grow inside their plots, on the ground"] = function()
		local w = world()
		local crops = 0
		for _, spec in w.byZone.fields do
			if string.match(spec.asset, "^Wheat") or string.match(spec.asset, "^Sprout") then
				crops += 1
				Expect.truthy(Plots.at(w.field.plots, spec.x, spec.z) ~= nil, "on a plot")
				Expect.truthy(math.abs(spec.y + 0.2 - w.field.height(spec.x, spec.z)) < 0.01, "on the ground")
			end
		end
		Expect.truthy(crops > 300, `{crops} crops`)
	end,

	["the Map keeps only gameplay objects"] = function()
		local w = world()
		local props = w.map:FindFirstChild("Props")
		for _, child in props:GetChildren() do
			Expect.equal(child.Name, "DevYard", "only the dev yard stays in Map.Props")
		end
		for _, tag in { "Kindleable", "Purifiable" } do
			for _, d in w.map:GetDescendants() do
				Expect.truthy(not d:HasTag(tag), `{tag} moved to the generated well and braziers`)
			end
		end
	end,
}
