--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formation = require(ReplicatedStorage.Shared.Formation)
local Logger = require(ReplicatedStorage.Shared.Logger)
local NpcDefs = require(ReplicatedStorage.Shared.NpcDefs)
local Route = require(ReplicatedStorage.Shared.Route)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local STATION_SPACING = 4
local RESUME_WINDOW = 80 -- studs along the route searched for the resume point after a fight
local END_HIDE_SHARE = 0.5 -- an open route's group leaves once no player is within this share of MaterializeRadius

local log = Logger.new("GroupService")

local AIService: any
local CombatService: any
local EntityService: any
local SpawnService: any

export type MemberSpec = {
	npc: string,
	level: number,
	--[=[ Authored level range; a replacement rolls in it again. ]=]
	range: { number }?,
	--[=[ Share of max HP, kept while the group has no bodies. ]=]
	hp: number,
	entity: Entity?,
}

export type Spec = {
	label: string,
	members: { MemberSpec },
	formation: Formation.Shape,
	spacing: number,
	--[=[ Walks this route; nil for a station. ]=]
	route: Route.Route?,
	--[=[ Seconds to wait at a route point index. ]=]
	stops: { [number]: number }?,
	--[=[ Station groups stand here; members wander `wander` studs. ]=]
	station: Vector3?,
	wander: number?,
	--[=[ An open route reached its end; the group is removed right after. ]=]
	onEnd: ((Group) -> ())?,
	--[=[ Every member died; the group is removed right after. ]=]
	onEmpty: ((Group) -> ())?,
	--[=[ One member died. ]=]
	onLoss: ((Group, MemberSpec) -> ())?,
	--[=[ Stays when every member is dead (a garrison waiting for replacements). ]=]
	keep: boolean?,
}

export type Group = Spec & {
	id: number,
	--[=[ Distance along the route. ]=]
	progress: number,
	pauseUntil: number,
	--[=[ Stop indices already waited at on this lap. ]=]
	waited: { [number]: boolean },
	lap: number,
	position: Vector3,
	heading: Vector3,
	materialized: boolean,
	spawning: boolean,
	busy: boolean,
	removed: boolean,
}

local groups: { [number]: Group } = {}
local byEntity: { [Entity]: { group: Group, spec: MemberSpec } } = {}
local nextId = 0

--[=[
	NPC groups in the open world (docs/systems/open-world.md): patrols, caravans, travelers, nest
	squads and stations. A group far from every player is data only and moves along its route; near
	a player it gets bodies (SpawnService) whose brains GroupService steers into formation behind the
	leader through `AIService.SetGoal`. In a fight the formation breaks and AI takes over; afterwards
	the group picks its route up from the nearest point.
]=]
local GroupService = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function alive(group: Group): { MemberSpec }
	local out = {}
	for _, spec in group.members do
		if spec.entity and spec.entity.alive then
			table.insert(out, spec)
		end
	end
	return out
end

-- Abstract pace: the slowest member's walk speed, slowed so bodies can keep up when they appear.
local function speedOf(group: Group): number
	local slowest = math.huge
	for _, spec in group.members do
		local def = NpcDefs.Get(spec.npc)
		if def then
			slowest = math.min(slowest, def.moveSpeed)
		end
	end
	return if slowest == math.huge then 0 else slowest * Tuning.Population.AbstractSpeed
end

local function bodies(): number
	local count = 0
	for entity in byEntity do
		if entity.alive then
			count += 1
		end
	end
	return count
end

local function nearestPlayer(position: Vector3): number
	local best = math.huge
	for _, entity in EntityService.All() do
		if entity.kind == "Player" and entity.alive then
			best = math.min(best, (flat(entity.root.Position) - flat(position)).Magnitude)
		end
	end
	return best
end

-- Advances `progress` by `distance`, waiting at stops and counting laps. Returns true at the end
-- of an open route.
local function advance(group: Group, distance: number, now: number): boolean
	local route = group.route :: Route.Route
	if now < group.pauseUntil then
		return false
	end
	local from = group.progress
	local to = from + distance
	local stops: { [number]: number } = group.stops or {}
	for index, seconds in stops do
		local mark = route.marks[index]
		if mark and not group.waited[index] and from <= mark and to >= mark then
			group.waited[index] = true
			group.progress = mark
			group.pauseUntil = now + seconds
			return false
		end
	end
	if route.loop and route.length > 0 and to >= route.length then
		to -= route.length
		table.clear(group.waited)
		group.lap += 1
	end
	group.progress = to
	return not route.loop and to >= route.length
end

local function finish(group: Group, ended: boolean)
	if group.removed then
		return
	end
	group.removed = true
	for _, spec in group.members do
		if spec.entity then
			byEntity[spec.entity] = nil
			SpawnService.Despawn(spec.entity)
			spec.entity = nil
		end
	end
	groups[group.id] = nil
	if ended and group.onEnd then
		group.onEnd(group)
	elseif not ended and group.onEmpty then
		group.onEmpty(group)
	end
end

-- Where member `index` (of `count`) stands right now.
local function slotOf(group: Group, index: number, count: number, origin: Vector3): Vector3
	if group.station then
		local offsets = Formation.Offsets("Ring", count, STATION_SPACING)
		return group.station + (if count > 1 then offsets[index] else Vector3.zero)
	end
	local offsets = Formation.Offsets(group.formation, count, group.spacing)
	return Formation.Place(origin, group.heading, offsets[index])
end

local function spawnMember(group: Group, spec: MemberSpec, at: Vector3)
	local wander = if group.station then group.wander or 0 else 0
	local entity = SpawnService.Spawn(spec.npc, spec.level, at, { home = at, wander = wander, hp = spec.hp })
	if not entity then
		return
	end
	if group.removed then
		SpawnService.Despawn(entity)
		return
	end
	spec.entity = entity
	byEntity[entity] = { group = group, spec = spec }
	entity.model:SetAttribute("Group", group.label)
end

local function materialize(group: Group)
	group.spawning = true
	group.materialized = true
	task.spawn(function()
		local count = #group.members
		for index, spec in group.members do
			if group.removed then
				break
			end
			spawnMember(group, spec, slotOf(group, index, count, group.position))
		end
		group.spawning = false
	end)
end

local function dematerialize(group: Group)
	for _, spec in group.members do
		local entity = spec.entity
		if entity then
			spec.hp = math.clamp(entity.hp / math.max(entity.stats.MaxHp, 1), 0.05, 1)
			byEntity[entity] = nil
			SpawnService.Despawn(entity)
			spec.entity = nil
		end
	end
	group.materialized = false
end

-- Bodies follow the route in formation behind the leader, or hold their station.
local function steer(group: Group, members: { MemberSpec }, dt: number, now: number): boolean
	local leader = members[1].entity :: Entity
	local origin = leader.root.Position
	group.position = origin
	local route = group.route
	if not route then
		for index, spec in members do
			local entity = spec.entity :: Entity
			AIService.SetGoal(entity, nil)
			AIService.SetHome(entity, slotOf(group, index, #members, origin))
		end
		return false
	end

	local settings = Tuning.Population
	local target = Route.At(route, group.progress)
	local lag = 0
	for index = 2, #members do
		local entity = members[index].entity :: Entity
		local slot = slotOf(group, index, #members, origin)
		lag = math.max(lag, (flat(entity.root.Position) - flat(slot)).Magnitude)
	end
	local ended = false
	if (flat(target) - flat(origin)).Magnitude < settings.Lookahead and lag < settings.FollowLag then
		ended = advance(group, speedOf(group) / settings.AbstractSpeed * 0.85 * dt, now)
	end
	local goal, heading = Route.At(route, group.progress + settings.Lookahead)
	local toward = flat(goal - origin)
	group.heading = if toward.Magnitude > 1 then toward.Unit else heading
	AIService.SetGoal(leader, if now < group.pauseUntil then nil else goal)
	AIService.SetHome(leader, origin)
	for index = 2, #members do
		local entity = members[index].entity :: Entity
		local slot = slotOf(group, index, #members, origin)
		AIService.SetGoal(entity, slot)
		AIService.SetHome(entity, slot)
	end
	return ended
end

local function tick(group: Group, dt: number, now: number)
	local settings = Tuning.Population
	if not group.materialized then
		if group.route then
			local ended = advance(group, speedOf(group) * dt, now)
			local at, heading = Route.At(group.route, group.progress)
			group.position, group.heading = at, heading
			if ended then
				finish(group, true)
				return
			end
		end
		local distance = nearestPlayer(group.position)
		if distance <= settings.MaterializeRadius and bodies() + #group.members <= settings.MaxBodies then
			materialize(group)
		end
		return
	end
	if group.spawning then
		return
	end

	local members = alive(group)
	if #members == 0 then
		-- Bodies could not be built; fall back to data.
		group.materialized = false
		return
	end
	local busy = false
	for _, spec in members do
		if AIService.Busy(spec.entity) then
			busy = true
			break
		end
	end
	if group.busy and not busy and group.route then
		group.progress =
			Route.Nearest(group.route, (members[1].entity :: Entity).root.Position, group.progress, RESUME_WINDOW)
	end
	group.busy = busy
	local distance = nearestPlayer(group.position)
	if busy then
		group.position = (members[1].entity :: Entity).root.Position
		return
	end
	local ended = steer(group, members, dt, now)
	if ended and distance > settings.MaterializeRadius * END_HIDE_SHARE then
		finish(group, true)
	elseif distance > settings.DematerializeRadius then
		dematerialize(group)
	end
end

--[=[ Creates a group with no bodies yet, `progress` studs along its route. ]=]
function GroupService.Create(spec: Spec, progress: number?): Group
	nextId += 1
	local group = spec :: Group
	group.id = nextId
	group.progress = progress or 0
	group.pauseUntil = 0
	group.waited = {}
	group.lap = 0
	group.materialized = false
	group.spawning = false
	group.busy = false
	group.removed = false
	if spec.route then
		local at, heading = Route.At(spec.route, group.progress)
		group.position, group.heading = at, heading
	else
		group.position = spec.station or Vector3.zero
		group.heading = Vector3.new(0, 0, -1)
	end
	groups[group.id] = group
	log:Debug("Group %d (%s) created with %d members", group.id, group.label, #group.members)
	return group
end

--[=[ Adds a member (a garrison's replacement); it gets a body at once if the group has bodies. ]=]
function GroupService.AddMember(group: Group, spec: MemberSpec)
	table.insert(group.members, spec)
	if group.materialized and not group.spawning then
		task.spawn(spawnMember, group, spec, slotOf(group, #group.members, #group.members, group.position))
	end
end

--[=[ Removes a group and its bodies without calling its callbacks. ]=]
function GroupService.Remove(group: Group)
	group.onEnd, group.onEmpty = nil, nil
	finish(group, true)
end

--[=[ Distance from `position` to the nearest living player, on the ground plane. ]=]
GroupService.NearestPlayer = nearestPlayer

function GroupService.Init(deps: { [string]: any })
	AIService = deps.AIService
	CombatService = deps.CombatService
	EntityService = deps.EntityService
	SpawnService = deps.SpawnService
end

function GroupService.Start()
	CombatService.Died:Connect(function(victim: Entity)
		local entry = byEntity[victim]
		if not entry then
			return
		end
		byEntity[victim] = nil
		local group, spec = entry.group, entry.spec
		spec.entity = nil
		local index = table.find(group.members, spec)
		if index then
			table.remove(group.members, index)
		end
		if group.onLoss then
			group.onLoss(group, spec)
		end
		if #group.members == 0 and not group.keep then
			finish(group, false)
		end
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Tuning.Population.TickInterval)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, group in table.clone(groups) do
				local ok, err = pcall(function()
					tick(group, dt, now)
				end)
				if not ok then
					log:Throttled("tick", 5, "error", "Group %s: %s", group.label, tostring(err))
				end
			end
		end
	end)
end

return GroupService
