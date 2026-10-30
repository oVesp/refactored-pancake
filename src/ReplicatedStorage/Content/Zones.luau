--!strict

export type ZoneDef = {
	id: string,
	name: string,
	band: string,
	safe: boolean,
}

--[=[
	Zones of the Midgard testing grounds (scope 01, section 2). Volumes are parts tagged `Zone`
	with a `ZoneId` attribute. In safe zones players take no damage and enemies do not enter.
]=]
local byId: { [string]: ZoneDef } = {
	village_core = { id = "village_core", name = "Village Core", band = "Safe", safe = true },
	dev_yard = { id = "dev_yard", name = "Dev Yard", band = "Safe", safe = true },
	harbor_dock = { id = "harbor_dock", name = "Harbor Dock", band = "Safe", safe = true },
	wheat_fields = { id = "wheat_fields", name = "Wheat Fields", band = "Lv 1-3", safe = false },
	orchard_edge = { id = "orchard_edge", name = "Orchard Edge", band = "Lv 3-4", safe = false },
	goblin_camp = { id = "goblin_camp", name = "Goblin Camp", band = "Lv 4-6", safe = false },
}

return table.freeze({
	ById = table.freeze(byId),
	Realm = "Midgard",
	--[=[ Where players spawn and respawn. ]=]
	RespawnZone = "village_core",
})
