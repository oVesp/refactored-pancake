--!strict

-- Compares two KeyframeSequences pose by pose at matching frames (30 fps) and prints the worst
-- rotation and position difference. Used to check an exporter against Studio's own FBX import of
-- the same clip (docs/art/animation-pipeline.md, Rig import):
--     lune run tools/anim/compare <studio.rbxm> <exported.rbxmx>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local function load(path: string): any
	return roblox.deserializeModel(fs.readFile(path))[1]
end

local function poses(keyframe: any): { [string]: any }
	local map = {}
	local function walk(pose: any)
		map[pose.Name] = pose.CFrame
		for _, child in pose:GetChildren() do
			if child.ClassName == "Pose" then
				walk(child)
			end
		end
	end
	for _, pose in keyframe:GetChildren() do
		if pose.ClassName == "Pose" then
			walk(pose)
		end
	end
	return map
end

local function byFrame(sequence: any): { [number]: { [string]: any } }
	local frames = {}
	for _, keyframe in sequence:GetChildren() do
		if keyframe.ClassName == "Keyframe" then
			frames[math.floor(keyframe.Time * 30 + 0.5)] = poses(keyframe)
		end
	end
	return frames
end

local a, b = byFrame(load(process.args[1])), byFrame(load(process.args[2]))
local worstAngle, worstPosition, worstAt, compared, missing = 0, 0, "", 0, 0
for frame, left in a do
	local right = b[frame]
	if not right then
		continue
	end
	for name, cframe in left do
		local other = right[name]
		if not other then
			missing += 1
			continue
		end
		compared += 1
		local _, angle = cframe:ToObjectSpace(other):ToAxisAngle()
		if math.abs(angle) > worstAngle then
			worstAngle = math.abs(angle)
			worstAt = `{name} at frame {frame}`
		end
		worstPosition = math.max(worstPosition, (cframe.Position - other.Position).Magnitude)
	end
end
print(
	`{compared} poses compared, {missing} missing; worst rotation {math.deg(worstAngle)} deg ({worstAt}), worst position {worstPosition} studs`
)
