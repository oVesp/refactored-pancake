--!strict
-- Workarounds for bugs in Roblox-shipped scripts. Each fix names the engine version it targets;
-- delete the fix and its vendored file once Roblox ships the correction.

local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local log = Logger.new("EngineFixes")

local EngineFixes = {}

-- Studio 0.744 ships StarterPlayer.PlayerModule with `function VRbaseCamera:UpdateFadeFromBlack`,
-- which errors on load and stops PlayerScriptsLoader for every client. Swap in the corrected copy
-- from vendor/PlayerModulePatch before any client requires it.
local function patchVRBaseCamera(playerModule: Instance)
	local cameraModule = playerModule:FindFirstChild("CameraModule")
	local original = cameraModule and cameraModule:FindFirstChild("VRBaseCamera")
	local patch = ServerStorage.EngineFixes:FindFirstChild("VRBaseCamera")
	if not (cameraModule and original and patch) then
		log:Warn("VRBaseCamera patch skipped: PlayerModule layout changed")
		return
	end
	original:Destroy()
	patch:Clone().Parent = cameraModule
	log:Info("Patched PlayerModule.CameraModule.VRBaseCamera")
end

function EngineFixes.Apply()
	local playerModule = StarterPlayer:FindFirstChild("PlayerModule")
	if playerModule then
		patchVRBaseCamera(playerModule)
		return
	end
	local connection: RBXScriptConnection
	connection = StarterPlayer.ChildAdded:Connect(function(child)
		if child.Name == "PlayerModule" then
			connection:Disconnect()
			patchVRBaseCamera(child)
		end
	end)
end

return EngineFixes
