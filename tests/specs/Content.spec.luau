--!strict

-- Content validators: every id a table references must exist (game-design.md 7.1).
local Expect = require("../Expect")
local Loader = require("../Loader")

local Content = "src/ReplicatedStorage/Content/"
local Classes = Loader.load(Content .. "Classes").ById
local Tuning = Loader.load(Content .. "Tuning")
local Skills = Loader.load(Content .. "Skills").ById
local Statuses = Loader.load(Content .. "Statuses").ById
local Enemies = Loader.load(Content .. "Enemies").ById
local Npcs = Loader.load(Content .. "Npcs").ById
local Appearance = Loader.load(Content .. "Appearance")
local Factions = Loader.load(Content .. "Factions").ById
local Items = Loader.load(Content .. "Items")
local Disciplines = Loader.load(Content .. "Disciplines").ById
local Loot = Loader.load("src/ServerStorage/ContentServerOnly/Loot")
local Animations = require("../AnimationKeys")()
local Basic = Loader.load(Content .. "Skills").Basic
local Chain = Loader.load("src/ReplicatedStorage/Shared/Chain")
local Strings = Loader.load(Content .. "Strings")

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
			Expect.truthy(#class.grants >= 1 and #class.grants <= class.cap, `{id} grants per level within the cap`)
			for _, skillId in class.grants do
				local skill = Skills[skillId]
				Expect.truthy(skill and skill.source == "Class", `{id}: grant {skillId}`)
			end
			for _, spellId in class.spellList do
				local spell = Skills[spellId]
				Expect.truthy(spell and spell.source == "Spell", `{id}: spell {spellId}`)
				Expect.equal(spell.line, class.line, `{spellId} line`)
				Expect.truthy(spell.tier <= 1, `{spellId} must be Tier 0-1 in M0.5`)
			end
		end
	end,
	["every spell charges, utility spells faster, and nothing else a player uses does"] = function()
		local cast = Tuning.Combat.Cast
		for id, skill in Skills do
			if skill.source == "Spell" then
				local castTime = skill.castTime
				Expect.truthy(castTime, `{id}: spells charge`)
				Expect.equal(skill.windup, nil, `{id}: spells charge, they do not wind up`)
				Expect.equal(skill.recovery, nil, `{id}: spells do not swing`)
				if skill.utility then
					Expect.truthy(castTime <= cast.UtilityMax, `{id}: utility spells cast faster`)
					Expect.equal(skill.damage, nil, `{id}: utility spells deal no damage`)
				else
					Expect.truthy(castTime >= cast.SpellMin, `{id}: below the spell cast minimum`)
				end
			elseif skill.source ~= "Enemy" then
				Expect.equal(skill.castTime, nil, `{id}: only spells charge`)
				Expect.equal(skill.utility, nil, `{id}: only spells are utility`)
			end
		end
	end,
	["weapon spells are spells no class teaches"] = function()
		for id, skill in Skills do
			if skill.weaponSpell then
				Expect.equal(skill.source, "Spell", `{id}: source`)
				for classId, class in Classes do
					Expect.equal(table.find(class.spellList, id), nil, `{classId} teaches {id}`)
				end
			end
		end
	end,
	["object spells name a tag and a known notice"] = function()
		for id, skill in Skills do
			if skill.delivery == "Object" then
				Expect.truthy(type(skill.objectTag) == "string", `{id}: objectTag`)
				Expect.truthy(skill.objectNotice == nil or Strings[skill.objectNotice], `{id}: objectNotice`)
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
			Expect.truthy(passives >= 1 and passives < #class.grants, `{id} passives: {passives}`)
		end
	end,
	["fighter is the first starter: 15 levels of physical, weapon-agnostic skills"] = function()
		local fighter = Classes.fighter
		Expect.equal(Loader.load(Content .. "Classes").Order[1], "fighter")
		Expect.equal(fighter.cap, 15)
		Expect.equal(#fighter.grants, 15)
		Expect.truthy(fighter.categories and table.find(fighter.categories, "Martial"), "Martial category")
		Expect.equal(#fighter.spellList, 0)
		for _, skillId in fighter.grants do
			local skill = Skills[skillId]
			Expect.truthy(skill.damage == nil or skill.damage.type == "physical", `{skillId}: physical only`)
			Expect.truthy(skill.cost == nil or skill.cost.resource == "Stamina", `{skillId}: Stamina`)
		end
		Expect.equal(Skills.precise_attack.weaponAttack.scale, 1.4, "Precise Attack is 140%")
		Expect.equal(Skills.precise_attack.critChance, 0.15, "Precise Attack crit")
		Expect.equal(Skills.disengage.cooldown, 15)
		local weapons = Loader.load(Content .. "Weapons").ById
		for _, weaponId in Loader.load(Content .. "Tuning").Combat.ProficiencyWeapons do
			Expect.truthy(weapons[weaponId], `proficiency weapon {weaponId}`)
		end
	end,
	["reserved Warrior candidates stay defined but ungranted"] = function()
		for _, skillId in { "cleave", "charge", "war_cry" } do
			Expect.truthy(Skills[skillId], skillId)
			for id, class in Classes do
				Expect.equal(table.find(class.grants, skillId), nil, `{id} grants reserved {skillId}`)
			end
		end
		Expect.equal(Skills.hardy, nil)
		Expect.equal(Skills.weapon_training, nil)
	end,
	["passive traits and fighter statuses resolve"] = function()
		for id, skill in Skills do
			checkEffects(id, skill.critEffects)
			local upgrade = skill.upgrade
			if upgrade then
				Expect.equal(skill.kind, "Passive", `{id}: upgrades are passive`)
				local target = Skills[upgrade.skill]
				Expect.truthy(target and target.kind == "Active", `{id}: upgrades unknown {upgrade.skill}`)
				Expect.truthy(upgrade.charges == nil or target.cooldown, `{id}: charges need a cooldown`)
				checkEffects(id, upgrade.selfEffects)
			end
			if skill.restore then
				Expect.equal(skill.delivery, "Self", `{id}: restore is a Self skill`)
			end
		end
		for id, status in Statuses do
			if status.expireSkill then
				Expect.truthy(Skills[status.expireSkill], `{id}: expireSkill`)
			end
			if status.magnitudeStat then
				Expect.equal(status.kind, "Stats", `{id}: magnitudeStat on a Stats status`)
			end
		end
	end,
	["active skills are complete"] = function()
		for id, skill in Skills do
			checkEffects(id, skill.effects)
			checkEffects(id, skill.selfEffects)
			if skill.kind == "Active" then
				Expect.truthy(skill.delivery or skill.weaponAttack, `{id} delivery`)
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
				if skill.recovery then
					Expect.truthy(skill.windup, `{id}: a swing with recovery has a windup`)
					Expect.truthy(
						(skill.cooldown or 0) >= (skill.windup or 0) + skill.recovery - 1e-6,
						`{id}: cooldown covers windup + recovery`
					)
				end
				if skill.source == "Spell" then
					Expect.truthy(skill.gcd, `{id}: spells are on the GCD`)
				end
				if skill.castTime and skill.source ~= "Enemy" and skill.source ~= "Basic" then
					Expect.truthy(skill.gcd, `{id}: off-GCD class actions are instant`)
				end
				if skill.delivery == "Projectile" or skill.delivery == "Target" then
					Expect.truthy(skill.speed and skill.range, `{id} projectile speed/range`)
				end
				if
					skill.delivery == "Target"
					or skill.delivery == "Dash"
					or skill.delivery == "Ally"
					or skill.delivery == "Leap"
				then
					Expect.truthy(skill.range, `{id} needs a range to validate its target`)
				end
				if skill.delivery == "Object" then
					Expect.truthy(skill.objectTag, `{id} objectTag`)
				end
			end
		end
	end,
	["skill animations resolve to manifest clips"] = function()
		for id, skill in Skills do
			if skill.animation then
				Expect.truthy(Animations[skill.animation], `{id}: unknown animation {skill.animation}`)
			end
		end
	end,
	["light chain is three basic melee hits with clips, ending heavier"] = function()
		local members = Chain.Members(Skills, Basic.Light)
		Expect.equal(#members, 3, "chain length")
		for _, id in members do
			local skill = Skills[id]
			Expect.truthy(skill, `{id} exists`)
			Expect.equal(skill.source, "Basic", `{id} source`)
			Expect.equal(skill.delivery, "Melee", `{id} delivery`)
			Expect.equal(skill.gcd, nil, `{id} off the GCD`)
			Expect.truthy(skill.animation and Animations[skill.animation], `{id} clip`)
		end
		local first, last = Skills[members[1]], Skills[members[3]]
		Expect.truthy(last.damage.base > first.damage.base, "finisher hits harder")
		Expect.truthy(last.cooldown > first.cooldown, "finisher recovers longer")
	end,
	["guard clips are in the manifest"] = function()
		Expect.truthy(Animations["GuardHold"], "GuardHold")
		Expect.truthy(Animations["GuardParry"], "GuardParry")
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
	["npcs resolve and never share an enemy id"] = function()
		for id, npc in Npcs do
			Expect.truthy(not Enemies[id], `{id} is both an enemy and an npc`)
			Expect.equal(npc.tier, "Civilian", id)
			Expect.equal(npc.template, "Human", id)
			Expect.truthy(npc.team and Factions[npc.team] and not Factions[npc.team].monster, `{id}: civilian faction`)
			Expect.truthy(npc.outfits and #npc.outfits > 0, `{id}: outfits`)
			for _, outfit in npc.outfits do
				Expect.truthy(Appearance.Outfits.ById[outfit], `{id}: outfit {outfit}`)
			end
			for _, skillId in npc.skills do
				Expect.truthy(Skills[skillId], `{id}: skill {skillId}`)
			end
			Expect.truthy(npc.combat, `{id}: combat data`)
		end
	end,
	["enemy combat data resolves"] = function()
		for id, enemy in Enemies do
			local combat = enemy.combat
			Expect.truthy(combat, `{id}: combat data`)
			local morale = combat.morale
			if morale then
				Expect.truthy(morale.fleeBelow < morale.base, `{id}: flees below its base morale`)
			end
			for _, summon in combat.summons or {} do
				Expect.truthy(Enemies[summon.enemy], `{id}: summons unknown {summon.enemy}`)
				Expect.truthy(summon.belowHp > 0 and summon.belowHp < 1, `{id}: summon threshold`)
				Expect.truthy(summon.count >= 1 and summon.level >= 1, `{id}: summon count and level`)
				checkEffects(id, summon.selfEffects)
			end
			Expect.truthy(
				enemy.behavior == nil or enemy.behavior == "Boss" or enemy.behavior == "Dummy",
				`{id}: behavior is only for special cases`
			)
		end
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
	["enemy attacks state their parry class and keep area telegraphs"] = function()
		local parries = { Normal = true, Heavy = true, None = true }
		for id, skill in Skills do
			if skill.source ~= "Enemy" or not skill.damage then
				continue
			end
			Expect.truthy(skill.parry and parries[skill.parry], `{id}: parry class`)
			local area = skill.delivery == "SelfArea" or skill.delivery == "Ground"
			if area then
				Expect.truthy(skill.telegraph ~= false, `{id}: area attacks keep their ground telegraph`)
			end
			if skill.telegraph == false then
				Expect.truthy(
					skill.delivery == "Melee" or skill.delivery == "Projectile",
					`{id}: only basic swings and throws, which play an Attack or Throw cue, drop the telegraph`
				)
				Expect.truthy(not skill.castTime, `{id}: casts keep their cast bar`)
			end
		end
	end,
}
