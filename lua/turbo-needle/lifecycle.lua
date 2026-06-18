local cleanup = require("turbo-needle.cleanup")
local state_store = require("turbo-needle.state")

local M = {}

local augroup = "turbo-needle"

function M.setup(opts)
	local debounce_delay = opts.config.completions.debounce_ms
	local states = opts.states
	local get_state = opts.get_state
	local complete = opts.complete
	local clear_ghost = opts.clear_ghost
	local sync_ghost = opts.sync_ghost
	local is_enabled = opts.is_enabled

	local function trigger_completion()
		if not is_enabled() then
			return
		end

		local state = get_state()
		if sync_ghost and sync_ghost() then
			return
		end

		clear_ghost()

		if state.debounce_timer then
			cleanup.stop_timer(state.debounce_timer)
			state.debounce_timer = nil
		end

		cleanup.invalidate_request(state)

		local timer = vim.loop.new_timer()
		state.debounce_timer = timer

		timer:start(
			debounce_delay,
			0,
			vim.schedule_wrap(function()
				if state.debounce_timer == timer then
					complete()
					state.debounce_timer = nil
					if timer then
						cleanup.stop_timer(timer)
					end
				end
			end)
		)
	end

	vim.api.nvim_create_augroup(augroup, { clear = true })

	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		callback = function()
			local state = get_state()
			cleanup.cleanup_state(state)
			clear_ghost()
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		group = augroup,
		callback = function(args)
			local bufnr = args.buf
			if states and states[bufnr] then
				local buf_state = states[bufnr]
				cleanup.cleanup_state(buf_state)
				state_store.delete(states, bufnr)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,
		callback = vim.schedule_wrap(function()
			if states then
				local valid_bufs = state_store.valid_buffers()
				for bufnr, _ in pairs(states) do
					if not valid_bufs[bufnr] then
						local buf_state = states[bufnr]
						if buf_state then
							cleanup.cleanup_state(buf_state)
						end
						state_store.delete(states, bufnr)
					end
				end
			end
		end),
	})

	vim.api.nvim_create_autocmd({ "InsertLeave", "CursorMovedI" }, {
		group = augroup,
		callback = trigger_completion,
	})
end

return M
