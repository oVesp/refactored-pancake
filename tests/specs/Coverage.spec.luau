--!strict

local fs = require("@lune/fs")

local Expect = require("../Expect")

-- Shared modules with no behaviour to test: plain data, or tied to the Roblox runtime.
local EXEMPT = {
	Constants = "plain data",
	Theme = "plain data",
	Logger = "needs RunService",
}

return {
	["every Shared module is exercised by a spec"] = function()
		local sources = {}
		for _, file in fs.readDir("tests/specs") do
			table.insert(sources, fs.readFile(`tests/specs/{file}`))
		end
		local specs = table.concat(sources, "\n")

		for _, entry in fs.readDir("src/ReplicatedStorage/Shared") do
			local name = string.match(entry, "^(.+)%.luau$") or entry
			if not EXEMPT[name] then
				local tested = string.find(specs, `Shared/{name}"`, 1, true) or string.find(specs, `"{name}"`, 1, true)
				Expect.truthy(tested, `{name} has no spec; add one or list it in EXEMPT`)
			end
		end
	end,
	["exempt modules still exist"] = function()
		for name in EXEMPT do
			Expect.truthy(fs.isFile(`src/ReplicatedStorage/Shared/{name}.luau`), `{name} is stale in EXEMPT`)
		end
	end,
}
