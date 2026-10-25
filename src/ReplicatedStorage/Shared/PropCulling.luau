--!strict

--[=[
	Pure helpers for the client prop detail controller: where a scatter chunk sits and which props
	survive thinning. Chunk names are `<i>_<k>` with i = x // size and k = z // size, as written by
	`WorldGen/Apply.luau`.
]=]
local PropCulling = {}

--[=[ Flat centre (x, z) of the chunk named `name`, or nil if the name is not a chunk key. ]=]
function PropCulling.ChunkCenter(name: string, size: number): (number?, number?)
	local i, k = string.match(name, "^(-?%d+)_(-?%d+)$")
	if not i or not k then
		return nil, nil
	end
	return ((tonumber(i) :: number) + 0.5) * size, ((tonumber(k) :: number) + 0.5) * size
end

--[=[ Flat distance from the chunk centre to (x, z), or nil for a non-chunk name. ]=]
function PropCulling.ChunkDistance(name: string, size: number, x: number, z: number): number?
	local cx, cz = PropCulling.ChunkCenter(name, size)
	if not cx or not cz then
		return nil
	end
	return math.sqrt((cx - x) ^ 2 + (cz - z) ^ 2)
end

--[=[
	Whether a prop at (x, z) stays visible when its layer is thinned to `keep` (0..1). Stable per
	position, so the same trees always remain.
]=]
function PropCulling.Keeps(x: number, z: number, keep: number): boolean
	local a = math.floor(x) % 65536
	local b = math.floor(z) % 65536
	local h = bit32.bxor((a * 73856093) % 4294967296, (b * 19349663) % 4294967296)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1274126177) % 4294967296
	return bit32.bxor(h, bit32.rshift(h, 16)) % 65536 / 65536 < keep
end

return PropCulling
