local M = {}

-- Context cache to avoid re-extraction for same cursor position
local context_cache = {
	bufnr = nil,
	cursor_row = nil,
	cursor_col = nil,
	options_cache_key = nil,
	context = nil,
	timestamp = 0,
}

local CACHE_TTL_MS = 500 -- Cache validity time (increased from 100ms to 500ms)

local default_options = {
	max_chars = 12000,
	prefix_ratio = 0.75,
	include_filepath = true,
	include_ellipsis = true,
}

local function normalize_options(opts)
	return vim.tbl_extend("force", default_options, opts or {})
end

local function cache_key_for_options(opts)
	return table.concat({
		tostring(opts.max_chars),
		tostring(opts.prefix_ratio),
		tostring(opts.include_filepath),
		tostring(opts.include_ellipsis),
	}, "|")
end

local function char_len(value)
	return vim.fn.strcharlen(value or "")
end

local function char_part(value, start, length)
	return vim.fn.strcharpart(value or "", start, length)
end

local function trim_prefix_to_budget(prefix, budget)
	if budget <= 0 then
		return "", prefix ~= ""
	end
	if char_len(prefix) <= budget then
		return prefix, false
	end

	local trimmed = char_part(prefix, char_len(prefix) - budget, budget)
	local newline = trimmed:find("\n", 1, true)
	if newline and newline < #trimmed then
		return trimmed:sub(newline + 1), true
	end
	return trimmed, true
end

local function trim_suffix_to_budget(suffix, budget)
	if budget <= 0 then
		return "", suffix ~= ""
	end
	if char_len(suffix) <= budget then
		return suffix, false
	end

	local trimmed = char_part(suffix, 0, budget)
	local last_newline = nil
	local search_start = 1
	while true do
		local newline = trimmed:find("\n", search_start, true)
		if not newline then
			break
		end
		last_newline = newline
		search_start = newline + 1
	end
	if last_newline and last_newline > 1 then
		return trimmed:sub(1, last_newline - 1), true
	end
	return trimmed, true
end

local function apply_budget(prefix, suffix, opts)
	local max_chars = opts.max_chars
	local prefix_len = char_len(prefix)
	local suffix_len = char_len(suffix)

	if prefix_len + suffix_len <= max_chars then
		return prefix, suffix, false, false
	end

	local prefix_budget = math.floor(max_chars * opts.prefix_ratio)
	local suffix_budget = max_chars - prefix_budget

	if prefix_len < prefix_budget then
		suffix_budget = suffix_budget + (prefix_budget - prefix_len)
		prefix_budget = prefix_len
	elseif suffix_len < suffix_budget then
		prefix_budget = prefix_budget + (suffix_budget - suffix_len)
		suffix_budget = suffix_len
	end

	local trimmed_prefix, prefix_truncated = trim_prefix_to_budget(prefix, prefix_budget)
	local trimmed_suffix, suffix_truncated = trim_suffix_to_budget(suffix, suffix_budget)
	return trimmed_prefix, trimmed_suffix, prefix_truncated, suffix_truncated
end

local fallback_commentstrings = {
	c = "// %s",
	cpp = "// %s",
	cs = "// %s",
	go = "// %s",
	java = "// %s",
	javascript = "// %s",
	javascriptreact = "// %s",
	jsonc = "// %s",
	kotlin = "// %s",
	lua = "-- %s",
	php = "// %s",
	python = "# %s",
	ruby = "# %s",
	rust = "// %s",
	sh = "# %s",
	sql = "-- %s",
	swift = "// %s",
	typescript = "// %s",
	typescriptreact = "// %s",
	vim = '" %s',
	yaml = "# %s",
	zsh = "# %s",
}

function M.get_commentstring(bufnr)
	local commentstring = vim.bo[bufnr].commentstring
	if type(commentstring) == "string" and commentstring:find("%%s") then
		return commentstring
	end

	local filetype = vim.bo[bufnr].filetype
	return fallback_commentstrings[filetype] or "# %s"
end

local function comment_line(bufnr, text)
	return string.format(M.get_commentstring(bufnr), text)
end

local function get_filepath(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	return name ~= "" and vim.fn.fnamemodify(name, ":p") or ""
end

local function add_comment_hints(result, bufnr, opts, prefix_truncated, suffix_truncated)
	local prefix_hints = {}
	if opts.include_filepath then
		local filepath = get_filepath(bufnr)
		if filepath ~= "" then
			result.filepath = filepath
			table.insert(prefix_hints, comment_line(bufnr, filepath))
		end
	end

	if opts.include_ellipsis and prefix_truncated then
		table.insert(prefix_hints, comment_line(bufnr, "…"))
	end

	if #prefix_hints > 0 then
		result.prefix = table.concat(prefix_hints, "\n") .. "\n" .. (result.prefix or "")
	end

	if opts.include_ellipsis and suffix_truncated then
		local suffix = result.suffix or ""
		if suffix ~= "" then
			suffix = suffix .. "\n"
		end
		result.suffix = suffix .. comment_line(bufnr, "…")
	end

	return result
end

-- Extract code context around cursor for FIM completion
function M.extract_context(bufnr, cursor_row, cursor_col, opts)
	opts = normalize_options(opts)
	local options_cache_key = cache_key_for_options(opts)

	-- Check cache first
	local current_time = vim.loop.now()
	if
		context_cache.bufnr == bufnr
		and context_cache.cursor_row == cursor_row
		and context_cache.cursor_col == cursor_col
		and context_cache.options_cache_key == options_cache_key
		and (current_time - context_cache.timestamp) < CACHE_TTL_MS
	then
		return context_cache.context
	end

	-- Get all lines in the buffer
	local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local total_lines = #all_lines

	-- Validate cursor position
	if cursor_row < 0 or cursor_row > total_lines - 1 then
		local empty_context = add_comment_hints({ prefix = "", suffix = "" }, bufnr, opts, false, false)
		context_cache = {
			bufnr = bufnr,
			cursor_row = cursor_row,
			cursor_col = cursor_col,
			options_cache_key = options_cache_key,
			context = empty_context,
			timestamp = current_time,
		}
		return empty_context
	end

	-- cursor_row is 0-based, cursor_col is 0-based byte index
	-- Convert to 1-based for Lua string operations and array indexing
	local cursor_line_1based = cursor_row + 1

	-- Extract prefix: all content before cursor.
	local prefix_lines = {}
	for i = 1, cursor_line_1based - 1 do
		table.insert(prefix_lines, all_lines[i])
	end

	local prefix = table.concat(prefix_lines, "\n")
	if #prefix_lines > 0 then
		prefix = prefix .. "\n"
	end

	-- Add the current line up to cursor position
	if cursor_line_1based <= total_lines then
		local current_line = all_lines[cursor_line_1based] or ""
		if cursor_col > 0 then
			-- Extract substring up to cursor column
			-- cursor_col is 0-based byte index, string.sub expects 1-based
			local prefix_part = string.sub(current_line, 1, cursor_col)
			prefix = prefix .. prefix_part
		end
		-- When cursor_col is 0, we're at the beginning of the line, no prefix from current line
	end

	-- Extract suffix: all content after cursor.
	local suffix_lines = {}
	local has_suffix_part = false
	if cursor_line_1based <= total_lines then
		local current_line = all_lines[cursor_line_1based] or ""
		-- cursor_col is 0-based byte position where cursor is
		-- We want everything from cursor_col+1 onwards (1-based for string.sub)
		if cursor_col < #current_line then
			-- Extract substring from cursor position to end of line
			local suffix_part = string.sub(current_line, cursor_col + 1)
			table.insert(suffix_lines, suffix_part)
			has_suffix_part = true
		elseif cursor_col == #current_line then
			-- Cursor at end of line, no suffix from current line but may have following lines
			table.insert(suffix_lines, "")
			has_suffix_part = true
		end
		-- If cursor_col > #current_line (shouldn't happen normally), treat as end of line
	end

	-- Add remaining lines after current line.
	for i = cursor_line_1based + 1, total_lines do
		table.insert(suffix_lines, all_lines[i])
	end

	-- If no suffix part but there are remaining lines, add empty string to start with \n
	if not has_suffix_part and #suffix_lines > 0 then
		table.insert(suffix_lines, 1, "")
	end

	local suffix = table.concat(suffix_lines, "\n")
	local prefix_truncated, suffix_truncated
	prefix, suffix, prefix_truncated, suffix_truncated = apply_budget(prefix, suffix, opts)

	local result = add_comment_hints({
		prefix = prefix,
		suffix = suffix,
	}, bufnr, opts, prefix_truncated, suffix_truncated)

	-- Update cache
	context_cache = {
		bufnr = bufnr,
		cursor_row = cursor_row,
		cursor_col = cursor_col,
		options_cache_key = options_cache_key,
		context = result,
		timestamp = current_time,
	}

	return result
end

-- Get current cursor position and extract context
function M.get_current_context(additional_sources)
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0) -- Returns {row (1-based), col (0-based byte index)}

	if not cursor or #cursor < 2 then
		return { prefix = "", suffix = "" }
	end

	local row, col = cursor[1] - 1, cursor[2] -- Convert row to 0-based, col is already 0-based

	local turbo_needle = require("turbo-needle")
	local config = turbo_needle.get_config()

	local current = M.extract_context(bufnr, row, col, config.context)
	local manager = require("turbo-needle.context_manager").new({
		max_chars = config.context.max_chars,
		commentstring = M.get_commentstring(bufnr),
		sources = config.context.sources,
	})
	return manager:build(current, additional_sources)
end

-- Check if current file type is supported
function M.is_filetype_supported()
	local turbo_needle = require("turbo-needle")
	local config = turbo_needle.get_config()
	local filetype = vim.bo.filetype

	-- Check if filetype is explicitly configured
	if config.filetypes[filetype] ~= nil then
		return config.filetypes[filetype]
	end

	-- Default: allow if not explicitly disabled
	return true
end

return M
