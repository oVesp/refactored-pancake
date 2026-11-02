--!strict

local RunService = game:GetService("RunService")

export type Level = "debug" | "info" | "warn" | "error"

export type Logger = {
	Debug: (self: Logger, message: string, ...any) -> (),
	Info: (self: Logger, message: string, ...any) -> (),
	Warn: (self: Logger, message: string, ...any) -> (),
	Error: (self: Logger, message: string, ...any) -> (),
	Throttled: (self: Logger, key: string, intervalSeconds: number, level: Level, message: string, ...any) -> (),
}

local LEVEL_RANK: { [Level]: number } = {
	debug = 1,
	info = 2,
	warn = 3,
	error = 4,
}

local globalLevel: Level = if RunService:IsStudio() then "debug" else "info"
local lastThrottled: { [string]: number } = {}

local function emit(level: Level, category: string, message: string, ...: any)
	if LEVEL_RANK[level] < LEVEL_RANK[globalLevel] then
		return
	end

	local text = if select("#", ...) > 0 then string.format(message, ...) else message
	local line = string.format("[%s][%s] %s", string.upper(level), category, text)
	if level == "warn" or level == "error" then
		warn(line)
	else
		print(line)
	end
end

local Logger = {}

--[=[
	Sets the minimum level written by every logger. Defaults to `debug` in Studio and `info` elsewhere.
]=]
function Logger.SetLevel(level: Level)
	globalLevel = level
end

--[=[
	Creates a logger tagged with a system category (e.g. "DataService").
	Messages are `string.format` patterns when extra arguments are passed.
	Never log secrets or personal data; use ids.
]=]
function Logger.new(category: string): Logger
	local function throttled(
		_self: Logger,
		key: string,
		intervalSeconds: number,
		level: Level,
		message: string,
		...: any
	)
		local fullKey = category .. ":" .. key
		local now = os.clock()
		local last = lastThrottled[fullKey]
		if last and now - last < intervalSeconds then
			return
		end
		lastThrottled[fullKey] = now
		emit(level, category, message, ...)
	end

	return {
		Debug = function(_self: Logger, message: string, ...: any)
			emit("debug", category, message, ...)
		end,
		Info = function(_self: Logger, message: string, ...: any)
			emit("info", category, message, ...)
		end,
		Warn = function(_self: Logger, message: string, ...: any)
			emit("warn", category, message, ...)
		end,
		Error = function(_self: Logger, message: string, ...: any)
			emit("error", category, message, ...)
		end,
		Throttled = throttled,
	}
end

return Logger
