--!strict

-- Writes the Roblox-side bone list of a raw Studio 3D import for the FBX exporter
-- (docs/art/animation-pipeline.md, Rig import). Each bone carries its rest offset from its parent in
-- studs, which the exporter compares with the FBX rest pose to find the importer's scale:
--     lune run tools/anim/rig_from_import <import.rbxm> <out.json>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local source, out = process.args[1], process.args[2]
assert(source and out, "usage: lune run tools/anim/rig_from_import <import.rbxm> <out.json>")

local bones = {}
for _, root in roblox.deserializeModel(fs.readFile(source)) do
	for _, item in { root, table.unpack(root:GetDescendants()) } do
		if item:IsA("Bone") then
			local parent = item.Parent
			table.insert(bones, {
				name = item.Name,
				parent = if parent and parent:IsA("Bone") then parent.Name else nil,
				offset = item.CFrame.Position.Magnitude,
			})
		end
	end
end
assert(#bones > 0, `{source} has no bones`)

fs.writeFile(out, serde.encode("json", { source = source, bones = bones }, true) .. "\n")
print(`{#bones} bones`)
