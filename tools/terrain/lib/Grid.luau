--!strict

-- Square float grids backed by buffers. Cell (i, j) maps to world X = originX + (i + 0.5) * cell,
-- Z = originZ + (j + 0.5) * cell. Index is i + j * n, zero-based.
local Grid = {}

export type Grid = { n: number, data: buffer }

function Grid.new(n: number, fill: number?): Grid
	local data = buffer.create(n * n * 4)
	if fill and fill ~= 0 then
		for k = 0, n * n - 1 do
			buffer.writef32(data, k * 4, fill)
		end
	end
	return { n = n, data = data }
end

function Grid.copy(g: Grid): Grid
	local data = buffer.create(buffer.len(g.data))
	buffer.copy(data, 0, g.data)
	return { n = g.n, data = data }
end

function Grid.get(g: Grid, i: number, j: number): number
	local n = g.n
	i = math.clamp(i, 0, n - 1)
	j = math.clamp(j, 0, n - 1)
	return buffer.readf32(g.data, (i + j * n) * 4)
end

function Grid.set(g: Grid, i: number, j: number, v: number)
	buffer.writef32(g.data, (i + j * g.n) * 4, v)
end

--[=[ Bilinear sample at fractional cell coordinates (cell centres at integers). ]=]
function Grid.sample(g: Grid, fi: number, fj: number): number
	local i0 = math.floor(fi)
	local j0 = math.floor(fj)
	local tx = fi - i0
	local tz = fj - j0
	local a = Grid.get(g, i0, j0)
	local b = Grid.get(g, i0 + 1, j0)
	local c = Grid.get(g, i0, j0 + 1)
	local d = Grid.get(g, i0 + 1, j0 + 1)
	return (a + (b - a) * tx) * (1 - tz) + (c + (d - c) * tx) * tz
end

--[=[ Height gradient in units per stud, by central differences. ]=]
function Grid.gradient(g: Grid, i: number, j: number, cell: number): (number, number)
	local dx = (Grid.get(g, i + 1, j) - Grid.get(g, i - 1, j)) / (2 * cell)
	local dz = (Grid.get(g, i, j + 1) - Grid.get(g, i, j - 1)) / (2 * cell)
	return dx, dz
end

--[=[ Slope angle in degrees. ]=]
function Grid.slopeDeg(g: Grid, i: number, j: number, cell: number): number
	local dx, dz = Grid.gradient(g, i, j, cell)
	return math.deg(math.atan(math.sqrt(dx * dx + dz * dz)))
end

function Grid.range(g: Grid): (number, number)
	local lo, hi = math.huge, -math.huge
	for k = 0, g.n * g.n - 1 do
		local v = buffer.readf32(g.data, k * 4)
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	return lo, hi
end

return Grid
