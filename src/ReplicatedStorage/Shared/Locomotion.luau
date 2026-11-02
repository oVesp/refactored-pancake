--!strict

--[=[
	Locomotion clip choice for animated rigs (docs/systems/ai-and-spawning.md, Animation): pure
	rules used by EnemyAnimationController. Planar speed is low-passed, each clip has separate enter
	and leave speeds, and a clip is kept for at least `MIN_DWELL` seconds, so replicated velocity
	jitter around a threshold never restarts the clips frame after frame.
]=]
local Locomotion = {}

-- "Idle", "Walk" or "Run".
export type Clip = string

export type State = {
	clip: Clip,
	-- Low-passed planar speed, studs/s.
	speed: number,
	-- Seconds since the last clip change.
	held: number,
}

-- Time constant of the speed low-pass, seconds.
Locomotion.SMOOTHING = 0.15
-- Shortest time a clip is kept before another may replace it, seconds.
Locomotion.MIN_DWELL = 0.25
Locomotion.WALK_ENTER = 0.8
Locomotion.WALK_LEAVE = 0.3
-- Enemy move speeds are 11 to 14 studs/s, so running sits clear of this band.
Locomotion.RUN_ENTER = 9
Locomotion.RUN_LEAVE = 7

--[=[ A rig standing still, free to change clip at once. ]=]
function Locomotion.new(): State
	return { clip = "Idle", speed = 0, held = math.huge }
end

local function target(state: State, hasRun: boolean): Clip
	local speed = state.speed
	if state.clip == "Idle" then
		if hasRun and speed > Locomotion.RUN_ENTER then
			return "Run"
		end
		return if speed > Locomotion.WALK_ENTER then "Walk" else "Idle"
	end
	if speed < Locomotion.WALK_LEAVE then
		return "Idle"
	end
	if state.clip == "Run" then
		return if hasRun and speed >= Locomotion.RUN_LEAVE then "Run" else "Walk"
	end
	return if hasRun and speed > Locomotion.RUN_ENTER then "Run" else "Walk"
end

--[=[
	Advances `state` by `dt` seconds with the measured planar `speed` and returns the clip to play.
	Sets without a run clip (`hasRun` false) keep walking.
]=]
function Locomotion.Step(state: State, speed: number, dt: number, hasRun: boolean): Clip
	local blend = 1 - math.exp(-math.max(dt, 0) / Locomotion.SMOOTHING)
	state.speed += (speed - state.speed) * blend
	state.held += dt
	local wanted = target(state, hasRun)
	if wanted ~= state.clip and state.held >= Locomotion.MIN_DWELL then
		state.clip = wanted
		state.held = 0
	end
	return state.clip
end

return Locomotion
