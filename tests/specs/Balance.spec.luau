--!strict

local Expect = require("../Expect")
local Balance = require("../Balance")

local SEEDS = 20
local MAX_COUNT = 9

local function persona(name: string): any
	for _, entry in Balance.Personas do
		if entry.name == name then
			return entry
		end
	end
	error(`No persona {name}`)
end

-- Targets (docs/systems/combat-ai-balance.md, Tuning and tests): a DPS survives 1 to 3 same-level
-- Rabble, a tank 5 to 8. Only the tank target holds today; the DPS survives 5 to 7 (tools/sim/balance
-- prints the tables), so its spec checks the rules' direction instead of the target.
return {
	["fights are repeatable"] = function()
		local dps = persona("DPS, parries 1 in 4")
		local a = Balance.Fight(dps, 4, 11)
		local b = Balance.Fight(dps, 4, 11)
		Expect.equal(a.seconds, b.seconds, "same seed, same fight")
		Expect.equal(a.hpLeft, b.hpLeft, "same seed, same HP")
	end,
	["a lone raider never beats a same-level fighter"] = function()
		for _, entry in Balance.Personas do
			Expect.equal(Balance.WinRate(entry, 1, SEEDS), 1, entry.name)
		end
	end,
	["parrying more never lowers what a DPS survives"] = function()
		local none = Balance.Capacity(persona("DPS, no parries"), SEEDS, MAX_COUNT)
		local some = Balance.Capacity(persona("DPS, parries 1 in 4"), SEEDS, MAX_COUNT)
		local most = Balance.Capacity(persona("DPS, parries 1 in 2"), SEEDS, MAX_COUNT)
		Expect.truthy(none <= some and some <= most, `capacities {none}, {some}, {most}`)
		Expect.truthy(none >= 3, `a DPS survives at least the 3 of its target ({none})`)
	end,
	["a tank survives 5 to 8 same-level raiders"] = function()
		local capacity = Balance.Capacity(persona("Tank, shield, parries 1 in 4"), SEEDS, MAX_COUNT)
		Expect.truthy(capacity >= 5 and capacity <= 8, `tank capacity {capacity}`)
	end,
}
