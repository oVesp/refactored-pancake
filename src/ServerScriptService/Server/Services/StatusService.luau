--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Statuses = require(ReplicatedStorage.Content.Statuses)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local TICK_INTERVAL = 0.2

local EntityService: any
local StatService: any

--[=[
	Applies, ticks and removes status effects (game-design.md 3.5). Stat modifiers and movement
	are applied by StatService.Recompute; damage and healing ticks go through `Ticked`, which
	CombatService handles so all HP changes share one path.
]=]
local StatusService = {}

--[=[ Fires `(entity, statusId, amount, source)` for each Dot/Hot tick. ]=]
StatusService.Ticked = Signal.new() :: Signal.Signal<Entity, string, number, Entity?>
--[=[ Fires `(entity, statusId)` when a status is applied that interrupts casting. ]=]
StatusService.Interrupted = Signal.new() :: Signal.Signal<Entity, string>

local function publish(entity: Entity)
	local ids = {}
	for id in entity.statuses do
		table.insert(ids, id)
	end
	table.sort(ids)
	entity.model:SetAttribute("Statuses", table.concat(ids, ","))
	entity.model:SetAttribute("Stunned", entity.statuses.stun ~= nil or entity.statuses.fear ~= nil)
	StatService.Recompute(entity)
end

local function setLight(entity: Entity, on: boolean)
	local existing = entity.root:FindFirstChild("StatusLight")
	if on and not existing then
		local light = Instance.new("PointLight")
		light.Name = "StatusLight"
		light.Range = 20
		light.Brightness = 1.5
		light.Parent = entity.root
	elseif not on and existing then
		existing:Destroy()
	end
end

--[=[
	Applies a status. Immune targets ignore it; harmful durations shrink with Resistance.
	Reapplying refreshes duration and keeps the larger magnitude. Returns true if applied.
]=]
function StatusService.Apply(
	entity: Entity,
	statusId: string,
	duration: number,
	magnitude: number?,
	source: Entity?
): boolean
	local def = Statuses.ById[statusId]
	if not def or not entity.alive then
		return false
	end
	if def.harmful and Formulas.TypeMultiplier(statusId, entity.tags, Tuning.Combat.TypeMultiplier) == 0 then
		return false
	end

	local now = os.clock()
	local seconds =
		Formulas.StatusDuration(duration, entity.stats.Resistance or 0, def.harmful, Tuning.Combat.ResistanceConstant)
	local existing = entity.statuses[statusId]
	if existing then
		existing.expiresAt = math.max(existing.expiresAt, now + seconds)
		existing.magnitude = math.max(existing.magnitude, magnitude or 0)
		existing.source = source or existing.source
	else
		entity.statuses[statusId] = {
			id = statusId,
			expiresAt = now + seconds,
			magnitude = magnitude or 0,
			nextTick = now + (def.tickInterval or 1),
			source = source,
		}
	end

	if def.kind == "Taunt" and source then
		entity.tauntedBy = source
	elseif def.kind == "Light" then
		setLight(entity, true)
	end
	if def.kind == "Stun" then
		StatusService.Interrupted:Fire(entity, statusId)
	end
	publish(entity)
	return true
end

--[=[ Removes a status if present. ]=]
function StatusService.Remove(entity: Entity, statusId: string)
	if not entity.statuses[statusId] then
		return
	end
	entity.statuses[statusId] = nil
	local def = Statuses.ById[statusId]
	if def and def.kind == "Taunt" then
		entity.tauntedBy = nil
	elseif def and def.kind == "Light" then
		setLight(entity, false)
	elseif def and def.kind == "Shield" then
		entity.shield = 0
	end
	publish(entity)
end

--[=[ Removes every cleansable harmful status. Returns how many were removed. ]=]
function StatusService.Cleanse(entity: Entity): number
	local removed = 0
	for _, id in Statuses.Cleansable do
		if entity.statuses[id] then
			StatusService.Remove(entity, id)
			removed += 1
		end
	end
	return removed
end

--[=[ Removes all statuses (death, leash reset). ]=]
function StatusService.Clear(entity: Entity)
	for id in table.clone(entity.statuses) do
		StatusService.Remove(entity, id)
	end
end

--[=[ True while the entity cannot act (stun, fear). ]=]
function StatusService.IsDisabled(entity: Entity): boolean
	return entity.statuses.stun ~= nil or entity.statuses.fear ~= nil
end

--[=[ True while the entity cannot move (root, stun, fear). ]=]
function StatusService.IsImmobile(entity: Entity): boolean
	return entity.statuses.root ~= nil or StatusService.IsDisabled(entity)
end

--[=[ Consumes a one-shot status (e.g. overcharge) and returns whether it was present. ]=]
function StatusService.Consume(entity: Entity, statusId: string): boolean
	if entity.statuses[statusId] then
		StatusService.Remove(entity, statusId)
		return true
	end
	return false
end

local function tick()
	local now = os.clock()
	for _, entity in EntityService.All() do
		local snapshot: { [string]: Types.StatusInstance } = table.clone(entity.statuses)
		for id, status in snapshot do
			local def = Statuses.ById[id]
			if now >= status.expiresAt then
				StatusService.Remove(entity, id)
			elseif def and (def.kind == "Dot" or def.kind == "Hot") and now >= status.nextTick then
				status.nextTick += def.tickInterval or 1
				StatusService.Ticked:Fire(entity, id, status.magnitude, status.source)
			end
		end
	end
end

function StatusService.Init(deps: { [string]: any })
	EntityService = deps.EntityService
	StatService = deps.StatService
end

function StatusService.Start()
	task.spawn(function()
		while true do
			task.wait(TICK_INTERVAL)
			tick()
		end
	end)
end

return StatusService
