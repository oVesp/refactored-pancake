--!strict

local fs = require("@lune/fs")

--[=[ Names of the Animation instances under src/ReplicatedStorage/Animations, as a set. ]=]
local function animationKeys(): { [string]: boolean }
	local keys = {}
	for _, name in fs.readDir("src/ReplicatedStorage/Animations") do
		local key = string.match(name, "^(.+)%.model%.json$")
		if key then
			keys[key] = true
		end
	end
	return keys
end

return animationKeys
