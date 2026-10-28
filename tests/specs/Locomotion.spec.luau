--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Locomotion = Loader.load("src/ReplicatedStorage/Shared/Locomotion")

local DT = 1 / 60

-- Steps `seconds` of frames at `speed` and returns the clip changes seen.
local function run(state: any, speed: number | (number) -> number, seconds: number, hasRun: boolean?): number
	local changes = 0
	local frames = math.floor(seconds / DT + 0.5)
	for frame = 1, frames do
		local before = state.clip
		local value = if type(speed) == "function" then speed(frame) else speed
		Locomotion.Step(state, value, DT, hasRun ~= false)
		if state.clip ~= before then
			changes += 1
		end
	end
	return changes
end

return {
	["starts idle and walks, runs and stops with steady speeds"] = function()
		local state = Locomotion.new()
		Expect.equal(state.clip, "Idle")
		run(state, 4, 1)
		Expect.equal(state.clip, "Walk")
		run(state, 13, 1)
		Expect.equal(state.clip, "Run")
		run(state, 0, 1)
		Expect.equal(state.clip, "Idle")
	end,
	["jitter around the walk threshold does not flip clips"] = function()
		local state = Locomotion.new()
		local changes = run(state, function(frame)
			return if frame % 2 == 0 then 0.4 else 0.6
		end, 3)
		Expect.equal(changes, 0, "stays idle")
		state = Locomotion.new()
		run(state, 4, 1)
		changes = run(state, function(frame)
			return if frame % 2 == 0 then 0.4 else 0.6
		end, 3)
		Expect.equal(changes, 0, "stays walking")
	end,
	["velocity spikes cannot flip clips every frame"] = function()
		local state = Locomotion.new()
		run(state, 12, 1)
		local changes = run(state, function(frame)
			return if frame % 3 == 0 then 0 else 12
		end, 3)
		Expect.equal(changes, 0, "keeps running through dropped frames")
		changes = run(state, function(frame)
			return if frame % 2 == 0 then 0 else 20
		end, 3)
		Expect.truthy(changes <= 3 / Locomotion.MIN_DWELL, "at most one change per dwell")
	end,
	["sets without a run clip keep walking"] = function()
		local state = Locomotion.new()
		run(state, 14, 1, false)
		Expect.equal(state.clip, "Walk")
	end,
}
