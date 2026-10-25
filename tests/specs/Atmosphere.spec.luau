--!strict

-- Atmosphere content, region blending and the shared day clock (docs/systems/atmosphere.md).
local Expect = require("../Expect")
local Loader = require("../Loader")
local Config = require("../../tools/terrain/lib/Config")
local roblox = require("@lune/roblox")

local Atmosphere = Loader.load("src/ReplicatedStorage/Content/Atmosphere")
local AtmosphereBlend = Loader.load("src/ReplicatedStorage/Shared/AtmosphereBlend")
local DayCycle = Loader.load("src/ReplicatedStorage/Shared/DayCycle")

local Vector3 = roblox.Vector3

local function near(a: number, b: number, eps: number, label: string)
	Expect.truthy(math.abs(a - b) <= eps, `{label}: {a} vs {b}`)
end

return {
	["region bands match the terrain generator"] = function()
		local w = Config.world
		local b = Atmosphere.Bands
		for _, pair in
			{
				{ b.mountain, w.mountains.fromZ, w.mountains.toZ, "mountain" },
				{ b.highland, w.highlands.fromZ, w.highlands.toZ, "highland" },
				{ b.swamp, w.swamp.fromX, w.swamp.toX, "swamp" },
				{ b.plains, w.plains.fromX, w.plains.toX, "plains" },
				{ b.coast, w.coast.fromZ, w.coast.toZ, "coast" },
			}
		do
			Expect.equal(pair[1].from, pair[2], `{pair[4]} from`)
			Expect.equal(pair[1].to, pair[3], `{pair[4]} to`)
		end
	end,
	["every mood has the same fields"] = function()
		local valley = Atmosphere.Moods.valley
		for name, mood in Atmosphere.Moods do
			for key in valley do
				Expect.truthy(mood[key] ~= nil, `{name} lacks {key}`)
			end
		end
	end,
	["weights sum to one and pick the region"] = function()
		local cases = {
			{ Vector3.new(0, 10, -330), "valley" },
			{ Vector3.new(0, 100, -4500), "mountain" },
			{ Vector3.new(-4000, 0, 0), "swamp" },
			{ Vector3.new(4000, 10, 0), "plains" },
			{ Vector3.new(0, 0, 4000), "coast" },
			{ Vector3.new(0, 500, -330), "alpine" },
		}
		for _, case in cases do
			local weights = AtmosphereBlend.Weights(case[1])
			local total = 0
			for _, w in weights do
				Expect.truthy(w >= 0, "non-negative")
				total += w
			end
			near(total, 1, 1e-9, `sum at {case[2]}`)
			near(weights[case[2]], 1, 1e-9, `{case[2]} dominates`)
		end
	end,
	["a single region mixes to its own mood"] = function()
		local mixed = AtmosphereBlend.Mix({ swamp = 1 })
		Expect.equal(mixed.density, Atmosphere.Moods.swamp.density)
		local half = AtmosphereBlend.Mix({ valley = 0.5, swamp = 0.5 })
		near(half.density, (Atmosphere.Moods.valley.density + Atmosphere.Moods.swamp.density) / 2, 1e-9, "half")
	end,
	["day clock has the owner's period and night share"] = function()
		local period = Atmosphere.DayLength
		Expect.equal(period, 1440)
		near(DayCycle.ClockAt(0), 6, 1e-9, "cycle starts at dawn")
		near(DayCycle.ClockAt(period), 6, 1e-9, "wraps")
		local nightSamples = 0
		local samples = 2880
		local previous = DayCycle.ClockAt(0)
		for k = 1, samples do
			local clock = DayCycle.ClockAt(k * period / samples)
			if DayCycle.IsNight(clock) then
				nightSamples += 1
			end
			local step = (clock - previous) % 24
			Expect.truthy(step > 0 and step < 0.1, `clock moves forward smoothly at sample {k}`)
			previous = clock
		end
		near(nightSamples / samples, Atmosphere.NightShare, 0.002, "night share")
	end,
	["light is continuous across the day"] = function()
		local previous = AtmosphereBlend.LightAt(0)
		for k = 1, 2400 do
			local light = AtmosphereBlend.LightAt(k / 100 % 24)
			Expect.truthy(math.abs(light.brightness - previous.brightness) < 0.05, `brightness jump at {k / 100}`)
			previous = light
		end
		near(AtmosphereBlend.LightAt(12).brightness, 2.6, 1e-9, "noon")
	end,
}
