--!strict

-- Deterministic hashing and coherent noise for the terrain generator. Noise is Luau's built-in
-- `math.noise` (Perlin, about -0.5..0.5); the seed becomes a coordinate offset per octave.
local Noise = {}

local TWO32 = 4294967296

local function mul32(a: number, b: number): number
	local lo = bit32.band(a, 0xFFFF)
	local hi = bit32.rshift(a, 16)
	return bit32.band(lo * b + bit32.lshift(bit32.band(hi * b, 0xFFFF), 16), 0xFFFFFFFF)
end

local function mix(h: number, v: number): number
	local k = mul32(math.floor(v) % TWO32, 0xCC9E2D51)
	k = bit32.lrotate(k, 15)
	k = mul32(k, 0x1B873593)
	h = bit32.bxor(h, k)
	h = bit32.lrotate(h, 13)
	return bit32.band(mul32(h, 5) + 0xE6546B64, 0xFFFFFFFF)
end

local function finalize(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

--[=[ 32-bit hash of a seed and up to three integers (MurmurHash3 mixing). ]=]
function Noise.hash32(seed: number, a: number, b: number?, c: number?): number
	local h = mix(seed % TWO32, a)
	h = mix(h, b or 0)
	h = mix(h, c or 0)
	return finalize(h)
end

--[=[ Hash mapped to [0, 1). ]=]
function Noise.hash01(seed: number, a: number, b: number?, c: number?): number
	return Noise.hash32(seed, a, b, c) / TWO32
end

--[=[ Layer seed: a stable sub-seed per named layer so layers never share random streams. ]=]
function Noise.layerSeed(seed: number, name: string): number
	local h = seed
	for i = 1, #name do
		h = Noise.hash32(h, string.byte(name, i))
	end
	return h
end

export type Fbm = (x: number, z: number) -> number

local function offsets(seed: number, octaves: number): { number }
	local list = table.create(octaves * 2)
	for o = 1, octaves do
		-- Fractional offsets keep samples off integer lattice points, where Perlin noise is zero.
		list[o * 2 - 1] = (Noise.hash01(seed, o, 1) - 0.5) * 20000 + 0.371
		list[o * 2] = (Noise.hash01(seed, o, 2) - 0.5) * 20000 + 0.613
	end
	return list
end

--[=[
	Fractal Brownian motion in about [-1, 1]. `wavelength` is in studs; each octave halves it by
	`lacunarity` and scales amplitude by `gain`.
]=]
function Noise.fbm(seed: number, wavelength: number, octaves: number, lacunarity: number, gain: number): Fbm
	local offs = offsets(seed, octaves)
	local norm = 0
	local amp = 1
	for _ = 1, octaves do
		norm += amp
		amp *= gain
	end
	local base = 1 / wavelength
	return function(x: number, z: number): number
		local sum, a, f = 0, 1, base
		for o = 1, octaves do
			sum += math.noise(x * f + offs[o * 2 - 1], z * f + offs[o * 2]) * a
			a *= gain
			f *= lacunarity
		end
		return math.clamp(sum / norm * 2, -1, 1)
	end
end

--[=[ Ridged multifractal in [0, 1]: sharp crests where the noise crosses zero. ]=]
function Noise.ridged(seed: number, wavelength: number, octaves: number, lacunarity: number, gain: number): Fbm
	local offs = offsets(seed, octaves)
	local base = 1 / wavelength
	return function(x: number, z: number): number
		local sum, a, f, weight, norm = 0, 1, base, 1, 0
		for o = 1, octaves do
			local n = 1 - math.abs(math.noise(x * f + offs[o * 2 - 1], z * f + offs[o * 2]) * 2)
			n = n * n * weight
			weight = math.clamp(n * 2, 0, 1)
			sum += n * a
			norm += a
			a *= gain
			f *= lacunarity
		end
		return math.clamp(sum / norm, 0, 1)
	end
end

--[=[ Domain warp: samples `field` at a point displaced by two fbm fields (Quilez). ]=]
function Noise.warp(seed: number, field: Fbm, wavelength: number, strength: number): Fbm
	local qx = Noise.fbm(Noise.hash32(seed, 11), wavelength, 3, 2, 0.5)
	local qz = Noise.fbm(Noise.hash32(seed, 12), wavelength, 3, 2, 0.5)
	local reach = strength * wavelength
	return function(x: number, z: number): number
		return field(x + qx(x, z) * reach, z + qz(x, z) * reach)
	end
end

--[=[ Seeded xorshift32 stream in [0, 1). Same seed, same sequence, on every machine. ]=]
function Noise.rng(seed: number): () -> number
	local state = Noise.hash32(seed, 0x2545F491)
	if state == 0 then
		state = 0x9E3779B9
	end
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / TWO32
	end
end

function Noise.smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

function Noise.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

return Noise
