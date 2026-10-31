--!strict

-- Weapon types, held loadouts and bow maths (docs/systems/weapons.md).
local Expect = require("../Expect")
local Loader = require("../Loader")

local Content = "src/ReplicatedStorage/Content/"
local Weapons = Loader.load(Content .. "Weapons")
local Items = Loader.load(Content .. "Items")
local Classes = Loader.load(Content .. "Classes").ById
local Skills = Loader.load(Content .. "Skills").ById
local Tuning = Loader.load(Content .. "Tuning")
local Animations = require("../AnimationKeys")()
local Chain = Loader.load("src/ReplicatedStorage/Shared/Chain")
local Loadout = Loader.load("src/ReplicatedStorage/Shared/Loadout")
local Archery = Loader.load("src/ReplicatedStorage/Shared/Archery")
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3

local function profile(equipment: { [string]: number }, ids: { string }): any
	local inventory = {}
	for uid, id in ids do
		table.insert(inventory, { uid = uid, id = id, count = 1 })
	end
	return { inventory = inventory, equipment = equipment }
end

return {
	["every weapon's basics are basic, off-GCD skills"] = function()
		Expect.truthy(Weapons.ById[Weapons.Default], "default weapon")
		for id, weapon in Weapons.ById do
			local basics = Loadout.Basics(Skills, weapon, false, Weapons.ShieldBash)
			for _, skillId in basics do
				local skill = Skills[skillId]
				Expect.truthy(skill, `{id}: {skillId} exists`)
				Expect.equal(skill.source, "Basic", `{skillId} source`)
				Expect.equal(skill.gcd, nil, `{skillId} off the GCD`)
				Expect.truthy(skill.animation == nil or Animations[skill.animation], `{skillId} clip`)
			end
			Expect.equal(weapon.drawn == true, weapon.heavy == nil, `{id}: only the drawn weapon has no heavy`)
			Expect.truthy(weapon.model == nil or weapon.hand, `{id}: a held model names its hand`)
		end
		Expect.truthy(Skills[Weapons.ShieldBash], "shield bash")
	end,
	["every chainNext belongs to a weapon chain"] = function()
		local chained = {}
		for _, weapon in Weapons.ById do
			for _, id in Chain.Members(Skills, weapon.light) do
				chained[id] = true
			end
		end
		for id, skill in Skills do
			if skill.chainNext then
				Expect.truthy(chained[id], `{id}: chainNext outside every weapon chain`)
			end
		end
	end,
	["wand chains committed bolts and casts its blast"] = function()
		local wand = Weapons.ById.wand
		local chain = Chain.Members(Skills, wand.light)
		Expect.equal(table.concat(chain, ","), "wand_bolt,wand_bolt_2,wand_bolt_3", "wand chain")
		for _, id in chain do
			local bolt = Skills[id]
			Expect.equal(bolt.delivery, "Projectile", `{id} delivery`)
			Expect.truthy(bolt.windup and bolt.recovery, `{id}: bolts commit the caster`)
			Expect.equal(bolt.range, 90, `{id} range`)
		end
		Expect.truthy(Skills.wand_bolt_3.damage.base > Skills.wand_bolt.damage.base, "closing bolt hits harder")
		local clips = {}
		for _, id in chain do
			Expect.truthy(Skills[id].animation, `{id} plays a clip`)
			Expect.equal(clips[Skills[id].animation], nil, `{id}: each step its own clip`)
			clips[Skills[id].animation] = true
		end
		local blast = Skills[wand.heavy]
		Expect.truthy(blast.castTime and blast.castTime > 0, "blast has a cast time")
		Expect.truthy(blast.cooldown and blast.cooldown >= blast.castTime, "blast cooldown")
		Expect.equal(blast.windup, nil, "blast casts, it does not wind up")
		Expect.equal(blast.gcd, nil, "blast off the GCD")
		Expect.truthy(blast.cost == nil or blast.cost.resource ~= "Mp", "blast costs no MP")
	end,
	["weapon and shield items resolve"] = function()
		for id, item in Items.ById do
			if item.kind == "Weapon" then
				Expect.truthy(item.weapon and Weapons.ById[item.weapon], `{id}: weapon type`)
			elseif item.kind == "Shield" then
				Expect.truthy(item.shield and item.shield.model, `{id}: shield data`)
			end
		end
		Expect.equal(Items.Slots.offhand, "Shield", "offhand slot")
	end,
	["loadout reads the equipped weapon and shield"] = function()
		local unarmed = Loadout.Of(profile({}, {}), Items.ById, Weapons.ById, Weapons.Default)
		Expect.equal(unarmed.weapon.id, "fists", "unarmed")
		Expect.equal(unarmed.shield, nil, "no shield")
		local armed = Loadout.Of(
			profile({ weapon = 1, offhand = 2 }, { "rusty_sword", "wooden_shield" }),
			Items.ById,
			Weapons.ById,
			Weapons.Default
		)
		Expect.equal(armed.weapon.id, "sword", "sword")
		Expect.equal(armed.shieldId, "wooden_shield", "shield id")
		local basics = Loadout.Basics(Skills, armed.weapon, true, Weapons.ShieldBash)
		Expect.truthy(table.find(basics, "shield_bash"), "bash with a shield")
		Expect.equal(table.find(basics, "strike"), nil, "no fist basics with a sword")
	end,
	["two hands push the shield off and back"] = function()
		local bow = Items.ById.hunting_bow
		local shield = Items.ById.wooden_shield
		local sword = Weapons.ById.sword
		Expect.equal(Loadout.Displaced("Weapon", bow, sword, Weapons.ById)[1], "offhand", "bow drops shield")
		Expect.equal(#Loadout.Displaced("Weapon", Items.ById.rusty_sword, sword, Weapons.ById), 0, "sword keeps it")
		Expect.equal(
			Loadout.Displaced("Shield", shield, Weapons.ById.staff, Weapons.ById)[1],
			"weapon",
			"shield drops staff"
		)
		Expect.equal(#Loadout.Displaced("Shield", shield, Weapons.ById.wand, Weapons.ById), 0, "wand keeps it")
	end,
	["a weaponAttack skill takes on each weapon's light attack"] = function()
		local precise = Skills.precise_attack
		local scale = precise.weaponAttack.scale
		for id, weapon in Weapons.ById do
			local light = Skills[weapon.light]
			local used = Loadout.Attack(Skills, precise, weapon)
			Expect.equal(used.id, "precise_attack", `{id}: keeps its id`)
			Expect.equal(used.shownAs, weapon.light, `{id}: shows the light attack`)
			Expect.equal(used.delivery, light.delivery, `{id}: delivery`)
			Expect.equal(used.range, light.range, `{id}: range`)
			Expect.equal(used.windup, light.windup, `{id}: windup`)
			Expect.equal(used.recovery, light.recovery, `{id}: recovery`)
			Expect.equal(used.speed, light.speed, `{id}: speed`)
			Expect.equal(used.drawn, light.drawn, `{id}: draw`)
			Expect.equal(used.damage.type, "physical", `{id}: always physical`)
			Expect.equal(used.damage.stat, "PhysAtk", `{id}: always scales with PhysAtk`)
			Expect.truthy(math.abs(used.damage.base - light.damage.base * scale) < 1e-6, `{id}: base`)
			Expect.truthy(math.abs(used.damage.ratio - light.damage.ratio * scale) < 1e-6, `{id}: ratio`)
			Expect.equal(used.gcd, true, `{id}: on the GCD`)
			Expect.equal(used.critChance, precise.critChance, `{id}: crit`)
			Expect.equal(used.maxTargets, precise.maxTargets, `{id}: single target`)
			Expect.equal(used.cooldown, nil, `{id}: no light cooldown`)
			Expect.equal(used.chainNext, nil, `{id}: outside the chain`)
		end
		Expect.equal(Skills.bow_shot.damage.base, 12, "the light attack itself is untouched")
		Expect.equal(Skills.staff_strike.damage.type, "force", "the staff's own attack stays force")
		Expect.equal(Skills.wand_bolt.damage.stat, "MagAtk", "the wand's own attack stays MagAtk")
		Expect.equal(
			Loadout.Attack(Skills, Skills.strike, Weapons.ById.sword),
			Skills.strike,
			"other skills pass through"
		)
	end,
	["every class lists real weapon types; only the fighter lacks the wand"] = function()
		for id, class in Classes do
			for _, weaponId in class.weapons do
				Expect.truthy(Weapons.ById[weaponId], `{id}: {weaponId}`)
			end
			for weaponId in Weapons.ById do
				local allowed = table.find(class.weapons, weaponId) ~= nil
				Expect.equal(allowed, not (id == "fighter" and weaponId == "wand"), `{id}: {weaponId}`)
			end
		end
	end,
	["a weapon needs any class that allows it"] = function()
		local wand = Items.ById.apprentice_wand
		local sword = Items.ById.rusty_sword
		local fighter = { id = "fighter", level = 1 }
		local mage = { id = "mage", level = 1 }
		Expect.equal(Loadout.CanEquip({ fighter }, wand, Classes), false, "fighter refuses the wand")
		Expect.truthy(Loadout.CanEquip({ fighter }, sword, Classes), "fighter takes the sword")
		Expect.truthy(Loadout.CanEquip({ mage }, wand, Classes), "mage takes the wand")
		Expect.truthy(Loadout.CanEquip({ fighter, mage }, wand, Classes), "multiclass takes the wand")
		Expect.equal(Loadout.CanEquip({}, sword, Classes), false, "no class, no weapon")
		Expect.equal(Loadout.CanEquip({ { id = "retired", level = 1 } }, sword, Classes), false, "unknown class")
		Expect.truthy(Loadout.CanEquip({ fighter }, Items.ById.wooden_shield, Classes), "shields are open")
		Expect.truthy(Loadout.CanEquip({}, Items.ById.minor_health_potion, Classes), "non-weapons are open")
	end,
	["guarding needs a guarding weapon or a shield"] = function()
		Expect.truthy(Loadout.CanGuard(Weapons.ById.sword, false), "sword")
		Expect.equal(Loadout.CanGuard(Weapons.ById.bow, false), false, "bow alone")
		Expect.truthy(Loadout.CanGuard(Weapons.ById.wand, true), "wand with shield")
	end,
	["bow draw scales, peaks in the perfect window and needs a minimum"] = function()
		local bow = Tuning.Combat.Bow
		Expect.equal(Archery.DrawScale(bow.MinDraw - 0.01, bow), 0, "too short")
		local early = Archery.DrawScale(bow.MinDraw, bow)
		Expect.truthy(math.abs(early - bow.MinScale) < 1e-6, "min scale at min draw")
		local mid = Archery.DrawScale((bow.MinDraw + bow.FullDraw) / 2, bow)
		Expect.truthy(mid > early and mid < 1, "grows while drawing")
		local perfect, isPerfect = Archery.DrawScale(bow.FullDraw + bow.PerfectWindow / 2, bow)
		Expect.truthy(isPerfect and math.abs(perfect - (1 + bow.PerfectBonus)) < 1e-6, "perfect release")
		local late, isLate = Archery.DrawScale(bow.FullDraw + bow.PerfectWindow + 0.5, bow)
		Expect.equal(late, 1, "held too long")
		Expect.equal(isLate, false, "not perfect")
	end,
	["rear hits come from behind the target"] = function()
		local origin = Vector3.new(0, 0, 0)
		local look = Vector3.new(0, 0, -1)
		Expect.truthy(Archery.FromBehind(origin, look, Vector3.new(0, 0, 10), 120), "behind")
		Expect.equal(Archery.FromBehind(origin, look, Vector3.new(0, 0, -10), 120), false, "in front")
		Expect.equal(Archery.FromBehind(origin, look, Vector3.new(10, 0, 0), 120), false, "beside")
	end,
}
