--!strict

local roblox = require("@lune/roblox")

local Expect = require("../Expect")
local Loader = require("../Loader")

local Remotes = Loader.load("src/ReplicatedStorage/Shared/Net")

local Vector3 = roblox.Vector3

local function clientRemotes(): { [string]: any }
	local found = {}
	for name, spec in Remotes do
		if spec.direction == "ClientToServer" then
			found[name] = spec
		end
	end
	return found
end

return {
	["client remotes are rate limited and validated"] = function()
		for name, spec in clientRemotes() do
			Expect.truthy(spec.rateLimit, `{name} rate limit`)
			Expect.truthy(spec.rateLimit.capacity > 0 and spec.rateLimit.perSecond > 0, `{name} rate`)
			Expect.truthy(spec.validate, `{name} validate`)
		end
	end,
	["server remotes carry no client validation"] = function()
		for name, spec in Remotes do
			if spec.direction == "ServerToClient" then
				Expect.equal(spec.validate, nil, `{name} validate`)
				Expect.equal(spec.rateLimit, nil, `{name} rate limit`)
			end
		end
	end,
	["no client remote accepts a junk payload"] = function()
		local nan = 0 / 0
		for name, spec in clientRemotes() do
			Expect.equal(spec.validate({ {} }), false, `{name} with a nested table`)
			Expect.equal(spec.validate(nan), false, `{name} with NaN`)
			Expect.equal(spec.validate({ {} }, {}, {}, {}, {}, {}, {}, {}), false, `{name} with too many arguments`)
		end
	end,
	["SetRun takes exactly one boolean"] = function()
		local validate = Remotes.SetRun.validate
		Expect.equal(validate(true), true, "on")
		Expect.equal(validate(false), true, "off")
		Expect.equal(validate(), false, "none")
		Expect.equal(validate(1), false, "number")
		Expect.equal(validate(true, true), false, "two")
	end,
	["Dodge refuses coordinates out of range and NaN"] = function()
		local validate = Remotes.Dodge.validate
		Expect.equal(validate(Vector3.new(1, 0, 0), 1), true, "valid")
		Expect.equal(validate(Vector3.new(1e6, 0, 0), 1), false, "out of range")
		Expect.equal(validate(Vector3.new(0 / 0, 0, 0), 1), false, "NaN")
		Expect.equal(validate(Vector3.new(1, 0, 0), 1.5), false, "fractional sequence")
		Expect.equal(validate(Vector3.new(1, 0, 0), -1), false, "negative sequence")
	end,
}
