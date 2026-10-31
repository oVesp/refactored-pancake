--!strict

-- Prints the balance simulation (tests/Balance.luau): win rate per pack size, the largest pack
-- each persona survives, and how many parries broke a raider in a 5-raider fight. Run from the
-- repo root: `lune run tools/sim/balance`.
local Balance = require("../../tests/Balance")

local SEEDS = 40
local MAX_COUNT = 12
local SAMPLE = 5

for _, persona in Balance.Personas do
	local rates = {}
	for count = 1, MAX_COUNT do
		local rate = math.floor(Balance.WinRate(persona, count, SEEDS) * 100 + 0.5)
		table.insert(rates, string.format("%d:%3d%%", count, rate))
	end
	local parries, parryBreaks, hitBreaks = 0, 0, 0
	for seed = 1, SEEDS do
		local fight = Balance.Fight(persona, SAMPLE, seed * 7919)
		parries += fight.parries
		parryBreaks += fight.parryBreaks
		hitBreaks += fight.hitBreaks
	end
	print(
		string.format(
			"%-30s capacity %2d | %s | vs %d: %d parries, %d broke, %d hit breaks",
			persona.name,
			Balance.Capacity(persona, SEEDS, MAX_COUNT),
			table.concat(rates, " "),
			SAMPLE,
			parries,
			parryBreaks,
			hitBreaks
		)
	)
end
