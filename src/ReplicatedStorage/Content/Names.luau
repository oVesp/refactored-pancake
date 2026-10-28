--!strict

--[=[
	Placeholder character names per gender until the name library exists. Original Norse-style
	given names only: never a name or reference from the source series (game-design.md 2).
	The server accepts only names from this table.
]=]
return table.freeze({
	male = table.freeze({
		"Arne",
		"Bjorn",
		"Eirik",
		"Gunnar",
		"Halvard",
		"Leif",
		"Orm",
		"Ragnvald",
		"Sten",
		"Torvald",
		"Ulf",
		"Vidar",
	}),
	female = table.freeze({
		"Astrid",
		"Dagny",
		"Freydis",
		"Gudrun",
		"Hilde",
		"Ingrid",
		"Liv",
		"Ragna",
		"Sigrid",
		"Solveig",
		"Thyra",
		"Yrsa",
	}),
})
