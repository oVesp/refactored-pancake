--!strict

-- Content register validator (game-design.md 7.1): every asset id and content file has a
-- provenance row, and no script hard-codes an asset id.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Expect = require("../Expect")
local Loader = require("../Loader")

local register = serde.decode("json", fs.readFile("content/register.json"))
local Assets = Loader.load("src/ReplicatedStorage/Content/Assets")

local function rowsById(): { [string]: any }
	local rows = {}
	for _, row in register.entries do
		Expect.truthy(rows[row.id] == nil, `duplicate register id {row.id}`)
		rows[row.id] = row
	end
	return rows
end

local function walk(dir: string, visit: (string) -> ())
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path, visit)
		else
			visit(path)
		end
	end
end

return {
	["every row is complete and uses a known status"] = function()
		for _, row in register.entries do
			for _, field in { "id", "type", "origin", "license", "owner", "status" } do
				Expect.truthy(row[field], `{row.id or "?"}: missing {field}`)
			end
			Expect.truthy(table.find(register.statuses, row.status), `{row.id}: bad status {row.status}`)
			if row.path then
				Expect.truthy(fs.isFile(row.path), `{row.id}: {row.path} does not exist`)
			end
		end
	end,
	["every manifest audio id is registered with the same id"] = function()
		local rows = rowsById()
		for key, asset in Assets.Audio do
			local row = rows["audio:" .. key]
			Expect.truthy(row, `audio {key} has no register row`)
			Expect.equal("rbxassetid://" .. row.assetId, asset.id, `audio {key} id`)
		end
	end,
	["every manifest texture has a file row and a matching id once uploaded"] = function()
		local rows = rowsById()
		for key, asset in Assets.Textures do
			local row = rows["texture:" .. key]
			Expect.truthy(row, `texture {key} has no register row`)
			-- VFX Studio textures are referenced by id, with no repo file (docs/art/vfx-library.md).
			Expect.truthy(row.path or row.origin == "VFX Studio", `texture {key} has no source file path`)
			Expect.truthy(string.match(asset.fallback, "^rbxasset://textures/"), `texture {key} fallback`)
			if asset.id or row.assetId then
				Expect.equal("rbxassetid://" .. tostring(row.assetId), asset.id, `texture {key} id`)
			end
		end
	end,
	["every manifest animation has an Animation file row and a matching id"] = function()
		local rows = rowsById()
		local count = 0
		for _, name in fs.readDir("src/ReplicatedStorage/Animations") do
			local key = string.match(name, "^(.+)%.model%.json$")
			Expect.truthy(key, `{name} is not an Animation model`)
			local row = rows["animation:" .. key]
			Expect.truthy(row, `animation {key} has no register row`)
			Expect.equal(`src/ReplicatedStorage/Animations/{name}`, row.path, `animation {key} path`)
			local model = serde.decode("json", fs.readFile("src/ReplicatedStorage/Animations/" .. name))
			Expect.equal("rbxassetid://" .. tostring(row.assetId), model.properties.AnimationId, `animation {key} id`)
			count += 1
		end
		Expect.truthy(count > 0, "no animations")
	end,
	["every manifest mesh is registered with the same id"] = function()
		local rows = rowsById()
		for key, asset in Assets.Meshes do
			local row = rows["mesh:" .. key]
			Expect.truthy(row, `mesh {key} has no register row`)
			Expect.equal("rbxassetid://" .. row.assetId, asset.id, `mesh {key} id`)
		end
	end,
	["every content, UI and world file is registered"] = function()
		local registered = {}
		for _, row in register.entries do
			if row.path then
				registered[row.path] = true
			end
		end
		for _, dir in
			{
				"src/ReplicatedStorage/Content",
				"src/ServerStorage",
				"src/StarterGui",
				"src/ReplicatedStorage/UiTemplates",
				"src/ReplicatedStorage/Animations",
				"src/ReplicatedStorage/Vfx",
				"src/Workspace",
				"src/Lighting",
			}
		do
			walk(dir, function(path)
				Expect.truthy(registered[path], `{path} has no register row`)
			end)
		end
	end,
	["scripts never hard-code asset ids"] = function()
		walk("src", function(path)
			if string.match(path, "%.luau$") and path ~= "src/ReplicatedStorage/Content/Assets.luau" then
				Expect.truthy(
					not string.find(fs.readFile(path), "rbxassetid://%d"),
					`{path} hard-codes an asset id; use Content/Assets`
				)
			end
		end)
	end,
}
