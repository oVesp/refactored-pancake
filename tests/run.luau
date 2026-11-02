--!strict

-- Runs every tests/specs/*.spec.luau. Each spec returns a map of test name to function.
-- `lune run tests/run <text>` keeps only the tests whose "Spec > test name" contains the text.
local fs = require("@lune/fs")
local process = require("@lune/process")

local filter = if process.args[1] then string.lower(process.args[1]) else nil

local passed, failed = 0, 0
local files = fs.readDir("tests/specs")
table.sort(files)

for _, file in files do
	local name = string.match(file, "^(.+)%.spec%.luau$")
	if name then
		-- A spec that throws while loading counts as a failure instead of ending the run.
		local loaded, spec = pcall(require, `./specs/{name}.spec`)
		if not loaded then
			failed += 1
			print(`FAIL {name} (load): {spec}`)
			continue
		end

		local testNames = {}
		for testName in spec :: { [string]: () -> () } do
			if not filter or string.find(string.lower(`{name} > {testName}`), filter, 1, true) then
				table.insert(testNames, testName)
			end
		end
		table.sort(testNames)

		local specFailed = 0
		for _, testName in testNames do
			local ok, err = pcall(spec[testName])
			if not ok then
				specFailed += 1
				print(`FAIL {name} > {testName}: {err}`)
			end
		end
		passed += #testNames - specFailed
		failed += specFailed
		if #testNames > 0 then
			print(`{name}: {#testNames - specFailed}/{#testNames}`)
		end
	end
end

print(`{passed} passed, {failed} failed`)
if failed > 0 then
	error("Unit tests failed", 0)
elseif passed == 0 then
	error(`No tests match "{filter}"`, 0)
end
