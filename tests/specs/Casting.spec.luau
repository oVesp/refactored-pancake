--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Casting = Loader.load("src/ReplicatedStorage/Shared/Casting")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")

local CAST = Tuning.Combat.Cast
local BASE_SPEED = Tuning.Base.MoveSpeed

-- Walks a cast at `speed` studs per second while `walking(elapsed)`; returns the seconds until it
-- cancels, or nil if it never does within `seconds`. For `ping` seconds the caster has not yet got the
-- creep and walks at `BASE_SPEED`, and the server counts that time as grace.
local function cancelledAfter(speed: number, seconds: number, walking: (number) -> boolean, ping: number?): number?
	local latency = ping or 0
	local dt = 1 / 60
	local anchor = nil
	local x = 0
	local elapsed = 0
	while elapsed < seconds do
		elapsed += dt
		if walking(elapsed) then
			x += (if elapsed < latency then BASE_SPEED else speed) * dt
		end
		local cancelled
		anchor, cancelled = Casting.Step(anchor, elapsed - latency, x, 0, CAST)
		if cancelled then
			return elapsed
		end
	end
	return nil
end

return {
	["a release fires when full, buffers just short of it and fizzles earlier"] = function()
		Expect.equal(Casting.Release(11, 10, 0.1), "Fire", "after full")
		Expect.equal(Casting.Release(10, 10, 0.1), "Fire", "at full")
		Expect.equal(Casting.Release(9.95, 10, 0.1), "Buffer", "inside the grace")
		Expect.equal(Casting.Release(9.5, 10, 0.1), "Fizzle", "early")
		Expect.equal(Casting.Release(0, 10, 0.1), "Fizzle", "a tap")
	end,
	["a tapped key does not cancel a cast"] = function()
		local speed = BASE_SPEED * CAST.MoveMultiplier
		local tap = cancelledAfter(speed, 5, function(elapsed)
			return elapsed > 0.5 and elapsed < 0.8
		end)
		Expect.equal(tap, nil, "a 0.3 s tap")
		local taps = cancelledAfter(speed, 5, function(elapsed)
			return elapsed % 1 < 0.2
		end)
		Expect.truthy(taps == nil or taps > 2, "single taps add up slowly")
	end,
	["a slide before the grace ends does not count"] = function()
		local slide = cancelledAfter(BASE_SPEED * Tuning.Base.Run.SpeedMultiplier, 3, function(elapsed)
			return elapsed < CAST.MoveGrace
		end)
		Expect.equal(slide, nil, "running into the press")
	end,
	["high ping does not use up the tolerance"] = function()
		local speed = BASE_SPEED * CAST.MoveMultiplier
		local stops = cancelledAfter(speed, 5, function(elapsed)
			return elapsed < 0.7
		end, Tuning.Combat.MaxRewind)
		Expect.equal(stops, nil, "walking into the press, then stopping")
		local keepsWalking = cancelledAfter(speed, 5, function()
			return true
		end, Tuning.Combat.MaxRewind)
		Expect.truthy(keepsWalking, "sustained walking still cancels")
	end,
	["sustained walking cancels within about a second, running sooner"] = function()
		local function always()
			return true
		end
		local walked = cancelledAfter(BASE_SPEED * CAST.MoveMultiplier, 5, always)
		Expect.truthy(walked and walked > 0.5 and walked < 1.5, `walked cancels at {walked}`)
		local ran = cancelledAfter(BASE_SPEED * Tuning.Base.Run.SpeedMultiplier * CAST.MoveMultiplier, 5, always)
		Expect.truthy(ran and walked and ran < walked, "running cancels sooner")
	end,
	["the time a disruptor sees runs to full, then to the hold's end"] = function()
		Expect.equal(Casting.Remaining(9, 10, nil), 1, "charging")
		Expect.equal(Casting.Remaining(11, 10, 20), 9, "holding a full charge")
		Expect.equal(Casting.Remaining(11, 10, nil), -1, "an NPC cast never holds")
	end,
}
