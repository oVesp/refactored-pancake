--!strict

--[=[
	Keep-out anchors for the settlement layout, read from the Map: trainers and the vendor,
	enemy spawners (with their spawn radius), training dummies, dev spawn pads and the respawn
	point. Works on Studio instances and on `@lune/roblox` instances (positions come from CFrame,
	which both provide).
]=]
export type Anchor = { x: number, z: number, r: number }

local Anchors = {}

local function position(part: any): (number, number)
	local p = part.CFrame.Position
	return p.X, p.Z
end

--[=[ Anchors from a Map model (Workspace.Map in Studio, src/Workspace/Map.rbxmx in Lune). ]=]
function Anchors.fromMap(map: any): { Anchor }
	local out: { Anchor } = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			if d:HasTag("Spawner") then
				local radius = d:GetAttribute("Radius")
				local x, z = position(d)
				table.insert(out, { x = x, z = z, r = if type(radius) == "number" then radius else 8 })
			elseif d:HasTag("Trainer") or d:HasTag("DevSpawnPad") or d:HasTag("RespawnPoint") then
				local x, z = position(d)
				table.insert(out, { x = x, z = z, r = math.max(d.Size.X, d.Size.Z) / 2 + 3 })
			end
		elseif d:IsA("Model") and d:HasTag("TrainingDummy") then
			for _, p in d:GetDescendants() do
				if p:IsA("BasePart") then
					local x, z = position(p)
					table.insert(out, { x = x, z = z, r = 3 })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.z < b.z
	end)
	return out
end

return Anchors
