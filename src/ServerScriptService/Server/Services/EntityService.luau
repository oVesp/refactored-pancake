--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Factions = require(ReplicatedStorage.Content.Factions)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Relations = require(ReplicatedStorage.Shared.Relations)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local HISTORY_INTERVAL = 0.05
local HISTORY_SECONDS = 0.6
local MOVEMENT_CHECK_INTERVAL = 0.5
local MOVEMENT_ALLOWANCE = 12

local log = Logger.new("EntityService")

local entities: { [Model]: Entity } = {}
local byPlayer: { [Player]: Entity } = {}
local lastSampleAt = 0
local movementSamples: { [Player]: { position: Vector3, time: number } } = {}
local movementViolations: { [Player]: number } = {}

--[=[
	Registry of combat entities and their recent positions (for lag-compensated hit checks).
	Every system that deals with "who can be hit" goes through here.
]=]
local EntityService = {}

EntityService.Added = Signal.new() :: Signal.Signal<Entity>
EntityService.Removing = Signal.new() :: Signal.Signal<Entity>

export type NewEntity = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	kind: "Player" | "Npc" | "Dummy",
	player: Player?,
	team: Factions.FactionId,
	defId: string,
	name: string,
	level: number,
	tags: Types.Tags,
}

--[=[ Registers a model as a combat entity. Stats are filled by StatService on Added. ]=]
function EntityService.Register(info: NewEntity): Entity
	assert(not entities[info.model], `{info.model:GetFullName()} is already registered`)
	local entity: Entity = {
		model = info.model,
		humanoid = info.humanoid,
		root = info.root,
		kind = info.kind,
		player = info.player,
		team = info.team,
		defId = info.defId,
		name = info.name,
		level = info.level,
		tags = info.tags,
		stats = {},
		extras = {},
		hp = 1,
		mp = 0,
		stamina = 0,
		maxStamina = 0,
		shield = 0,
		alive = true,
		god = false,
		lastCombatAt = -math.huge,
		cooldowns = {},
		gcdReadyAt = 0,
		lockedUntil = 0,
		casting = nil,
		castToken = 0,
		guardSince = nil,
		chainLast = nil,
		chainAt = 0,
		commitUntil = 0,
		invulnerableUntil = 0,
		statuses = {},
		history = {},
		threat = {},
		tauntedBy = nil,
		lastHitBy = nil,
	}
	entities[info.model] = entity
	if info.player then
		byPlayer[info.player] = entity
	end
	info.model:SetAttribute("Team", info.team)
	info.model:SetAttribute("Level", info.level)
	info.model:SetAttribute("DisplayName", info.name)
	info.model:SetAttribute("EntityKind", info.kind)
	EntityService.Added:Fire(entity)
	return entity
end

--[=[ Removes an entity. Safe to call twice. ]=]
function EntityService.Unregister(model: Model)
	local entity = entities[model]
	if not entity then
		return
	end
	EntityService.Removing:Fire(entity)
	entities[model] = nil
	if entity.player and byPlayer[entity.player] == entity then
		byPlayer[entity.player] = nil
	end
	for _, other in entities do
		other.threat[entity] = nil
		if other.tauntedBy == entity then
			other.tauntedBy = nil
		end
	end
end

function EntityService.Get(model: Model): Entity?
	return entities[model]
end

--[=[ The entity for a player's current character, if alive and registered. ]=]
function EntityService.ForPlayer(player: Player): Entity?
	return byPlayer[player]
end

--[=[ Finds the entity owning a part (walks up to the registered model). ]=]
function EntityService.FromPart(part: Instance): Entity?
	local current: Instance? = part
	while current and current ~= workspace do
		if current:IsA("Model") and entities[current] then
			return entities[current]
		end
		current = current.Parent
	end
	return nil
end

function EntityService.All(): { [Model]: Entity }
	return entities
end

--[=[
	True when two entities' factions are hostile (Shared/Relations). Players never hurt players
	(no PvP in M0.5).
]=]
function EntityService.AreEnemies(a: Entity, b: Entity): boolean
	return a ~= b and Relations.Hostile(a.team, b.team)
end

--[=[
	Position of an entity `rewind` seconds ago, interpolated from recorded samples. Rewind is
	capped by Tuning.Combat.MaxRewind; without samples it returns the current position.
]=]
function EntityService.PositionAt(entity: Entity, rewind: number): Vector3
	local current = entity.root.Position
	local seconds = math.clamp(rewind, 0, Tuning.Combat.MaxRewind)
	if seconds <= 0 or #entity.history == 0 then
		return current
	end
	local target = os.clock() - seconds
	local history = entity.history
	for i = #history, 1, -1 do
		local sample = history[i]
		if sample.time <= target then
			local nextSample = history[i + 1]
			if not nextSample then
				return sample.position
			end
			local alpha = (target - sample.time) / math.max(nextSample.time - sample.time, 1e-3)
			return sample.position:Lerp(nextSample.position, math.clamp(alpha, 0, 1))
		end
	end
	return history[1].position
end

--[=[ Seconds of rewind allowed for a player's hit checks (their latency, capped). ]=]
function EntityService.RewindFor(player: Player?): number
	if not player then
		return 0
	end
	return math.min(player:GetNetworkPing(), Tuning.Combat.MaxRewind)
end

--[=[ Marks a server-initiated teleport so the movement check ignores the jump. ]=]
function EntityService.NoteTeleport(player: Player)
	movementSamples[player] = nil
end

local function sampleHistory(now: number)
	for _, entity in entities do
		local history = entity.history
		table.insert(history, { time = now, position = entity.root.Position })
		while #history > 0 and now - history[1].time > HISTORY_SECONDS do
			table.remove(history, 1)
		end
	end
end

-- Movement sanity check (game-design.md 5.10): flags horizontal speed far above WalkSpeed.
-- In M0.5 it logs and counts; it does not rubber-band.
local function checkMovement(now: number)
	for player, entity in byPlayer do
		local humanoid = entity.humanoid
		if not humanoid or not entity.alive then
			continue
		end
		local position = entity.root.Position
		local previous = movementSamples[player]
		movementSamples[player] = { position = position, time = now }
		if previous then
			local elapsed = now - previous.time
			local delta = position - previous.position
			local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
			local allowed = (humanoid.WalkSpeed * 1.5) * elapsed + MOVEMENT_ALLOWANCE
			if horizontal > allowed then
				movementViolations[player] = (movementViolations[player] or 0) + 1
				log:Throttled(
					`move:{player.UserId}`,
					10,
					"warn",
					"Movement check: %d moved %.1f studs in %.2fs (allowed %.1f)",
					player.UserId,
					horizontal,
					elapsed,
					allowed
				)
			end
		end
	end
end

--[=[ Count of movement-check violations for a player this session (exploit signal). ]=]
function EntityService.MovementViolations(player: Player): number
	return movementViolations[player] or 0
end

function EntityService.Init(_deps: { [string]: any }) end

function EntityService.Start()
	local lastMovementCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastSampleAt >= HISTORY_INTERVAL then
			lastSampleAt = now
			sampleHistory(now)
		end
		if now - lastMovementCheck >= MOVEMENT_CHECK_INTERVAL then
			lastMovementCheck = now
			checkMovement(now)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		movementSamples[player] = nil
		movementViolations[player] = nil
	end)
end

return EntityService
