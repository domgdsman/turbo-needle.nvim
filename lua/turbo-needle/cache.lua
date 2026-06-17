local M = {}

local Cache = {}
Cache.__index = Cache

local function get_cache_key(ctx)
	local prefix = ctx.prefix or ""
	local key_prefix = prefix:sub(-100)
	return table.concat({
		ctx.cache_fingerprint or "",
		key_prefix,
		(ctx.suffix or ""):sub(1, 50),
	}, "|")
end

function M.new(opts)
	opts = opts or {}
	return setmetatable({
		entries = {},
		max_size = opts.max_size or 50,
		ttl_ms = opts.ttl_ms or 2000,
	}, Cache)
end

function Cache:get(ctx)
	local key = get_cache_key(ctx)
	local entry = self.entries[key]

	if entry then
		local current_time = vim.loop.now()
		if (current_time - entry.timestamp) < self.ttl_ms then
			entry.last_access = current_time
			return entry.completion
		end
		self.entries[key] = nil
	end

	return nil
end

function Cache:set(ctx, completion)
	local key = get_cache_key(ctx)
	local current_time = vim.loop.now()
	local cache_size = 0
	local oldest_key = nil
	local oldest_time = current_time

	for k, v in pairs(self.entries) do
		cache_size = cache_size + 1
		local access_time = v.last_access or v.timestamp
		if access_time < oldest_time then
			oldest_time = access_time
			oldest_key = k
		end
	end

	if cache_size >= self.max_size and oldest_key then
		self.entries[oldest_key] = nil
	end

	self.entries[key] = {
		completion = completion,
		timestamp = current_time,
		last_access = current_time,
	}
end

function Cache:clear()
	self.entries = {}
end

return M
