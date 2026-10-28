--!strict

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Enemies = require(ReplicatedStorage.Content.Enemies)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Skills = require(ReplicatedStorage.Content.Skills)
local Swarm = require(ReplicatedStorage.Shared.Swarm)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type Member = Types.SquadMember

type State = "Idle" | "Patrol" | "Aggro" | "Position" | "Attack" | "Disrupt" | "Flee" | "Regroup" | "Stagger" | "Return"

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
	--[=[ Indices of `combat.summons` entries already spawned. ]=]
	summoned: { [number]: boolean },
	member: Member,
	--[=[ Poise damage taken in the current stagger window and when it was last added to. ]=]
	poiseDamage: number,
	poiseAt: number,
	--[=[ Decisions pause until this os.clock(); no new stagger before staggerReadyAt. ]=]
	staggerUntil: number,
	staggerReadyAt: number,
}

local AGGRO_ON_HIT_RADIUS = 60
local HEAL_THRESHOLD = 0.7
local ARRIVE_DISTANCE = 4
local SLOT_ARRIVE = 1.5
local REGROUP_DISTANCE = 6

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
local debugAttributes = RunService:IsStudio()
local cueSequence = 0
local random = Random.new()
local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Exclude

--[=[
	Server-only enemy brains (game-design.md 5.6): idle, patrol, aggro, position, attack, disrupt,
	flee, regroup, stagger, return. Each thinks on a jittered interval; detection is a distance check over living players;
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

-- A Disruptor keeps its interrupt skills out of its rotation, ready for the player's next cast.
local function reserved(brain: Brain, skillId: string): boolean
	local member = brain.member
	return member.role == "Disruptor" and table.find(member.profile.interrupts, skillId) ~= nil
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
		if not skill or reserved(brain, skillId) or SkillService.CooldownRemaining(brain.entity, skillId) > 0 then
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
		if
			skill
			and skill.targets ~= "Ally"
			and not reserved(brain, skillId)
			and SkillService.CooldownRemaining(brain.entity, skillId) <= 0
		then
			return Swarm.TokenKind(skill)
		end
	end
	return nil
end

local function preferredRange(brain: Brain): number
	if brain.def.keepDistance then
		return brain.def.keepDistance + 6
	end
	-- Melee stands at its shortest attack reach: closer never hurts, farther leaves skills unusable.
	local reach = math.huge
	for _, skillId in brain.def.skills do
		local skill = Skills.ById[skillId]
		if skill and skill.targets ~= "Ally" and skill.delivery ~= "Dash" then
			reach = math.min(reach, skillReach(skill), 8)
		end
	end
	return if reach == math.huge then 6 else reach
end

local function attackCue(entity: Entity, skill: any)
	local delivery = skill.delivery
	cue(entity, if delivery == "Melee" or delivery == "Dash" or delivery == "SelfArea" then "Attack" else "Throw")
end

-- Disruptor: when the target starts a cast that an interrupt skill can still beat, run at it and
-- fire the (telegraphed) interrupt without waiting for a token. Returns true when it acted.
local function disrupt(brain: Brain, target: Entity, distance: number, now: number): boolean
	local member = brain.member
	local cast = target.casting
	if not cast or not SquadService.MayDisrupt(member, now) then
		return false
	end
	local entity = brain.entity
	local speed = if entity.humanoid then entity.humanoid.WalkSpeed else 0
	for _, skillId in member.profile.interrupts do
		local skill = Skills.ById[skillId]
		if SkillService.CooldownRemaining(entity, skillId) > 0 then
			continue
		end
		local reach = if skill.delivery == "Dash" then skill.range or 20 else skillReach(skill)
		local remaining = cast.endsAt - now
		if
			not Swarm.CanInterruptInTime(
				remaining,
				distance,
				reach,
				speed,
				skill.windup or 0,
				Tuning.Swarm.DisruptMargin
			)
		then
			continue
		end
		local aim, aimedAt = usable(brain, skill, target, distance)
		if aim then
			setState(brain, "Attack")
			stop(brain)
			face(brain, aim)
			SquadService.MarkDisrupt(member, now)
			SkillService.Cast(entity, skillId, aim, aimedAt)
			attackCue(entity, skill)
			log:Debug("%s interrupts %s with %s", entity.name, target.name, skillId)
			return true
		end
		setState(brain, "Disrupt")
		moveTo(brain, target.root.Position, now)
		return true
	end
	return false
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

-- Spawns each `combat.summons` entry once, when HP first falls below its threshold.
local function summon(brain: Brain)
	local entity = brain.entity
	local summons = brain.def.combat and brain.def.combat.summons
	if not summons then
		return
	end
	for index, entry in summons do
		if brain.summoned[index] or entity.hp > entity.stats.MaxHp * entry.belowHp then
			continue
		end
		brain.summoned[index] = true
		entity.model:SetAttribute("Phase", index + 1)
		CombatService.ApplyEffects(entity, entity, entry.selfEffects)
		for i = 1, entry.count do
			local angle = (i - 0.5) / entry.count * math.pi * 2
			local position = entity.root.Position + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
			local spawned = SpawnService.Spawn(
				entry.enemy,
				entry.level,
				Vector3.new(position.X, brain.home.Y, position.Z),
				brain.home
			)
			if spawned then
				SpawnService.TrackSummon(spawned)
			end
		end
		log:Debug("%s summons %d %s", entity.name, entry.count, entry.enemy)
	end
end

-- Flee home, or regroup on a nearby leader, while morale is broken. Returns true while it does.
local function fleeOrRegroup(brain: Brain, target: Entity, now: number): boolean
	local member = brain.member
	if not SquadService.UpdateMorale(member, now) then
		return false
	end
	local root = brain.entity.root
	local leader = SquadService.LeaderOf(member)
	if leader then
		setState(brain, "Regroup")
		local away = flat(leader.root.Position - target.root.Position)
		local behind = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
		local spot = leader.root.Position + behind * REGROUP_DISTANCE + separation(brain)
		if (flat(spot) - flat(root.Position)).Magnitude > SLOT_ARRIVE then
			moveTo(brain, spot, now)
		else
			stop(brain)
			face(brain, target.root.Position)
		end
	else
		setState(brain, "Flee")
		-- Run home, unless home is too close to the attacker; then run straight away from it.
		local fleeDistance = Tuning.Swarm.Morale.FleeDistance
		local refuge = brain.home
		if (flat(refuge) - flat(target.root.Position)).Magnitude < fleeDistance then
			local away = flat(root.Position - target.root.Position)
			local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
			refuge = target.root.Position + direction * fleeDistance
		end
		if (flat(refuge) - flat(root.Position)).Magnitude > ARRIVE_DISTANCE and not ZoneService.IsSafe(refuge) then
			moveTo(brain, refuge, now)
		else
			stop(brain)
		end
	end
	return true
end

local function think(brain: Brain, now: number)
	local entity = brain.entity
	if not entity.alive or brain.def.behavior == "Dummy" then
		return
	end
	if now < brain.staggerUntil then
		stop(brain)
		return
	end
	if brain.state == "Stagger" then
		setState(brain, "Aggro")
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
			SquadService.ResetMorale(brain.member)
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
		if brain.state ~= "Idle" and brain.state ~= "Patrol" then
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

	summon(brain)
	if fleeOrRegroup(brain, target, now) then
		return
	end
	local distance = (target.root.Position - root.Position).Magnitude
	if disrupt(brain, target, distance, now) then
		return
	end
	local skillId, aim, aimedAt = chooseSkill(brain, target, distance, now)
	if skillId and aim then
		local skill = Skills.ById[skillId]
		setState(brain, "Attack")
		stop(brain)
		face(brain, aim)
		SquadService.Commit(brain.member, now + (skill.castTime or skill.windup or 0) + Tuning.Swarm.RecoveryHold)
		SkillService.Cast(entity, skillId, aim, aimedAt)
		attackCue(entity, skill)
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

-- Studio-only overlay attributes: role, slot (ring, index, flank), token and morale.
local function publishDebug(brain: Brain)
	local member = brain.member
	local model = brain.entity.model
	model:SetAttribute("AiRole", if member.target then member.role else nil)
	local slot: string? = nil
	local direction = SquadService.SlotDirection(member)
	local target = member.target
	if direction and target and member.slot then
		local ring = Swarm.RingOf(member.profile.slot) or ""
		slot = `{ring}{member.slot} {Swarm.Flank(direction, target.root.CFrame.LookVector)}`
	end
	model:SetAttribute("AiSlot", slot)
	model:SetAttribute("AiToken", SquadService.TokenState(member))
	model:SetAttribute("AiMorale", if member.profile.morale then math.floor(member.morale) else nil)
end

-- Poise: enough damage in a short window cancels the windup, gives back the token and pauses.
local function poiseHit(brain: Brain, amount: number)
	local entity = brain.entity
	local now = os.clock()
	if entity.hp <= 0 or now < brain.staggerReadyAt then
		return
	end
	local settings = Tuning.Swarm.Stagger
	local staggered
	brain.poiseDamage, staggered = Swarm.PoiseHit(
		brain.poiseDamage,
		brain.poiseAt,
		amount,
		entity.stats.MaxHp,
		brain.member.profile.poise,
		settings.Window,
		now
	)
	brain.poiseAt = now
	if not staggered then
		return
	end
	brain.staggerUntil = now + settings.Seconds
	brain.staggerReadyAt = now + settings.Cooldown
	SkillService.Interrupt(entity)
	SquadService.DropToken(brain.member)
	stop(brain)
	setState(brain, "Stagger")
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
		summoned = {},
		poiseDamage = 0,
		poiseAt = 0,
		staggerUntil = 0,
		staggerReadyAt = 0,
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
		local brain = brains[target]
		if brain and target.alive and amount > 0 then
			cue(target, "Hit")
			poiseHit(brain, amount)
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
						if debugAttributes then
							publishDebug(brain)
						end
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
