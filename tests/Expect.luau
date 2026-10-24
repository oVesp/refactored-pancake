--!strict

--[=[ Minimal assertion helpers for Lune unit tests of pure modules. ]=]
local Expect = {}

function Expect.equal(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function Expect.truthy(value: any, label: string?)
	if not value then
		error(`{label or "value"}: expected truthy, got {tostring(value)}`, 2)
	end
end

function Expect.errors(fn: () -> (), label: string?)
	if pcall(fn) then
		error(`{label or "call"}: expected an error`, 2)
	end
end

return Expect
