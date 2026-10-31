--!strict

-- Prints the balance simulation (tests/Balance.luau): win rate per pack size and the largest pack
-- each persona survives. Run from the repo root: `lune run tools/sim/balance`.
local Balance = require("../../tests/Balance")

local SEEDS = 40
local MAX_COUNT = 12

for _, persona in Balance.Personas do
	local rates = {}
	for count = 1, MAX_COUNT do
		table.insert(
			rates,
			string.format("%d:%3d%%", count, math.floor(Balance.WinRate(persona, count, SEEDS) * 100 + 0.5))
		)
	end
	print(
		string.format(
			"%-30s capacity %2d | %s",
			persona.name,
			Balance.Capacity(persona, SEEDS, MAX_COUNT),
			table.concat(rates, " ")
		)
	)
end
