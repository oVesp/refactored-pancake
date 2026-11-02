--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Summons = Loader.load("src/ReplicatedStorage/Shared/Summons")
local Families = Loader.load("src/ReplicatedStorage/Content/Summons").ById
local Enemies = Loader.load("src/ReplicatedStorage/Content/Enemies").ById
local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")

local family = { base = { "zombie" }, pool = { "zombie", "skeleton" }, levelOffset = -1 }

return {
	["an undiscovered pool leaves only the base"] = function()
		local options = Summons.Options(family, {})
		Expect.equal(#options, 1)
		Expect.equal(options[1], "zombie")
	end,
	["a discovery adds its option once, after the base"] = function()
		local options = Summons.Options(family, { skeleton = true, zombie = true })
		Expect.equal(#options, 2)
		Expect.equal(options[1], "zombie")
		Expect.equal(options[2], "skeleton")
	end,
	["a discovery outside the pool adds nothing"] = function()
		Expect.equal(#Summons.Options(family, { goblin_raider = true }), 1)
	end,
	["refuses an undiscovered request"] = function()
		Expect.equal(Summons.Choose(family, {}, "skeleton", nil), nil)
	end,
	["refuses an id outside the family, discovered or not"] = function()
		Expect.equal(Summons.Choose(family, { goblin_raider = true }, "goblin_raider", nil), nil)
	end,
	["accepts a discovered request, in any case"] = function()
		Expect.equal(Summons.Choose(family, { skeleton = true }, "skeleton", nil), "skeleton")
		Expect.equal(Summons.Choose(family, { skeleton = true }, "SKELETON", nil), "skeleton")
	end,
	["without a request uses the remembered option, else the first"] = function()
		Expect.equal(Summons.Choose(family, { skeleton = true }, nil, "skeleton"), "skeleton")
		Expect.equal(Summons.Choose(family, {}, nil, "skeleton"), "zombie")
		Expect.equal(Summons.Choose(family, {}, nil, nil), "zombie")
	end,
	["summon level follows the caster and never drops below 1"] = function()
		Expect.equal(Summons.Level(family, 5), 4)
		Expect.equal(Summons.Level(family, 1), 1)
	end,
	["only pool entries outside the base count as unlocks"] = function()
		local families = { undead = family }
		Expect.equal(Summons.Unlocks(families, "skeleton"), true)
		Expect.equal(Summons.Unlocks(families, "zombie"), false)
		Expect.equal(Summons.Unlocks(families, "goblin_raider"), false)
	end,
	["families name known enemies and respect the caster cap"] = function()
		for id, def in Families do
			Expect.truthy(#def.base > 0, `{id}: needs a base summon`)
			Expect.truthy(def.duration > 0, `{id}: duration`)
			Expect.truthy(def.cap >= 1 and def.cap <= Tuning.Summons.MaxPerCaster, `{id}: cap`)
			for _, list in { def.base, def.pool } do
				for _, enemy in list do
					Expect.truthy(Enemies[enemy], `{id}: unknown enemy {enemy}`)
				end
			end
		end
	end,
	["summon skills name a known family, and only they do"] = function()
		for id, skill in Skills do
			if skill.delivery == "Summon" then
				Expect.truthy(Families[skill.summon], `{id}: unknown family {skill.summon}`)
			else
				Expect.equal(skill.summon, nil, `{id}: summon without the Summon delivery`)
			end
		end
	end,
	["Create Undead raises a zombie by default and a skeleton once discovered"] = function()
		local undead = Families[Skills.create_undead.summon]
		Expect.equal(Summons.Choose(undead, {}, nil, nil), "zombie")
		Expect.equal(Summons.Choose(undead, {}, "skeleton", nil), nil)
		Expect.equal(Summons.Choose(undead, { skeleton = true }, "skeleton", nil), "skeleton")
	end,
}
