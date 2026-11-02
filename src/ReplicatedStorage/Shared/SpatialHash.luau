--!strict

--[=[
	Uniform grid over the ground plane for neighbour queries (game-design.md 5.6: detection by
	spatial queries). Rebuilt each AI step from current positions. Pure, so Lune tests cover it.
]=]
local SpatialHash = {}

export type Hash<T> = {
	cell: number,
	buckets: { [number]: { { item: T, position: Vector3 } } },
}

-- Packs a cell coordinate pair into one key; cells span +-2^20 on each axis.
local function key(cx: number, cz: number): number
	return (cx + 1048576) * 2097152 + (cz + 1048576)
end

function SpatialHash.new<T>(cell: number): Hash<T>
	return { cell = cell, buckets = {} }
end

function SpatialHash.Clear<T>(hash: Hash<T>)
	table.clear(hash.buckets)
end

function SpatialHash.Insert<T>(hash: Hash<T>, item: T, position: Vector3)
	local k = key(math.floor(position.X / hash.cell), math.floor(position.Z / hash.cell))
	local bucket = hash.buckets[k]
	if not bucket then
		bucket = {}
		hash.buckets[k] = bucket
	end
	table.insert(bucket, { item = item, position = position })
end

--[=[ Items within `radius` (3D distance) of `position`. ]=]
function SpatialHash.Query<T>(hash: Hash<T>, position: Vector3, radius: number): { T }
	local out: { T } = {}
	local x0 = math.floor((position.X - radius) / hash.cell)
	local x1 = math.floor((position.X + radius) / hash.cell)
	local z0 = math.floor((position.Z - radius) / hash.cell)
	local z1 = math.floor((position.Z + radius) / hash.cell)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local bucket = hash.buckets[key(cx, cz)]
			if bucket then
				for _, entry in bucket do
					if (entry.position - position).Magnitude <= radius then
						table.insert(out, entry.item)
					end
				end
			end
		end
	end
	return out
end

return SpatialHash
