--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local EngineFixes = require(script.Parent.EngineFixes)

local Services = script.Parent.Services

type Service = {
	Init: (deps: { [string]: any }) -> (),
	Start: () -> (),
}

-- Order matters: each service receives the services listed before it as `deps` in Init.
local SERVICE_ORDER = {
	"DataService",
	"ZoneService",
	"EntityService",
	"StatService",
	"NeedsService",
	"StatusService",
	"CombatService",
	"SkillService",
	"DisciplineService",
	"InventoryService",
	"LoadoutService",
	"ProgressionService",
	"AvatarService",
	"SquadService",
	"AIService",
	"SpawnService",
	"SummonService",
	"GroupService",
	"PopulationService",
	"ShopService",
	"QuestService",
	"DevService",
	"ChatCastService",
}

local log = Logger.new("Bootstrap")

EngineFixes.Apply()
NetServer.Init()

local deps: { [string]: any } = {}
local services: { Service } = {}
for _, name in SERVICE_ORDER do
	local service = require(Services:FindFirstChild(name) :: ModuleScript) :: Service
	service.Init(table.clone(deps))
	deps[name] = service
	table.insert(services, service)
end

for _, service in services do
	service.Start()
end

log:Info("Server started with %d services", #services)
