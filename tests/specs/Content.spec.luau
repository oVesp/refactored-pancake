--!strict

-- Content validators: every id a table references must exist (game-design.md 7.1).
local Expect = require("../Expect")
local Loader = require("../Loader")

local Content = "src/ReplicatedStorage/Content/"
local Classes = Loader.load(Content .. "Classes").ById
local Skills = Loader.load(Content .. "Skills").ById
local Statuses = Loader.load(Content .. "Statuses").ById
local Enemies = Loader.load(Content .. "Enemies").ById
local Items = Loader.load(Content .. "Items")
local Disciplines = Loader.load(Content .. "Disciplines").ById
local Loot = Loader.load("src/ServerStorage/ContentServerOnly/Loot")

local function checkEffects(owner: string, effects: { any }?)
	for _, effect in effects or {} do
		Expect.truthy(effect.status == "cleanse" or Statuses[effect.status], `{owner}: unknown status {effect.status}`)
	end
end

return {
	["spell numbers are unique and only on spells"] = function()
		local seen: { [number]: string } = {}
		for id, skill in Skills do
			if skill.source == "Spell" then
				local number = skill.number
				Expect.truthy(type(number) == "number" and number >= 1 and number % 1 == 0, `{id}: number`)
				Expect.equal(seen[number], nil, `{id}: number {number} reused`)
				seen[number] = id
			else
				Expect.equal(skill.number, nil, `{id}: only spells are numbered`)
			end
		end
	end,
	["class grants and spell lists resolve"] = function()
		for id, class in Classes do
			Expect.equal(#class.grants, 5, `{id} grants per level`)
			for _, skillId in class.grants do
				local skill = Skills[skillId]
				Expect.truthy(skill and skill.source == "Class", `{id}: grant {skillId}`)
			end
			for _, spellId in class.spellList do
				local spell = Skills[spellId]
				Expect.truthy(spell and spell.source == "Spell", `{id}: spell {spellId}`)
				Expect.equal(spell.line, class.line, `{spellId} line`)
				Expect.truthy(spell.circle <= 1, `{spellId} must be Circle 0-1 in M0.5`)
			end
		end
	end,
	["every class mixes actives and passives"] = function()
		for id, class in Classes do
			local passives = 0
			for _, skillId in class.grants do
				if Skills[skillId].kind == "Passive" then
					passives += 1
				end
			end
			Expect.truthy(passives >= 2 and passives <= 3, `{id} passives: {passives}`)
		end
	end,
	["active skills are complete"] = function()
		for id, skill in Skills do
			checkEffects(id, skill.effects)
			checkEffects(id, skill.selfEffects)
			if skill.kind == "Active" then
				Expect.truthy(skill.delivery, `{id} delivery`)
				Expect.truthy(skill.targets, `{id} targets`)
				if skill.gcd then
					Expect.truthy(
						skill.source == "Class" or skill.source == "Spell",
						`{id}: only class and spells use the GCD`
					)
					Expect.equal(skill.windup, nil, `{id}: GCD skills cast, they do not wind up`)
				else
					Expect.truthy(skill.cooldown, `{id} off-GCD needs a cooldown`)
				end
				if skill.source == "Spell" then
					Expect.truthy(skill.gcd, `{id}: spells are on the GCD`)
				end
				if skill.castTime and skill.source ~= "Enemy" then
					Expect.truthy(skill.gcd, `{id}: off-GCD actions are instant`)
				end
				if skill.delivery == "Projectile" or skill.delivery == "Target" then
					Expect.truthy(skill.speed and skill.range, `{id} projectile speed/range`)
				end
				if skill.delivery == "Target" or skill.delivery == "Dash" or skill.delivery == "Ally" then
					Expect.truthy(skill.range, `{id} needs a range to validate its target`)
				end
				if skill.delivery == "Object" then
					Expect.truthy(skill.objectTag, `{id} objectTag`)
				end
			end
		end
	end,
	["enemies reference known skills and have loot"] = function()
		for id, enemy in Enemies do
			for _, skillId in enemy.skills do
				Expect.truthy(Skills[skillId], `{id}: skill {skillId}`)
			end
			if enemy.tier ~= "Training" then
				Expect.truthy(Loot[id], `{id} loot table`)
			end
			if enemy.tier == "Warband" then
				Expect.truthy(enemy.levelMin >= 7, `{id} Warband is level 7+`)
			end
		end
		Expect.truthy(Enemies.goblin_hexer.tier == "Warband", "Hexer is Warband")
	end,
	["loot and starter items resolve"] = function()
		for enemyId, drops in Loot do
			Expect.truthy(Enemies[enemyId], `loot for unknown enemy {enemyId}`)
			for _, drop in drops do
				Expect.truthy(Items.ById[drop.item], `{enemyId}: item {drop.item}`)
			end
		end
		for _, entry in Items.Starter do
			Expect.truthy(Items.ById[entry.id], `starter {entry.id}`)
		end
	end,
	["only item affixes carry Haste"] = function()
		for id, skill in Skills do
			Expect.equal(skill.modifiers and skill.modifiers.Haste, nil, `{id}: Haste comes only from items`)
		end
		for id, status in Statuses do
			Expect.equal(status.modifiers and status.modifiers.Haste, nil, `{id}: Haste comes only from items`)
		end
	end,
	["disciplines map to statuses"] = function()
		for id, discipline in Disciplines do
			Expect.truthy(Statuses[discipline.status], `{id} status`)
		end
	end,
}
