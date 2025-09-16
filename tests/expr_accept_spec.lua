---@diagnostic disable: undefined-field

local turbo_needle = require("turbo-needle")
local stub = require("luassert.stub")
local async = require("plenary.async")

-- This test simulates an <expr> mapping acceptance where direct text edits
-- would normally raise E565 (textlock) inside the mapping evaluation.
-- We rely on the asynchronous fallback (vim.schedule) path in accept_completion.

async.tests.describe("turbo-needle expr mapping acceptance", function()
	async.tests.before_each(function()
		package.loaded["turbo-needle"] = nil
		turbo_needle = require("turbo-needle")
	end)

	async.tests.it("should schedule insertion when accept called in expr context", async.void(function()
		turbo_needle.setup()

		-- Create buffer first (real buffer for testing)
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(bufnr)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })
		vim.api.nvim_win_set_cursor(0, { 1, #"local x = 1" })

		-- Use targeted stubbing instead of full mock
		stub(vim.api, "nvim_get_mode")
		vim.api.nvim_get_mode.returns({ mode = "i" })

		stub(vim.api, "nvim_create_namespace")
		vim.api.nvim_create_namespace.returns(2025)

		stub(vim.api, "nvim_buf_set_extmark")
		vim.api.nvim_buf_set_extmark.returns(8080)

		-- Mock buffer operations that need to work with real buffer
		stub(vim.api, "nvim_buf_get_lines")
		local buffer_lines = { "local x = 1" }
		local ghost_text_inserted = false
		vim.api.nvim_buf_get_lines.invokes(function(buf, start, end_, strict)
			if buf == bufnr and start == 0 and end_ == 1 then
				-- Return updated content if ghost text was inserted
				if ghost_text_inserted then
					return { "local x = 1 -- appended_expr" }
				end
				return buffer_lines
			end
			return vim.api.nvim_buf_get_lines(buf, start, end_, strict)
		end)

		-- Override set_ghost_text to control ghost text state
		local set_ghost_called = false
		local set_ghost_text_arg = nil
		local original_set_ghost = turbo_needle.set_ghost_text
		turbo_needle.set_ghost_text = function(text)
			set_ghost_called = true
			set_ghost_text_arg = text
			ghost_text_inserted = true
			-- Simulate setting ghost text state
			turbo_needle._buf_states = turbo_needle._buf_states or {}
			turbo_needle._buf_states[bufnr] = {
				cached_completion = text,
				current_extmark = { ns_id = 2025, id = 8080 },
				cursor_position = { row = 0, col = #"local x = 1" },
			}
			return original_set_ghost(text)
		end

		stub(vim.api, "nvim_win_get_cursor")
		local cursor_position = { 1, #"local x = 1" }
		local cursor_updated = false
		vim.api.nvim_win_get_cursor.invokes(function()
			if cursor_updated then
				return { 1, #"local x = 1 -- appended_expr" - 1 }
			end
			return cursor_position
		end)

		stub(vim.api, "nvim_win_set_cursor")
		vim.api.nvim_win_set_cursor.invokes(function()
			cursor_updated = true
			return true
		end)

		-- Provide ghost text
		turbo_needle.set_ghost_text(" -- appended_expr")
		local state = turbo_needle._buf_states[bufnr]
		assert.is_not_nil(state.cached_completion)

		-- Use plenary.async for clean async testing
		local schedule_called = false
		local original_schedule = vim.schedule

		-- Create a promise-like mechanism for async completion
		local async_completed = false
		vim.schedule = function(callback)
			schedule_called = true
			-- Execute callback in next tick
			vim.defer_fn(function()
				callback()
				async_completed = true
			end, 1)
		end

		-- Simulate expr mapping invocation
		local ret = turbo_needle.accept_completion()
		assert.are.equal("", ret) -- should suppress Tab

		-- Wait for async operation to complete
		while not async_completed do
			async.util.sleep(1)
		end

		assert.is_true(schedule_called, "vim.schedule should have been called")

		local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
		assert.are.equal("local x = 1 -- appended_expr", line)
		local cur = vim.api.nvim_win_get_cursor(0)
		assert.are.equal(1, cur[1])
		assert.are.equal(#"local x = 1 -- appended_expr" - 1, cur[2])
		assert.is_nil(state.cached_completion)
		assert.is_nil(state.current_extmark)

		-- Verify the mocked functions were called with correct arguments
		assert.stub(vim.api.nvim_get_mode).was_called()
		assert.stub(vim.api.nvim_create_namespace).was_called()
		assert.stub(vim.api.nvim_buf_set_extmark).was_called()
		assert.is_true(set_ghost_called, "set_ghost_text should have been called")
		assert.are.equal(
			" -- appended_expr",
			set_ghost_text_arg,
			"set_ghost_text should have been called with correct argument"
		)

		-- Restore vim.schedule
		vim.schedule = original_schedule

		-- Cleanup
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end))
end)
