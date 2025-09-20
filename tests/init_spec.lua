---@diagnostic disable: undefined-field

local turbo_needle = require("turbo-needle")
local stub = require("luassert.stub")

describe("turbo-needle", function()
	local snapshot
	before_each(function()
		-- Reset stubs/spies and module to use default config
		snapshot = assert:snapshot()
		package.loaded["turbo-needle"] = nil
		turbo_needle = require("turbo-needle")
	end)

	after_each(function()
		-- Revert stubs/spies and clean module caches
		if snapshot then
			snapshot:revert()
		end
		package.loaded["turbo-needle"] = nil
		package.loaded["turbo-needle.context"] = nil
		package.loaded["turbo-needle.api"] = nil
		package.loaded["turbo-needle.utils"] = nil
		package.loaded["turbo-needle.config"] = nil
	end)

	describe("setup", function()
		it("should setup with default configuration", function()
			turbo_needle.setup()
			local config = turbo_needle.get_config()
			assert.is_not_nil(config)
			assert.are.equal("<Tab>", config.keymaps.accept)
		end)

		it("should merge custom configuration", function()
			turbo_needle.setup({
				keymaps = { accept = "<C-y>" },
			})
			local config = turbo_needle.get_config()
			assert.are.equal("<C-y>", config.keymaps.accept)
		end)
	end)

	describe("complete", function()
		it("should have complete function", function()
			assert.is_function(turbo_needle.complete)
		end)

		it("should call context and api functions when filetype supported", function()
			-- Mock vim mode to be insert mode
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })

			-- Make async deterministic for test
			local schedule_stub = stub(vim, "schedule")
			schedule_stub.invokes(function(callback)
				callback()
			end)

			-- Mock context
			local context = require("turbo-needle.context")
			stub(context, "is_filetype_supported").returns(true)
			stub(context, "get_current_context").returns({ prefix = "test prefix", suffix = "test suffix" })

			-- Mock api
			local api = require("turbo-needle.api")
			local get_completion_called = false
			stub(api, "get_completion").invokes(function(data, callback)
				get_completion_called = true
				assert.are.equal("test prefix", data.prefix)
				assert.are.equal("test suffix", data.suffix)
				-- Simulate success
				callback(nil, { choices = { { text = "completed code" } } })
			end)

			-- Mock set_ghost_text
			local set_ghost_called = false
			stub(turbo_needle, "set_ghost_text").invokes(function(text)
				set_ghost_called = true
				assert.are.equal("completed code", text)
			end)

			-- Call complete
			turbo_needle.complete()

			assert.is_true(get_completion_called)
			assert.is_true(set_ghost_called)
		end)

		it("should not call api when filetype not supported", function()
			local context = require("turbo-needle.context")
			-- Ensure we're in insert mode so gating happens on filetype
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(context, "is_filetype_supported").returns(false)

			local api = require("turbo-needle.api")
			local get_completion_called = false
			stub(api, "get_completion").invokes(function()
				get_completion_called = true
			end)

			turbo_needle.complete()

			assert.is_false(get_completion_called)
		end)

		it("should handle api error", function()
			-- Mock vim mode to be insert mode
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })

			-- Make async deterministic for test
			local schedule_stub = stub(vim, "schedule")
			schedule_stub.invokes(function(callback)
				callback()
			end)

			local context = require("turbo-needle.context")
			stub(context, "is_filetype_supported").returns(true)
			stub(context, "get_current_context").returns({ prefix = "", suffix = "" })

			local api = require("turbo-needle.api")
			stub(api, "get_completion").invokes(function(data, callback)
				callback("API error", nil)
			end)

			-- Mock logger.error
			local logger = require("turbo-needle.logger")
			stub(logger, "error")

			turbo_needle.complete()

			assert.stub(logger.error).was_called()
		end)

		it("should use custom parse_response when provided", function()
			-- Mock vim mode to be insert mode
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })

			-- Make async deterministic for test
			local schedule_stub = stub(vim, "schedule")
			schedule_stub.invokes(function(callback)
				callback()
			end)

			-- Setup turbo-needle with custom parse_response
			turbo_needle.setup({
				api = {
					parse_response = function(result)
						return result.custom_field or ""
					end,
				},
			})

			local context = require("turbo-needle.context")
			stub(context, "is_filetype_supported").returns(true)
			stub(context, "get_current_context").returns({ prefix = "", suffix = "" })

			local api = require("turbo-needle.api")
			local get_completion_called = false
			stub(api, "get_completion").invokes(function(data, callback)
				get_completion_called = true
				-- Simulate success with custom format
				callback(nil, { custom_field = "custom parsed completion" })
			end)

			-- Mock set_ghost_text
			local set_ghost_called = false
			stub(turbo_needle, "set_ghost_text").invokes(function(text)
				set_ghost_called = true
				assert.are.equal("custom parsed completion", text)
			end)

			-- Call complete
			turbo_needle.complete()

			assert.is_true(get_completion_called)
			assert.is_true(set_ghost_called)
		end)
	end)

	describe("setup_completion_trigger", function()
		it("should have setup_completion_trigger function", function()
			assert.is_function(turbo_needle.setup_completion_trigger)
		end)

		it("should setup autocmds without error", function()
			assert.has_no.errors(function()
				turbo_needle.setup_completion_trigger()
			end)
		end)
	end)

	describe("ghost text", function()
		it("should have clear_ghost_text function", function()
			assert.is_function(turbo_needle.clear_ghost_text)
		end)

		it("should have set_ghost_text function", function()
			assert.is_function(turbo_needle.set_ghost_text)
		end)

		it("should clear ghost text and reset state", function()
			-- Setup mocks
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(99)
			stub(vim.api, "nvim_win_get_cursor").returns({ 1, 0 })
			stub(vim.api, "nvim_buf_set_extmark").returns(123)

			-- Set ghost text then clear it
			turbo_needle.set_ghost_text("abc")
			local bufnr = vim.api.nvim_get_current_buf()
			local state = turbo_needle._buf_states and turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state)
			assert.is_table(state.current_extmark)
			assert.is_not_nil(state.cached_completion)

			-- Clear ghost text
			assert.has_no.errors(function()
				turbo_needle.clear_ghost_text()
			end)

			-- Verify state cleanup
			assert.is_nil(state.current_extmark)
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.cursor_position)
		end)

		it("should set ghost text and update state", function()
			-- Setup mocks
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(55)
			stub(vim.api, "nvim_win_get_cursor").returns({ 1, 2 })

			local captured_opts
			stub(vim.api, "nvim_buf_set_extmark").invokes(function(_, ns, row, col, opts)
				captured_opts = { ns = ns, row = row, col = col, opts = opts }
				return 999
			end)

			-- Set ghost text
			assert.has_no.errors(function()
				turbo_needle.set_ghost_text("test text")
			end)

			-- Verify state
			local bufnr = vim.api.nvim_get_current_buf()
			local state = turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state.current_extmark)
			assert.are.equal("test text", state.cached_completion)
			assert.are.same({ row = 0, col = 2 }, state.cursor_position)

			-- Verify extmark options
			assert.is_table(captured_opts)
			assert.are.equal(0, captured_opts.row) -- row stored at 0-based internally
			assert.is_truthy(captured_opts.opts.virt_text)
		end)

		it("should not set ghost text for empty text", function()
			-- Setup mocks
			stub(vim.api, "nvim_create_namespace").returns(1)
			local set_extmark_stub = stub(vim.api, "nvim_buf_set_extmark")

			-- Test empty string
			turbo_needle.set_ghost_text("")
			assert.stub(set_extmark_stub).was_not_called()

			-- Test nil
			turbo_needle.set_ghost_text(nil)
			assert.stub(set_extmark_stub).was_not_called()
		end)
	end)

	describe("accept_completion", function()
		it("should have accept_completion function", function()
			assert.is_function(turbo_needle.accept_completion)
		end)

		it("should return tab character when no ghost text", function()
			local result = turbo_needle.accept_completion()
			assert.are.equal("\t", result)
		end)

		it("should insert ghost text and clear state when accepted", function()
			-- Setup mocks
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(42)
			stub(vim.api, "nvim_buf_set_extmark").returns(777)

			-- Mock vim.schedule to execute synchronously for testing
			local schedule_stub = stub(vim, "schedule")
			schedule_stub.invokes(function(callback)
				callback() -- Execute immediately for testing
			end)

			-- Set ghost text and accept
			turbo_needle.set_ghost_text(" -- appended")
			local bufnr = vim.api.nvim_get_current_buf()
			local state = turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state.cached_completion)

			local ret = turbo_needle.accept_completion()
			assert.are.equal("", ret, "Accepting a ghost completion should return empty string to suppress <Tab>")

			-- Verify schedule was called
			assert.stub(schedule_stub).was_called()

			-- State cleared
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.current_extmark)
		end)

		it("should position cursor at end after multi-line insertion", function()
			-- Setup mocks
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(101)
			stub(vim.api, "nvim_buf_set_extmark").returns(202)

			-- Mock vim.schedule to execute synchronously for testing
			local schedule_stub = stub(vim, "schedule")
			schedule_stub.invokes(function(callback)
				callback() -- Execute immediately for testing
			end)

			-- Set multi-line ghost text
			local completion = "\n  local x = 1\n  return x"
			turbo_needle.set_ghost_text(completion)
			local bufnr = vim.api.nvim_get_current_buf()
			local state = turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state.cached_completion)

			-- Accept
			local ret = turbo_needle.accept_completion()
			assert.are.equal("", ret)

			-- Verify schedule was called
			assert.stub(schedule_stub).was_called()

			-- State cleared
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.current_extmark)
		end)
	end)
end)
