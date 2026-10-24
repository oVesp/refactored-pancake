--!strict

local Expect = require("../Expect")
local Profile = require("../../src/ServerScriptService/Server/Data/Profile")

return {
	["new profile is serializable and current"] = function()
		local profile = Profile.new()
		Expect.equal(profile.schemaVersion, Profile.SchemaVersion)
		Expect.truthy(Profile.IsSerializable(profile))
	end,
	["rejects NaN, infinity and functions"] = function()
		Expect.equal(Profile.IsSerializable({ xp = 0 / 0 }), false, "NaN")
		Expect.equal(Profile.IsSerializable({ xp = math.huge }), false, "inf")
		Expect.equal(Profile.IsSerializable({ fn = print }), false, "function")
	end,
	["rejects metatables, cycles and shared references"] = function()
		Expect.equal(Profile.IsSerializable(setmetatable({}, {})), false, "metatable")
		local cycle = {}
		cycle.self = cycle
		Expect.equal(Profile.IsSerializable(cycle), false, "cycle")
		local shared = {}
		Expect.equal(Profile.IsSerializable({ a = shared, b = shared }), false, "shared")
	end,
	["migrate refuses newer schema"] = function()
		local profile = Profile.new()
		profile.schemaVersion = Profile.SchemaVersion + 1
		Expect.errors(function()
			Profile.Migrate(profile)
		end)
	end,
}
