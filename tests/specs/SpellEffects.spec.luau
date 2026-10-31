--!strict

-- Every usable skill has a look, and every effect it plays exists (docs/systems/vfx.md).
local fs = require("@lune/fs")

local Expect = require("../Expect")
local Loader = require("../Loader")

local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById
local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client/Vfx/SpellEffects.luau")
local controller = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VfxController.luau")

local function exists(name: string): boolean
	return fs.isFile(`src/ReplicatedStorage/Vfx/{name}.model.json`)
end

return {
	["every usable skill has a recipe"] = function()
		for id, skill in Skills do
			if skill.delivery and skill.delivery ~= "Dev" then
				Expect.truthy(string.find(source, `SpellEffects.{id} =`, 1, true), `{id} has no recipe`)
			end
		end
	end,
	["every effect named in a recipe has a template"] = function()
		for _, code in { source, controller } do
			for name in string.gmatch(code, 'Effects%.%a+%("(%a+)"') do
				Expect.truthy(exists(name), `no template {name}`)
			end
		end
		for helper, call in string.gmatch(source, "= (%a+)%(([^\n]*)%)\n") do
			-- `hexMissile` takes a name prefix, not a template.
			if helper ~= "hexMissile" then
				for name in string.gmatch(call, '"(%u%a+)"') do
					Expect.truthy(exists(name), `no template {name}`)
				end
			end
		end
	end,
}
