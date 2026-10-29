--!strict

-- Zone-graph world generator (src/ServerStorage/WorldGen/Gen, docs/systems/world-generation.md).
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Expect = require("../Expect")
local Loader = require("../Loader")

local Bake = Loader.load("src/ServerStorage/WorldGen/Gen/Bake")
local Field = Loader.load("src/ServerStorage/WorldGen/Gen/Field")
local Graph = Loader.load("src/ServerStorage/WorldGen/Gen/Graph")
local Realm = Loader.load("src/ServerStorage/WorldGen/Midgard")

local MARGIN = 48

local function copyRealm(): any
	local function deep(t: any): any
		if type(t) ~= "table" then
			return t
		end
		local out = {}
		for k, v in t do
			out[k] = deep(v)
		end
		return out
	end
	return deep(Realm)
end

local cached: any = nil
local function world(): (any, any, any)
	if not cached then
		local graph = Graph.build(Realm)
		local field = Field.new(graph)
		cached = { graph = graph, field = field, extents = Bake.extents(field) }
	end
	return cached.graph, cached.field, cached.extents
end

local results: { [string]: any } = {}
local function zoneResult(id: string): any
	if not results[id] then
		local graph, field, extents = world()
		local node = graph.byId[id]
		results[id] = Bake.generate(field, node, extents[node.index], MARGIN)
	end
	return results[id]
end

local function partCFrame(p: any): any
	return roblox.CFrame.new(p.x, p.y, p.z) * roblox.CFrame.fromEulerAnglesYXZ(p.pitch, p.yaw, p.roll)
end

return {
	["graph rejects unknown nodes, upward drops and duplicate edges"] = function()
		local bad = copyRealm()
		table.insert(bad.edges, { a = "village", b = "nowhere", kind = "open" })
		Expect.errors(function()
			Graph.build(bad)
		end, "unknown node")
		bad = copyRealm()
		table.insert(bad.edges, { a = "village", b = "west-heights", kind = "drop" })
		Expect.errors(function()
			Graph.build(bad)
		end, "drop going up")
		bad = copyRealm()
		table.insert(bad.edges, { a = "fields", b = "village", kind = "open" })
		Expect.errors(function()
			Graph.build(bad)
		end, "duplicate pair")
	end,

	["force layout places unanchored nodes deterministically and apart"] = function()
		local realm = copyRealm()
		table.insert(realm.nodes, { id = "loose", kind = "zone", tier = 1, r = 200, biome = "grove", band = 1 })
		table.insert(realm.edges, { a = "loose", b = "east-terrace", kind = "open" })
		local a = Graph.build(realm).byId.loose
		local b = Graph.build(realm).byId.loose
		Expect.equal(a.x, b.x, "same x")
		Expect.equal(a.z, b.z, "same z")
		local terrace = Graph.build(realm).byId["east-terrace"]
		local d = math.sqrt((a.x - terrace.x) ^ 2 + (a.z - terrace.z) ^ 2)
		Expect.truthy(d > (a.r + terrace.r) * 0.6, `loose sits {math.floor(d)} studs from its neighbour`)
	end,

	["field is deterministic"] = function()
		local _, field = world()
		local other = Field.new(Graph.build(Realm))
		for k = 1, 200 do
			local x, z = -900 + k * 9.3, -1300 + k * 9.7
			local a, b = field.sample(x, z), other.sample(x, z)
			Expect.equal(a.height, b.height, "height")
			Expect.equal(a.material, b.material, "material")
			Expect.equal(a.owner, b.owner, "owner")
		end
	end,

	["pads are flat at padHeight inside their zone"] = function()
		local graph, field = world()
		for _, pad in Realm.pads do
			for _, f in { { 0.2, 0.2 }, { 0.5, 0.5 }, { 0.8, 0.3 } } do
				local x = pad.x0 + (pad.x1 - pad.x0) * f[1]
				local z = pad.z0 + (pad.z1 - pad.z0) * f[2]
				local s = field.sample(x, z)
				Expect.truthy(math.abs(s.height - Realm.padHeight) < 0.01, `{pad.name} height {s.height}`)
				Expect.equal(graph.nodes[s.owner].floor, graph.byId[pad.zone].floor, `{pad.name} on its zone's floor`)
			end
		end
	end,

	["every ramp, stairs, pass and cave has a corridor that meets both floors"] = function()
		local graph, field = world()
		local byEdge = {}
		for _, c in field.corridors do
			byEdge[c.edge.index] = c
		end
		for _, edge in graph.edges do
			if edge.kind == "open" or edge.kind == "drop" then
				continue
			end
			local c = byEdge[edge.index]
			Expect.truthy(c, `{edge.kind} {graph.nodes[edge.a].id}-{graph.nodes[edge.b].id} has a corridor`)
			local floors = { [graph.nodes[edge.a].floor] = true, [graph.nodes[edge.b].floor] = true }
			Expect.truthy(floors[c.points[1].h], "starts on a floor")
			Expect.truthy(floors[c.points[#c.points].h], "ends on a floor")
		end
	end,

	["slopes stay walkable"] = function()
		local _, field = world()
		for _, c in field.corridors do
			local limit = if c.kind == "stairs" then Realm.corridor.stairsSlope else Realm.corridor.rampSlope
			if c.kind ~= "ramp" and c.kind ~= "stairs" then
				continue
			end
			for k = 1, #c.points - 1 do
				local p, q = c.points[k], c.points[k + 1]
				local run = math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2)
				if run > 1 then
					Expect.truthy(
						math.abs(q.h - p.h) / run <= limit * 1.05,
						`{c.kind} segment slope {math.abs(q.h - p.h) / run}`
					)
				end
			end
		end
	end,

	["no cliff, spire or outcrop blocks the headroom of any corridor"] = function()
		local graph, field = world()
		local ids = {}
		for _, c in field.corridors do
			ids[graph.nodes[c.edge.a].id] = true
			ids[graph.nodes[c.edge.b].id] = true
			-- The zone a corridor runs through (a tunnel under a plateau) builds walls along it too.
			for _, p in c.points do
				local a, b = field.owner(p.x, p.z)
				local owner = if a ~= 0 then a else b
				if owner ~= 0 then
					ids[graph.nodes[owner].id] = true
				end
			end
		end
		for id in ids do
			for _, part in zoneResult(id).parts do
				if part.kind ~= "Cliff" and part.kind ~= "Outcrop" and part.kind ~= "Spire" then
					continue
				end
				local frame = partCFrame(part)
				local radius = math.max(part.sx, part.sz) * 0.75
				for _, c in field.corridors do
					if
						part.x + radius < c.minX
						or part.x - radius > c.maxX
						or part.z + radius < c.minZ
						or part.z - radius > c.maxZ
					then
						continue
					end
					for k = 1, #c.points - 1 do
						local p, q = c.points[k], c.points[k + 1]
						for t = 0, 1, 0.1 do
							local x, z = p.x + (q.x - p.x) * t, p.z + (q.z - p.z) * t
							local y = p.h + (q.h - p.h) * t + 4
							local lp = frame:PointToObjectSpace(roblox.Vector3.new(x, y, z))
							local inside = math.abs(lp.X) < part.sx / 2 - 1
								and math.abs(lp.Y) < part.sy / 2
								and math.abs(lp.Z) < part.sz / 2 - 1
							Expect.truthy(
								not inside,
								`{id} {part.kind} at ({math.floor(part.x)}, {math.floor(part.z)}) blocks {c.kind}`
							)
						end
					end
				end
			end
		end
	end,

	["props keep off corridors, water and pads"] = function()
		local _, field = world()
		for _, id in { "orchard", "fields", "south-hollow" } do
			for _, prop in zoneResult(id).props do
				local s = field.sample(prop.x, prop.z)
				Expect.truthy(s.corridor == nil, `{id} {prop.asset} on a corridor`)
				Expect.truthy(s.water == nil, `{id} {prop.asset} in water`)
				Expect.truthy(s.padDistance >= 10, `{id} {prop.asset} on a pad`)
			end
		end
	end,

	["neighbours by shared ground include rim neighbours without an edge"] = function()
		local graph, field = world()
		local touching = Bake.neighbours(field, MARGIN)
		local orchard = graph.byId.orchard.index
		local terrace = graph.byId["east-terrace"].index
		Expect.truthy(Graph.edgeBetween(graph, orchard, terrace) == nil, "no edge between them")
		Expect.truthy(touching[orchard] and touching[orchard][terrace], "orchard and east terrace share ground")
		Expect.truthy(touching[terrace] and touching[terrace][orchard], "symmetric")
	end,

	["a zone is untouched by changes to a zone it does not border"] = function()
		local changed = copyRealm()
		changed.biomes.hollow.trees = 9
		changed.biomes.hollow.terrace = { -1, 0 }
		local field = Field.new(Graph.build(changed))
		local graph = field.graph
		local node = graph.byId["goblin-camp"]
		local again = Bake.generate(field, node, Bake.extents(field)[node.index], MARGIN)
		local before = zoneResult("goblin-camp")
		Expect.equal(#again.parts, #before.parts, "part count")
		Expect.equal(#again.props, #before.props, "prop count")
		for k, h in before.columns.height do
			if before.columns.assign[k] == node.index then
				Expect.equal(again.columns.height[k], h, "column height")
			end
		end
	end,

	["a bake decodes to the generated zone"] = function()
		local graph = world()
		local node = graph.byId["fern-ledge"]
		local result = zoneResult("fern-ledge")
		local source = Bake.encode(node, result)
		local decoded = Bake.decode(luau.load(source)(), node.index)
		Expect.equal(#decoded.parts, #result.parts, "parts")
		Expect.equal(#decoded.props, #result.props, "props")
		for k, h in result.columns.height do
			Expect.truthy(math.abs(decoded.columns.height[k] - h) <= 1 / 32, "height")
			Expect.equal(decoded.columns.material[k], result.columns.material[k], "material")
			Expect.equal(decoded.columns.assign[k] == node.index, result.columns.assign[k] == node.index, "ownership")
		end
		for k, p in result.parts do
			Expect.truthy(math.abs(decoded.parts[k].y - p.y) < 0.01, "part y")
			Expect.equal(decoded.parts[k].kind, p.kind, "part kind")
		end
	end,

	["pads match the Map zones"] = function()
		local map = roblox.deserializeModel(require("@lune/fs").readFile("src/Workspace/Map.rbxmx"))[1]
		local zones = map:FindFirstChild("Zones")
		Expect.truthy(zones, "Map has Zones")
		for _, pad in Realm.pads do
			local part = zones:FindFirstChild(pad.name)
			Expect.truthy(part, `Map zone {pad.name}`)
			local pos, size = part.CFrame.Position, part.Size
			Expect.truthy(math.abs(pos.X - size.X / 2 - pad.x0) < 1, `{pad.name} x0`)
			Expect.truthy(math.abs(pos.X + size.X / 2 - pad.x1) < 1, `{pad.name} x1`)
			Expect.truthy(math.abs(pos.Z - size.Z / 2 - pad.z0) < 1, `{pad.name} z0`)
			Expect.truthy(math.abs(pos.Z + size.Z / 2 - pad.z1) < 1, `{pad.name} z1`)
		end
	end,
}
