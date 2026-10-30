--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Items = require(ReplicatedStorage.Content.Items)
local Loadout = require(ReplicatedStorage.Shared.Loadout)
local Loot = require(ServerStorage.ContentServerOnly.Loot)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Profile = require(script.Parent.Parent.Data.Profile)
local Types = require(script.Parent.Parent.Types)
local Weapons = require(ReplicatedStorage.Content.Weapons)

type Entity = Types.Entity

local CombatService: any
local DataService: any
local EntityService: any
local StatService: any

local random = Random.new()

--[=[
	Inventory, equipment, consumables and loot (scope 01, section 6). Drops go straight to the
	killer's inventory; there is no world pickup in M0.5.
]=]
local InventoryService = {}

local function notify(player: Player, key: string, ...: any)
	NetServer.Fire("Notify", player, key, { ... })
end

--[=[ Grants items. Returns how many did not fit. ]=]
function InventoryService.Grant(player: Player, itemId: string, count: number): number
	local def = Items.ById[itemId]
	if not def or count <= 0 or not DataService.Get(player) then
		return count
	end
	local leftover = 0
	DataService.Update(player, function(p: any)
		leftover = Profile.AddItem(p, itemId, count, def.stack, Items.InventorySize)
	end, "inventory")
	if count - leftover > 0 then
		NetServer.Fire("ShowGain", player, "Item", def.name, count - leftover)
	end
	if leftover > 0 then
		notify(player, "InventoryFull")
	end
	return leftover
end

local function rollLoot(player: Player, enemyId: string)
	for _, drop in (Loot[enemyId] or {}) :: { Loot.Drop } do
		if random:NextNumber() < drop.chance then
			InventoryService.Grant(player, drop.item, random:NextInteger(drop.min, drop.max))
		end
	end
end

local function equip(player: Player, uid: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local stack = Profile.FindStack(profile, uid)
	local def = stack and Items.ById[stack.id]
	if not def then
		return
	end
	-- Two hands: a two-handed weapon and a shield push each other off (docs/systems/weapons.md).
	local current = Loadout.Of(profile, Items.ById, Weapons.ById, Weapons.Default).weapon
	local displaced = Loadout.Displaced(def.kind, def, current, Weapons.ById)
	for slot, kind in Items.Slots do
		if kind == def.kind then
			DataService.Update(player, function(p: any)
				p.equipment[slot] = uid
				for _, other in displaced do
					p.equipment[other] = nil
				end
			end, "equipment")
			return
		end
	end
end

local function unequip(player: Player, slot: string)
	if not Items.Slots[slot] or not DataService.Get(player) then
		return
	end
	DataService.Update(player, function(p: any)
		p.equipment[slot] = nil
	end, "equipment")
end

local function use(player: Player, uid: number)
	local profile = DataService.Get(player)
	local entity = EntityService.ForPlayer(player)
	if not profile or not entity or not entity.alive then
		return
	end
	local stack = Profile.FindStack(profile, uid)
	local def = stack and Items.ById[stack.id]
	if not def or def.kind ~= "Consumable" or not def.use then
		return
	end
	local key = "item:" .. def.id
	if os.clock() < (entity.cooldowns[key] or 0) then
		return
	end
	entity.cooldowns[key] = os.clock() + 2
	DataService.Update(player, function(p: any)
		Profile.ConsumeOne(p, uid)
	end, "inventory")
	if def.use.hp then
		CombatService.Heal(entity, entity, def.use.hp)
	end
	if def.use.mp then
		StatService.Restore(entity, "Mp", def.use.mp)
	end
end

function InventoryService.Init(deps: { [string]: any })
	CombatService = deps.CombatService
	DataService = deps.DataService
	EntityService = deps.EntityService
	StatService = deps.StatService
	NetServer.Connect("EquipItem", equip)
	NetServer.Connect("UnequipSlot", unequip)
	NetServer.Connect("UseItem", use)
end

function InventoryService.Start()
	CombatService.Died:Connect(function(victim: Entity, killer: Entity?)
		if victim.kind == "Npc" and killer and killer.player then
			rollLoot(killer.player, victim.defId)
		end
	end)
end

return InventoryService
