--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atmosphere = require(ReplicatedStorage.Content.Atmosphere)
local ChatCast = require(ReplicatedStorage.Shared.ChatCast)
local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local DevService = require(script.Parent.Services.DevService)
local Logger = require(ReplicatedStorage.Shared.Logger)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Types = require(script.Parent.Types)
local Zones = require(ReplicatedStorage.Content.Zones)

type Entity = Types.Entity

local DETECT_RADIUS = 150
local DETECT_SECONDS = 10
-- The engine draws at most 31 Highlights at once.
local MAX_DETECTED = 30
local GATE_DROP = 600
local GATE_CLEARANCE = 4

local log = Logger.new("DevSkillEffects")

local EntityService: any
local ZoneService: any

local DAY_HOUR = 12
local NIGHT_HOUR = 0

--[=[
	Server-side effects of dev skills (delivery `Dev`, docs/systems/dev-tools.md). SkillService
	runs them once the cast has passed its checks; each re-checks that the caster is a developer.
]=]
local DevSkillEffects = {}

local function notify(caster: Entity, key: string, ...: any)
	if caster.player then
		NetServer.Fire("Notify", caster.player, key, { ... })
	end
end

local function whole(value: number?): number
	return math.floor((value or 0) + 0.5)
end

local function fly(caster: Entity)
	local flying = not caster.model:GetAttribute("Flying")
	caster.model:SetAttribute("Flying", if flying then true else nil)
	notify(caster, if flying then "FlyOn" else "FlyOff")
end

local function lifeEssence(caster: Entity, target: Entity)
	notify(caster, "LifeEssence", target.name, whole(target.hp), whole(target.stats.MaxHp))
end

local function manaEssence(caster: Entity, target: Entity)
	notify(caster, "ManaEssence", target.name, whole(target.mp), whole(target.stats.MaxMp))
end

local function discernEnemy(caster: Entity, target: Entity?)
	if not target or target == caster then
		notify(caster, "DiscernNoTarget")
		return
	end
	local stats = target.stats
	notify(
		caster,
		"DiscernEnemy",
		target.name,
		target.level,
		target.defId,
		target.team,
		whole(target.hp),
		whole(stats.MaxHp),
		whole(stats.PhysAtk),
		whole(stats.MagAtk),
		whole(stats.PhysDef),
		whole(stats.MagDef)
	)
end

local function detectLife(caster: Entity)
	local found = {}
	for _, other in EntityService.All() do
		if other ~= caster and other.alive then
			local distance = (other.root.Position - caster.root.Position).Magnitude
			if distance <= DETECT_RADIUS then
				table.insert(found, { model = other.model, distance = distance })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local models = {}
	for i = 1, math.min(#found, MAX_DETECTED) do
		models[i] = found[i].model
	end
	if caster.player then
		NetServer.Fire("ShowDetectedLife", caster.player, models, DETECT_SECONDS)
	end
	notify(caster, "DetectLife", #found)
end

-- Zone id named by a Gate argument: its id or display name, normalized like chat casting.
local function zoneNamed(arg: string): string?
	for id, zone in Zones.ById do
		if ChatCast.Normalize(id) == arg or ChatCast.Normalize(zone.name) == arg then
			return id
		end
	end
	return nil
end

local PYLON = "pylon"

local function zoneList(): string
	local names = { "Pylon" }
	for _, zone in Zones.ById do
		table.insert(names, zone.name)
	end
	table.sort(names)
	return table.concat(names, ", ")
end

local function gate(caster: Entity, arg: string?)
	local toPylon = arg == PYLON
	local zoneId = if toPylon then PYLON elseif arg and arg ~= "" then zoneNamed(arg) else Zones.RespawnZone
	local anchor: Vector3? = nil
	if toPylon then
		anchor = ZoneService.PylonPoint()
	elseif zoneId == Zones.RespawnZone then
		local spawn = ZoneService.RespawnPoint()
		anchor = if spawn then spawn.Position else nil
	end
	if zoneId and not anchor then
		anchor = ZoneService.Anchor(zoneId)
	end
	if not zoneId or not anchor then
		notify(caster, "GateUnknown", zoneList())
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { caster.model }
	local top = anchor + Vector3.new(0, GATE_DROP / 2, 0)
	local ground = workspace:Raycast(top, Vector3.new(0, -GATE_DROP, 0), params)
	local destination = (if ground then ground.Position else anchor) + Vector3.new(0, GATE_CLEARANCE, 0)
	if caster.player then
		EntityService.NoteTeleport(caster.player)
	end
	caster.model:PivotTo(CFrame.new(destination) * caster.root.CFrame.Rotation)
	notify(caster, "Gated", if toPylon then "the Pylon" else Zones.ById[zoneId].name)
end

-- Moves the shared world clock to `hour` (or back to the natural cycle with nil) through the
-- workspace `ClockShift` attribute that DayCycle.Now reads.
local function setClock(hour: number?)
	if not hour then
		workspace:SetAttribute("ClockShift", nil)
		return
	end
	local cycle = Atmosphere.DayLength
	local shift = DayCycle.SecondsAt(hour) - (workspace:GetServerTimeNow() % cycle)
	workspace:SetAttribute("ClockShift", shift)
end

local function controlWeather(caster: Entity, arg: string?)
	local request = if arg and arg ~= "" then arg else if DayCycle.IsNight(DayCycle.Now()) then "day" else "night"
	if request == "day" then
		setClock(DAY_HOUR)
	elseif request == "night" then
		setClock(NIGHT_HOUR)
	elseif request == "reset" then
		setClock(nil)
	else
		notify(caster, "WeatherUnknown")
		return
	end
	notify(caster, "WeatherSet", if request == "reset" then "its natural course" else request)
end

local function nightVision(caster: Entity)
	local on = not caster.model:GetAttribute("NightVision")
	caster.model:SetAttribute("NightVision", if on then true else nil)
	notify(caster, if on then "NightVisionOn" else "NightVisionOff")
end

--[=[
	Runs a dev skill's effect. `target` is the caster's chosen target (any living entity) or nil;
	`arg` is the normalized chat argument (Gate's destination).
]=]
function DevSkillEffects.Resolve(caster: Entity, skill: any, target: Entity?, arg: string?)
	local player = caster.player
	if not player or not DevService.IsDev(player) then
		log:Warn("Dev skill %s refused for %s", skill.id, caster.name)
		return
	end
	local effect = skill.devEffect
	if effect == "Fly" then
		fly(caster)
	elseif effect == "LifeEssence" then
		lifeEssence(caster, target or caster)
	elseif effect == "ManaEssence" then
		manaEssence(caster, target or caster)
	elseif effect == "DiscernEnemy" then
		discernEnemy(caster, target)
	elseif effect == "DetectLife" then
		detectLife(caster)
	elseif effect == "Gate" then
		gate(caster, arg)
	elseif effect == "ControlWeather" then
		controlWeather(caster, arg)
	elseif effect == "NightVision" then
		nightVision(caster)
	end
end

function DevSkillEffects.Init(deps: { [string]: any })
	EntityService = deps.EntityService
	ZoneService = deps.ZoneService
end

return DevSkillEffects
