--!strict

--[=[
	Resolves a realm's authored zone graph (`WorldGen/Midgard`) into indexed nodes and edges,
	checks it, gives every node a floor height and a seed, and places nodes that have no authored
	position with a deterministic force layout.
]=]
local Hash = require(script.Parent.Hash)

export type Node = {
	index: number,
	id: string,
	kind: string,
	tier: number,
	floor: number,
	x: number,
	z: number,
	r: number,
	biome: string,
	band: number,
	roof: boolean,
	locked: boolean,
	seed: number,
	anchored: boolean,
}

export type Edge = {
	index: number,
	a: number,
	b: number,
	kind: string,
	width: number,
	along: number?,
	secret: boolean,
	seed: number,
}

export type Graph = {
	realm: any,
	seed: number,
	nodes: { Node },
	edges: { Edge },
	byId: { [string]: Node },
	-- Unordered pair key "i:j" (i < j) to the edge joining them.
	pairs: { [string]: Edge },
}

local Graph = {}

local KINDS = { open = true, pass = true, ramp = true, stairs = true, cave = true, drop = true }

local LAYOUT_STEPS = 240
local NO_NODES: { Node } = {}

--[=[ Key for an unordered node pair. ]=]
function Graph.pairKey(i: number, j: number): string
	if i > j then
		i, j = j, i
	end
	return `{i}:{j}`
end

--[=[
	Places nodes without an authored position. Each starts at the mean of the placed nodes it
	connects to plus a hashed offset, then springs pull connected nodes to touching distance and
	every pair is pushed apart while their cells would overlap. Authored nodes never move.
]=]
local function layout(graph: Graph)
	local free: { Node } = {}
	for _, node in graph.nodes do
		if not node.anchored then
			table.insert(free, node)
		end
	end
	if #free == 0 then
		return
	end

	local neighbours: { [number]: { Node } } = {}
	for _, edge in graph.edges do
		local a, b = graph.nodes[edge.a], graph.nodes[edge.b]
		neighbours[a.index] = neighbours[a.index] or {}
		neighbours[b.index] = neighbours[b.index] or {}
		table.insert(neighbours[a.index], b)
		table.insert(neighbours[b.index], a)
	end

	for _, node in free do
		local sx, sz, count = 0, 0, 0
		for _, other in neighbours[node.index] or NO_NODES do
			if other.anchored then
				sx += other.x
				sz += other.z
				count += 1
			end
		end
		local angle = Hash.unit(node.seed, 1) * math.pi * 2
		local reach = node.r * 1.5
		node.x = (if count > 0 then sx / count else 0) + math.cos(angle) * reach
		node.z = (if count > 0 then sz / count else 0) + math.sin(angle) * reach
	end

	for step = 1, LAYOUT_STEPS do
		local rate = 0.5 * (1 - step / (LAYOUT_STEPS + 1))
		local fx: { [number]: number } = {}
		local fz: { [number]: number } = {}
		for _, node in graph.nodes do
			fx[node.index], fz[node.index] = 0, 0
		end
		for _, edge in graph.edges do
			local a, b = graph.nodes[edge.a], graph.nodes[edge.b]
			local dx, dz = b.x - a.x, b.z - a.z
			local d = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
			local pull = (d - (a.r + b.r) * 0.85) / d
			fx[a.index] += dx * pull
			fz[a.index] += dz * pull
			fx[b.index] -= dx * pull
			fz[b.index] -= dz * pull
		end
		for i = 1, #graph.nodes do
			for j = i + 1, #graph.nodes do
				local a, b = graph.nodes[i], graph.nodes[j]
				local dx, dz = b.x - a.x, b.z - a.z
				local d = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
				local overlap = (a.r + b.r) * 0.9 - d
				if overlap > 0 then
					fx[a.index] -= dx / d * overlap
					fz[a.index] -= dz / d * overlap
					fx[b.index] += dx / d * overlap
					fz[b.index] += dz / d * overlap
				end
			end
		end
		for _, node in free do
			node.x += fx[node.index] * rate
			node.z += fz[node.index] * rate
		end
	end
	for _, node in free do
		node.x = math.round(node.x)
		node.z = math.round(node.z)
	end
end

--[=[ Builds the graph for a realm data table. Errors name the offending node or edge. ]=]
function Graph.build(realm: any): Graph
	local graph: Graph = {
		realm = realm,
		seed = realm.seed,
		nodes = {},
		edges = {},
		byId = {},
		pairs = {},
	}
	for index, raw in realm.nodes do
		assert(graph.byId[raw.id] == nil, `duplicate node {raw.id}`)
		assert(realm.biomes[raw.biome], `node {raw.id}: unknown biome {raw.biome}`)
		local floor = raw.floor or realm.tiers[raw.tier]
		assert(floor, `node {raw.id}: tier {raw.tier} has no height`)
		assert(raw.r > 0, `node {raw.id}: r must be positive`)
		local node: Node = {
			index = index,
			id = raw.id,
			kind = raw.kind,
			tier = raw.tier,
			floor = floor,
			x = raw.x or 0,
			z = raw.z or 0,
			r = raw.r,
			biome = raw.biome,
			band = raw.band,
			roof = raw.roof == true,
			locked = raw.locked == true,
			seed = Hash.named(realm.seed, raw.id),
			anchored = raw.x ~= nil and raw.z ~= nil,
		}
		graph.nodes[index] = node
		graph.byId[raw.id] = node
	end
	for index, raw in realm.edges do
		local a, b = graph.byId[raw.a], graph.byId[raw.b]
		assert(a and b, `edge {raw.a}-{raw.b}: unknown node`)
		assert(KINDS[raw.kind], `edge {raw.a}-{raw.b}: unknown kind {raw.kind}`)
		local key = Graph.pairKey(a.index, b.index)
		assert(graph.pairs[key] == nil, `edge {raw.a}-{raw.b} is listed twice`)
		if raw.kind == "drop" then
			assert(a.floor > b.floor, `drop {raw.a}-{raw.b} must go down`)
		end
		local edge: Edge = {
			index = index,
			a = a.index,
			b = b.index,
			kind = raw.kind,
			width = raw.width or realm.corridor.width,
			along = raw.along,
			secret = raw.secret == true,
			seed = Hash.pair(realm.seed, raw.a, raw.b),
		}
		graph.edges[index] = edge
		graph.pairs[key] = edge
	end
	for _, pad in realm.pads do
		assert(graph.byId[pad.zone], `pad {pad.name}: unknown zone {pad.zone}`)
	end
	for _, lake in realm.lakes do
		assert(graph.byId[lake.zone], `lake in unknown zone {lake.zone}`)
	end
	layout(graph)
	return graph
end

--[=[ Edge joining two nodes, if any. ]=]
function Graph.edgeBetween(graph: Graph, i: number, j: number): Edge?
	return graph.pairs[Graph.pairKey(i, j)]
end

return Graph
