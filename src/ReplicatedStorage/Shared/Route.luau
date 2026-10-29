--!strict

--[=[
	Progress along a polyline for patrols, caravans and roaming squads
	(docs/systems/open-world.md). Distances are measured on the ground plane; height is
	interpolated. Pure, so Lune tests cover it.
]=]
local Route = {}

export type Route = {
	points: { Vector3 },
	--[=[ Distance from the start to each point; a loop adds the closing leg. ]=]
	marks: { number },
	length: number,
	loop: boolean,
}

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
end

function Route.new(points: { Vector3 }, loop: boolean): Route
	assert(#points >= 1, "a route needs a point")
	local marks = { 0 }
	local total = 0
	for i = 2, #points do
		total += flatDistance(points[i - 1], points[i])
		table.insert(marks, total)
	end
	if loop and #points > 1 then
		total += flatDistance(points[#points], points[1])
	end
	return { points = points, marks = marks, length = total, loop = loop }
end

-- Point index after `i`, wrapping on loops.
local function nextIndex(route: Route, i: number): number?
	if i < #route.points then
		return i + 1
	end
	return if route.loop and #route.points > 1 then 1 else nil
end

--[=[
	Position and flat heading `distance` along the route. Loops wrap; open routes clamp at the end
	and report `finished`.
]=]
function Route.At(route: Route, distance: number): (Vector3, Vector3, boolean)
	local points = route.points
	if #points == 1 or route.length <= 0 then
		return points[1], Vector3.new(0, 0, -1), true
	end
	local finished = false
	if route.loop then
		distance %= route.length
	elseif distance >= route.length then
		distance = route.length
		finished = true
	end
	distance = math.max(distance, 0)
	for i = 1, #points do
		local j = nextIndex(route, i)
		if not j then
			break
		end
		local from = route.marks[i]
		local to = if j == 1 then route.length else route.marks[j]
		if distance <= to then
			local a, b = points[i], points[j]
			local t = if to > from then (distance - from) / (to - from) else 0
			local heading = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			return a:Lerp(b, t), if heading.Magnitude > 1e-3 then heading.Unit else Vector3.new(0, 0, -1), finished
		end
	end
	local last, before = points[#points], points[#points - 1]
	local heading = Vector3.new(last.X - before.X, 0, last.Z - before.Z)
	return last, if heading.Magnitude > 1e-3 then heading.Unit else Vector3.new(0, 0, -1), finished
end

--[=[ Distance along the route of the closest point to `position` (resumes after a fight). ]=]
function Route.Nearest(route: Route, position: Vector3): number
	local points = route.points
	if #points == 1 then
		return 0
	end
	local best, bestDistance = 0, math.huge
	local p = Vector3.new(position.X, 0, position.Z)
	for i = 1, #points do
		local j = nextIndex(route, i)
		if not j then
			break
		end
		local a = Vector3.new(points[i].X, 0, points[i].Z)
		local b = Vector3.new(points[j].X, 0, points[j].Z)
		local ab = b - a
		local lengthSq = ab:Dot(ab)
		local t = if lengthSq > 0 then math.clamp((p - a):Dot(ab) / lengthSq, 0, 1) else 0
		local gap = (a + ab * t - p).Magnitude
		if gap < bestDistance then
			bestDistance = gap
			best = route.marks[i] + math.sqrt(lengthSq) * t
		end
	end
	return best
end

return Route
