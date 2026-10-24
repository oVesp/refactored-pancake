--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(script.Parent.Parent.Constants)
local Logger = require(script.Parent.Parent.Logger)
local RateLimiter = require(script.Parent.Parent.RateLimiter)
local Remotes = require(script.Parent)

local log = Logger.new("Net")

local events: { [string]: RemoteEvent } = {}
local limiters: { [string]: RateLimiter.RateLimiter<Player> } = {}
local rejections: { [string]: number } = {}

local NetServer = {}

local function getEvent(name: string): RemoteEvent
	local event = events[name]
	assert(event, `Unknown remote {name}; declare it in Shared/Net and call NetServer.Init first`)
	return event
end

local function reject(name: string, player: Player, reason: string)
	rejections[name] = (rejections[name] or 0) + 1
	log:Throttled(`{name}:{reason}`, 5, "debug", "Rejected %s from %d (%s)", name, player.UserId, reason)
end

--[=[
	Creates every declared remote under ReplicatedStorage. Call once from the server bootstrap
	before any service connects handlers.
]=]
function NetServer.Init()
	assert(not ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName), "NetServer.Init called twice")

	local folder = Instance.new("Folder")
	folder.Name = Constants.RemotesFolderName

	for name, spec in Remotes do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		events[name] = event

		if spec.direction == "ClientToServer" then
			local rate = spec.rateLimit :: Remotes.RateLimit
			limiters[name] = RateLimiter.new(rate.capacity, rate.perSecond)
		end
	end

	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:Forget(player)
		end
	end)
end

--[=[
	Connects a handler to a ClientToServer remote. The handler only runs after the per-player
	rate limit and the declared payload validation pass; rejected calls are dropped silently
	and counted.
]=]
function NetServer.Connect(name: string, handler: (player: Player, ...any) -> ()): RBXScriptConnection
	local spec = Remotes[name]
	assert(spec and spec.direction == "ClientToServer", `{name} is not a ClientToServer remote`)
	local validate = spec.validate :: (...any) -> boolean
	local limiter = limiters[name]

	return getEvent(name).OnServerEvent:Connect(function(player: Player, ...: any)
		if not limiter:Allow(player) then
			reject(name, player, "rate")
			return
		end
		if not validate(...) then
			reject(name, player, "payload")
			return
		end
		handler(player, ...)
	end)
end

--[=[ Sends a ServerToClient remote to one player. ]=]
function NetServer.Fire(name: string, player: Player, ...: any)
	assert(Remotes[name] and Remotes[name].direction == "ServerToClient", `{name} is not a ServerToClient remote`)
	getEvent(name):FireClient(player, ...)
end

--[=[ Sends a ServerToClient remote to every player. ]=]
function NetServer.FireAll(name: string, ...: any)
	assert(Remotes[name] and Remotes[name].direction == "ServerToClient", `{name} is not a ServerToClient remote`)
	getEvent(name):FireAllClients(...)
end

--[=[ Returns how many calls to a remote were rejected since startup (exploit signal). ]=]
function NetServer.GetRejectionCount(name: string): number
	return rejections[name] or 0
end

return NetServer
