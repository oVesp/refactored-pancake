--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)

local Controllers = script.Parent.Controllers

type Controller = {
	Init: (deps: { [string]: any }) -> (),
	Start: () -> (),
}

-- Order matters: each controller receives the controllers listed before it as `deps` in Init.
local CONTROLLER_ORDER = {
	"UIController",
	"ProfileController",
	"TargetController",
	"CombatController",
	"AudioController",
	"VfxController",
	"InputController",
	"HudController",
	"SpellbookController",
	"InventoryController",
	"CharacterController",
	"DeathController",
	"NameplateController",
	"DebugController",
}

local log = Logger.new("Bootstrap")

NetClient.Init()

local deps: { [string]: any } = {}
local controllers: { Controller } = {}
for _, name in CONTROLLER_ORDER do
	local controller = require(Controllers:FindFirstChild(name) :: ModuleScript) :: Controller
	controller.Init(table.clone(deps))
	deps[name] = controller
	table.insert(controllers, controller)
end

for _, controller in controllers do
	controller.Start()
end

log:Info("Client started with %d controllers", #controllers)
