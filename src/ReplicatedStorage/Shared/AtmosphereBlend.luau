--!strict

local Atmosphere = require(script.Parent.Parent.Content.Atmosphere)

type Mood = Atmosphere.Mood
type Light = Atmosphere.Light

--[=[
	Pure blending for the atmosphere controller: region weights at a position, the mood they mix
	to, and the light at a clock time. No instances are touched here.
]=]
local AtmosphereBlend = {}

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(lerp(a.R, b.R, t), lerp(a.G, b.G, t), lerp(a.B, b.B, t))
end

local function mulColor(a: Color3, b: Color3): Color3
	return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B)
end

AtmosphereBlend.LerpColor = lerpColor

--[=[
	Region weights at a world position, summing to 1. Same shape as the terrain generator's
	`Layout.regions`, plus `alpine` from height and `valley` for whatever is left.
]=]
function AtmosphereBlend.Weights(position: Vector3): { [string]: number }
	local b = Atmosphere.Bands
	local mountain = smoothstep(b.mountain.from, b.mountain.to, position.Z)
	local coast = smoothstep(b.coast.from, b.coast.to, position.Z)
	local open = (1 - mountain) * (1 - coast)
	local highland = smoothstep(b.highland.from, b.highland.to, position.Z) * (1 - mountain)
	local lowland = open * (1 - highland)
	local swamp = smoothstep(b.swamp.from, b.swamp.to, position.X) * lowland
	local plains = smoothstep(b.plains.from, b.plains.to, position.X) * lowland
	local alpine = smoothstep(b.alpine.from, b.alpine.to, position.Y)
	local ground = 1 - alpine
	local weights: { [string]: number } = {
		mountain = mountain * ground,
		coast = coast * ground,
		highland = highland * ground,
		swamp = swamp * ground,
		plains = plains * ground,
		alpine = alpine,
	}
	local used = 0
	for _, w in weights do
		used += w
	end
	weights.valley = math.max(0, 1 - used)
	return weights
end

--[=[ The mood mixed from `weights` (as returned by `Weights`). ]=]
function AtmosphereBlend.Mix(weights: { [string]: number }): Mood
	local out: Mood = table.clone(Atmosphere.Moods.valley)
	local total = 0
	local first = true
	for name, w in weights do
		local mood = Atmosphere.Moods[name]
		if w <= 0 or not mood then
			continue
		end
		total += w
		local t = w / total
		if first then
			out = table.clone(mood)
			first = false
		else
			for key, value in mood :: any do
				local current = (out :: any)[key];
				(out :: any)[key] = if typeof(value) == "Color3"
					then lerpColor(current, value, t)
					else lerp(current, value, t)
			end
		end
	end
	return out
end

--[=[ The light at `clock` (0..24), interpolated between the surrounding keys. ]=]
function AtmosphereBlend.LightAt(clock: number): Light
	local keys = Atmosphere.Lights
	local count = #keys
	local index = count
	for k = 1, count do
		if keys[k].hour <= clock then
			index = k
		end
	end
	local before, after = keys[index], keys[index % count + 1]
	local span = (after.hour - before.hour) % 24
	local t = if span > 0 then ((clock - before.hour) % 24) / span else 0
	local out: any = {}
	for key, value in before :: any do
		local other = (after :: any)[key]
		out[key] = if typeof(value) == "Color3" then lerpColor(value, other, t) else lerp(value, other, t)
	end
	out.hour = clock
	return out :: Light
end

--[=[ Region mood lit by the time of day: colours multiplied by `skyLight`, haze scaled. ]=]
function AtmosphereBlend.Lit(mood: Mood, light: Light): Mood
	local out = table.clone(mood)
	out.color = mulColor(mood.color, light.skyLight)
	out.decay = mulColor(mood.decay, light.skyLight)
	out.tint = lerpColor(mood.tint, mulColor(mood.tint, light.skyLight), 0.35)
	out.haze = mood.haze * light.hazeScale
	return out
end

return AtmosphereBlend
