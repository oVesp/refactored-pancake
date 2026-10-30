--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")
local Profile = require("../../src/ServerScriptService/Server/Data/Profile")
local Hotbar = Loader.load("src/ReplicatedStorage/Shared/Hotbar")

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
	["new profile has an empty hotbar of the shared size"] = function()
		local profile = Profile.new()
		Expect.equal(Profile.HotbarSize, Hotbar.Size)
		Expect.equal(#profile.hotbar, Hotbar.Size)
		for _, slot in profile.hotbar do
			Expect.equal(slot, "")
		end
	end,
	["migrates schema 1 by adding an empty hotbar"] = function()
		local profile = Profile.new() :: any
		profile.schemaVersion = 1
		profile.hotbar = nil
		local migrated = Profile.Migrate(profile)
		Expect.equal(migrated.schemaVersion, Profile.SchemaVersion)
		Expect.equal(#migrated.hotbar, Hotbar.Size)
		Expect.truthy(Profile.IsSerializable(migrated))
	end,
	["new profile starts uncreated"] = function()
		local profile = Profile.new()
		Expect.equal(profile.created, false)
		Expect.equal(profile.name, "")
		Expect.equal(profile.heritage, "human")
	end,
	["migrates schema 2 to an uncreated character"] = function()
		local profile = Profile.new() :: any
		profile.schemaVersion = 2
		profile.created = nil
		profile.name = nil
		profile.appearance = nil
		profile.heritage = "Human"
		local migrated = Profile.Migrate(profile)
		Expect.equal(migrated.schemaVersion, Profile.SchemaVersion)
		Expect.equal(migrated.created, false)
		Expect.equal(migrated.heritage, "human")
		Expect.truthy(Profile.IsSerializable(migrated))
	end,
	["migrates schema 3 warriors to fighters with no proficiency chosen"] = function()
		local profile = Profile.new() :: any
		profile.schemaVersion = 3
		profile.proficiency = nil
		profile.classes = { { id = "warrior", level = 4 }, { id = "mage", level = 1 } }
		local migrated = Profile.Migrate(profile)
		Expect.equal(migrated.schemaVersion, Profile.SchemaVersion)
		Expect.equal(migrated.classes[1].id, "fighter")
		Expect.equal(migrated.classes[1].level, 4)
		Expect.equal(migrated.classes[2].id, "mage")
		Expect.equal(migrated.proficiency, "")
	end,
}
