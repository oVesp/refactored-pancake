--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Disciplines = require(ReplicatedStorage.Content.Disciplines)
local Hotbar = require(ReplicatedStorage.Shared.Hotbar)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local FOCUS_REFRESH = 0.25

local DataService: any
local EntityService: any
local StatusService: any

--[=[
	Disciplines (game-design.md 3.3, scope 01 D3): learned from the Discipline trainer, toggled
	on top of action combat, each occupying Focus capacity while active.
]=]
local DisciplineService = {}

local function notify(player: Player, key: string, ...: any)
	NetServer.Fire("Notify", player, key, { ... })
end

local function usedCapacity(entity: Entity): number
	local used = 0
	for _, id in Disciplines.Order do
		local def = Disciplines.ById[id]
		if entity.statuses[def.status] then
			used += def.cost
		end
	end
	return used
end

local function refreshFocus(entity: Entity)
	local capacity = entity.model:GetAttribute(Constants.Attributes.MaxFocus)
	if type(capacity) == "number" then
		entity.model:SetAttribute(Constants.Attributes.Focus, capacity - usedCapacity(entity))
	end
end

--[=[ Teaches every Discipline the trainer offers that the player does not know yet. ]=]
function DisciplineService.LearnAll(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local learned = {}
	DataService.Update(player, function(p: any)
		for _, id in Disciplines.Order do
			if not table.find(p.disciplines, id) then
				table.insert(p.disciplines, id)
				table.insert(learned, Disciplines.ById[id].name)
				Hotbar.AutoPlace(p.hotbar, Hotbar.Encode("Discipline", id))
			end
		end
	end, "disciplines")
	if #learned == 0 then
		notify(player, "DisciplinesKnown")
	else
		for _, name in learned do
			notify(player, "LearnedDiscipline", name)
		end
	end
end

local function toggle(player: Player, id: string)
	local def = Disciplines.ById[id]
	local profile = DataService.Get(player)
	local entity = EntityService.ForPlayer(player)
	if not def or not profile or not entity or not entity.alive or not table.find(profile.disciplines, id) then
		return
	end

	if entity.statuses[def.status] then
		if def.mode == "Toggle" then
			StatusService.Remove(entity, def.status)
			refreshFocus(entity)
		end
		return
	end

	local key = "discipline:" .. id
	if StatusService.IsDisabled(entity) or os.clock() < (entity.cooldowns[key] or 0) then
		return
	end
	local capacity = entity.model:GetAttribute(Constants.Attributes.MaxFocus)
	if type(capacity) ~= "number" or usedCapacity(entity) + def.cost > capacity then
		notify(player, "NoFocus")
		return
	end
	entity.cooldowns[key] = os.clock() + def.cooldown
	StatusService.Apply(entity, def.status, def.duration, nil, entity)
	refreshFocus(entity)
end

function DisciplineService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EntityService = deps.EntityService
	StatusService = deps.StatusService
	NetServer.Connect("ToggleDiscipline", toggle)
end

function DisciplineService.Start()
	task.spawn(function()
		while true do
			task.wait(FOCUS_REFRESH)
			for _, entity in EntityService.All() do
				if entity.kind == "Player" then
					refreshFocus(entity)
				end
			end
		end
	end)
end

return DisciplineService
