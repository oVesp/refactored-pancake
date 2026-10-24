--!strict

-- Loads a Rojo-style module from disk under Lune, resolving `require(script.Parent.X)` chains to
-- sibling files. Lets tests use content and shared modules without Roblox.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}
local cache: { [string]: any } = {}

local function resolve(path: string): string
	if fs.isFile(path .. ".luau") then
		return path .. ".luau"
	elseif fs.isFile(path .. "/init.luau") then
		return path .. "/init.luau"
	end
	error(`Cannot resolve module {path}`)
end

local function proxy(path: string): any
	return setmetatable({ __path = path }, {
		__index = function(self, key: string)
			local own = rawget(self, "__path")
			if key == "Parent" then
				local parent = string.match(own, "^(.*)/[^/]+$")
				assert(parent, `No parent above {own}`)
				return proxy(parent)
			end
			return proxy(own .. "/" .. key)
		end,
	})
end

--[=[ Loads the module at `path` (repo-relative, no extension). Cached per path. ]=]
function Loader.load(path: string): any
	local cached = cache[path]
	if cached ~= nil then
		return cached
	end

	local file = resolve(path)
	local env = {
		script = proxy(path),
		require = function(target: any)
			return Loader.load(rawget(target, "__path"))
		end,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
	}
	local chunk = luau.load(fs.readFile(file), { debugName = file, environment = env })
	local result = chunk()
	cache[path] = result
	return result
end

return Loader
