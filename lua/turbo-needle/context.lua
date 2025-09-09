local M = {}

-- Context cache to avoid re-extraction for same cursor position
local context_cache = {
	bufnr = nil,
	cursor_row = nil,
	cursor_col = nil,
	context = nil,
	timestamp = 0,
}

-- Maximum context size limits
local MAX_PREFIX_LINES = 50
local MAX_SUFFIX_LINES = 50
local MAX_LINE_LENGTH = 200
local CACHE_TTL_MS = 100 -- Cache validity time

-- Extract code context around cursor for FIM completion
function M.extract_context(bufnr, cursor_row, cursor_col)
	-- Check cache first
	local current_time = vim.loop.now()
	if context_cache.bufnr == bufnr and
	   context_cache.cursor_row == cursor_row and
	   context_cache.cursor_col == cursor_col and
	   (current_time - context_cache.timestamp) < CACHE_TTL_MS then
		return context_cache.context
	end

	-- Get all lines in the buffer
	local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local total_lines = #all_lines

	-- Validate cursor position
	if cursor_row < 0 or cursor_row > total_lines - 1 then
		local empty_context = { prefix = "", suffix = "" }
		context_cache = {
			bufnr = bufnr,
			cursor_row = cursor_row,
			cursor_col = cursor_col,
			context = empty_context,
			timestamp = current_time,
		}
		return empty_context
	end

	-- Convert cursor position to 1-based for string operations
	-- cursor_row is 0-based, cursor_col is 0-based
	local cursor_line_1based = cursor_row + 1
	local cursor_col_1based = cursor_col + 1

	-- Extract prefix: all content before cursor (with size limits)
	local prefix_lines = {}
	local prefix_start = math.max(1, cursor_line_1based - MAX_PREFIX_LINES)
	for i = prefix_start, cursor_line_1based - 1 do
		local line = all_lines[i]
		if line and #line > MAX_LINE_LENGTH then
			line = line:sub(1, MAX_LINE_LENGTH) .. "..."
		end
		table.insert(prefix_lines, line)
	end

	local prefix = table.concat(prefix_lines, "\n")
	if #prefix_lines > 0 then
		prefix = prefix .. "\n"
	end

	-- Add the current line up to cursor position
	if cursor_line_1based <= total_lines then
		local current_line = all_lines[cursor_line_1based]
		if cursor_col_1based > 1 then
			-- Extract substring up to cursor column (cursor in middle of line)
			local prefix_part = string.sub(current_line, 1, cursor_col_1based - 1)
			prefix = prefix .. prefix_part
		end
		-- Note: When cursor is at column 0, don't add current line to prefix
		-- The current line will be handled in the suffix extraction
	end

	-- Extract suffix: all content after cursor
	local suffix_lines = {}
	local has_suffix_part = false
	if cursor_line_1based <= total_lines then
		local current_line = all_lines[cursor_line_1based]
		if cursor_col_1based <= #current_line then
			-- Extract substring from cursor column to end of line
			local suffix_part = string.sub(current_line, cursor_col_1based)
			table.insert(suffix_lines, suffix_part)
			has_suffix_part = true
		else
			-- Cursor beyond line length, add empty string to maintain line structure
			table.insert(suffix_lines, "")
			has_suffix_part = true
		end
	end

	-- Add remaining lines after current line (with size limits)
	local suffix_end = math.min(total_lines, cursor_line_1based + MAX_SUFFIX_LINES)
	for i = cursor_line_1based + 1, suffix_end do
		local line = all_lines[i]
		if line and #line > MAX_LINE_LENGTH then
			line = line:sub(1, MAX_LINE_LENGTH) .. "..."
		end
		table.insert(suffix_lines, line)
	end

	-- If no suffix part but there are remaining lines, add empty string to start with \n
	if not has_suffix_part and #suffix_lines > 0 then
		table.insert(suffix_lines, 1, "")
	end

	local result = {
		prefix = prefix,
		suffix = table.concat(suffix_lines, "\n"),
	}

	-- Update cache
	context_cache = {
		bufnr = bufnr,
		cursor_row = cursor_row,
		cursor_col = cursor_col,
		context = result,
		timestamp = current_time,
	}

	return result
end

-- Get current cursor position and extract context
function M.get_current_context()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0) -- Returns {row, col} 0-based

	if not cursor or #cursor < 2 then
		return { prefix = "", suffix = "" }
	end

	local row, col = cursor[1], cursor[2] -- Both are 0-based

	return M.extract_context(bufnr, row, col)
end

-- Check if current file type is supported
function M.is_filetype_supported()
	local turbo_needle = require("turbo-needle")
	local config = turbo_needle.get_config()
	local filetype = vim.bo.filetype

	-- Check if filetype is in disabled list first (disabled takes precedence)
	for _, disabled_type in ipairs(config.filetypes.disabled) do
		if filetype == disabled_type then
			return false
		end
	end

	-- Check if filetype is in enabled list
	for _, enabled_type in ipairs(config.filetypes.enabled) do
		if filetype == enabled_type then
			return true
		end
	end

	-- Default: allow if not explicitly disabled
	return true
end

return M
