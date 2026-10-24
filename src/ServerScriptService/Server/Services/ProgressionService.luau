--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Content.Classes)
local Enemies = require(ReplicatedStorage.Content.Enemies)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Logger = require(ReplicatedStorage.Shared.Logger)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Skills = require(ReplicatedStorage.Content.Skills)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local log = Logger.new("ProgressionService")

local CombatService: any
local DataService: any
local DisciplineService: any
local EntityService: any
local SkillService: any
local StatService: any
local StatusService: any

local pendingSnapshot: { [Player]: boolean } = {}
local weakenOnSpawn: { [Player]: boolean } = {}

--[=[
	XP, character level, class training at trainers, spell picks, death debt and the profile
	snapshot sent to clients (scope 01, section 6).
]=]
local ProgressionService = {}

local function notify(player: Player, key: string, ...: any)
	NetServer.Fire("Notify", player, key, { ... })
end

local function levelInfo(profile: any): (number, number, number?)
	return Formulas.CharacterLevel(profile.xp, Tuning.Progression.XpToNext, Tuning.Progression.LevelCap)
end

--[=[ Builds the client snapshot: profile plus derived progression data. ]=]
function ProgressionService.Snapshot(player: Player): { [string]: any }?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local level, into, need = levelInfo(profile)
	return {
		level = level,
		xp = profile.xp,
		xpInto = into,
		xpNeed = need,
		xpDebt = profile.xpDebt,
		unspent = level - Formulas.TotalClassLevels(profile.classes),
		classes = profile.classes,
		spells = profile.spells,
		disciplines = profile.disciplines,
		picks = Formulas.SpellPicks(profile.classes, profile.spells, Classes.ById, Tuning.Magic.SpellPicksPerLevel),
		ceilings = Formulas.CircleCeilings(profile.classes, Classes.ById, Tuning.Magic),
		actives = SkillService.KnownActives(profile),
		granted = Formulas.GrantedSkills(profile.classes, Classes.ById),
		inventory = profile.inventory,
		equipment = profile.equipment,
	}
end

local function pushSnapshot(player: Player)
	if pendingSnapshot[player] then
		return
	end
	pendingSnapshot[player] = true
	task.defer(function()
		pendingSnapshot[player] = nil
		if player.Parent then
			local snapshot = ProgressionService.Snapshot(player)
			if snapshot then
				NetServer.Fire("SendProfileSnapshot", player, snapshot)
			end
		end
	end)
end

local function totalPicks(profile: any): number
	local total = 0
	for _, count in Formulas.SpellPicks(profile.classes, profile.spells, Classes.ById, Tuning.Magic.SpellPicksPerLevel) do
		total += count
	end
	return total
end

--[=[ Adds XP (repaying debt first) and announces level-ups. ]=]
function ProgressionService.GrantXp(player: Player, amount: number)
	local profile = DataService.Get(player)
	if not profile or amount <= 0 then
		return
	end
	local before = levelInfo(profile)
	DataService.Update(player, function(p: any)
		p.xp, p.xpDebt = Formulas.GainXp(p.xp, p.xpDebt, amount)
	end, "xp")
	local after = levelInfo(profile)
	if after > before then
		notify(player, "LevelUp", after)
	end
end

--[=[ Dev: sets XP to exactly the start of `level`, clearing debt. ]=]
function ProgressionService.SetLevel(player: Player, level: number)
	local target = math.clamp(math.floor(level), 1, Tuning.Progression.LevelCap)
	local xp = 0
	for i = 1, target - 1 do
		xp += Tuning.Progression.XpToNext[i]
	end
	DataService.Update(player, function(p: any)
		p.xp = xp
		p.xpDebt = 0
		local over = Formulas.TotalClassLevels(p.classes) - target
		while over > 0 and #p.classes > 0 do
			local last = p.classes[#p.classes]
			last.level -= 1
			if last.level <= 0 then
				table.remove(p.classes)
			end
			over -= 1
		end
	end, "xp")
end

--[=[ Puts one unspent level into a class. Returns ok and a reason code. ]=]
function ProgressionService.TrainClass(player: Player, classId: string): (boolean, string?)
	local profile = DataService.Get(player)
	if not profile then
		return false, "NoProfile"
	end
	local ok, reason = Formulas.CanTrain(profile.classes, classId, Classes.ById, (levelInfo(profile)))
	if not ok then
		return false, reason
	end
	local newLevel = 0
	DataService.Update(player, function(p: any)
		for _, entry in p.classes do
			if entry.id == classId then
				entry.level += 1
				newLevel = entry.level
				return
			end
		end
		table.insert(p.classes, { id = classId, level = 1 })
		newLevel = 1
	end, "classes")
	notify(player, "Trained", Classes.ById[classId].name, newLevel)
	local picks = totalPicks(profile)
	if picks > 0 then
		notify(player, "SpellPickReady", picks)
	end
	return true, nil
end

--[=[ Dev: removes every level of a class (and spells only that class taught). ]=]
function ProgressionService.RemoveClass(player: Player, classId: string)
	DataService.Update(player, function(p: any)
		for index, entry in p.classes do
			if entry.id == classId then
				table.remove(p.classes, index)
				break
			end
		end
		local def = Classes.ById[classId]
		if def then
			for i = #p.spells, 1, -1 do
				if table.find(def.spellList, p.spells[i]) then
					table.remove(p.spells, i)
				end
			end
		end
	end, "classes")
end

local function learnSpell(player: Player, spellId: string)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local ok, reason =
		Formulas.CanLearnSpell(profile.classes, profile.spells, spellId, Classes.ById, Skills.ById, Tuning.Magic)
	if not ok then
		notify(player, reason or "UnknownSpell")
		return
	end
	DataService.Update(player, function(p: any)
		table.insert(p.spells, spellId)
	end, "spells")
	notify(player, "LearnedSpell", Skills.ById[spellId].name)
end

local function onTrainerPrompt(prompt: ProximityPrompt, player: Player)
	local body = prompt.Parent
	if not body then
		return
	end
	local kind = body:GetAttribute("TrainerType")
	if kind == "Class" then
		local classId = body:GetAttribute("ClassId")
		if type(classId) == "string" then
			local ok, reason = ProgressionService.TrainClass(player, classId)
			if not ok then
				notify(player, reason or "UnknownClass")
			end
		end
	elseif kind == "Discipline" then
		DisciplineService.LearnAll(player)
	elseif kind == "Vendor" then
		notify(player, "VendorClosed")
	end
end

local function bindTrainer(instance: Instance)
	local prompt = instance:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			onTrainerPrompt(prompt, player)
		end)
	end
end

local function onDied(victim: Entity, killer: Entity?)
	if victim.kind == "Npc" and killer and killer.kind == "Player" and killer.player then
		local def = Enemies.ById[victim.defId]
		if def then
			local amount = Formulas.KillXp(
				def.xp,
				victim.level,
				killer.level,
				Tuning.Progression.KillXpLevelGapStep,
				Tuning.Progression.KillXpMin,
				Tuning.Progression.KillXpMax
			)
			ProgressionService.GrantXp(killer.player, amount)
		end
	elseif victim.kind == "Player" and victim.player then
		local player = victim.player
		local profile = DataService.Get(player)
		if profile then
			local level = levelInfo(profile)
			local curve = Tuning.Progression.XpToNext
			local basis = curve[math.min(level, #curve)]
			local debt = math.floor(basis * Tuning.Death.DebtFraction + 0.5)
			DataService.Update(player, function(p: any)
				p.xpDebt += debt
			end, "xp")
			weakenOnSpawn[player] = true
			notify(player, "Died", profile.xpDebt)
			NetServer.Fire("SendDeathState", player, { respawnIn = Tuning.Death.RespawnSeconds, debt = profile.xpDebt })
			log:Debug("Player %d died; debt now %d", player.UserId, profile.xpDebt)
		end
	end
end

function ProgressionService.Init(deps: { [string]: any })
	CombatService = deps.CombatService
	DataService = deps.DataService
	DisciplineService = deps.DisciplineService
	EntityService = deps.EntityService
	SkillService = deps.SkillService
	StatService = deps.StatService
	StatusService = deps.StatusService

	NetServer.Connect("RequestProfile", pushSnapshot)
	NetServer.Connect("LearnSpell", learnSpell)
end

function ProgressionService.Start()
	DataService.Changed:Connect(pushSnapshot)
	CombatService.Died:Connect(onDied)

	EntityService.Added:Connect(function(entity: Entity)
		local player = entity.player
		if player and weakenOnSpawn[player] then
			weakenOnSpawn[player] = nil
			StatusService.Apply(entity, "weakened", Tuning.Death.WeakenedDuration, nil, nil)
			StatService.Refill(entity)
		end
		if player then
			pushSnapshot(player)
		end
	end)

	for _, instance in CollectionService:GetTagged("Trainer") do
		bindTrainer(instance)
	end
	CollectionService:GetInstanceAddedSignal("Trainer"):Connect(bindTrainer)

	Players.PlayerRemoving:Connect(function(player)
		pendingSnapshot[player] = nil
		weakenOnSpawn[player] = nil
	end)
end

return ProgressionService
