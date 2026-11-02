--!strict

--[=[
	Pure spell cast rules (docs/systems/combat.md, Cast): hold to charge, release once full to fire.
	No requires and no Roblox services: callers pass clocks, positions and Tuning.Combat.Cast in.
	SkillService decides with them; CombatController predicts with the same rules.
]=]
local Casting = {}

export type Release = "Fire" | "Buffer" | "Fizzle"

export type MoveSettings = {
	MoveGrace: number,
	MoveTolerance: number,
}

export type Anchor = { x: number, z: number }

--[=[
	What letting go at `now` does to a charge full at `fullAt`: `Fire` at once when full, `Buffer`
	(fire when it fills) within `grace` seconds of full, which absorbs network jitter, else `Fizzle`:
	the cast is cancelled and refunded.
]=]
function Casting.Release(now: number, fullAt: number, grace: number): Release
	if now >= fullAt then
		return "Fire"
	end
	return if now >= fullAt - grace then "Buffer" else "Fizzle"
end

--[=[
	One movement check of a cast `elapsed` seconds in, at flat position (`x`, `z`). The first
	`MoveGrace` seconds do not count, since the caster is still slowing down from before the press.
	After that the caster is anchored where it stands and cancels past `MoveTolerance` studs from
	there. Returns the anchor to pass next time and whether the cast is cancelled.
]=]
function Casting.Step(
	anchor: Anchor?,
	elapsed: number,
	x: number,
	z: number,
	settings: MoveSettings
): (Anchor?, boolean)
	if elapsed < settings.MoveGrace then
		return nil, false
	end
	if not anchor then
		return { x = x, z = z }, false
	end
	local dx, dz = x - anchor.x, z - anchor.z
	return anchor, dx * dx + dz * dz > settings.MoveTolerance * settings.MoveTolerance
end

--[=[
	Seconds a disruptor can count on the cast lasting: until full, then, for a charge being held, until
	its `holdUntil`.
]=]
function Casting.Remaining(now: number, fullAt: number, holdUntil: number?): number
	if now < fullAt or not holdUntil then
		return fullAt - now
	end
	return holdUntil - now
end

return table.freeze(Casting)
