--!strict

-- Bakes every locked zone of the realm (docs/systems/world-generation.md, section loop).
-- Run from the repo root: `lune run tools/worldgen/bake`.
-- Writes src/ServerStorage/WorldGen/Baked/<zone>.luau for each node with `locked = true` and
-- deletes bakes of zones that are no longer locked. A zone that already has a bake keeps it;
-- pass `--rebake <zone>` to regenerate one on purpose.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Loader = require("../../tests/Loader")

local Bake = Loader.load("src/ServerStorage/WorldGen/Gen/Bake")
local Field = Loader.load("src/ServerStorage/WorldGen/Gen/Field")
local Graph = Loader.load("src/ServerStorage/WorldGen/Gen/Graph")
local realm = Loader.load("src/ServerStorage/WorldGen/Midgard")

local OUT = "src/ServerStorage/WorldGen/Baked"
local MARGIN = 48 -- must match Sections.luau

local rebake: { [string]: boolean } = {}
for k, arg in process.args do
	if arg == "--rebake" and process.args[k + 1] then
		rebake[process.args[k + 1]] = true
	end
end

local graph = Graph.build(realm)
local field = Field.new(graph)
local extents = Bake.extents(field)

local locked: { [string]: boolean } = {}
for _, node in graph.nodes do
	if node.locked then
		locked[node.id] = true
	end
end

if fs.isDir(OUT) then
	for _, file in fs.readDir(OUT) do
		local id = string.match(file, "^(.+)%.luau$")
		if id and not locked[id] then
			fs.removeFile(`{OUT}/{file}`)
			print(`removed {file}: {id} is no longer locked`)
		end
	end
end

local wrote = 0
for _, node in graph.nodes do
	if not node.locked then
		continue
	end
	local path = `{OUT}/{node.id}.luau`
	if fs.isFile(path) and not rebake[node.id] then
		print(`{node.id}: kept existing bake`)
		continue
	end
	local extent = extents[node.index]
	assert(extent, `{node.id} owns no ground inside a section`)
	local started = os.clock()
	local result = Bake.generate(field, node, extent, MARGIN)
	if not fs.isDir(OUT) then
		fs.writeDir(OUT)
	end
	fs.writeFile(path, Bake.encode(node, result))
	wrote += 1
	print(string.format("%s: %d parts, %d props, %.1fs", node.id, #result.parts, #result.props, os.clock() - started))
end
print(`baked {wrote} zone(s)`)
