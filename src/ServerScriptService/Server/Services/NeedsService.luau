--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Needs = require(ReplicatedStorage.Shared.Needs)
local Tuning = require(ReplicatedStorage.Content.Tuning)

type Kind = Needs.Kind

local Config = Tuning.Needs :: Needs.Config

local DataService: any
local EntityService: any
local StatService: any

type State = {
	values: { [string]: number },
	--[=[ Starvation HP owed but not yet applied; SetHp works in whole HP. ]=]
	owed: number,
}

local states: { [Player]: State } = {}

--[=[
	Hunger and thirst (docs/systems/stats-and-hud.md, Hunger and thirst). Session state per
	player that survives respawn; replicated as `Hunger` and `Thirst` attributes on the Player.
	Low needs scale the entity's HP and MP regen; empty needs drain HP down to `FloorHp`.
]=]
local NeedsService = {}

local function publish(player: Player, state: State)
	for _, kind in Needs.Kinds do
		local shown = math.ceil(state.values[kind])
		if player:GetAttribute(Constants.Attributes[kind]) ~= shown then
			player:SetAttribute(Constants.Attributes[kind], shown)
		end
	end
end

--[=[ Current value of a need (0 to `Tuning.Needs.Max`), or nil if the player has no state. ]=]
function NeedsService.Get(player: Player, kind: Kind): number?
	local state = states[player]
	return if state then state.values[kind] else nil
end

--[=[
	Restores `amount` of a need (items, spells such as Create Water). Clamped to the max;
	a negative amount lowers it. Does nothing for a player without state.
]=]
function NeedsService.Restore(player: Player, kind: Kind, amount: number)
	local state = states[player]
	if not state or amount ~= amount then
		return
	end
	state.values[kind] = Needs.Restore(state.values[kind], amount, Config)
	publish(player, state)
end

--[=[ Sets a need to `value`, clamped to [0, Max] (dev tools). ]=]
function NeedsService.Set(player: Player, kind: Kind, value: number)
	local current = NeedsService.Get(player, kind)
	if current then
		NeedsService.Restore(player, kind, value - current)
	end
end

local function tick(dt: number)
	for player, state in states do
		local entity = EntityService.ForPlayer(player)
		local profile = DataService.Get(player)
		if not entity or not entity.alive or not profile or not profile.created then
			continue
		end
		for _, kind: Needs.Kind in Needs.Kinds do
			state.values[kind] = Needs.Decay(state.values[kind], kind, dt, Config)
		end
		publish(player, state)
		entity.regenScale = Needs.CombinedRegenScale(state.values, Config)

		local rate = Needs.DrainRate(state.values, Config)
		local owed, hp = Needs.Starve(state.owed, entity.hp, rate, dt, entity.god, Config)
		state.owed = owed
		if hp then
			StatService.SetHp(entity, hp)
		end
	end
end

function NeedsService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EntityService = deps.EntityService
	StatService = deps.StatService
end

function NeedsService.Start()
	local function onPlayerAdded(player: Player)
		local state: State = { values = {}, owed = 0 }
		for _, kind in Needs.Kinds do
			state.values[kind] = Config.Max
		end
		states[player] = state
		publish(player, state)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	task.spawn(function()
		while true do
			tick(task.wait(Tuning.Needs.TickInterval))
		end
	end)
end

return NeedsService
