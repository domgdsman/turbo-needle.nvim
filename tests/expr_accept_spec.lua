---@diagnostic disable: undefined-field

local turbo_needle = require("turbo-needle")
local async = require("plenary.async")
local stub = require("luassert.stub")

-- Helper: Setup test buffer with initial content
local function setup_test_buffer()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })
	vim.api.nvim_win_set_cursor(0, { 1, #"local x = 1" })
	return bufnr
end

-- Helper: Setup minimal mocks needed for the test
local function setup_minimal_mocks(bufnr)
	-- Only mock what's actually tested
	stub(vim.api, "nvim_get_mode").returns({ mode = "i" })

	-- Mock buffer operations with state tracking
	local ghost_text_inserted = false
	stub(vim.api, "nvim_buf_get_lines").invokes(function(buf, start, end_, strict)
		if buf == bufnr and start == 0 and end_ == 1 then
			return ghost_text_inserted and { "local x = 1 -- appended_expr" } or { "local x = 1" }
		end
		return vim.api.nvim_buf_get_lines(buf, start, end_, strict)
	end)

	-- Mock cursor operations
	local cursor_updated = false
	stub(vim.api, "nvim_win_get_cursor").invokes(function()
		return cursor_updated and { 1, #"local x = 1 -- appended_expr" - 1 } or { 1, #"local x = 1" }
	end)

	stub(vim.api, "nvim_win_set_cursor").invokes(function()
		cursor_updated = true
		return true
	end)
end

-- Helper: Setup ghost text with spy
local function setup_ghost_text_spy(bufnr)
	-- Use a stub that both records calls and implements behavior
	local set_ghost_stub = stub(turbo_needle, "set_ghost_text")
	set_ghost_stub.invokes(function(text)
		-- Simulate setting ghost text state
		turbo_needle._buf_states = turbo_needle._buf_states or {}
		turbo_needle._buf_states[bufnr] = {
			cached_completion = text,
			current_extmark = { ns_id = 2025, id = 8080 },
			cursor_position = { row = 0, col = #"local x = 1" },
		}
		return true -- Mock return value
	end)
	return set_ghost_stub
end

-- Helper: Test async schedule behavior
local function test_async_schedule()
	local schedule_stub = stub(vim, "schedule")
	local async_completed = false

	schedule_stub.invokes(function(callback)
		vim.defer_fn(function()
			callback()
			async_completed = true
		end, 1)
	end)

	return {
		schedule_stub = function()
			return schedule_stub
		end,
		async_completed = function()
			return async_completed
		end,
		wait_completion = function()
			while not async_completed do
				async.util.sleep(1)
			end
		end,
		-- no manual restore; after_each will revert
	}
end

-- This test simulates an <expr> mapping acceptance where direct text edits
-- would normally raise E565 (textlock) inside the mapping evaluation.
-- We rely on the asynchronous fallback (vim.schedule) path in accept_completion.

async.tests.describe("turbo-needle expr mapping acceptance", function()
	async.tests.before_each(function()
		package.loaded["turbo-needle"] = nil
		turbo_needle = require("turbo-needle")
		_G.__snapshot = assert:snapshot()
	end)

	async.tests.after_each(function()
		if _G.__snapshot then
			_G.__snapshot:revert()
		end
		package.loaded["turbo-needle"] = nil
		package.loaded["turbo-needle.context"] = nil
		package.loaded["turbo-needle.api"] = nil
		package.loaded["turbo-needle.utils"] = nil
		package.loaded["turbo-needle.config"] = nil
	end)

	async.tests.it(
		"should schedule insertion when accept called in expr context",
		async.void(function()
			turbo_needle.setup()

			-- Setup: Create buffer and mocks
			local bufnr = setup_test_buffer()
			setup_minimal_mocks(bufnr)
			local set_ghost_stub = setup_ghost_text_spy(bufnr)

			-- Setup: Provide ghost text
			turbo_needle.set_ghost_text(" -- appended_expr")
			local state = turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state.cached_completion)

			-- Test: Async schedule behavior
			local async_test = test_async_schedule()

			-- Execute: Simulate expr mapping invocation
			local ret = turbo_needle.accept_completion()
			assert.are.equal("", ret) -- should suppress Tab

			-- Wait: For async operation to complete
			async_test.wait_completion()

			-- Assert: Schedule behavior
			assert.stub(async_test.schedule_stub()).was_called()

			-- Assert: Buffer state after completion
			local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
			assert.are.equal("local x = 1 -- appended_expr", line)

			local cur = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(1, cur[1])
			assert.are.equal(#"local x = 1 -- appended_expr" - 1, cur[2])

			-- Assert: State cleanup
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.current_extmark)

			-- Assert: Function calls
			assert.stub(vim.api.nvim_get_mode).was_called()
			assert.stub(set_ghost_stub).was_called_with(" -- appended_expr")

			-- Cleanup handled by after_each
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	)
end)
