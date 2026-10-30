--!strict

--[=[
	Where NPC groups stand (docs/systems/open-world.md). Pure: offsets are in the leader's frame, X
	to the leader's right and Z behind it, so Lune tests cover them. Marching follows Shared/Tasks.
]=]
local Formation = {}

--[=[ Offsets for a station of `count` members: the first at the origin, the others around it, `spacing` studs out. ]=]
function Formation.Ring(count: number, spacing: number): { Vector3 }
	local out: { Vector3 } = { Vector3.zero }
	for i = 1, count - 1 do
		local angle = (i - 1) / (count - 1) * math.pi * 2
		table.insert(out, Vector3.new(math.sin(angle) * spacing, 0, math.cos(angle) * spacing))
	end
	return out
end

--[=[ World position of a leader-frame offset; `forward` is the leader's flat heading. ]=]
function Formation.Place(origin: Vector3, forward: Vector3, offset: Vector3): Vector3
	local flat = Vector3.new(forward.X, 0, forward.Z)
	local ahead = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-ahead.Z, 0, ahead.X)
	return origin + right * offset.X - ahead * offset.Z
end

return Formation
