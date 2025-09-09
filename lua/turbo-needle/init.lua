local config = require("turbo-needle.config")
local utils = require("turbo-needle.utils")

local M = {}

-- Completion cache
local completion_cache = {
	entries = {},
	max_size = 50,
	ttl_ms = 2000, -- 2 seconds
}

-- Buffer-local state
local function get_buf_state()
	local bufnr = vim.api.nvim_get_current_buf()
	if not M._buf_states then
		M._buf_states = {}
	end
	if not M._buf_states[bufnr] then
		M._buf_states[bufnr] = {
			debounce_timer = nil,
			current_extmark = nil,
			active_request = nil, -- Track active API request
		}
	end
	return M._buf_states[bufnr]
end

-- Cache management functions
local function get_cache_key(ctx)
	-- Create a hash of the prefix (last 100 chars to avoid overly long keys)
	local prefix = ctx.prefix or ""
	local key_prefix = prefix:sub(-100)
	-- Use simple string concatenation instead of sha256 for compatibility
	return key_prefix .. "|" .. (ctx.suffix or ""):sub(1, 50)
end

local function get_cached_completion(ctx)
	local key = get_cache_key(ctx)
	local entry = completion_cache.entries[key]

	if entry then
		local current_time = vim.loop.now()
		if (current_time - entry.timestamp) < completion_cache.ttl_ms then
			return entry.completion
		else
			-- Remove expired entry
			completion_cache.entries[key] = nil
		end
	end

	return nil
end

local function cache_completion(ctx, completion)
	local key = get_cache_key(ctx)

	-- Simple cache size management
	local cache_size = 0
	for _ in pairs(completion_cache.entries) do
		cache_size = cache_size + 1
	end

	if cache_size >= completion_cache.max_size then
		-- Clear oldest entries (simple approach - clear all)
		completion_cache.entries = {}
	end

	completion_cache.entries[key] = {
		completion = completion,
		timestamp = vim.loop.now(),
	}
end

-- Private config storage
local _config = config.defaults

-- Public getter for config
function M.get_config()
	return vim.deepcopy(_config)
end

function M.setup(opts)
	_config = vim.tbl_deep_extend("force", _config, opts or {})

	-- Validate configuration
	local config_module = require("turbo-needle.config")
	local success, err = pcall(config_module.validate, _config)
	if not success then
		utils.notify("Configuration validation failed: " .. err, vim.log.levels.ERROR)
		return
	end

	-- Validate API key configuration
	local api = require("turbo-needle.api")
	api.validate_api_key_config()

	-- Setup completion triggering
	M.setup_completion_trigger()

	-- Setup keymaps
	M.setup_keymaps()

	utils.notify("turbo-needle setup complete", vim.log.levels.INFO)
end

function M.setup_keymaps()
	if _config.keymaps.accept and _config.keymaps.accept ~= "" then
		vim.keymap.set("i", _config.keymaps.accept, function()
			return M.accept_completion()
		end, { expr = true, desc = "turbo-needle: accept completion" })
	end
end

function M.setup_completion_trigger()
	local debounce_delay = _config.completions.debounce_ms

	local function trigger_completion()
		local state = get_buf_state()
		-- Clear existing ghost text
		M.clear_ghost_text()

		-- Cancel existing timer
		if state.debounce_timer then
			state.debounce_timer:stop()
			state.debounce_timer = nil
		end

		-- Cancel any active API request
		if state.active_request then
			state.active_request = nil -- Mark as cancelled
		end

		-- Start new timer
		state.debounce_timer = vim.defer_fn(function()
			-- Check if timer was cancelled before execution
			if state.debounce_timer then
				M.complete()
				state.debounce_timer = nil
			end
		end, debounce_delay)
	end

	-- Clear timer, cancel requests, and ghost text on buffer leave
	vim.api.nvim_create_autocmd("BufLeave", {
		callback = function()
			local state = get_buf_state()
			if state.debounce_timer then
				state.debounce_timer:stop()
				state.debounce_timer = nil
			end
			if state.active_request then
				state.active_request = nil -- Cancel active request
			end
			M.clear_ghost_text()
		end,
	})

	-- Clean up buffer state when buffer is deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		callback = function(args)
			local bufnr = args.buf
			if M._buf_states and M._buf_states[bufnr] then
				local state = M._buf_states[bufnr]
				if state.debounce_timer then
					state.debounce_timer:stop()
				end
				if state.active_request then
					state.active_request = nil
				end
				M._buf_states[bufnr] = nil
			end
		end,
	})

	-- Trigger on insert leave and cursor moved in insert
	vim.api.nvim_create_autocmd({ "InsertLeave", "CursorMovedI" }, {
		callback = trigger_completion,
	})
end

-- Completion function: extract context and request completion
function M.complete()
	local context = require("turbo-needle.context")
	if not context.is_filetype_supported() then
		return
	end

	local ctx = context.get_current_context()
	local api = require("turbo-needle.api")
	local state = get_buf_state()

	-- Check cache first
	local cached_completion = get_cached_completion(ctx)
	if cached_completion then
		M.set_ghost_text(cached_completion)
		return
	end

	-- Create a request ID to track this request
	local request_id = {}
	state.active_request = request_id

	api.get_completion({ prefix = ctx.prefix, suffix = ctx.suffix }, function(err, result)
		-- Check if this request was cancelled
		if state.active_request ~= request_id then
			return -- Request was cancelled, ignore result
		end

		-- Clear the active request
		state.active_request = nil

		if err then
			utils.notify("Completion error: " .. err, vim.log.levels.ERROR)
			return
		end

		-- Parse the completion text from API response
		local completion_text = api.parse_response(result)

		-- Validate completion text quality
		local is_valid, validation_error = utils.validate_completion(completion_text, ctx)
		if not is_valid then
			-- Don't show warnings for common cases like empty completions
			if validation_error ~= "Empty completion" and validation_error ~= "Completion too short" then
				utils.notify("Completion filtered: " .. validation_error, vim.log.levels.DEBUG)
			end
			return
		end

		-- Cache the valid completion
		cache_completion(ctx, completion_text)

		-- Set ghost text for the completion
		M.set_ghost_text(completion_text)
	end)
end

-- Clear ghost text
function M.clear_ghost_text()
	local state = get_buf_state()
	if state.current_extmark then
		local success = pcall(vim.api.nvim_buf_del_extmark, 0, state.current_extmark.ns_id, state.current_extmark.id)
		if not success then
			utils.notify("Failed to clear ghost text extmark", vim.log.levels.WARN)
		end
		state.current_extmark = nil
	end
end

-- Set ghost text at cursor
function M.set_ghost_text(text)
	local state = get_buf_state()
	M.clear_ghost_text()

	-- Validate input
	if not text or text == "" or type(text) ~= "string" then
		return
	end

	-- Get cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	if not cursor or #cursor < 2 then
		return
	end

	local row, col = cursor[1] - 1, cursor[2] -- Convert to 0-based

	-- Create namespace
	local ns_id = vim.api.nvim_create_namespace("turbo-needle-ghost")

	-- Handle multi-line text
	if text:find("\n") then
		-- Multi-line completion: use virt_lines for better display
		local lines = vim.split(text, "\n", { plain = true })
		local virt_lines = {}

		for _, line in ipairs(lines) do
			table.insert(virt_lines, { { line, "Comment" } })
		end

		local success, multiline_extmark_id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
			virt_lines = virt_lines,
			virt_text_pos = "overlay",
		})
		if not success then
			utils.notify("Failed to set multi-line ghost text extmark", vim.log.levels.ERROR)
			return
		end
		state.current_extmark = { ns_id = ns_id, id = multiline_extmark_id }
	else
		-- Single line completion
		local success, singleline_extmark_id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
			virt_text = { { text, "Comment" } },
			virt_text_pos = "inline",
		})
		if not success then
			utils.notify("Failed to set ghost text extmark", vim.log.levels.ERROR)
			return
		end
		state.current_extmark = { ns_id = ns_id, id = singleline_extmark_id }
	end
end

-- Accept completion: insert ghost text if present, else return tab
function M.accept_completion()
	local state = get_buf_state()
	if state.current_extmark then
		-- Get the extmark details
		local extmark = vim.api.nvim_buf_get_extmark_by_id(
			0,
			state.current_extmark.ns_id,
			state.current_extmark.id,
			{ details = true }
		)

		if extmark and extmark[3] then
			local details = extmark[3]
			local text_to_insert = nil

			-- Handle multi-line completion (virt_lines)
			if details.virt_lines then
				local lines = {}
				for _, line_parts in ipairs(details.virt_lines) do
					if line_parts[1] then
						table.insert(lines, line_parts[1][1] or "")
					else
						table.insert(lines, "")
					end
				end
				text_to_insert = table.concat(lines, "\n")
			-- Handle single-line completion (virt_text)
			elseif details.virt_text and details.virt_text[1] then
				text_to_insert = details.virt_text[1][1]
			end

			if text_to_insert and text_to_insert ~= "" then
				-- Split into lines for proper insertion
				local lines = vim.split(text_to_insert, "\n", { plain = true })
				vim.api.nvim_put(lines, "c", false, true)
				M.clear_ghost_text()
				return "" -- Don't insert tab
			end
		end
	end
	-- No ghost text, insert tab
	return "\t"
end

return M
