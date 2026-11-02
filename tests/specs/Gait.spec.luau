--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Gait = Loader.load("src/ReplicatedStorage/Shared/Gait")
local Run = Loader.load("src/ReplicatedStorage/Content/Tuning").Base.Run

local WINDOW = Run.DoubleTapWindow

local function runningState(): any
	local state = Gait.new()
	Gait.ForwardBegan(state, false, 10, WINDOW)
	Gait.ForwardEnded(state)
	Gait.ForwardBegan(state, false, 10 + WINDOW / 2, WINDOW)
	Expect.equal(state.running, true, "started running")
	return state
end

return {
	["starts walking"] = function()
		Expect.equal(Gait.new().running, false)
	end,
	["a second tap inside the window runs"] = function()
		local state = Gait.new()
		Gait.ForwardBegan(state, false, 10, WINDOW)
		Expect.equal(state.running, false, "first tap")
		Gait.ForwardBegan(state, false, 10 + WINDOW * 0.99, WINDOW)
		Expect.equal(state.running, true, "second tap at the end of the window")
	end,
	["a second tap after the window starts over"] = function()
		local state = Gait.new()
		Gait.ForwardBegan(state, false, 10, WINDOW)
		Gait.ForwardBegan(state, false, 10 + WINDOW + 0.01, WINDOW)
		Expect.equal(state.running, false, "late tap")
		Gait.ForwardBegan(state, false, 10 + WINDOW + 0.02, WINDOW)
		Expect.equal(state.running, true, "the late tap opened a new window")
	end,
	["a triple tap needs a fresh double tap to run again"] = function()
		local state = runningState()
		Gait.ForwardEnded(state)
		Gait.ForwardBegan(state, false, 10 + WINDOW * 0.75, WINDOW)
		Expect.equal(state.running, false, "the tap that started running is spent")
	end,
	["keys taken by chat or UI are not taps"] = function()
		local state = Gait.new()
		Gait.ForwardBegan(state, true, 10, WINDOW)
		Gait.ForwardBegan(state, false, 10.1, WINDOW)
		Expect.equal(state.running, false, "processed first tap")
		Gait.ForwardBegan(state, true, 10.2, WINDOW)
		Expect.equal(state.running, false, "processed second tap")
	end,
	["releasing forward stops running"] = function()
		local state = runningState()
		Gait.ForwardEnded(state)
		Expect.equal(state.running, false)
	end,
	["keeps running while moving"] = function()
		local state = runningState()
		Gait.Step(state, true, 100, 1)
		Gait.Step(state, true, 100, Gait.STOP_MOVE_MAGNITUDE)
		Expect.equal(state.running, true)
	end,
	["standing still stops running"] = function()
		local state = runningState()
		Gait.Step(state, true, 100, 0)
		Expect.equal(state.running, false, "stopped")
		state = runningState()
		Gait.Step(state, true, 100, Gait.STOP_MOVE_MAGNITUDE - 0.01)
		Expect.equal(state.running, false, "just under the threshold")
	end,
	["dying or losing the character stops running"] = function()
		local state = runningState()
		Gait.Step(state, true, 0, 1)
		Expect.equal(state.running, false, "dead")
		state = runningState()
		Gait.Step(state, false, 0, 0)
		Expect.equal(state.running, false, "no character")
	end,
	["running needs a new double tap after stopping"] = function()
		local state = runningState()
		Gait.Step(state, true, 100, 0)
		Gait.Step(state, true, 100, 1)
		Expect.equal(state.running, false, "moving again walks")
	end,
}
