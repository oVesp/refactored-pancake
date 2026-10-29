--!strict

--[=[
	Marching formations for NPC groups (docs/systems/open-world.md). Pure: offsets are in the
	leader's frame, X to the leader's right and Z behind it, so Lune tests cover them.
]=]
local Formation = {}

export type Shape = "Column" | "Line" | "Wedge" | "Ring"

-- Leader first, then alternating right and left: 0, 1, -1, 2, -2, ...
local function abreast(index: number): number
	if index == 0 then
		return 0
	end
	local rank = math.ceil(index / 2)
	return if index % 2 == 1 then rank else -rank
end

--[=[
	Offsets for `count` members, `spacing` studs apart. Index 1 is the leader at the origin.
	Column: single file. Line: abreast. Wedge: a V behind the leader. Ring: the others around the
	leader (escorts around a wagon).
]=]
function Formation.Offsets(shape: Shape, count: number, spacing: number): { Vector3 }
	local out: { Vector3 } = {}
	for i = 0, count - 1 do
		if i == 0 then
			table.insert(out, Vector3.zero)
		elseif shape == "Column" then
			table.insert(out, Vector3.new(0, 0, i * spacing))
		elseif shape == "Line" then
			table.insert(out, Vector3.new(abreast(i) * spacing, 0, 0))
		elseif shape == "Wedge" then
			local rank = math.ceil(i / 2)
			local side = if i % 2 == 1 then 1 else -1
			table.insert(out, Vector3.new(side * rank * spacing, 0, rank * spacing))
		else
			local angle = (i - 1) / (count - 1) * math.pi * 2
			table.insert(out, Vector3.new(math.sin(angle) * spacing, 0, math.cos(angle) * spacing))
		end
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
