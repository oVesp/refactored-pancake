--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Shared.Logger)
local PropCulling = require(ReplicatedStorage.Shared.PropCulling)
local PropDetail = require(ReplicatedStorage.Content.PropDetail)

--[=[
	Client distance culling for the generated props (docs/systems/atmosphere.md, Performance).
	Small layers drop whole chunks past their distance and far trees thin to a share, under the
	haze. Hidden instances are parented to a holder outside the DataModel, so they cost no
	rendering; streaming still adds and removes them by identity. Cosmetic only.
]=]
local PropDetailController = {}

local log = Logger.new("PropDetail")

-- Never parented: anything inside renders nowhere.
local holder = Instance.new("Folder")
holder.Name = "HiddenProps"

type Thinned = { hidden: { Instance }, added: RBXScriptConnection }

local hiddenChunks: { [Instance]: Instance } = {} -- chunk -> its layer folder
local thinnedChunks: { [Instance]: Thinned } = {}

local function propPosition(prop: Instance): Vector3?
	if prop:IsA("Model") then
		return prop:GetPivot().Position
	elseif prop:IsA("BasePart") then
		return prop.Position
	end
	return nil
end

local function thinOne(prop: Instance, keep: number, state: Thinned)
	local position = propPosition(prop)
	if position and not PropCulling.Keeps(position.X, position.Z, keep) then
		prop.Parent = holder
		table.insert(state.hidden, prop)
	end
end

local function thin(chunk: Instance, keep: number)
	local state: Thinned = { hidden = {}, added = nil :: any }
	for _, prop in chunk:GetChildren() do
		thinOne(prop, keep, state)
	end
	-- Props streamed in while the chunk is far are thinned as they arrive.
	state.added = chunk.ChildAdded:Connect(function(prop)
		task.defer(thinOne, prop, keep, state)
	end)
	thinnedChunks[chunk] = state
end

local function unthin(chunk: Instance)
	local state = thinnedChunks[chunk]
	thinnedChunks[chunk] = nil
	state.added:Disconnect()
	for _, prop in state.hidden do
		-- Streaming may have removed it meanwhile.
		if prop.Parent == holder then
			prop.Parent = chunk
		end
	end
end

local function update(root: Instance)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local position = camera.CFrame.Position
	local size = PropDetail.ChunkStuds
	local margin = PropDetail.Hysteresis
	for layerName, rule in PropDetail.Layers do
		local layerFolder = root:FindFirstChild(layerName)
		if not layerFolder then
			continue
		end
		if rule.hideBeyond then
			for _, chunk in layerFolder:GetChildren() do
				local d = PropCulling.ChunkDistance(chunk.Name, size, position.X, position.Z)
				if d and d > rule.hideBeyond + margin then
					hiddenChunks[chunk] = layerFolder
					chunk.Parent = holder
				end
			end
		end
		if rule.thinBeyond and rule.keep then
			for _, chunk in layerFolder:GetChildren() do
				local d = PropCulling.ChunkDistance(chunk.Name, size, position.X, position.Z)
				if not d then
					continue
				end
				if not thinnedChunks[chunk] and d > rule.thinBeyond + margin then
					thin(chunk, rule.keep)
				elseif thinnedChunks[chunk] and d < rule.thinBeyond then
					unthin(chunk)
				end
			end
		end
	end
	for chunk, layerFolder in hiddenChunks do
		local rule = PropDetail.Layers[layerFolder.Name]
		local d = PropCulling.ChunkDistance(chunk.Name, size, position.X, position.Z)
		if d and rule.hideBeyond and d < rule.hideBeyond then
			hiddenChunks[chunk] = nil
			chunk.Parent = layerFolder
		end
	end
end

function PropDetailController.Init(_deps: { [string]: any }) end

function PropDetailController.Start()
	task.spawn(function()
		local root = workspace:WaitForChild("Nature", 30)
		if not root then
			log:Info("no Nature props in this place; culling off")
			return
		end
		local interval = 1 / PropDetail.UpdateHz
		local elapsed = interval
		RunService.Heartbeat:Connect(function(dt: number)
			elapsed += dt
			if elapsed >= interval then
				elapsed = 0
				update(root)
			end
		end)
	end)
end

return PropDetailController
