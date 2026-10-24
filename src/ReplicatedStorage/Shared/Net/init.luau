--!strict

export type Direction = "ClientToServer" | "ServerToClient"

export type RateLimit = {
	capacity: number,
	perSecond: number,
}

export type RemoteSpec = {
	direction: Direction,
	--[=[ Required for ClientToServer remotes: per-player token bucket. ]=]
	rateLimit: RateLimit?,
	--[=[ Required for ClientToServer remotes: returns true when the arguments match the payload schema. ]=]
	validate: ((...any) -> boolean)?,
}

local function noArguments(...: any): boolean
	return select("#", ...) == 0
end

--[=[
	Every remote in the game, declared once (game-design.md 5.4). Names are `Verb` + `Noun`.
	The server creates them at startup; clients wait for them.
]=]
local Remotes: { [string]: RemoteSpec } = {
	RequestProfile = {
		direction = "ClientToServer",
		rateLimit = { capacity = 3, perSecond = 0.5 },
		validate = noArguments,
	},
	SendProfileSnapshot = {
		direction = "ServerToClient",
	},
}

for name, spec in Remotes do
	if spec.direction == "ClientToServer" then
		assert(spec.rateLimit, `Remote {name} needs a rateLimit`)
		assert(spec.validate, `Remote {name} needs a validate function`)
	end
	table.freeze(spec)
end

return table.freeze(Remotes)
