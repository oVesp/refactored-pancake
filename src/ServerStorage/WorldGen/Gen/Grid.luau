--!strict

--[=[
	A rectangle of field samples on a regular grid (one per terrain column). Terrain writes, cliff
	detection and prop placement read the same samples, so the field is evaluated once per build.
]=]
local Field = require(script.Parent.Field)

export type Grid = {
	x0: number, -- world position of sample (0, 0)
	z0: number,
	nx: number,
	nz: number,
	step: number,
	height: { number },
	material: { string },
	owner: { number },
	assign: { number },
	water: { number }, -- 0 = dry (water surfaces are never at exactly 0)
	corridor: { [number]: Field.Corridor }, -- sparse: only samples on a corridor
	padDistance: { number },
}

local Grid = {}

--[=[ Samples `nx` x `nz` points from (x0, z0), `step` studs apart. ]=]
function Grid.sample(field: Field.Field, x0: number, z0: number, nx: number, nz: number, step: number): Grid
	local total = nx * nz
	local grid: Grid = {
		x0 = x0,
		z0 = z0,
		nx = nx,
		nz = nz,
		step = step,
		height = table.create(total, 0),
		material = table.create(total, ""),
		owner = table.create(total, 0),
		assign = table.create(total, 0),
		water = table.create(total, 0),
		corridor = {},
		padDistance = table.create(total, 0),
	}
	local k = 0
	for j = 0, nz - 1 do
		local z = z0 + j * step
		for i = 0, nx - 1 do
			k += 1
			local s = field.sample(x0 + i * step, z)
			grid.height[k] = s.height
			grid.material[k] = s.material
			grid.owner[k] = s.owner
			grid.assign[k] = s.assign
			grid.water[k] = s.water or 0
			local corridor = s.corridor
			if corridor then
				grid.corridor[k] = corridor
			end
			grid.padDistance[k] = s.padDistance
		end
	end
	return grid
end

--[=[ 1-based index of sample (i, j), clamped to the grid. ]=]
function Grid.index(grid: Grid, i: number, j: number): number
	return math.clamp(i, 0, grid.nx - 1) + math.clamp(j, 0, grid.nz - 1) * grid.nx + 1
end

--[=[ Height at a world position, bilinear between samples. ]=]
function Grid.heightAt(grid: Grid, x: number, z: number): number
	local fx = (x - grid.x0) / grid.step
	local fz = (z - grid.z0) / grid.step
	local i, j = math.floor(fx), math.floor(fz)
	local tx, tz = fx - i, fz - j
	local h = grid.height
	local a = h[Grid.index(grid, i, j)]
	local b = h[Grid.index(grid, i + 1, j)]
	local c = h[Grid.index(grid, i, j + 1)]
	local d = h[Grid.index(grid, i + 1, j + 1)]
	return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz
end

return Grid
