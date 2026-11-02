--!strict

--[=[
	Cascading NPC tasks and leader following (docs/systems/ai-and-spawning.md, Tasks). Pure: callers
	pass definitions, predicates and tuning in, so Lune tests cover it. AIService runs the cascade
	whenever a brain has no combat target.
]=]
local Tasks = {}

export type Kind = "FollowLeader" | "Guard" | "Patrol" | "Wander" | "Idle"

export type Task = {
	kind: Kind,
	--[=[ Guard: CollectionService tag of what to guard. ]=]
	tag: string?,
	--[=[ Guard: studs kept from the guarded thing. Default Tuning.Tasks.GuardRadius. ]=]
	radius: number?,
}

export type Stance = "Hostile" | "Neutral"

export type FollowSettings = {
	--[=[ Studs from the leader to the first row, and between rows and columns. ]=]
	Back: number,
	Spacing: number,
	RowWidth: number,
	--[=[ Slot offset per axis, at most this many studs either way. ]=]
	Jitter: number,
	--[=[ A walking follower stops within ArriveRadius; a standing one walks again beyond ResumeRadius. ]=]
	ArriveRadius: number,
	ResumeRadius: number,
	--[=[ Pace against the leader's: CatchUpFactor beyond CatchUpDistance, SettleFactor beyond ArriveRadius, else equal. ]=]
	CatchUpDistance: number,
	CatchUpFactor: number,
	SettleFactor: number,
}

--[=[ The cascade of a definition without `tasks`: follow, else walk the route, else wander, else stand. ]=]
local defaults: { Task } = {
	{ kind = "FollowLeader" },
	{ kind = "Patrol" },
	{ kind = "Wander" },
	{ kind = "Idle" },
}
Tasks.Default = table.freeze(defaults)

local IDLE: Task = { kind = "Idle" }

--[=[ First task in priority order whose precondition holds; Idle when none does. ]=]
function Tasks.Select(tasks: { Task }, possible: (Task) -> boolean): Task
	for _, task in tasks do
		if possible(task) then
			return task
		end
	end
	return IDLE
end

--[=[ The definition's `stance`, by default Hostile for monster factions and Neutral for everyone else. ]=]
function Tasks.Stance(def: any, monster: boolean): Stance
	return def.stance or if monster then "Hostile" else "Neutral"
end

-- Stable noise in [-1, 1] from a number: the same member keeps the same slot.
local function noise(seed: number): number
	local value = math.sin(seed * 12.9898) * 43758.5453
	return (value - math.floor(value)) * 2 - 1
end

--[=[
	Loose slot of follower `index` (1-based) in the leader's frame, X to its right and Z behind it
	(Shared/Formation): rows behind the leader, shifted by jitter that depends only on `seed`.
]=]
function Tasks.SlotOffset(index: number, seed: number, settings: FollowSettings): Vector3
	local width = settings.RowWidth
	local row = math.floor((index - 1) / width)
	local column = (index - 1) % width - (width - 1) / 2
	return Vector3.new(
		column * settings.Spacing + noise(seed) * settings.Jitter,
		0,
		settings.Back + row * settings.Spacing + noise(seed + 0.5) * settings.Jitter
	)
end

--[=[
	True when a follower `gap` studs from its slot should be walking. It never stops while the
	leader walks; the deadband around a standing leader stops twitching.
]=]
function Tasks.ShouldWalk(gap: number, walking: boolean, leaderMoving: boolean, settings: FollowSettings): boolean
	if walking and leaderMoving then
		return true
	end
	return gap > (if walking then settings.ArriveRadius else settings.ResumeRadius)
end

--[=[
	Share of its own full speed a follower walks at: the leader's walking speed, faster when far
	from its slot, never above its own speed.
]=]
function Tasks.FollowPace(gap: number, leaderSpeed: number, ownSpeed: number, settings: FollowSettings): number
	if ownSpeed <= 0 then
		return 1
	end
	local factor = if gap > settings.CatchUpDistance
		then settings.CatchUpFactor
		elseif gap > settings.ArriveRadius then settings.SettleFactor
		else 1
	return math.min(leaderSpeed * factor / ownSpeed, 1)
end

export type LeaderCandidate = {
	key: any,
	--[=[ Order in the squad; the lowest capable member wins. ]=]
	seq: number,
	capable: boolean,
}

--[=[ Who takes over a squad: the first member with `combat.leader`, or nil when nobody can lead. ]=]
function Tasks.PickLeader(candidates: { LeaderCandidate }): any?
	local best: LeaderCandidate? = nil
	for _, candidate in candidates do
		if candidate.capable and (best == nil or candidate.seq < best.seq) then
			best = candidate
		end
	end
	return if best then best.key else nil
end

return Tasks
