--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Chain = Loader.load("src/ReplicatedStorage/Shared/Chain")

local SKILLS = {
	a = { chainNext = "b" },
	b = { chainNext = "c" },
	c = {},
}

return {
	["members follow chainNext from the entry"] = function()
		local members = Chain.Members(SKILLS, "a")
		Expect.equal(#members, 3)
		Expect.equal(members[1], "a")
		Expect.equal(members[3], "c")
		Expect.truthy(Chain.Contains(SKILLS, "a", "c"), "contains c")
		Expect.equal(Chain.Contains(SKILLS, "a", "x"), false, "unknown id")
	end,
	["members reject a loop"] = function()
		Expect.errors(function()
			Chain.Members({ a = { chainNext = "b" }, b = { chainNext = "a" } }, "a")
		end)
	end,
	["next continues inside the window and restarts outside it"] = function()
		Expect.equal(Chain.Next(SKILLS, "a", nil, 0, 10, 0.8), "a", "no last hit")
		Expect.equal(Chain.Next(SKILLS, "a", "a", 10, 10.5, 0.8), "b")
		Expect.equal(Chain.Next(SKILLS, "a", "b", 10, 10.75, 0.8), "c", "inside the window")
		Expect.equal(Chain.Next(SKILLS, "a", "b", 10, 10.9, 0.8), "a", "window expired")
		Expect.equal(Chain.Next(SKILLS, "a", "c", 10, 10.1, 0.8), "a", "after the last hit")
	end,
	["allowed only in order and within the window"] = function()
		Expect.truthy(Chain.Allowed(SKILLS, "a", nil, 0, "a", 5, 0.8), "entry always")
		Expect.truthy(Chain.Allowed(SKILLS, "a", "a", 5, "b", 5.4, 0.8), "a then b")
		Expect.equal(Chain.Allowed(SKILLS, "a", nil, 0, "b", 5, 0.8), false, "b without a")
		Expect.equal(Chain.Allowed(SKILLS, "a", "a", 5, "c", 5.4, 0.8), false, "skips b")
		Expect.equal(Chain.Allowed(SKILLS, "a", "a", 5, "b", 6, 0.8), false, "too late")
		Expect.equal(Chain.Allowed(SKILLS, "a", "c", 5, "b", 5.2, 0.8), false, "after the end")
	end,
	["a hit's own chain window replaces the default"] = function()
		local slow = { a = { chainNext = "b", chainWindow = 1.35 }, b = {} }
		Expect.equal(Chain.Next(slow, "a", "a", 10, 11.2, 0.8), "b", "past the default, inside its own")
		Expect.equal(Chain.Next(slow, "a", "a", 10, 11.4, 0.8), "a", "past its own")
		Expect.truthy(Chain.Allowed(slow, "a", "a", 5, "b", 6.2, 0.8), "allowed inside its own window")
		Expect.equal(Chain.Allowed(slow, "a", "a", 5, "b", 6.4, 0.8), false, "too late for its own window")
	end,
}
