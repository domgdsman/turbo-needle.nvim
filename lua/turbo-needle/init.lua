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

		-- Start new timer
		state.debounce_timer = vim.defer_fn(function()
			M.complete()
			state.debounce_timer = nil
		end, debounce_delay)
	end

	-- Clear timer and ghost text on buffer leave
	vim.api.nvim_create_autocmd("BufLeave", {
		callback = function()
			local state = get_buf_state()
			if state.debounce_timer then
				state.debounce_timer:stop()
				state.debounce_timer = nil
			end
			M.clear_ghost_text()
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

	api.get_completion({ prefix = ctx.prefix, suffix = ctx.suffix }, function(err, result)
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
		vim.api.nvim_buf_del_extmark(0, state.current_extmark.ns_id, state.current_extmark.id)
		state.current_extmark = nil
	end
end

-- Set ghost text at cursor
function M.set_ghost_text(text)
	local state = get_buf_state()
	M.clear_ghost_text()
	if text and text ~= "" then
		local ns_id = vim.api.nvim_create_namespace("turbo-needle-ghost")
		local cursor = vim.api.nvim_win_get_cursor(0)
		local row, col = cursor[1] - 1, cursor[2] -- 0-based
		local extmark_id = vim.api.nvim_buf_set_extmark(0, ns_id, row, col, {
			virt_text = { { text, "Comment" } },
			virt_text_pos = "inline",
		})
		state.current_extmark = { ns_id = ns_id, id = extmark_id }
	end
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
			-- Validate text before insertion
			if not text or text == "" or type(text) ~= "string" then
				utils.notify("Invalid ghost text format", vim.log.levels.ERROR)
				M.clear_ghost_text()
				return "\t" -- Fall back to inserting tab
			end
			-- Insert text at cursor
			vim.api.nvim_put({ text }, "c", false, true)
			M.clear_ghost_text()
			return "" -- Don't insert tab
		end
	end
	-- No ghost text, insert tab
	return "\t"
end

return M
