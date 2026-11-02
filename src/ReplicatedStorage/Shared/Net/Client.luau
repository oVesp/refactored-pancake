--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Parent.Constants)
local Remotes = require(script.Parent)

local events: { [string]: RemoteEvent } = {}

local NetClient = {}

local function getEvent(name: string): RemoteEvent
	local event = events[name]
	assert(event, `Unknown remote {name}; declare it in Shared/Net and call NetClient.Init first`)
	return event
end

--[=[
	Waits for the server-created remotes. Yields up to `Constants.ClientWaitTimeout` per
	instance and errors if one is missing, so a broken Net setup fails loudly at startup.
]=]
function NetClient.Init()
	local folder = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName, Constants.ClientWaitTimeout)
	assert(folder, "Remotes folder did not replicate")

	for name in Remotes do
		local event = folder:WaitForChild(name, Constants.ClientWaitTimeout)
		assert(event and event:IsA("RemoteEvent"), `Remote {name} did not replicate`)
		events[name] = event
	end
end

--[=[ Sends a ClientToServer remote. The server may drop it (rate limit or validation). ]=]
function NetClient.Fire(name: string, ...: any)
	assert(Remotes[name] and Remotes[name].direction == "ClientToServer", `{name} is not a ClientToServer remote`)
	getEvent(name):FireServer(...)
end

--[=[ Connects a handler to a ServerToClient remote. ]=]
function NetClient.Connect(name: string, handler: (...any) -> ()): RBXScriptConnection
	assert(Remotes[name] and Remotes[name].direction == "ServerToClient", `{name} is not a ServerToClient remote`)
	return getEvent(name).OnClientEvent:Connect(handler)
end

return NetClient
