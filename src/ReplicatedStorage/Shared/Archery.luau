--!strict

--[=[
	Bow rules (docs/systems/weapons.md, Bow): pure maths shared by SkillService and the client's
	draw feedback.
]=]
local Archery = {}

export type BowTuning = {
	MinDraw: number,
	FullDraw: number,
	PerfectWindow: number,
	MinScale: number,
	PerfectBonus: number,
}

--[=[
	Damage scale for an arrow released after `held` seconds of drawing, and whether the release
	was perfect. Below `MinDraw` nothing is shot (scale 0). The scale grows from `MinScale` to 1 at
	`FullDraw`; releasing within `PerfectWindow` after full draw adds `PerfectBonus`.
]=]
function Archery.DrawScale(held: number, tuning: BowTuning): (number, boolean)
	if held < tuning.MinDraw then
		return 0, false
	end
	if held < tuning.FullDraw then
		local t = (held - tuning.MinDraw) / (tuning.FullDraw - tuning.MinDraw)
		return tuning.MinScale + (1 - tuning.MinScale) * t, false
	end
	if held <= tuning.FullDraw + tuning.PerfectWindow then
		return 1 + tuning.PerfectBonus, true
	end
	return 1, false
end

--[=[
	True when `from` is behind a target at `position` facing `look`: within `arc` degrees (full
	width) of the target's back, measured flat.
]=]
function Archery.FromBehind(position: Vector3, look: Vector3, from: Vector3, arc: number): boolean
	local back = Vector3.new(-look.X, 0, -look.Z)
	local toward = Vector3.new(from.X - position.X, 0, from.Z - position.Z)
	if back.Magnitude < 1e-3 or toward.Magnitude < 1e-3 then
		return false
	end
	return back.Unit:Dot(toward.Unit) >= math.cos(math.rad(arc / 2))
end

return table.freeze(Archery)
