--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local ChatCast = Loader.load("src/ReplicatedStorage/Shared/ChatCast")
local DevSkills = Loader.load("src/ReplicatedStorage/Shared/DevSkills")
local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById

local FAKE = {
	magic_arrow = { id = "magic_arrow", name = "Magic Arrow", kind = "Active", source = "Spell" },
	light = { id = "light", name = "Light", kind = "Active", source = "Spell" },
	cure = { id = "cure", name = "Curé Léger", kind = "Active", source = "Spell" },
	charge = { id = "charge", name = "Charge", kind = "Active", source = "Class" },
	ward = { id = "ward", name = "Ward", kind = "Passive", source = "Spell" },
	gate = { id = "gate", name = "Gate", kind = "Active", source = "Dev", chatArg = true },
	fly = { id = "fly", name = "Fly", kind = "Active", source = "Dev" },
}
local ALL = { "magic_arrow", "light", "cure", "charge", "ward", "gate", "fly" }

return {
	["normalize folds case, accents, punctuation and spaces"] = function()
		Expect.equal(ChatCast.Normalize("  MAGIC   arrow! "), "magic arrow")
		Expect.equal(ChatCast.Normalize("Curé Léger"), "cure leger")
		Expect.equal(ChatCast.Normalize("ÀÉÎÕÜ çñ"), "aeiou cn")
		Expect.equal(ChatCast.Normalize("goblin_camp"), "goblin camp")
		Expect.equal(ChatCast.Normalize("\255\254"), "", "invalid utf-8")
	end,
	["a message that is exactly a known spell name casts it"] = function()
		Expect.equal(ChatCast.Resolve("magic arrow", ALL, FAKE), "magic_arrow")
		Expect.equal(ChatCast.Resolve("Magic Arrow!", ALL, FAKE), "magic_arrow")
		Expect.equal(ChatCast.Resolve("cure leger", ALL, FAKE), "cure", "accent-insensitive")
		Expect.equal(ChatCast.Resolve("CURÉ LÉGER", ALL, FAKE), "cure")
	end,
	["ordinary chat, commands and unknown spells stay chat"] = function()
		Expect.equal(ChatCast.Resolve("I need light here", ALL, FAKE), nil, "name inside a sentence")
		Expect.equal(ChatCast.Resolve("fly away", ALL, FAKE), nil, "no argument without chatArg")
		Expect.equal(ChatCast.Resolve("/fly", ALL, FAKE), nil, "slash command")
		Expect.equal(ChatCast.Resolve("light", { "magic_arrow" }, FAKE), nil, "not known")
		Expect.equal(ChatCast.Resolve("charge", ALL, FAKE), nil, "class actives are not spells")
		Expect.equal(ChatCast.Resolve("ward", ALL, FAKE), nil, "passive")
		Expect.equal(ChatCast.Resolve("", ALL, FAKE), nil, "empty")
		Expect.equal(ChatCast.Resolve(string.rep("a", ChatCast.MaxLength + 1), ALL, FAKE), nil, "too long")
	end,
	["chatArg skills take the rest of the message as the argument"] = function()
		local id, arg = ChatCast.Resolve("Gate Goblin Camp", ALL, FAKE)
		Expect.equal(id, "gate")
		Expect.equal(arg, "goblin camp")
		id, arg = ChatCast.Resolve("gate", ALL, FAKE)
		Expect.equal(id, "gate")
		Expect.equal(arg, nil)
	end,
	["dev skills are granted only to developers"] = function()
		local ids = DevSkills.Ids(Skills)
		Expect.equal(#ids, 8, "eight dev skills")
		for _, id in ids do
			local skill = Skills[id]
			Expect.equal(skill.delivery, "Dev", `{id} delivery`)
			Expect.truthy(skill.devEffect, `{id} devEffect`)
		end
		Expect.equal(#DevSkills.Grant({ "light" }, false, Skills), 1, "non-dev unchanged")
		local granted = DevSkills.Grant({ "light" }, true, Skills)
		Expect.equal(#granted, 9, "dev gets them all")
		Expect.equal(#DevSkills.Grant(granted, true, Skills), 9, "no duplicates")
	end,
	["dev skills resolve from chat only for developers"] = function()
		local dev = DevSkills.Grant({}, true, Skills)
		Expect.equal(ChatCast.Resolve("Detect Life", dev, Skills), "dev_detect_life")
		Expect.equal(ChatCast.Resolve("detect life", DevSkills.Grant({}, false, Skills), Skills), nil)
		local id, arg = ChatCast.Resolve("Gate wheat fields", dev, Skills)
		Expect.equal(id, "dev_gate")
		Expect.equal(arg, "wheat fields")
	end,
}
