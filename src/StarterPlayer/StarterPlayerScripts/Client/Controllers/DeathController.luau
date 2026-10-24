--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetClient = require(ReplicatedStorage.Shared.Net.Client)

--[=[ Death screen: respawn countdown and XP debt (game-design.md 3.9, Standard rules). ]=]
local DeathController = {}

local UIController: any

function DeathController.Init(deps: { [string]: any })
	UIController = deps.UIController
end

function DeathController.Start()
	local screen = UIController.GetScreen("DeathScreen")
	local text = UIController.Bind(screen, { "Bind_DeathText" }).Bind_DeathText :: TextLabel

	NetClient.Connect("SendDeathState", function(info: { respawnIn: number, debt: number })
		UIController.CloseTop()
		screen.Enabled = true
		local endsAt = os.clock() + info.respawnIn
		task.spawn(function()
			while screen.Enabled and os.clock() < endsAt do
				text.Text = string.format(
					"Respawning in the village in %d s · XP debt %d · Weakened for a while after respawn",
					math.ceil(endsAt - os.clock()),
					info.debt
				)
				task.wait(0.2)
			end
		end)
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		screen.Enabled = false
	end)
end

return DeathController
