--!strict

--[=[
	Pure target scoring shared by the client soft target and tests. Lower scores are better: a
	blend of the angle from the camera centre and the distance from the character. The current
	target gets a stickiness bonus so it does not flicker between enemies in a crowd.
]=]
local Targeting = {}

export type Candidate<K> = {
	key: K,
	position: Vector3,
}

export type Options<K> = {
	--[=[ Camera position: the angle is measured from here. ]=]
	eye: Vector3,
	--[=[ Camera look direction. ]=]
	forward: Vector3,
	--[=[ Character position: the range is measured from here. ]=]
	from: Vector3,
	range: number,
	coneDegrees: number,
	angleWeight: number,
	stickiness: number,
	current: K?,
}

--[=[ Score for a position, or nil when it is out of range or outside the cone. ]=]
function Targeting.Score(
	eye: Vector3,
	forward: Vector3,
	from: Vector3,
	position: Vector3,
	range: number,
	coneDegrees: number,
	angleWeight: number
): number?
	local distance = (position - from).Magnitude
	local toTarget = position - eye
	if distance > range or toTarget.Magnitude < 1e-3 or forward.Magnitude < 1e-3 then
		return nil
	end
	local cosine = math.clamp(forward.Unit:Dot(toTarget.Unit), -1, 1)
	local angle = math.deg(math.acos(cosine))
	if angle > coneDegrees then
		return nil
	end
	return angleWeight * (angle / coneDegrees) + (1 - angleWeight) * (distance / range)
end

--[=[ Candidates that score, best first. The current target's score is reduced by `stickiness`. ]=]
function Targeting.Rank<K>(candidates: { Candidate<K> }, options: Options<K>): { K }
	local scored: { { key: K, score: number } } = {}
	for _, candidate in candidates do
		local score = Targeting.Score(
			options.eye,
			options.forward,
			options.from,
			candidate.position,
			options.range,
			options.coneDegrees,
			options.angleWeight
		)
		if score then
			if options.current ~= nil and candidate.key == options.current then
				score -= options.stickiness
			end
			table.insert(scored, { key = candidate.key, score = score })
		end
	end
	table.sort(scored, function(a, b)
		return a.score < b.score
	end)
	local keys = {}
	for _, entry in scored do
		table.insert(keys, entry.key)
	end
	return keys
end

--[=[ Best candidate, or nil. ]=]
function Targeting.Pick<K>(candidates: { Candidate<K> }, options: Options<K>): K?
	return Targeting.Rank(candidates, options)[1]
end

--[=[
	Next target in score order after `current` (ignoring stickiness). Past the last one it returns
	nil, so cycling also releases a lock.
]=]
function Targeting.Next<K>(candidates: { Candidate<K> }, options: Options<K>, current: K?): K?
	local ranked = Targeting.Rank(candidates, {
		eye = options.eye,
		forward = options.forward,
		from = options.from,
		range = options.range,
		coneDegrees = options.coneDegrees,
		angleWeight = options.angleWeight,
		stickiness = 0,
		current = nil,
	})
	if current == nil then
		return ranked[1]
	end
	local index = table.find(ranked, current)
	if index == nil then
		return ranked[1]
	end
	return ranked[index + 1]
end

--[=[ Angle in degrees between two directions projected on the ground plane. ]=]
function Targeting.FlatAngle(a: Vector3, b: Vector3): number
	local fa = Vector3.new(a.X, 0, a.Z)
	local fb = Vector3.new(b.X, 0, b.Z)
	if fa.Magnitude < 1e-3 or fb.Magnitude < 1e-3 then
		return 180
	end
	return math.deg(math.acos(math.clamp(fa.Unit:Dot(fb.Unit), -1, 1)))
end

return table.freeze(Targeting)
