--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Items = require(ReplicatedStorage.Content.Items)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Profile = require(script.Parent.Parent.Data.Profile)
local Signal = require(ReplicatedStorage.Shared.Signal)

local log = Logger.new("DataService")

local profiles: { [Player]: Profile.Profile } = {}
local waiting: { [Player]: { thread } } = {}

--[=[
	In-memory profile store (game-design.md 5.8). The contract below stays fixed when the
	persistent Data module replaces this stub; systems never touch DataStores directly.
]=]
local DataService = {}

--[=[ Fires `(player, path)` after every `Update`. `path` names the changed field or `"*"`. ]=]
DataService.Changed = Signal.new() :: Signal.Signal<Player, string>

local function resumeWaiting(player: Player)
	local threads = waiting[player]
	waiting[player] = nil
	if threads then
		for _, thread in threads do
			task.spawn(thread, profiles[player])
		end
	end
end

local function load(player: Player)
	profiles[player] = Profile.Migrate(Profile.new(Items.Starter))
	log:Debug("Loaded profile for %d", player.UserId)
	resumeWaiting(player)
end

--[=[ Returns the live profile, or nil if it is not loaded. Callers must not keep references across yields. ]=]
function DataService.Get(player: Player): Profile.Profile?
	return profiles[player]
end

--[=[
	Mutates a loaded profile through `fn`, then fires `Changed`. Does nothing if the profile is
	not loaded. In Studio, errors if the result is not serializable.
]=]
function DataService.Update(player: Player, fn: (Profile.Profile) -> (), path: string?)
	local profile = profiles[player]
	if not profile then
		log:Warn("Update for %d without a loaded profile", player.UserId)
		return
	end

	fn(profile)

	if RunService:IsStudio() then
		local ok, reason = Profile.IsSerializable(profile)
		assert(ok, reason)
	end

	DataService.Changed:Fire(player, path or "*")
end

--[=[ Yields until the profile is loaded. Returns nil if the player leaves first. ]=]
function DataService.WaitForProfile(player: Player): Profile.Profile?
	local profile = profiles[player]
	if profile or player.Parent == nil then
		return profile
	end

	local threads = waiting[player]
	if not threads then
		threads = {}
		waiting[player] = threads
	end
	table.insert(threads, coroutine.running())
	return coroutine.yield()
end

--[=[ Single leave path. The persistent module will save here before dropping the profile. ]=]
function DataService.Release(player: Player)
	profiles[player] = nil
	resumeWaiting(player)
end

function DataService.Init(_deps: { [string]: any }) end

function DataService.Start()
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(DataService.Release)
	for _, player in Players:GetPlayers() do
		if not profiles[player] then
			load(player)
		end
	end
end

return DataService
