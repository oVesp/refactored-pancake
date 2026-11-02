--!strict

local Types = require(script.Parent.Types)

--[=[
	Summon families (docs/systems/ai-and-spawning.md, Summons). A summon skill names a family: the
	caster may always raise `base`, and any `pool` entry the player has discovered by killing one.
	Ids are `Content/Enemies` ids.
]=]
local list: { Types.SummonFamily } = {
	{
		id = "undead",
		base = { "zombie" },
		pool = { "zombie", "skeleton" },
		cap = 2,
		duration = 60,
		levelOffset = -1,
	},
}

local byId: { [string]: Types.SummonFamily } = {}
for _, family in list do
	byId[family.id] = table.freeze(family)
end

return table.freeze({
	ById = table.freeze(byId),
})
