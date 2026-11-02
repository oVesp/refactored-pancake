--!strict

--[=[
	UI palette (docs/art/ui-style.md). Screens and templates carry these colours in their
	`.model.json`; this table is only for the few tints a controller changes at runtime.
]=]
return table.freeze({
	Panel = Color3.fromHex("151922"),
	PanelRaised = Color3.fromHex("252D3A"),
	Gold = Color3.fromHex("D2B783"),
	GoldDim = Color3.fromHex("8C7853"),
	GoldBright = Color3.fromHex("F0DDB0"),
	Text = Color3.fromHex("E6DFCF"),
	Dim = Color3.fromHex("AEB4BF"),
	Ink = Color3.fromHex("1B1610"),
	Hp = Color3.fromHex("A94D56"),
	HpBright = Color3.fromHex("D2707A"),
	Mp = Color3.fromHex("4C91C6"),
	Green = Color3.fromHex("7EAF8A"),
	GreenDeep = Color3.fromHex("2F4A3A"),
	Xp = Color3.fromHex("5E9FD0"),
})
