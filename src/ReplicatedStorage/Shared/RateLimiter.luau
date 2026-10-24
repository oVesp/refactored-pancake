--!strict

export type RateLimiter<K> = {
	Allow: (self: RateLimiter<K>, key: K) -> boolean,
	Forget: (self: RateLimiter<K>, key: K) -> (),
}

type Bucket = {
	tokens: number,
	updatedAt: number,
}

local RateLimiter = {}

--[=[
	Creates a token-bucket limiter keyed by any value (usually a Player).
	Each key starts full with `capacity` tokens and refills at `refillPerSecond`.
	`clock` defaults to `os.clock` and is injectable for tests.
]=]
function RateLimiter.new<K>(capacity: number, refillPerSecond: number, clock: (() -> number)?): RateLimiter<K>
	assert(capacity >= 1, "capacity must be at least 1")
	assert(refillPerSecond > 0, "refillPerSecond must be positive")

	local now = clock or os.clock
	local buckets: { [K]: Bucket } = {}

	local function allow(_self: RateLimiter<K>, key: K): boolean
		local time = now()
		local bucket = buckets[key]
		if not bucket then
			bucket = { tokens = capacity, updatedAt = time }
			buckets[key] = bucket
		end

		bucket.tokens = math.min(capacity, bucket.tokens + (time - bucket.updatedAt) * refillPerSecond)
		bucket.updatedAt = time

		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end

	local function forget(_self: RateLimiter<K>, key: K)
		buckets[key] = nil
	end

	return {
		Allow = allow,
		Forget = forget,
	}
end

return RateLimiter
