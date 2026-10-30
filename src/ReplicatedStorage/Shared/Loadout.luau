--!strict

local Chain = require(script.Parent.Chain)
local Types = require(script.Parent.Parent.Content.Types)

--[=[
	What a character holds (docs/systems/weapons.md): pure rules shared by the server (from the
	profile) and the client (from the character's `Weapon` and `Shield` attributes).
]=]
local Loadout = {}

type ItemMap = { [string]: Types.ItemDef }
type WeaponMap = { [string]: Types.WeaponDef }
-- Skills.ById; only `chainNext` is read.
type SkillMap = { [string]: any }

export type Held = {
	weapon: Types.WeaponDef,
	--[=[ Equipped shield item id, if any. ]=]
	shieldId: string?,
	shield: Types.ShieldDef?,
}

local function itemIn(profile: any, items: ItemMap, uid: number?): Types.ItemDef?
	if not uid then
		return nil
	end
	for _, stack in profile.inventory do
		if stack.uid == uid then
			return items[stack.id]
		end
	end
	return nil
end

--[=[ The weapon and shield a profile has equipped; no weapon means `defaultWeapon` (fists). ]=]
function Loadout.Of(profile: any, items: ItemMap, weapons: WeaponMap, defaultWeapon: string): Held
	local weaponItem = itemIn(profile, items, profile.equipment.weapon)
	local shieldItem = itemIn(profile, items, profile.equipment.offhand)
	local weapon = weaponItem and weaponItem.weapon and weapons[weaponItem.weapon] or weapons[defaultWeapon]
	local shield = if shieldItem and shieldItem.shield then shieldItem else nil
	return {
		weapon = weapon,
		shieldId = if shield then shield.id else nil,
		shield = if shield then shield.shield else nil,
	}
end

--[=[ Basic attacks the holder may use: the weapon's light chain and heavy, plus `bash` with a shield. ]=]
function Loadout.Basics(skills: SkillMap, weapon: Types.WeaponDef, hasShield: boolean, bash: string): { string }
	local basics = Chain.Members(skills, weapon.light)
	if weapon.heavy then
		table.insert(basics, weapon.heavy)
	end
	if hasShield then
		table.insert(basics, bash)
	end
	return basics
end

--[=[ True when the holder can guard: a shield, or a weapon that guards on its own. ]=]
function Loadout.CanGuard(weapon: Types.WeaponDef, hasShield: boolean): boolean
	return hasShield or weapon.guard
end

--[=[
	Slots to clear when equipping an item of `kind` (`weapon` or `offhand`): a two-handed weapon
	pushes the shield off, and a shield pushes a two-handed weapon off.
]=]
function Loadout.Displaced(kind: string, item: Types.ItemDef, current: Types.WeaponDef, weapons: WeaponMap): { string }
	if kind == "Weapon" then
		local weapon = item.weapon and weapons[item.weapon]
		return if weapon and weapon.hands == "Two" then { "offhand" } else {}
	elseif kind == "Shield" then
		return if current.hands == "Two" then { "weapon" } else {}
	end
	return {}
end

return table.freeze(Loadout)
