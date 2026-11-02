--!strict

local Enemies = require(script.Parent.Parent.Content.Enemies)
local Npcs = require(script.Parent.Parent.Content.Npcs)
local Types = require(script.Parent.Parent.Content.Types)

--[=[ One lookup over every NPC definition: monsters (`Content/Enemies`) and people (`Content/Npcs`). ]=]
local NpcDefs = {}

function NpcDefs.Get(id: string): Types.EnemyDef?
	return Enemies.ById[id] or Npcs.ById[id]
end

return NpcDefs
