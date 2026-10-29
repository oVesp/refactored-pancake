--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local Logger = require(ReplicatedStorage.Shared.Logger)
local NpcDefs = require(ReplicatedStorage.Shared.NpcDefs)
local Population = require(ServerStorage.ContentServerOnly.Population)
local Route = require(ReplicatedStorage.Shared.Route)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type Group = any

local GROUND_TOP = 400 -- studs above which the ground is searched for route points
local RESIDENT_WANDER = 14
-- People leave the world (go indoors, off the map) only this far from every player.
local UNSEEN_DISTANCE = 140
local TRADE_DISTANCE = 10

local log = Logger.new("PopulationService")

local EntityService: any
local GroupService: any

local random = Random.new()

type Schedule = {
	label: string,
	active: { Group },
	max: number,
	interval: number,
	nextAt: number,
	time: ("Day" | "Night")?,
	dispatch: () -> Group?,
}

local schedules: { Schedule } = {}
local residents: { Group } = {}

--[=[
	Fills Midgard from `ContentServerOnly/Population` (docs/systems/open-world.md): garrisons and
	nest lairs that hold their ground and replace their dead, patrols, caravans and travelers sent
	along their routes on timers, townsfolk that thin out at night, and nest squads that roam their
	territory, sent only while no player is near the nest. GroupService gives them bodies near
	players.
]=]
local PopulationService = {}

local function ground(x: number, z: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local world = workspace:FindFirstChild("World")
	params.FilterDescendantsInstances = if world then { workspace.Terrain, world } else { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, GROUND_TOP, z), Vector3.new(0, -GROUND_TOP * 2, 0), params)
	return Vector3.new(x, if hit then hit.Position.Y else 0, z)
end

local function points(list: { { number } }): { Vector3 }
	local out = {}
	for _, p in list do
		table.insert(out, ground(p[1], p[2]))
	end
	return out
end

local function isNight(): boolean
	return DayCycle.IsNight(DayCycle.ClockAt(workspace:GetServerTimeNow()))
end

local function timeFits(time: ("Day" | "Night")?): boolean
	return time == nil or (time == "Night") == isNight()
end

local function memberSpec(npc: string, level: { number }?): any
	local def = NpcDefs.Get(npc)
	local low = if level then level[1] elseif def then def.levelMin else 1
	local high = if level then level[2] elseif def then def.levelMax else low
	return { npc = npc, level = random:NextInteger(low, high), range = level, hp = 1, entity = nil }
end

local function expand(members: { Population.Member }): { any }
	local out = {}
	for _, member in members do
		for _ = 1, member.count do
			table.insert(out, memberSpec(member.npc, member.level))
		end
	end
	return out
end

-- A station that replaces each dead member after `respawnSeconds`.
local function garrison(def: Population.Garrison, label: string)
	GroupService.Create({
		label = label,
		members = expand(def.members),
		formation = "Ring",
		spacing = 4,
		station = ground(def.at[1], def.at[2]),
		wander = def.wander,
		keep = true,
		onLoss = function(group: Group, lost: any)
			task.delay(def.respawnSeconds, function()
				if not group.removed then
					GroupService.AddMember(group, memberSpec(lost.npc, lost.range))
				end
			end)
		end,
	})
end

local function forget(schedule: Schedule, group: Group)
	local index = table.find(schedule.active, group)
	if index then
		table.remove(schedule.active, index)
	end
	schedule.nextAt = os.clock() + schedule.interval
end

local function addSchedule(schedule: Schedule)
	table.insert(schedules, schedule)
end

-- Patrols, caravans and travelers walking their route in formation.
local function troopSchedule(troop: Population.Troop, warm: boolean)
	local route = Route.new(points(troop.route.points), troop.route.loop)
	local schedule: Schedule
	schedule = {
		label = troop.id,
		active = {},
		max = troop.max,
		interval = troop.interval,
		-- Loops start at once somewhere along the way, so the world is already busy on join.
		nextAt = if warm then 0 else os.clock() + random:NextNumber(0, troop.interval),
		time = troop.time,
		dispatch = function()
			local start = if warm and troop.route.loop then random:NextNumber(0, route.length) else 0
			local group: Group
			group = GroupService.Create({
				label = troop.id,
				members = expand(troop.members),
				formation = troop.formation,
				spacing = troop.spacing,
				route = route,
				stops = troop.route.stops,
				onEnd = function()
					forget(schedule, group)
				end,
				onEmpty = function()
					forget(schedule, group)
				end,
			}, start)
			return group
		end,
	}
	addSchedule(schedule)
end

local function nestSchedules(nest: Population.Nest)
	for _, station in nest.stationed do
		garrison(station, `{nest.id}/{station.id}`)
	end
	if #nest.squads == 0 then
		return
	end
	local territory = Route.new(points(nest.territory), true)
	local anchor = ground(nest.at[1], nest.at[2])
	local nextSquad = 0
	local schedule: Schedule
	schedule = {
		label = nest.id,
		active = {},
		max = nest.maxSquads,
		interval = nest.interval,
		nextAt = 0,
		time = nest.time,
		dispatch = function()
			if GroupService.NearestPlayer(anchor) <= Tuning.Population.HiddenRadius then
				return nil
			end
			nextSquad = nextSquad % #nest.squads + 1
			local squad = nest.squads[nextSquad]
			local group: Group
			group = GroupService.Create({
				label = nest.id,
				members = expand(squad.members),
				formation = squad.formation,
				spacing = 5,
				route = territory,
				onEmpty = function()
					forget(schedule, group)
				end,
			}, 0)
			return group
		end,
	}
	addSchedule(schedule)
end

-- Groups out at the wrong time of day go home once nobody can see them leave.
local function recall(schedule: Schedule)
	for _, group in table.clone(schedule.active) do
		if GroupService.NearestPlayer(group.position) > UNSEEN_DISTANCE then
			GroupService.Remove(group)
			forget(schedule, group)
		end
	end
end

local function runSchedules()
	local now = os.clock()
	for _, schedule in schedules do
		if not timeFits(schedule.time) then
			recall(schedule)
		elseif #schedule.active < schedule.max and now >= schedule.nextAt then
			local group = schedule.dispatch()
			if group then
				table.insert(schedule.active, group)
				schedule.nextAt = now + schedule.interval
			end
		end
	end
end

local function residentAt(def: Population.Residents): Vector3
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(0, def.radius)
	return ground(def.at[1] + math.cos(angle) * distance, def.at[2] + math.sin(angle) * distance)
end

-- Keeps the day or night head count of townsfolk.
local function runResidents()
	local night = isNight()
	for _, def in Population.Residents do
		local target = if night then def.night else def.day
		local own = {}
		for _, group in residents do
			if group.label == def.id and not group.removed then
				table.insert(own, group)
			end
		end
		if #own < target then
			local group: Group
			group = GroupService.Create({
				label = def.id,
				members = { memberSpec(def.npc, nil) },
				formation = "Ring",
				spacing = 4,
				station = residentAt(def),
				wander = RESIDENT_WANDER,
				onEmpty = function()
					local index = table.find(residents, group)
					if index then
						table.remove(residents, index)
					end
				end,
			})
			table.insert(residents, group)
		elseif #own > target then
			local group = own[1]
			if GroupService.NearestPlayer(group.position) > UNSEEN_DISTANCE then
				GroupService.Remove(group)
				table.remove(residents, table.find(residents, group) :: number)
			end
		end
	end
end

-- Merchants open the (closed) vendor panel through the trainer flow.
local function tradePrompt(entity: Entity)
	if entity.defId ~= "merchant" then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Trade"
	prompt.ObjectText = entity.name
	prompt.MaxActivationDistance = TRADE_DISTANCE
	prompt.RequiresLineOfSight = false
	entity.root:SetAttribute("TrainerType", "Vendor")
	prompt.Parent = entity.root
	entity.root:AddTag("Trainer")
end

function PopulationService.Init(deps: { [string]: any })
	EntityService = deps.EntityService
	GroupService = deps.GroupService
end

function PopulationService.Start()
	EntityService.Added:Connect(tradePrompt)
	for _, def in Population.Garrisons do
		garrison(def, def.id)
	end
	for _, troop in Population.Patrols do
		troopSchedule(troop, true)
	end
	for _, troop in Population.Caravans do
		troopSchedule(troop, false)
	end
	for _, troop in Population.Travelers do
		troopSchedule(troop, false)
	end
	for _, nest in Population.Nests do
		nestSchedules(nest)
	end
	log:Info("%d schedules, %d garrisons", #schedules, #Population.Garrisons)

	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				runSchedules()
				runResidents()
			end)
			if not ok then
				log:Throttled("schedule", 10, "error", "Population pass failed: %s", tostring(err))
			end
			task.wait(Tuning.Population.ScheduleInterval)
		end
	end)
end

return PopulationService
