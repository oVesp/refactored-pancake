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

local MAX_ID_LENGTH = 40
local MAX_COORDINATE = 1e5

local function isId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH and string.match(value, "^[%w_]+$") ~= nil
end

local function isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	for _, axis in { value.X, value.Y, value.Z } do
		if axis ~= axis or math.abs(axis) > MAX_COORDINATE then
			return false
		end
	end
	return true
end

local function isCount(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < 2 ^ 31 and value % 1 == 0
end

local function arity(n: number, ...: any): boolean
	return select("#", ...) == n
end

--[=[
	Every remote in the game, declared once (game-design.md 5.4). Names are `Verb` + `Noun`.
	The server creates them at startup; clients wait for them.
]=]
local Remotes: { [string]: RemoteSpec } = {
	RequestProfile = {
		direction = "ClientToServer",
		rateLimit = { capacity = 3, perSecond = 0.5 },
		validate = function(...)
			return arity(0, ...)
		end,
	},
	UseSkill = {
		direction = "ClientToServer",
		rateLimit = { capacity = 10, perSecond = 8 },
		validate = function(...)
			local skillId, aim, seq, target = ...
			local count = select("#", ...)
			local targetOk = target == nil or (typeof(target) == "Instance" and target:IsA("Model"))
			return (count == 3 or count == 4) and isId(skillId) and isFiniteVector(aim) and isCount(seq) and targetOk
		end,
	},
	SetGuard = {
		direction = "ClientToServer",
		rateLimit = { capacity = 6, perSecond = 4 },
		validate = function(...)
			return arity(1, ...) and type((...)) == "boolean"
		end,
	},
	Dodge = {
		direction = "ClientToServer",
		rateLimit = { capacity = 3, perSecond = 2 },
		validate = function(...)
			local direction, seq = ...
			return arity(2, ...) and isFiniteVector(direction) and isCount(seq)
		end,
	},
	ToggleDiscipline = {
		direction = "ClientToServer",
		rateLimit = { capacity = 6, perSecond = 3 },
		validate = function(...)
			return arity(1, ...) and isId((...))
		end,
	},
	LearnSpell = {
		direction = "ClientToServer",
		rateLimit = { capacity = 6, perSecond = 3 },
		validate = function(...)
			return arity(1, ...) and isId((...))
		end,
	},
	SetHotbarSlot = {
		direction = "ClientToServer",
		rateLimit = { capacity = 10, perSecond = 5 },
		validate = function(...)
			local index, kind, id = ...
			local indexOk = type(index) == "number" and index >= 1 and index <= 8 and index % 1 == 0
			local entryOk = (kind == "" and id == "") or ((kind == "Skill" or kind == "Discipline") and isId(id))
			return arity(3, ...) and indexOk and entryOk
		end,
	},
	EquipItem = {
		direction = "ClientToServer",
		rateLimit = { capacity = 6, perSecond = 3 },
		validate = function(...)
			return arity(1, ...) and isCount((...))
		end,
	},
	UnequipSlot = {
		direction = "ClientToServer",
		rateLimit = { capacity = 6, perSecond = 3 },
		validate = function(...)
			return arity(1, ...) and isId((...))
		end,
	},
	RequestTrain = {
		direction = "ClientToServer",
		rateLimit = { capacity = 3, perSecond = 1 },
		validate = function(...)
			return arity(1, ...) and typeof((...)) == "Instance"
		end,
	},
	UseItem = {
		direction = "ClientToServer",
		rateLimit = { capacity = 6, perSecond = 3 },
		validate = function(...)
			return arity(1, ...) and isCount((...))
		end,
	},
	--[=[ `(creation)`: a flat table of string fields; `Shared/Avatar.ValidateCreation` checks the content. ]=]
	CreateCharacter = {
		direction = "ClientToServer",
		rateLimit = { capacity = 2, perSecond = 0.5 },
		validate = function(...)
			local creation = ...
			if not arity(1, ...) or type(creation) ~= "table" then
				return false
			end
			local count = 0
			for key, value in creation do
				count += 1
				if type(key) ~= "string" or type(value) ~= "string" or #value > MAX_ID_LENGTH then
					return false
				end
			end
			return count <= 12
		end,
	},

	SendProfileSnapshot = { direction = "ServerToClient" },
	RejectSkill = { direction = "ServerToClient" },
	ShowCast = { direction = "ServerToClient" },
	ShowImpact = { direction = "ServerToClient" },
	ShowDamage = { direction = "ServerToClient" },
	--[=[ `(defender, attacker)`: a guard parried a hit (cosmetic; the stun is a status). ]=]
	ShowParry = { direction = "ServerToClient" },
	Notify = { direction = "ServerToClient" },
	SendDeathState = { direction = "ServerToClient" },
	SendDevLog = { direction = "ServerToClient" },
	OpenTrainer = { direction = "ServerToClient" },
	ShowGain = { direction = "ServerToClient" },
}

for name, spec in Remotes do
	if spec.direction == "ClientToServer" then
		assert(spec.rateLimit, `Remote {name} needs a rateLimit`)
		assert(spec.validate, `Remote {name} needs a validate function`)
	end
	table.freeze(spec)
end

return table.freeze(Remotes)
