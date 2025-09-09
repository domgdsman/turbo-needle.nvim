local config = require("turbo-needle.config")
local utils = require("turbo-needle.utils")

local M = {}

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

		-- Validate completion text
		if not completion_text or completion_text == "" then
			utils.notify("Received empty completion from API", vim.log.levels.WARN)
			return
		end

		-- Ensure completion_text is a string
		if type(completion_text) ~= "string" then
			utils.notify("Invalid completion format received from API", vim.log.levels.ERROR)
			return
		end

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

	-- Create namespace and set extmark
	local ns_id = vim.api.nvim_create_namespace("turbo-needle-ghost")
	local extmark_id = vim.api.nvim_buf_set_extmark(0, ns_id, row, col, {
		virt_text = { { text, "Comment" } },
		virt_text_pos = "inline",
	})

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

	state.current_extmark = { ns_id = ns_id, id = extmark_id }
end

-- Accept completion: insert ghost text if present, else return tab
function M.accept_completion()
	local state = get_buf_state()
	if state.current_extmark then
		-- Get the virt_text from extmark
		local extmark = vim.api.nvim_buf_get_extmark_by_id(
			0,
			state.current_extmark.ns_id,
			state.current_extmark.id,
			{ details = true }
		)
		if extmark and extmark[3] and extmark[3].virt_text then
			local text = extmark[3].virt_text[1][1]
			if text and text ~= "" then
				vim.api.nvim_put({ text }, "c", false, true)
				M.clear_ghost_text()
				return "" -- Don't insert tab
			end
		end
	end
	-- No ghost text, insert tab
	return "\t"
end

return M
