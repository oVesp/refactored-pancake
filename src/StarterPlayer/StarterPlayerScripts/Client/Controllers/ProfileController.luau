--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Signal = require(ReplicatedStorage.Shared.Signal)

--[=[
	Holds the latest profile snapshot pushed by the server. Read-only view model; nothing here
	changes authoritative state.
]=]
local ProfileController = {}

--[=[ Fires with the new snapshot whenever the server pushes one. ]=]
ProfileController.Changed = Signal.new() :: Signal.Signal<{ [string]: any }>

local snapshot: { [string]: any }? = nil

--[=[ The latest snapshot, or nil before the first push. ]=]
function ProfileController.Get(): { [string]: any }?
	return snapshot
end

function ProfileController.Init(_deps: { [string]: any }) end

function ProfileController.Start()
	NetClient.Connect("SendProfileSnapshot", function(data: { [string]: any })
		snapshot = data
		ProfileController.Changed:Fire(data)
	end)
	NetClient.Fire("RequestProfile")
end

return ProfileController
