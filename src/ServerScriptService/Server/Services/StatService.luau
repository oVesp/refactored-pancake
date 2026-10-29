--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Content.Classes)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NpcDefs = require(ReplicatedStorage.Shared.NpcDefs)
local Items = require(ReplicatedStorage.Content.Items)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Skills = require(ReplicatedStorage.Content.Skills)
local Statuses = require(ReplicatedStorage.Content.Statuses)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local Attributes = Constants.Attributes
local REGEN_INTERVAL = 0.25

local log = Logger.new("StatService")

local DataService: any
local EntityService: any

--[=[
	Owns entity stats and pools. HP, MP and Stamina live on the entity table and are mirrored to
	attributes for display; the Humanoid's health mirrors HP so Roblox death stays consistent.
]=]
local StatService = {}

local function writePools(entity: Entity)
	local model = entity.model
	model:SetAttribute(Attributes.Hp, entity.hp)
	model:SetAttribute(Attributes.MaxHp, entity.stats.MaxHp)
	model:SetAttribute(Attributes.Mp, math.floor(entity.mp))
	model:SetAttribute(Attributes.MaxMp, entity.stats.MaxMp)
	model:SetAttribute("Stamina", math.floor(entity.stamina))
	model:SetAttribute("MaxStamina", entity.maxStamina)
	model:SetAttribute("Shield", entity.shield)
	local humanoid = entity.humanoid
	if humanoid and humanoid.Health > 0 then
		humanoid.MaxHealth = math.max(entity.stats.MaxHp, 1)
		humanoid.Health = math.max(entity.hp, if entity.alive then 0.01 else 0)
	end
end

local function statusModifiers(entity: Entity): ({ Formulas.StatBlock }, number)
	local blocks = {}
	local moveMultiplier = 1
	for id, status in entity.statuses do
		local def = Statuses.ById[id]
		if def then
			if def.modifiers then
				table.insert(blocks, def.modifiers)
			end
			if def.kind == "Move" then
				moveMultiplier *= math.clamp(1 - status.magnitude, 0, 1)
			elseif def.kind == "Root" or def.kind == "Stun" then
				moveMultiplier = 0
			end
		end
	end
	if entity.commitUntil > os.clock() then
		moveMultiplier *= Tuning.Combat.Commit.MoveMultiplier
	end
	return blocks, moveMultiplier
end

local function playerModifiers(profile: any): { Formulas.StatBlock }
	local blocks = {}
	for _, skillId in Formulas.GrantedSkills(profile.classes, Classes.ById) do
		local skill = Skills.ById[skillId]
		if skill and skill.kind == "Passive" and skill.modifiers then
			table.insert(blocks, skill.modifiers)
		end
	end
	for _, uid in profile.equipment do
		for _, stack in profile.inventory do
			if stack.uid == uid then
				local item = Items.ById[stack.id]
				if item and item.modifiers then
					table.insert(blocks, item.modifiers)
				end
			end
		end
	end
	return blocks
end

--[=[ Character level from a profile's XP. ]=]
function StatService.LevelFromProfile(profile: any): number
	return (Formulas.CharacterLevel(profile.xp, Tuning.Progression.XpToNext, Tuning.Progression.LevelCap))
end

--[=[
	Recomputes stats from classes, passives, equipment and statuses (players) or enemy data
	(NPCs), then updates pools, attributes and walk speed. Raising MaxHp raises HP by the same amount.
]=]
function StatService.Recompute(entity: Entity)
	local base: Formulas.StatBlock = table.clone(Tuning.Base.Stats)
	local classes = {}
	local modifiers, moveMultiplier = statusModifiers(entity)

	if entity.kind == "Player" and entity.player then
		local profile = DataService.Get(entity.player)
		if profile then
			classes = profile.classes
			for _, block in playerModifiers(profile) do
				table.insert(modifiers, block)
			end
			entity.level = StatService.LevelFromProfile(profile)
		end
	else
		local def = NpcDefs.Get(entity.defId)
		if def then
			base = {}
			for name, value in def.base do
				base[name] = value
			end
			for name, value in def.growth do
				base[name] = (base[name] or 0) + value * (entity.level - 1)
			end
		end
	end

	local previousMaxHp = entity.stats.MaxHp
	local stats, extras = Formulas.ComputeStats({
		base = base,
		classes = classes,
		classDefs = Classes.ById,
		modifiers = modifiers,
	})
	entity.stats = stats
	entity.extras = extras
	entity.maxStamina = Tuning.Base.MaxStamina

	if previousMaxHp and stats.MaxHp > previousMaxHp and entity.alive then
		entity.hp += stats.MaxHp - previousMaxHp
	end
	entity.hp = math.clamp(entity.hp, 0, stats.MaxHp)
	entity.mp = math.clamp(entity.mp, 0, stats.MaxMp)
	entity.stamina = math.clamp(entity.stamina, 0, entity.maxStamina)

	entity.model:SetAttribute("Level", entity.level)
	for _, name in Formulas.StatNames do
		entity.model:SetAttribute("Stat_" .. name, stats[name])
	end
	for _, name in Formulas.ExtraNames do
		entity.model:SetAttribute("Extra_" .. name, if extras[name] ~= 0 then extras[name] else nil)
	end
	entity.model:SetAttribute(
		Attributes.MaxFocus,
		Formulas.DisciplineCapacity(entity.level, Tuning.Disciplines.CapacityBase, Tuning.Disciplines.CapacityPerLevels)
	)

	local humanoid = entity.humanoid
	if humanoid and entity.kind == "Player" then
		local agilitySpeed = 1 + (stats.Agility - Tuning.Base.Stats.Agility) * Tuning.Combat.MoveSpeedPerAgility
		humanoid.WalkSpeed = Tuning.Base.MoveSpeed * agilitySpeed * (1 + extras.MoveSpeedPct) * moveMultiplier
		humanoid.JumpPower = if moveMultiplier == 0 then 0 else 50
	elseif humanoid then
		local def = NpcDefs.Get(entity.defId)
		local speed = if def then def.moveSpeed else 0
		humanoid.WalkSpeed = speed * (1 + extras.MoveSpeedPct) * moveMultiplier
	end

	writePools(entity)
end

--[=[ Fills HP, MP and Stamina to max. ]=]
function StatService.Refill(entity: Entity)
	entity.hp = entity.stats.MaxHp
	entity.mp = entity.stats.MaxMp
	entity.stamina = entity.maxStamina
	writePools(entity)
end

--[=[ Sets HP (clamped) and mirrors it. Does not handle death; CombatService does. ]=]
function StatService.SetHp(entity: Entity, hp: number)
	entity.hp = math.clamp(math.floor(hp + 0.5), 0, entity.stats.MaxHp)
	writePools(entity)
end

--[=[ Sets the absorb shield amount. ]=]
function StatService.SetShield(entity: Entity, amount: number)
	entity.shield = math.max(0, math.floor(amount + 0.5))
	writePools(entity)
end

--[=[ Spends MP or Stamina if enough is available. Returns false and spends nothing otherwise. ]=]
function StatService.Spend(entity: Entity, resource: "Mp" | "Stamina", amount: number): boolean
	if resource == "Mp" then
		if entity.mp < amount then
			return false
		end
		entity.mp -= amount
	else
		if entity.stamina < amount then
			return false
		end
		entity.stamina -= amount
	end
	writePools(entity)
	return true
end

--[=[ Restores MP or HP from items or effects. ]=]
function StatService.Restore(entity: Entity, resource: "Hp" | "Mp", amount: number)
	if resource == "Hp" then
		entity.hp = math.min(entity.stats.MaxHp, entity.hp + amount)
	else
		entity.mp = math.min(entity.stats.MaxMp, entity.mp + amount)
	end
	writePools(entity)
end

local function regenerate(dt: number)
	local now = os.clock()
	for _, entity in EntityService.All() do
		if not entity.alive or entity.kind ~= "Player" then
			continue
		end
		local changed = false
		local mpRate = Tuning.Base.MpRegen + entity.extras.MpRegen
		if entity.mp < entity.stats.MaxMp then
			entity.mp = math.min(entity.stats.MaxMp, entity.mp + mpRate * dt)
			changed = true
		end
		if entity.stamina < entity.maxStamina and entity.guardSince == nil then
			entity.stamina = math.min(entity.maxStamina, entity.stamina + Tuning.Base.StaminaRegen * dt)
			changed = true
		end
		if entity.hp < entity.stats.MaxHp and now - entity.lastCombatAt > Tuning.Base.OutOfCombatDelay then
			entity.hp = math.min(entity.stats.MaxHp, entity.hp + Tuning.Base.HpRegenOutOfCombat * dt)
			changed = true
		end
		if changed then
			writePools(entity)
		end
	end
end

local function setUpCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		log:Warn("Character for %d is missing Humanoid or root", player.UserId)
		return
	end
	if not character:IsDescendantOf(game) then
		return
	end

	local profile = DataService.WaitForProfile(player)
	if not profile or not character:IsDescendantOf(game) then
		return
	end

	humanoid.BreakJointsOnDeath = false
	local entity = EntityService.Register({
		model = character,
		root = root,
		humanoid = humanoid,
		kind = "Player",
		player = player,
		team = "Players",
		defId = "player",
		name = player.DisplayName,
		level = StatService.LevelFromProfile(profile),
		tags = {},
	})
	-- A new character starts a new movement baseline; without this every respawn counts as a violation.
	EntityService.NoteTeleport(player)
	StatService.Recompute(entity)
	StatService.Refill(entity)

	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			EntityService.Unregister(character)
		end
	end)
end

function StatService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EntityService = deps.EntityService
end

function StatService.Start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			setUpCharacter(player, character)
		end)
		if player.Character then
			task.spawn(setUpCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.RespawnTime = Tuning.Death.RespawnSeconds

	DataService.Changed:Connect(function(player: Player)
		local entity = EntityService.ForPlayer(player)
		if entity then
			StatService.Recompute(entity)
		end
	end)

	task.spawn(function()
		while true do
			regenerate(task.wait(REGEN_INTERVAL))
		end
	end)
end

return StatService
