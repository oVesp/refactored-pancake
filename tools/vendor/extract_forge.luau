--!strict

--[=[
	Copies the VFX Forge emit module out of the installed plugin file into vendor/ForgeVFX
	(docs/systems/vfx.md). The module's license (VFX-DL 1.1) allows shipping it inside the game
	runtime only; the license text lives in the module source and is also written beside it.

	Usage: lune run tools/vendor/extract_forge <path-to-forge-plugin.rbxm>
]=]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local pluginPath = process.args[1]
assert(pluginPath, "usage: lune run tools/vendor/extract_forge <forge-plugin.rbxm>")

local roots = roblox.deserializeModel(fs.readFile(pluginPath))
local module
for _, root in roots do
	module = root:FindFirstChild("ForgeVFX", true)
	if module then
		break
	end
end
assert(module and module:IsA("ModuleScript"), "ForgeVFX module not found in the plugin file")

local source = (module :: any).Source :: string
local license = string.match(source, "%[%[(.-)%]%]")
assert(license and string.find(license, "VFX%-DL"), "license block not found in ForgeVFX source")

fs.writeDir("vendor/ForgeVFX")
fs.writeFile("vendor/ForgeVFX/ForgeVFX.rbxm", roblox.serializeModel({ module }))
fs.writeFile("vendor/ForgeVFX/LICENSE.txt", license)
print(`Extracted ForgeVFX ({#module:GetDescendants()} descendants) to vendor/ForgeVFX`)
