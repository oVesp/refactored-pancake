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
	`Assets.Animations` are `<AnimSet><Role>`; `content/animations/<set>.json` maps each role to a
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

return table.freeze({
	Enemy = table.freeze(Enemy),
})
