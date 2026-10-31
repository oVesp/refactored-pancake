--!strict

-- Every usable skill sounds at each phase of its delivery (docs/systems/vfx.md, "Sound").
local fs = require("@lune/fs")

local Expect = require("../Expect")
local Loader = require("../Loader")

local Content = "src/ReplicatedStorage/Content/"
local Assets = Loader.load(Content .. "Assets")
local SkillSounds = Loader.load(Content .. "SkillSounds")
local Skills = Loader.load(Content .. "Skills").ById

local PHASES: { [string]: { string } } = {
	Projectile = { "launch", "impact" },
	Target = { "launch", "impact" },
	Melee = { "swing", "hit" },
	Cone = { "swing", "hit" },
	Dash = { "resolve", "hit" },
}

return {
	["every usable skill has a registered sound for each phase of its delivery"] = function()
		for id, skill in Skills do
			if skill.delivery and skill.delivery ~= "Dev" then
				for _, phase in PHASES[skill.delivery] or { "resolve" } do
					local key = SkillSounds.For(skill, phase)
					Expect.truthy(key, `{id} has no {phase} sound`)
					Expect.truthy(Assets.Audio[key], `{id} {phase} sound {key} is not in Assets.Audio`)
				end
			end
		end
	end,
	["a skill with a cast time charges with a sound; one without does not"] = function()
		for id, skill in Skills do
			Expect.equal(skill.castTime ~= nil, SkillSounds.For(skill, "cast") ~= nil, `{id} cast sound`)
		end
	end,
	["sound overrides name real skills"] = function()
		local source = fs.readFile(Content .. "SkillSounds.luau")
		local table_ = string.match(source, "local BY_SKILL.-\n}") :: string
		for id in string.gmatch(table_, "\n\t([%w_]+) = ") do
			Expect.truthy(Skills[id], `SkillSounds names unknown skill {id}`)
		end
	end,
}
