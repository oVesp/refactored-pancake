--!strict

export type DisciplineDef = {
	id: string,
	name: string,
	cost: number,
	mode: "Burst" | "Toggle",
	duration: number,
	cooldown: number,
	status: string,
	description: string,
}

--[=[
	Disciplines in M0.5 (scope 01, D3). Each occupies `cost` Focus capacity while active.
	Burst runs for `duration`; Toggle runs until switched off or `duration` runs out.
]=]
local byId: { [string]: DisciplineDef } = {
	dash_step = {
		id = "dash_step",
		name = "Dash Step",
		cost = 1,
		mode = "Burst",
		duration = 3,
		cooldown = 8,
		status = "dash_step",
		description = "+40% move speed for 3 seconds.",
	},
	body_hardening = {
		id = "body_hardening",
		name = "Body Hardening",
		cost = 1,
		mode = "Toggle",
		duration = 20,
		cooldown = 10,
		status = "body_hardening",
		description = "+15 physical and +5 magic defense while active (up to 20 seconds).",
	},
}

return table.freeze({
	ById = table.freeze(byId),
	Order = table.freeze({ "dash_step", "body_hardening" }),
})
