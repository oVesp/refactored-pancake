--!strict

-- Runs every tests/specs/*.spec.luau. Each spec returns a map of test name to function.
local fs = require("@lune/fs")

local passed, failed = 0, 0
local files = fs.readDir("tests/specs")
table.sort(files)

for _, file in files do
	local name = string.match(file, "^(.+)%.spec%.luau$")
	if name then
		local spec = require(`./specs/{name}.spec`) :: { [string]: () -> () }
		for testName, fn in spec do
			local ok, err = pcall(fn)
			if ok then
				passed += 1
			else
				failed += 1
				print(`FAIL {name} > {testName}: {err}`)
			end
		end
	end
end

print(`{passed} passed, {failed} failed`)
if failed > 0 then
	error("Unit tests failed", 0)
end
