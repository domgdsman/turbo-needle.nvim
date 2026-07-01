local M = {}

local List = {}
List.__index = List
local uv = vim.uv or vim.loop

local function default_now()
	return uv.now()
end

function List.new(opts)
	opts = opts or {}
	local self = setmetatable({
		entries = {},
		keep_last = opts.keep_last or 10,
		ttl_ms = opts.ttl_ms,
		key = opts.key,
		policies = opts.policies or {},
		now = opts.now or default_now,
		in_policy = false,
		timer = nil,
	}, List)

	if opts.eviction_interval_ms then
		self.timer = uv.new_timer()
		self.timer:start(
			opts.eviction_interval_ms,
			opts.eviction_interval_ms,
			vim.schedule_wrap(function()
				self:prune()
			end)
		)
	end
	return self
end

function List:_key(item)
	if self.key then
		return self.key(item)
	end
	return item
end

function List:prune()
	if self.ttl_ms then
		local cutoff = self.now() - self.ttl_ms
		for index = #self.entries, 1, -1 do
			if (self.entries[index].captured_at or 0) <= cutoff then
				table.remove(self.entries, index)
			end
		end
	end
	while #self.entries > self.keep_last do
		table.remove(self.entries)
	end
end

function List:items()
	self:prune()
	return vim.deepcopy(self.entries)
end

function List:remove(key_or_predicate)
	local predicate = type(key_or_predicate) == "function" and key_or_predicate
		or function(item)
			return self:_key(item) == key_or_predicate
		end
	local removed = 0
	for index = #self.entries, 1, -1 do
		if predicate(self.entries[index]) then
			table.remove(self.entries, index)
			removed = removed + 1
		end
	end
	return removed
end

function List:insert(item)
	if self.in_policy then
		error("ContextList policies cannot insert entries", 0)
	end
	local next_item = vim.deepcopy(item)
	next_item.captured_at = next_item.captured_at or self.now()

	self:prune()
	self.in_policy = true
	local ok, err = pcall(function()
		for _, policy in ipairs(self.policies) do
			policy(next_item, self)
		end
	end)
	self.in_policy = false
	if not ok then
		error(err, 0)
	end

	self:remove(self:_key(next_item))
	table.insert(self.entries, 1, next_item)
	self:prune()
	return vim.deepcopy(next_item)
end

List.upsert = List.insert

function List:touch(key)
	self:prune()
	for index, item in ipairs(self.entries) do
		if self:_key(item) == key then
			local touched = table.remove(self.entries, index)
			touched.captured_at = self.now()
			table.insert(self.entries, 1, touched)
			return true
		end
	end
	return false
end

function List:clear()
	self.entries = {}
end

function List:close()
	if self.timer then
		self.timer:stop()
		self.timer:close()
		self.timer = nil
	end
end

M.List = List

function M.new(opts)
	return List.new(opts)
end

return M
