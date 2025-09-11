local config = require("turbo-needle.config")
local utils = require("turbo-needle.utils")

local M = {}

-- Module-scoped enabled state (private)
local enabled = true

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
			active_request_id = nil, -- Track active API request ID
			active_job = nil, -- Track active plenary.job for cancellation
			request_counter = 0, -- Counter for generating unique request IDs
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
			-- Update access time for LRU
			entry.last_access = current_time
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
	local current_time = vim.loop.now()

	-- LRU cache management
	local cache_size = 0
	local oldest_key = nil
	local oldest_time = current_time

	for k, v in pairs(completion_cache.entries) do
		cache_size = cache_size + 1
		-- Find oldest accessed entry
		local access_time = v.last_access or v.timestamp
		if access_time < oldest_time then
			oldest_time = access_time
			oldest_key = k
		end
	end

	-- Remove oldest entry if cache is full
	if cache_size >= completion_cache.max_size and oldest_key then
		completion_cache.entries[oldest_key] = nil
	end

	completion_cache.entries[key] = {
		completion = completion,
		timestamp = current_time,
		last_access = current_time,
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
		if not enabled then return end

		local state = get_buf_state()
		-- Clear existing ghost text
		M.clear_ghost_text()

		-- Cancel existing timer
		if state.debounce_timer then
			if type(state.debounce_timer) == "userdata" then
				-- It's a uv timer, stop it properly
				state.debounce_timer:stop()
				state.debounce_timer:close()
			else
				-- Legacy: it might be a vim.defer_fn handle (number)
				pcall(function()
					vim.fn.timer_stop(state.debounce_timer)
				end)
			end
			state.debounce_timer = nil
		end

		-- Cancel any active API request by incrementing the request counter
		state.request_counter = state.request_counter + 1
		state.active_request_id = nil

		-- Create new timer using vim.loop
		local timer = vim.loop.new_timer()
		state.debounce_timer = timer

		timer:start(
			debounce_delay,
			0,
			vim.schedule_wrap(function()
				-- Check if this timer is still valid
				if state.debounce_timer == timer then
					M.complete()
					state.debounce_timer = nil
					if timer then
						timer:stop()
						timer:close()
					end
				end
			end)
		)
	end

	-- Clear timer, cancel requests, and ghost text on buffer leave
	vim.api.nvim_create_autocmd("BufLeave", {
		callback = function()
			local state = get_buf_state()
			if state.debounce_timer then
				if type(state.debounce_timer) == "userdata" then
					state.debounce_timer:stop()
					state.debounce_timer:close()
				else
					-- Legacy cleanup
					pcall(function()
						vim.fn.timer_stop(state.debounce_timer)
					end)
				end
				state.debounce_timer = nil
			end
			-- Cancel active request by incrementing counter
			state.request_counter = state.request_counter + 1
			state.active_request_id = nil
			-- Cancel active job
			if state.active_job then
				pcall(function()
					state.active_job:shutdown()
				end)
				state.active_job = nil
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
					if type(state.debounce_timer) == "userdata" then
						state.debounce_timer:stop()
						state.debounce_timer:close()
					else
						pcall(function()
							vim.fn.timer_stop(state.debounce_timer)
						end)
					end
				end
				-- Cancel active job
				if state.active_job then
					pcall(function()
						state.active_job:shutdown()
					end)
				end
				M._buf_states[bufnr] = nil
			end
		end,
	})

	-- Clean up old buffer states periodically to prevent memory leak
	vim.api.nvim_create_autocmd("BufEnter", {
		callback = vim.schedule_wrap(function()
			if M._buf_states then
				-- Get list of valid buffers
				local valid_bufs = {}
				for _, buf in ipairs(vim.api.nvim_list_bufs()) do
					if vim.api.nvim_buf_is_valid(buf) then
						valid_bufs[buf] = true
					end
				end

				-- Clean up states for invalid buffers
				for bufnr, _ in pairs(M._buf_states) do
					if not valid_bufs[bufnr] then
						local state = M._buf_states[bufnr]
						if state and state.debounce_timer then
							if type(state.debounce_timer) == "userdata" then
								state.debounce_timer:stop()
								state.debounce_timer:close()
							end
						end
						M._buf_states[bufnr] = nil
					end
				end
			end
		end),
	})

	-- Trigger on insert leave and cursor moved in insert
	vim.api.nvim_create_autocmd({ "InsertLeave", "CursorMovedI" }, {
		callback = trigger_completion,
	})
end

-- Enable completions
function M.enable()
	enabled = true
	utils.notify("turbo-needle completions enabled", vim.log.levels.INFO)
end

-- Disable completions
function M.disable()
	enabled = false
	utils.notify("turbo-needle completions disabled", vim.log.levels.INFO)
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

	-- Cancel any existing job before starting a new request
	if state.active_job then
		pcall(function()
			state.active_job:shutdown()
		end)
		state.active_job = nil
	end

	-- Create a unique request ID to track this request
	state.request_counter = state.request_counter + 1
	local request_id = state.request_counter
	state.active_request_id = request_id

	-- Start the new request and store the job for potential cancellation
	state.active_job = api.get_completion({ prefix = ctx.prefix, suffix = ctx.suffix }, function(err, result)
		-- Check if this request was cancelled (newer request started)
		if state.active_request_id ~= request_id then
			return -- Request was cancelled, ignore result
		end

		-- Clear the active request and job
		state.active_request_id = nil
		state.active_job = nil

		if err then
			utils.notify("Completion error: " .. err, vim.log.levels.ERROR)
			return
		end

		-- Parse the completion text from API response
		local completion_text
		if _config.api.parse_response then
			completion_text = _config.api.parse_response(result)
		else
			completion_text = api.parse_response(result)
		end

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
		-- Multi-line completion: use virt_lines with smart positioning
		local lines = vim.split(text, "\n", { plain = true })

		-- Limit the number of lines shown to prevent overwhelming the UI
		local max_lines = 10
		if #lines > max_lines then
			lines = vim.list_slice(lines, 1, max_lines)
			-- Add a truncation indicator
			lines[max_lines] = lines[max_lines] .. "..."
		end

		local virt_lines = {}
		local current_line_indent = ""

		-- Get current line's indentation to preserve it in multi-line completions
		local current_line = vim.api.nvim_get_current_line()
		if current_line then
			current_line_indent = current_line:match("^%s*") or ""
		end

		for i, line in ipairs(lines) do
			local display_line = line
			-- For continuation lines, preserve relative indentation
			if i > 1 and line:match("^%s*") then
				-- Remove existing indentation and add current line's indentation
				display_line = current_line_indent .. line:gsub("^%s*", "")
			end

			-- Truncate very long lines
			if #display_line > 100 then
				display_line = display_line:sub(1, 97) .. "..."
			end

			table.insert(virt_lines, { { display_line, "Comment" } })
		end

		-- Use better positioning for multi-line completions
		local success, multiline_extmark_id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
			virt_lines = virt_lines,
			virt_text_pos = "overlay",
			-- Add priority to ensure our ghost text appears above other extmarks
			priority = 100,
		})
		if not success then
			utils.notify("Failed to set multi-line ghost text extmark", vim.log.levels.ERROR)
			return
		end
		state.current_extmark = { ns_id = ns_id, id = multiline_extmark_id }
	else
		-- Single line completion with smart positioning
		local display_text = text

		-- Truncate very long single-line completions
		if #display_text > 100 then
			display_text = display_text:sub(1, 97) .. "..."
		end

		local success, singleline_extmark_id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
			virt_text = { { display_text, "Comment" } },
			virt_text_pos = "inline",
			-- Add priority to ensure our ghost text appears above other extmarks
			priority = 100,
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
		-- Safely get the extmark details
		local success, extmark = pcall(
			vim.api.nvim_buf_get_extmark_by_id,
			0,
			state.current_extmark.ns_id,
			state.current_extmark.id,
			{ details = true }
		)

		if success and extmark and #extmark >= 3 and extmark[3] then
			local details = extmark[3]
			local text_to_insert = nil

			-- Handle multi-line completion (virt_lines)
			if details.virt_lines and type(details.virt_lines) == "table" then
				local lines = {}
				for _, line_parts in ipairs(details.virt_lines) do
					if type(line_parts) == "table" and line_parts[1] then
						if type(line_parts[1]) == "table" and line_parts[1][1] then
							table.insert(lines, line_parts[1][1])
						elseif type(line_parts[1]) == "string" then
							table.insert(lines, line_parts[1])
						else
							table.insert(lines, "")
						end
					else
						table.insert(lines, "")
					end
				end
				if #lines > 0 then
					text_to_insert = table.concat(lines, "\n")
				end
			-- Handle single-line completion (virt_text)
			elseif details.virt_text and type(details.virt_text) == "table" and details.virt_text[1] then
				if type(details.virt_text[1]) == "table" and details.virt_text[1][1] then
					text_to_insert = details.virt_text[1][1]
				elseif type(details.virt_text[1]) == "string" then
					text_to_insert = details.virt_text[1]
				end
			end

			if text_to_insert and type(text_to_insert) == "string" and text_to_insert ~= "" then
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

-- Metatable for read-only 'enabled' property
local mt = {
	__index = function(t, k)
		if k == 'enabled' then
			return enabled  -- Return the private enabled value
		end
		return rawget(t, k)  -- Normal table access for other keys
	end,
	__newindex = function(t, k, v)
		if k == 'enabled' then
			error("Cannot set 'enabled' directly. Use enable() or disable() functions.", 2)
		end
		rawset(t, k, v)  -- Normal table assignment for other keys
	end
}

return setmetatable(M, mt)
