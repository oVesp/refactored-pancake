--!strict

--[=[
	Deterministic hashing and coherent noise for the world generator. Runs the same in Studio and
	in Lune, so a seed gives the same world in both. Noise is Luau's built-in `math.noise`
	(Perlin, about -0.5..0.5); a seed becomes a coordinate offset per octave.
]=]
local Hash = {}

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
function Hash.u32(seed: number, a: number, b: number?, c: number?): number
	local h = mix(seed % TWO32, a)
	h = mix(h, b or 0)
	h = mix(h, c or 0)
	return finalize(h)
end

--[=[ Hash mapped to [0, 1). ]=]
function Hash.unit(seed: number, a: number, b: number?, c: number?): number
	return Hash.u32(seed, a, b, c) / TWO32
end

--[=[ Hash mapped to [lo, hi). ]=]
function Hash.range(seed: number, lo: number, hi: number, a: number, b: number?, c: number?): number
	return lo + (hi - lo) * Hash.unit(seed, a, b, c)
end

--[=[ Stable sub-seed for a name, so zones, borders and layers never share a random stream. ]=]
function Hash.named(seed: number, name: string): number
	local h = seed % TWO32
	for i = 1, #name do
		h = Hash.u32(h, string.byte(name, i))
	end
	return h
end

--[=[ Seed for the border between two zones; the same whichever side asks. ]=]
function Hash.pair(seed: number, a: string, b: string): number
	if a > b then
		a, b = b, a
	end
	return Hash.named(seed, a .. "|" .. b)
end

--[=[ Small deterministic generator for sequential draws (xorshift32). ]=]
export type Rng = {
	next: (self: Rng) -> number,
	range: (self: Rng, lo: number, hi: number) -> number,
	int: (self: Rng, lo: number, hi: number) -> number,
}

function Hash.rng(seed: number): Rng
	local state = Hash.u32(seed, 0x9E3779B9)
	if state == 0 then
		state = 0x6D2B79F5
	end
	local self = {}
	function self.next(_: Rng): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / TWO32
	end
	function self.range(r: Rng, lo: number, hi: number): number
		return lo + (hi - lo) * r:next()
	end
	function self.int(r: Rng, lo: number, hi: number): number
		return math.min(hi, lo + math.floor((hi - lo + 1) * r:next()))
	end
	return self :: any
end

export type Fbm = (x: number, z: number) -> number

--[=[
	Fractal noise in about -1..1 with `octaves` layers, base wavelength `scale` studs. Each octave
	gets its own seeded offset; fractional offsets keep samples off lattice points, where Perlin
	noise is zero.
]=]
function Hash.fbm(seed: number, scale: number, octaves: number, gain: number?): Fbm
	local g = gain or 0.5
	local offsets = table.create(octaves * 2)
	local norm = 0
	local amp = 1
	for o = 1, octaves do
		offsets[o * 2 - 1] = (Hash.unit(seed, o, 1) - 0.5) * 20000 + 0.371
		offsets[o * 2] = (Hash.unit(seed, o, 2) - 0.5) * 20000 + 0.613
		norm += amp
		amp *= g
	end
	local inv = 2 / norm
	return function(x: number, z: number): number
		local sum, a, f = 0, 1, 1 / scale
		for o = 1, octaves do
			sum += a * math.noise(x * f + offsets[o * 2 - 1], z * f + offsets[o * 2])
			a *= g
			f *= 2
		end
		return sum * inv
	end
end

return Hash
