--!strict

local Expect = require("../Expect")
local RateLimiter = require("../../src/ReplicatedStorage/Shared/RateLimiter")

local function fakeClock()
	local time = 0
	return function()
		return time
	end, function(seconds: number)
		time += seconds
	end
end

return {
	["allows up to capacity then blocks"] = function()
		local clock = fakeClock()
		local limiter = RateLimiter.new(2, 1, clock)
		Expect.truthy(limiter:Allow("a"))
		Expect.truthy(limiter:Allow("a"))
		Expect.equal(limiter:Allow("a"), false)
	end,
	["refills over time and never above capacity"] = function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new(2, 1, clock)
		limiter:Allow("a")
		limiter:Allow("a")
		advance(10)
		Expect.truthy(limiter:Allow("a"))
		Expect.truthy(limiter:Allow("a"))
		Expect.equal(limiter:Allow("a"), false)
	end,
	["keys are independent and forget resets"] = function()
		local clock = fakeClock()
		local limiter = RateLimiter.new(1, 1, clock)
		Expect.truthy(limiter:Allow("a"))
		Expect.truthy(limiter:Allow("b"))
		Expect.equal(limiter:Allow("a"), false)
		limiter:Forget("a")
		Expect.truthy(limiter:Allow("a"))
	end,
}
