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
			cached_completion = nil, -- Cache original completion text
			cursor_position = nil, -- Store cursor position when setting ghost text
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
		if not enabled then
			return
		end

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
	utils.notify("[turbo-needle] completions enabled", vim.log.levels.INFO)
end

-- Disable completions
function M.disable()
	enabled = false
	utils.notify("[turbo-needle] completions disabled", vim.log.levels.INFO)
end

-- Completion function: extract context and request completion
function M.complete()
	-- Only trigger completions in insert mode
	-- Also respect global enabled toggle
	if not M.enabled then
		return
	end
	if vim.api.nvim_get_mode().mode ~= "i" then
		return
	end

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
	state.active_job = api.get_completion(
		{ prefix = ctx.prefix, suffix = ctx.suffix },
		vim.schedule_wrap(function(err, result)
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
	)
end

-- Clear ghost text
function M.clear_ghost_text()
	local state = get_buf_state()
	if state.current_extmark then
		-- Always attempt deletion so tests detecting call still pass; suppress benign 'invalid extmark' errors
		local ok, err = pcall(vim.api.nvim_buf_del_extmark, 0, state.current_extmark.ns_id, state.current_extmark.id)
		if not ok then
			local msg = tostring(err)
			-- Only warn if it's not a common already-cleared scenario
			if not (msg:match("Invalid extmark id") or msg:match("Invalid namespace id")) then
				utils.notify("Failed to clear ghost text extmark", vim.log.levels.WARN)
			end
		end
		state.current_extmark = nil
	end
	-- Clear cached completion text
	state.cached_completion = nil
	-- Clear stored cursor position
	state.cursor_position = nil
end

-- Set ghost text at cursor
function M.set_ghost_text(text)
	-- Only show ghost text in insert mode
	if vim.api.nvim_get_mode().mode ~= "i" then
		return
	end

	local state = get_buf_state()
	M.clear_ghost_text()

	if not text or text == "" or type(text) ~= "string" then
		return
	end

	state.cached_completion = text

	local cursor = vim.api.nvim_win_get_cursor(0)
	if not cursor or #cursor < 2 then
		return
	end
	local row, col = cursor[1] - 1, cursor[2]
	state.cursor_position = { row = row, col = col }

	local ns_id = vim.api.nvim_create_namespace("turbo-needle-ghost")

	if text:find("\n") then
		-- Hybrid: first line inline, remaining lines as virt_lines
		local lines = vim.split(text, "\n", { plain = true })
		if #lines == 0 then
			return
		end

		local max_lines = 10
		if #lines > max_lines then
			lines = vim.list_slice(lines, 1, max_lines)
			lines[#lines] = lines[#lines] .. "..."
		end

		local head = lines[1]
		local tail = {}
		for i = 2, #lines do
			tail[#tail + 1] = lines[i]
		end

		-- Prepare virt_lines for tail with indentation alignment
		local virt_lines = nil
		if #tail > 0 then
			virt_lines = {}
			local current_line = vim.api.nvim_get_current_line()
			local base_indent = (current_line and current_line:match("^%s*")) or ""
			for _, l in ipairs(tail) do
				local display_line = l
				if l:match("^%s*") then
					display_line = base_indent .. l:gsub("^%s*", "")
				end
				if #display_line > 100 then
					display_line = display_line:sub(1, 97) .. "..."
				end
				table.insert(virt_lines, { { display_line, "Comment" } })
			end
		end

		local ok, id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
			virt_text = { { head, "Comment" } }, -- inline first line
			virt_text_pos = "inline",
			virt_lines = virt_lines,
			priority = 4096,
		})
		if not ok then
			utils.notify("Failed to set multi-line hybrid ghost", vim.log.levels.ERROR)
			return
		end
		state.current_extmark = { ns_id = ns_id, id = id }
	else
		local display_text = text
		if #display_text > 100 then
			display_text = display_text:sub(1, 97) .. "..."
		end
		local ok, id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
			virt_text = { { display_text, "Comment" } },
			virt_text_pos = "inline",
			priority = 4096,
		})
		if not ok then
			utils.notify("Failed to set ghost text extmark", vim.log.levels.ERROR)
			return
		end
		state.current_extmark = { ns_id = ns_id, id = id }
	end
end

-- Accept completion: insert ghost text if present, else return tab
function M.accept_completion()
	local state = get_buf_state()
	if state.cached_completion then
		local current_cursor = vim.api.nvim_win_get_cursor(0)
		local current_row, current_col = current_cursor[1] - 1, current_cursor[2]

		if not state.cursor_position
			or state.cursor_position.row ~= current_row
			or state.cursor_position.col ~= current_col
		then
			return "\t"
		end

		local text_to_insert = state.cached_completion
		local lines = vim.split(text_to_insert, "\n", { plain = true })

		-- Instrumentation locals
		local dbg_context = {}

		local insert_ok, insert_err = pcall(function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local cursor_row, cursor_col = cursor[1] - 1, cursor[2]
			dbg_context.cursor_row = cursor_row
			dbg_context.cursor_col = cursor_col

			if #lines == 1 then
				local line_text = vim.api.nvim_get_current_line()
				local line_len = #line_text
				dbg_context.line_len = line_len
				dbg_context.line_text = line_text
				dbg_context.insert_fragment = lines[1]

				local col = cursor_col
				if col >= line_len then
					col = line_len
				elseif col == line_len - 1 then
					col = line_len
				end
				dbg_context.final_col = col

				-- Direct check before inserting
				if col < 0 or col > line_len then
					error(string.format("col_out_of_range col=%d line_len=%d", col, line_len))
				end

				vim.api.nvim_buf_set_text(0, cursor_row, col, cursor_row, col, { lines[1] })
			else
				-- Multi-line path
				local line_text = vim.api.nvim_get_current_line()
				dbg_context.line_text = line_text
				dbg_context.line_len = #line_text
				dbg_context.insert_first = lines[1]
				dbg_context.tail_count = #lines - 1

				local cursor = vim.api.nvim_win_get_cursor(0)
				local cursor_row, cursor_col = cursor[1] - 1, cursor[2]
				local before = line_text:sub(1, cursor_col)
				local after = line_text:sub(cursor_col + 1)
				dbg_context.before = before
				dbg_context.after = after

				local merged_first = before .. lines[1] .. after
				vim.api.nvim_buf_set_lines(0, cursor_row, cursor_row + 1, false, { merged_first })

				if #lines > 1 then
					local tail = {}
					for i = 2, #lines do
						tail[#tail + 1] = lines[i]
					end
					vim.api.nvim_buf_set_lines(0, cursor_row + 1, cursor_row + 1, false, tail)
				end
			end
		end)

		if insert_ok then
			M.clear_ghost_text()
			return ""
		else
			local err_msg = tostring(insert_err)
			-- Handle textlock (E565) by scheduling the insertion
			if err_msg:match("E565") then
				local cached = state.cached_completion
				local stored_pos = state.cursor_position and { row = state.cursor_position.row, col = state.cursor_position.col }
				local lines_copy = vim.split(cached or "", "\n", { plain = true })
				vim.schedule(function()
					-- Revalidate state & cursor
					if not cached or not stored_pos then return end
					local cur = vim.api.nvim_win_get_cursor(0)
					local row = cur[1] - 1
					local col = cur[2]
					if row ~= stored_pos.row then return end
					if #lines_copy == 1 then
						local line_text = vim.api.nvim_get_current_line()
						local line_len = #line_text
						if col > line_len then col = line_len end
						if col == line_len - 1 then col = line_len end
						pcall(vim.api.nvim_buf_set_text, 0, row, col, row, col, { lines_copy[1] })
					else
						local line_text = vim.api.nvim_get_current_line()
						local before = line_text:sub(1, col)
						local after = line_text:sub(col + 1)
						local merged_first = before .. lines_copy[1] .. after
						local ok1 = pcall(vim.api.nvim_buf_set_lines, 0, row, row + 1, false, { merged_first })
						if ok1 and #lines_copy > 1 then
							local tail = {}
							for i = 2, #lines_copy do tail[#tail + 1] = lines_copy[i] end
							pcall(vim.api.nvim_buf_set_lines, 0, row + 1, row + 1, false, tail)
						end
					end
					M.clear_ghost_text()
				end)
				-- Do not treat as failure for user; insertion is pending
				return ""
			end

			utils.notify(
				string.format(
					"Insertion error: %s | ctx=%s",
					err_msg,
					vim.inspect(dbg_context)
				),
				vim.log.levels.ERROR
			)
			return "\t"
		end
	end
	return "\t"
end

-- Metatable for read-only 'enabled' property
local mt = {
	__index = function(t, k)
		if k == "enabled" then
			return enabled -- Return the private enabled value
		end
		return rawget(t, k) -- Normal table access for other keys
	end,
	__newindex = function(t, k, v)
		if k == "enabled" then
			error("Cannot set 'enabled' directly. Use enable() or disable() functions.", 2)
		end
		rawset(t, k, v) -- Normal table assignment for other keys
	end,
}

return setmetatable(M, mt)
