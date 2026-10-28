--!strict

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enemies = require(ReplicatedStorage.Content.Enemies)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Skills = require(ReplicatedStorage.Content.Skills)
local Swarm = require(ReplicatedStorage.Shared.Swarm)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type Member = Types.SquadMember

type State = "Idle" | "Patrol" | "Aggro" | "Position" | "Attack" | "Return"

type Brain = {
	entity: Entity,
	def: any,
	home: Vector3,
	leash: number,
	state: State,
	target: Entity?,
	nextThink: number,
	nextPatrol: number,
	waypoints: { Vector3 },
	waypointIndex: number,
	pathTarget: Vector3?,
	nextPathAt: number,
	summoned: boolean,
	member: Member,
}

local AGGRO_ON_HIT_RADIUS = 60
local HEAL_THRESHOLD = 0.7
local ARRIVE_DISTANCE = 4
local SLOT_ARRIVE = 1.5

local log = Logger.new("AIService")

local CombatService: any
local EntityService: any
local SkillService: any
local StatService: any
local StatusService: any
local ZoneService: any
local SpawnService: any
local SquadService: any

local brains: { [Entity]: Brain } = {}
local cueSequence = 0
local random = Random.new()
local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Exclude

--[=[
	Server-only enemy brains (game-design.md 5.6): idle, patrol, aggro, position, attack, return.
	Each thinks on a jittered interval; detection is a distance check over living players;
	PathfindingService only runs when the straight line is blocked. Attacks need a token from
	SquadService; without one the enemy waits in position.
]=]
local AIService = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function setState(brain: Brain, state: State)
	if brain.state ~= state then
		brain.state = state
		brain.entity.model:SetAttribute("AiState", state)
	end
end

-- One-shot animation cue for clients ("<clip>:<sequence>"); the sequence makes repeats fire.
local function cue(entity: Entity, clip: string)
	cueSequence += 1
	entity.model:SetAttribute("AnimCue", string.format("%s:%d", clip, cueSequence))
end

local function lineBlocked(from: Vector3, to: Vector3): boolean
	local offset = to - from
	if offset.Magnitude < 1 then
		return false
	end
	return workspace:Raycast(from, offset, blockParams) ~= nil
end

local function moveTo(brain: Brain, destination: Vector3, now: number)
	local humanoid = brain.entity.humanoid
	if not humanoid then
		return
	end
	local root = brain.entity.root
	if not lineBlocked(root.Position, destination + Vector3.new(0, root.Position.Y - destination.Y, 0)) then
		brain.waypoints = {}
		humanoid:MoveTo(destination)
		return
	end

	local stale = brain.pathTarget == nil or (brain.pathTarget - destination).Magnitude > 6
	if (stale or #brain.waypoints == 0) and now >= brain.nextPathAt then
		brain.nextPathAt = now + Tuning.Npc.PathRecompute + random:NextNumber(0, 0.5)
		brain.pathTarget = destination
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
		local ok = pcall(function()
			path:ComputeAsync(root.Position, destination)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			brain.waypoints = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(brain.waypoints, waypoint.Position)
			end
			brain.waypointIndex = math.min(2, #brain.waypoints)
		else
			brain.waypoints = {}
			humanoid:MoveTo(destination)
			return
		end
	end

	local waypoint = brain.waypoints[brain.waypointIndex]
	if waypoint then
		if
			(flat(waypoint) - flat(root.Position)).Magnitude < ARRIVE_DISTANCE
			and brain.waypointIndex < #brain.waypoints
		then
			brain.waypointIndex += 1
			waypoint = brain.waypoints[brain.waypointIndex]
		end
		humanoid:MoveTo(waypoint)
	else
		humanoid:MoveTo(destination)
	end
end

local function stop(brain: Brain)
	local humanoid = brain.entity.humanoid
	if humanoid then
		humanoid:MoveTo(brain.entity.root.Position)
	end
	brain.waypoints = {}
end

local function face(brain: Brain, point: Vector3)
	local root = brain.entity.root
	local look = flat(point - root.Position)
	if look.Magnitude > 0.1 then
		local position = root.Position
		brain.entity.model:PivotTo(CFrame.lookAt(position, position + look))
	end
end

local function validTarget(brain: Brain, target: Entity?): boolean
	if not target or not target.alive or target.kind ~= "Player" then
		return false
	end
	if ZoneService.IsSafe(target.root.Position) then
		return false
	end
	return (flat(target.root.Position) - flat(brain.home)).Magnitude <= brain.leash + 10
end

local function pickTarget(brain: Brain): Entity?
	local entity = brain.entity
	if validTarget(brain, entity.tauntedBy) then
		return entity.tauntedBy
	end

	local best, bestThreat = nil, 0
	for other, threat in entity.threat do
		if threat > bestThreat and validTarget(brain, other) then
			best, bestThreat = other, threat
		end
	end
	if best then
		return best
	end

	if validTarget(brain, brain.target) then
		return brain.target
	end

	local nearest, nearestDistance = nil, brain.def.aggroRadius
	for _, other in EntityService.All() do
		if other.kind == "Player" and validTarget(brain, other) then
			local distance = (other.root.Position - entity.root.Position).Magnitude
			if distance <= nearestDistance then
				nearest, nearestDistance = other, distance
			end
		end
	end
	return nearest
end

local function skillReach(skill: any): number
	if skill.delivery == "SelfArea" then
		return (skill.radius or 6) - 1
	end
	return (skill.range or 6) - 0.5
end

local function woundedAlly(brain: Brain, range: number): Entity?
	local entity = brain.entity
	local best, lowest = nil, HEAL_THRESHOLD
	for _, other in EntityService.All() do
		if other.alive and other.team == entity.team and other.kind == "Npc" then
			local ratio = other.hp / math.max(other.stats.MaxHp, 1)
			if ratio < lowest and (other.root.Position - entity.root.Position).Magnitude <= range then
				best, lowest = other, ratio
			end
		end
	end
	return best
end

local function alliesNear(brain: Brain, radius: number): number
	local count = 0
	for _, other in EntityService.All() do
		if other ~= brain.entity and other.alive and other.team == brain.entity.team then
			if (other.root.Position - brain.entity.root.Position).Magnitude <= radius then
				count += 1
			end
		end
	end
	return count
end

-- Aim and aimed-at entity for a ready skill whose conditions hold, or nil.
local function usable(brain: Brain, skill: any, target: Entity, distance: number): (Vector3?, Entity?)
	local entity = brain.entity
	if skill.targets == "Ally" then
		if skill.delivery == "SelfArea" then
			if alliesNear(brain, skill.radius or 20) > 0 then
				return entity.root.Position, nil
			end
		else
			local ally = woundedAlly(brain, skill.range or 30)
			if ally then
				return ally.root.Position, ally
			end
		end
	elseif skill.delivery == "Dash" then
		if distance > 8 and distance <= (skill.range or 20) then
			return target.root.Position, target
		end
	elseif distance <= skillReach(skill) then
		return target.root.Position, target
	end
	return nil, nil
end

-- Picks the first ready skill in data order whose conditions hold and whose budget grants a
-- token. Returns skill id, aim and the entity it is aimed at.
local function chooseSkill(brain: Brain, target: Entity, distance: number, now: number): (string?, Vector3?, Entity?)
	for _, skillId in brain.def.skills do
		local skill = Skills.ById[skillId]
		if not skill or SkillService.CooldownRemaining(brain.entity, skillId) > 0 then
			continue
		end
		local aim, aimedAt = usable(brain, skill, target, distance)
		if aim and SquadService.RequestToken(brain.member, Swarm.TokenKind(skill), now) then
			return skillId, aim, aimedAt
		end
	end
	return nil, nil, nil
end

-- Budget of the first ready attack skill, used to queue for a token before walking into reach.
local function readyAttackKind(brain: Brain): Swarm.TokenKind?
	for _, skillId in brain.def.skills do
		local skill = Skills.ById[skillId]
		if skill and skill.targets ~= "Ally" and SkillService.CooldownRemaining(brain.entity, skillId) <= 0 then
			return Swarm.TokenKind(skill)
		end
	end
	return nil
end

local function preferredRange(brain: Brain): number
	if brain.def.keepDistance then
		return brain.def.keepDistance + 6
	end
	local reach = 6
	for _, skillId in brain.def.skills do
		local skill = Skills.ById[skillId]
		if skill and skill.targets ~= "Ally" and skill.delivery ~= "Dash" then
			reach = math.max(reach, math.min(skillReach(skill), 8))
		end
	end
	return reach
end

-- Push away from other enemies closer than the separation radius, in studs.
local function separation(brain: Brain): Vector3
	local settings = Tuning.Swarm.Separation
	local position = brain.entity.root.Position
	local neighbours: { Vector3 } = {}
	for _, other in EntityService.All() do
		if other ~= brain.entity and other.alive and other.kind == "Npc" then
			local at = other.root.Position
			if (at - position).Magnitude < settings.Radius then
				table.insert(neighbours, at)
			end
		end
	end
	if #neighbours == 0 then
		return Vector3.zero
	end
	return Swarm.Separation(position, neighbours, settings.Radius) * settings.Strength
end

local function startReturn(brain: Brain)
	SquadService.Leave(brain.member)
	setState(brain, "Return")
	brain.target = nil
	table.clear(brain.entity.threat)
	brain.entity.tauntedBy = nil
end

local function bossPhase(brain: Brain)
	local entity = brain.entity
	if brain.def.behavior ~= "Boss" or brain.summoned or entity.hp > entity.stats.MaxHp * 0.5 then
		return
	end
	brain.summoned = true
	entity.model:SetAttribute("Phase", 2)
	StatusService.Apply(entity, "rally", 600, nil, entity)
	for i = 1, 2 do
		local offset = Vector3.new(if i == 1 then -6 else 6, 0, 4)
		local position = entity.root.Position + offset
		local summon =
			SpawnService.Spawn("goblin_raider", 4, Vector3.new(position.X, brain.home.Y, position.Z), brain.home)
		if summon then
			SpawnService.TrackSummon(summon)
		end
	end
	log:Debug("%s entered phase 2", entity.name)
end

local function think(brain: Brain, now: number)
	local entity = brain.entity
	if not entity.alive or brain.def.behavior == "Dummy" then
		return
	end
	if StatusService.IsDisabled(entity) or entity.casting then
		stop(brain)
		return
	end

	local root = entity.root
	local fromHome = (flat(root.Position) - flat(brain.home)).Magnitude

	if brain.state == "Return" then
		if fromHome <= ARRIVE_DISTANCE + 2 then
			StatusService.Clear(entity)
			StatService.Refill(entity)
			setState(brain, "Idle")
		else
			StatService.SetHp(
				entity,
				entity.hp + entity.stats.MaxHp * Tuning.Npc.ReturnRegenPerSecond * Tuning.Npc.ThinkInterval
			)
			moveTo(brain, brain.home, now)
		end
		return
	end

	if fromHome > brain.leash then
		startReturn(brain)
		moveTo(brain, brain.home, now)
		return
	end

	local target = pickTarget(brain)
	brain.target = target
	if target then
		SquadService.Join(brain.member, target)
	else
		SquadService.Leave(brain.member)
	end
	if not target then
		if brain.state == "Aggro" or brain.state == "Position" or brain.state == "Attack" then
			startReturn(brain)
			return
		end
		if now >= brain.nextPatrol then
			brain.nextPatrol = now + random:NextNumber(6, 10)
			local angle = random:NextNumber(0, math.pi * 2)
			local radius = random:NextNumber(2, Tuning.Npc.PatrolRadius)
			local point = brain.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			if not ZoneService.IsSafe(point) then
				setState(brain, "Patrol")
				moveTo(brain, point, now)
			end
		elseif brain.state == "Patrol" and (flat(root.Position) - flat(brain.home)).Magnitude < 2 then
			setState(brain, "Idle")
		end
		return
	end

	bossPhase(brain)
	local distance = (target.root.Position - root.Position).Magnitude
	local skillId, aim, aimedAt = chooseSkill(brain, target, distance, now)
	if skillId and aim then
		local skill = Skills.ById[skillId]
		setState(brain, "Attack")
		stop(brain)
		face(brain, aim)
		SquadService.Commit(brain.member, now + (skill.castTime or skill.windup or 0) + Tuning.Swarm.RecoveryHold)
		SkillService.Cast(entity, skillId, aim, aimedAt)
		local delivery = skill.delivery
		cue(entity, if delivery == "Melee" or delivery == "Dash" or delivery == "SelfArea" then "Attack" else "Throw")
		return
	end

	local member = brain.member
	local attackKind = readyAttackKind(brain)
	local cleared = SquadService.HasToken(member)
		or (attackKind ~= nil and SquadService.RequestToken(member, attackKind, now))
	setState(brain, if cleared then "Aggro" else "Position")
	local melee = member.profile.slot == "Melee"
	local reach = preferredRange(brain)
	member.reach = reach
	local keep = brain.def.keepDistance
	local slotDirection = SquadService.SlotDirection(member)
	local spot: Vector3? = nil
	if slotDirection and not (keep and distance < keep) then
		-- Engagement slot: in reach with a token, just outside it without one.
		local radius = if not melee then reach elseif cleared then reach - 1 else reach + Tuning.Swarm.WaitDistance
		spot = target.root.Position + slotDirection * radius
	elseif not cleared and melee then
		-- No slot free: hold outside reach on the current bearing.
		local offset = flat(root.Position - target.root.Position)
		local bearing = if offset.Magnitude > 0.1 then offset.Unit else Vector3.new(1, 0, 0)
		spot = target.root.Position + bearing * (reach + Tuning.Swarm.WaitDistance)
	end
	if spot then
		local destination = spot + separation(brain)
		if
			(flat(destination) - flat(root.Position)).Magnitude > SLOT_ARRIVE and not ZoneService.IsSafe(destination)
		then
			moveTo(brain, destination, now)
		else
			stop(brain)
			face(brain, target.root.Position)
		end
		return
	end

	if keep and distance < keep then
		local away = flat(root.Position - target.root.Position)
		local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
		local retreat = root.Position + direction * 10
		if not ZoneService.IsSafe(retreat) then
			moveTo(brain, retreat, now)
		else
			stop(brain)
		end
	elseif distance > reach then
		moveTo(brain, target.root.Position, now)
	else
		stop(brain)
		face(brain, target.root.Position)
	end
end

--[=[ Gives a spawned enemy a brain anchored at `home` with a leash radius. ]=]
function AIService.Attach(entity: Entity, home: Vector3, leash: number)
	local def = Enemies.ById[entity.defId]
	if not def then
		return
	end
	brains[entity] = {
		entity = entity,
		def = def,
		home = home,
		leash = leash,
		state = "Idle",
		target = nil,
		nextThink = os.clock() + random:NextNumber(0, Tuning.Npc.ThinkInterval),
		nextPatrol = os.clock() + random:NextNumber(2, 8),
		waypoints = {},
		waypointIndex = 1,
		pathTarget = nil,
		nextPathAt = 0,
		summoned = false,
		member = SquadService.NewMember(entity, def),
	}
	entity.model:SetAttribute("AiState", "Idle")
end

--[=[ Late binding to avoid a dependency cycle: SpawnService calls this from Start. ]=]
function AIService.SetSpawnService(service: any)
	SpawnService = service
end

local function refreshFilter()
	local exclude: { Instance } = {}
	for model in EntityService.All() do
		table.insert(exclude, model)
	end
	blockParams.FilterDescendantsInstances = exclude
end

function AIService.Init(deps: { [string]: any })
	CombatService = deps.CombatService
	EntityService = deps.EntityService
	SkillService = deps.SkillService
	StatService = deps.StatService
	SquadService = deps.SquadService
	StatusService = deps.StatusService
	ZoneService = deps.ZoneService
end

function AIService.Start()
	EntityService.Removing:Connect(function(entity: Entity)
		brains[entity] = nil
		task.defer(refreshFilter)
	end)
	EntityService.Added:Connect(refreshFilter)

	CombatService.Damaged:Connect(function(target: Entity, amount: number)
		if brains[target] and target.alive and amount > 0 then
			cue(target, "Hit")
		end
	end)
	CombatService.Died:Connect(function(target: Entity)
		if brains[target] then
			cue(target, "Death")
		end
	end)

	-- Damage from far away still pulls the victim's pack into the fight.
	CombatService.Damaged:Connect(function(target: Entity, _amount: number, _type: string, source: Entity?)
		local brain = brains[target]
		if not brain or not source or source.kind ~= "Player" then
			return
		end
		if brain.state == "Idle" or brain.state == "Patrol" then
			for _, other in brains do
				if
					other ~= brain
					and other.entity.team == target.team
					and (other.state == "Idle" or other.state == "Patrol")
				then
					if (other.entity.root.Position - target.root.Position).Magnitude <= AGGRO_ON_HIT_RADIUS / 3 then
						other.entity.threat[source] = (other.entity.threat[source] or 0) + 1
					end
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Tuning.Npc.ThinkInterval / 2)
			local now = os.clock()
			for _, brain in brains do
				if now >= brain.nextThink then
					brain.nextThink = now + Tuning.Npc.ThinkInterval
					local ok, err = pcall(function()
						think(brain, now)
					end)
					if not ok then
						log:Throttled("think", 5, "error", "Brain error for %s: %s", brain.entity.name, tostring(err))
					end
				end
			end
		end
	end)
end

return AIService
