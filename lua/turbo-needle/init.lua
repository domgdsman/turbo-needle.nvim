local config = require("turbo-needle.config")
local cache = require("turbo-needle.cache")
local cleanup = require("turbo-needle.cleanup")
local edit = require("turbo-needle.edit")
local logger = require("turbo-needle.logger")
local state_store = require("turbo-needle.state")
local version = require("turbo-needle.version")

local M = {}
M.version = version.version
M._VERSION = version.version

local TurboNeedle = {
	augroup = "turbo-needle",
}

-- Module-scoped enabled state (private)
local enabled = true

-- Completion cache
local completion_cache = cache.new({ max_size = 50, ttl_ms = 2000 })

-- Buffer-local state
M._buf_states = {}
local function get_buf_state()
	return state_store.get(M._buf_states)
end

-- Private config storage
local _config = config.defaults
local current_accept_keymap = nil

-- Public getter for config
function M.get_config()
	return vim.deepcopy(_config)
end

function M.setup(opts)
	local next_config = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), opts or {})

	-- Substitute environment variables in config
	local config_module = require("turbo-needle.config")
	local success, err = pcall(config_module.substitute_config_values_from_env, next_config)
	if not success then
		logger.error("Configuration substitution failed: " .. err)
		return
	end

	-- Validate configuration after substitution
	success, err = pcall(config_module.validate, next_config)
	if not success then
		logger.error("Configuration validation failed: " .. err)
		return
	end

	_config = next_config

	-- Set up logging
	logger.setup(M.get_config().logging)

	-- Setup completion triggering
	M.setup_completion_trigger()

	-- Setup keymaps
	M.setup_keymaps()

	logger.info("setup complete")
end

function M.setup_keymaps()
	if current_accept_keymap then
		pcall(vim.keymap.del, "i", current_accept_keymap)
		current_accept_keymap = nil
	end

	if _config.keymaps.accept and _config.keymaps.accept ~= "" then
		vim.keymap.set("i", _config.keymaps.accept, function()
			return M.accept_completion()
		end, { expr = true, desc = "turbo-needle: accept completion" })
		current_accept_keymap = _config.keymaps.accept
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

		if state.debounce_timer then
			cleanup.stop_timer(state.debounce_timer)
			state.debounce_timer = nil
		end

		cleanup.invalidate_request(state)

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
						cleanup.stop_timer(timer)
					end
				end
			end)
		)
	end

	vim.api.nvim_create_augroup(TurboNeedle.augroup, { clear = true })

	-- Clear timer, cancel requests, and ghost text on buffer leave
	vim.api.nvim_create_autocmd("BufLeave", {
		group = TurboNeedle.augroup,
		callback = function()
			local state = get_buf_state()
			cleanup.cleanup_state(state)
			M.clear_ghost_text()
		end,
	})

	-- Clean up buffer state when buffer is deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		group = TurboNeedle.augroup,
		callback = function(args)
			local bufnr = args.buf
			if M._buf_states and M._buf_states[bufnr] then
				local buf_state = M._buf_states[bufnr]
				cleanup.cleanup_state(buf_state)
				state_store.delete(M._buf_states, bufnr)
			end
		end,
	})

	-- Clean up old buffer states periodically to prevent memory leak
	vim.api.nvim_create_autocmd("BufEnter", {
		group = TurboNeedle.augroup,
		callback = vim.schedule_wrap(function()
			if M._buf_states then
				local valid_bufs = state_store.valid_buffers()
				for bufnr, _ in pairs(M._buf_states) do
					if not valid_bufs[bufnr] then
						local buf_state = M._buf_states[bufnr]
						if buf_state then
							cleanup.cleanup_state(buf_state)
						end
						state_store.delete(M._buf_states, bufnr)
					end
				end
			end
		end),
	})

	-- Trigger on insert leave and cursor moved in insert
	vim.api.nvim_create_autocmd({ "InsertLeave", "CursorMovedI" }, {
		group = TurboNeedle.augroup,
		callback = trigger_completion,
	})
end

-- Enable completions
function M.enable()
	enabled = true
	logger.info("completions enabled")
end

-- Disable completions
function M.disable()
	enabled = false
	logger.info("completions disabled")
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
	local cached_completion = completion_cache:get(ctx)
	if cached_completion then
		M.set_ghost_text(cached_completion)
		return
	end

	-- Cancel any existing job before starting a new request
	if state.active_job then
		cleanup.shutdown_job(state.active_job)
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
				logger.error("Completion error: " .. err)
				return
			end

			-- Parse the completion text from API response
			local completion_text = api.parse_response(result)

			-- Cache the valid completion
			completion_cache:set(ctx, completion_text)

			-- Set ghost text for the completion
			M.set_ghost_text(completion_text)
		end),
		_config.api.api_key
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
				logger.warn("Failed to clear ghost text extmark")
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
			logger.error("Failed to set multi-line hybrid ghost")
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
			logger.error("Failed to set ghost text extmark")
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

		if
			not state.cursor_position
			or state.cursor_position.row ~= current_row
			or state.cursor_position.col ~= current_col
		then
			return "\t"
		end

		-- Store current state for scheduled insertion
		local cached = state.cached_completion
		local stored_pos = state.cursor_position
			and { row = state.cursor_position.row, col = state.cursor_position.col }
		-- Schedule the insertion to avoid textlock
		vim.schedule(function()
			local sched_final = edit.insert_at_cursor(cached, stored_pos)
			M.clear_ghost_text()
			if sched_final then
				pcall(vim.api.nvim_win_set_cursor, 0, { sched_final.row + 1, sched_final.col })
			end
		end)

		return ""
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
