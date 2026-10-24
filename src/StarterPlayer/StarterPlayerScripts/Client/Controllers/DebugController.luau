--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetClient = require(ReplicatedStorage.Shared.Net.Client)

local MAX_LINES = 60

--[=[
	Dev debug overlay (scope 01, section 7): damage log lines streamed by the server to dev
	players, and AI state on nameplates while the overlay is open. Toggle with F2.
]=]
local DebugController = {}

local UIController: any
local NameplateController: any

function DebugController.Init(deps: { [string]: any })
	UIController = deps.UIController
	NameplateController = deps.NameplateController
end

function DebugController.Start()
	local screen = UIController.GetScreen("DebugOverlay")
	local list = UIController.Bind(screen, { "Bind_LogList" }).Bind_LogList :: ScrollingFrame
	local order = 0

	NetClient.Connect("SendDevLog", function(line: string)
		order += 1
		local row = UIController.Clone("LogLine") :: TextLabel
		row.Text = line
		row.LayoutOrder = order
		row.Parent = list
		local rows = {}
		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(rows, child)
			end
		end
		if #rows > MAX_LINES then
			table.sort(rows, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			rows[1]:Destroy()
		end
		list.CanvasPosition = Vector2.new(0, math.huge)
	end)

	screen:GetPropertyChangedSignal("Enabled"):Connect(function()
		NameplateController.SetDebug(screen.Enabled)
	end)
end

return DebugController
