--!strict

export type Priority = "Core" | "Idle" | "Movement" | "Action" | "Action2" | "Action3" | "Action4"

export type Role = {
	-- Enum.AnimationPriority item name.
	priority: Priority,
	looped: boolean,
	-- A set without this role fails the animation spec; optional roles are skipped at runtime.
	required: boolean,
}

--[=[
	Clip roles an enemy `AnimSet` can fill (docs/art/animation-pipeline.md). Clip keys in
	animations under ReplicatedStorage.Animations are `<AnimSet><Role>`; `content/animations/<set>.json` maps each role to a
	source clip. Adding a role here makes `EnemyAnimationController` load it for every set that has it.
]=]
local Enemy: { [string]: Role } = {
	Idle = { priority = "Core", looped = true, required = true },
	Walk = { priority = "Core", looped = true, required = true },
	Run = { priority = "Core", looped = true, required = false },
	Attack = { priority = "Action", looped = false, required = true },
	Throw = { priority = "Action", looped = false, required = false },
	Hit = { priority = "Action", looped = false, required = false },
	Death = { priority = "Action4", looped = false, required = true },
}

--[=[
	Marker names every animation uses (docs/art/animation-pipeline.md, Markers): `Hit` is the frame a
	melee swing, throw or deflection takes effect, `Release` the frame a projectile leaves the hand or
	bow, `Step` a footfall.
]=]
local Markers = table.freeze({ Hit = "Hit", Release = "Release", Step = "Step" })

return table.freeze({
	Enemy = table.freeze(Enemy),
	Markers = Markers,
})
