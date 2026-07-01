local buffer = require("turbo-needle.buffer")
local context_list = require("turbo-needle.context_list")

local M = {}
local RecentlyEdited = {}
RecentlyEdited.__index = RecentlyEdited

local function range_id(item)
	return string.format("%s:%d:%d", item.filepath, item.start_line, item.end_line)
end

local function ranges_match(left, right, merge_adjacent)
	if merge_adjacent then
		return left.start_line <= right.end_line and right.start_line <= left.end_line
	end
	return left.start_line < right.end_line and right.start_line < left.end_line
end

local function read_range(bufnr, start_line, end_line)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return {}
	end
	return vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
end

function RecentlyEdited.new(config)
	config = config or {}
	local self = setmetatable({
		config = config,
		attached = {},
		augroup = nil,
	}, RecentlyEdited)

	local function merge_policy(new_item, list)
		for _, existing in ipairs(list:items()) do
			if
				existing.filepath == new_item.filepath
				and ranges_match(existing, new_item, config.merge_adjacent ~= false)
			then
				new_item.start_line = math.min(new_item.start_line, existing.start_line)
				new_item.end_line = math.max(new_item.end_line, existing.end_line)
				list:remove(existing.id)
			end
		end
		new_item.content = read_range(new_item.bufnr, new_item.start_line, new_item.end_line)
		new_item.id = range_id(new_item)
	end

	self.list = context_list.new({
		keep_last = config.max_ranges or 3,
		ttl_ms = config.ttl_ms or 120000,
		key = function(item)
			return item.id
		end,
		policies = { merge_policy },
	})
	return self
end

function RecentlyEdited:record(bufnr, firstline, new_lastline)
	if not buffer.is_normal_file(bufnr) then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local start_line = math.min(firstline, math.max(0, line_count - 1))
	local end_line = new_lastline
	if end_line <= start_line then
		end_line = math.min(line_count, start_line + 1)
	end
	if end_line <= start_line then
		return
	end

	local item = {
		bufnr = bufnr,
		filepath = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p"),
		start_line = start_line,
		end_line = end_line,
		content = read_range(bufnr, start_line, end_line),
	}
	item.id = range_id(item)
	self.list:insert(item)
end

function RecentlyEdited:attach(bufnr)
	if self.attached[bufnr] or not buffer.is_normal_file(bufnr) then
		return false
	end
	local attached = vim.api.nvim_buf_attach(bufnr, false, {
		on_lines = function(_, changed_bufnr, _, firstline, _, new_lastline)
			self:record(changed_bufnr, firstline, new_lastline)
		end,
		on_detach = function(_, detached_bufnr)
			self.attached[detached_bufnr] = nil
		end,
	})
	if attached then
		self.attached[bufnr] = true
	end
	return attached
end

function RecentlyEdited:setup()
	if self.config.enabled == false then
		return
	end
	self.augroup = vim.api.nvim_create_augroup("turbo-needle-recently-edited", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
		group = self.augroup,
		callback = function(args)
			self:attach(args.buf)
		end,
	})
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		self:attach(bufnr)
	end
end

function RecentlyEdited:get_context(bufnr, cursor_row)
	local parts = {}
	for _, item in ipairs(self.list:items()) do
		local contains_cursor = item.bufnr == bufnr and item.start_line <= cursor_row and cursor_row < item.end_line
		if not contains_cursor and #item.content > 0 then
			local path = vim.fn.fnamemodify(item.filepath, ":.")
			table.insert(parts, "Path: " .. path .. "\n" .. table.concat(item.content, "\n"))
		end
	end
	if #parts == 0 then
		return nil
	end
	return {
		source = "recently_edited",
		priority = self.config.priority or 100,
		sort_order = self.config.sort_order or 10,
		can_truncate = true,
		content = parts,
	}
end

function RecentlyEdited:close()
	for bufnr in pairs(self.attached) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			pcall(vim.api.nvim_buf_detach, bufnr)
		end
	end
	self.attached = {}
	self.list:close()
	if self.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
		self.augroup = nil
	end
end

M.RecentlyEdited = RecentlyEdited
function M.new(config)
	return RecentlyEdited.new(config)
end
return M
