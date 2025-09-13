local turbo_needle = require("turbo-needle")

describe("turbo-needle", function()
	before_each(function()
		-- Reset the module to use default config
		package.loaded["turbo-needle"] = nil
		turbo_needle = require("turbo-needle")
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
			local original_get_mode = vim.api.nvim_get_mode
			vim.api.nvim_get_mode = function()
				return { mode = "i" }
			end

			-- Mock context
			local context = require("turbo-needle.context")
			local original_is_supported = context.is_filetype_supported
			local original_get_context = context.get_current_context
			context.is_filetype_supported = function()
				return true
			end
			context.get_current_context = function()
				return { prefix = "test prefix", suffix = "test suffix" }
			end

			-- Mock api
			local api = require("turbo-needle.api")
			local original_get_completion = api.get_completion
			local get_completion_called = false
			api.get_completion = function(data, callback)
				get_completion_called = true
				assert.are.equal("test prefix", data.prefix)
				assert.are.equal("test suffix", data.suffix)
				-- Simulate success
				callback(nil, { choices = { { text = "completed code" } } })
			end

			-- Mock set_ghost_text
			local original_set_ghost = turbo_needle.set_ghost_text
			local set_ghost_called = false
			turbo_needle.set_ghost_text = function(text)
				set_ghost_called = true
				assert.are.equal("completed code", text)
			end

			-- Call complete
			turbo_needle.complete()

			-- Wait for async callbacks to complete
			vim.wait(100)

			-- Restore mocks
			vim.api.nvim_get_mode = original_get_mode
			context.is_filetype_supported = original_is_supported
			context.get_current_context = original_get_context
			api.get_completion = original_get_completion
			turbo_needle.set_ghost_text = original_set_ghost

			assert.is_true(get_completion_called)
			assert.is_true(set_ghost_called)
		end)

		it("should not call api when filetype not supported", function()
			local context = require("turbo-needle.context")
			local original_is_supported = context.is_filetype_supported
			context.is_filetype_supported = function()
				return false
			end

			local api = require("turbo-needle.api")
			local original_get_completion = api.get_completion
			local get_completion_called = false
			api.get_completion = function()
				get_completion_called = true
			end

			turbo_needle.complete()

			context.is_filetype_supported = original_is_supported
			api.get_completion = original_get_completion

			assert.is_false(get_completion_called)
		end)

		it("should handle api error", function()
			-- Mock vim mode to be insert mode
			local original_get_mode = vim.api.nvim_get_mode
			vim.api.nvim_get_mode = function()
				return { mode = "i" }
			end

			local context = require("turbo-needle.context")
			local original_is_supported = context.is_filetype_supported
			local original_get_context = context.get_current_context
			context.is_filetype_supported = function()
				return true
			end
			context.get_current_context = function()
				return { prefix = "", suffix = "" }
			end

			local api = require("turbo-needle.api")
			local original_get_completion = api.get_completion
			api.get_completion = function(data, callback)
				callback("API error", nil)
			end

			local utils = require("turbo-needle.utils")
			local original_notify = utils.notify
			local notify_called = false
			utils.notify = function(msg, level)
				notify_called = true
				assert.is_not_nil(string.find(msg, "API error"))
				assert.are.equal(level, vim.log.levels.ERROR)
			end

			turbo_needle.complete()

			-- Wait for async callbacks to complete
			vim.wait(100)

			vim.api.nvim_get_mode = original_get_mode
			context.is_filetype_supported = original_is_supported
			context.get_current_context = original_get_context
			api.get_completion = original_get_completion
			utils.notify = original_notify

			assert.is_true(notify_called)
		end)

		it("should use custom parse_response when provided", function()
			-- Mock vim mode to be insert mode
			local original_get_mode = vim.api.nvim_get_mode
			vim.api.nvim_get_mode = function()
				return { mode = "i" }
			end

			-- Setup turbo-needle with custom parse_response
			turbo_needle.setup({
				api = {
					parse_response = function(result)
						return result.custom_field or ""
					end,
				},
			})

			local context = require("turbo-needle.context")
			local original_is_supported = context.is_filetype_supported
			local original_get_context = context.get_current_context
			context.is_filetype_supported = function()
				return true
			end
			context.get_current_context = function()
				return { prefix = "", suffix = "" }
			end

			local api = require("turbo-needle.api")
			local original_get_completion = api.get_completion
			local get_completion_called = false
			api.get_completion = function(data, callback)
				get_completion_called = true
				-- Simulate success with custom format
				callback(nil, { custom_field = "custom parsed completion" })
			end

			-- Mock set_ghost_text
			local original_set_ghost = turbo_needle.set_ghost_text
			local set_ghost_called = false
			turbo_needle.set_ghost_text = function(text)
				set_ghost_called = true
				assert.are.equal("custom parsed completion", text)
			end

			-- Call complete
			turbo_needle.complete()

			-- Wait for async callbacks to complete
			vim.wait(100)

			-- Restore mocks
			vim.api.nvim_get_mode = original_get_mode
			context.is_filetype_supported = original_is_supported
			context.get_current_context = original_get_context
			api.get_completion = original_get_completion
			turbo_needle.set_ghost_text = original_set_ghost

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
			-- Prime state by setting ghost text (mock minimal api)
			local original_get_mode = vim.api.nvim_get_mode
			vim.api.nvim_get_mode = function()
				return { mode = "i" }
			end

			-- Mock extmark creation so set_ghost_text succeeds
			local original_create_ns = vim.api.nvim_create_namespace
			local original_win_get_cursor = vim.api.nvim_win_get_cursor
			local original_buf_set_extmark = vim.api.nvim_buf_set_extmark
			vim.api.nvim_create_namespace = function()
				return 99
			end
			vim.api.nvim_win_get_cursor = function()
				return { 1, 0 }
			end
			local fake_extmark_id = 123
			vim.api.nvim_buf_set_extmark = function()
				return fake_extmark_id
			end

			-- Set ghost text then clear it
			turbo_needle.set_ghost_text("abc")
			local bufnr = vim.api.nvim_get_current_buf()
			local state = turbo_needle._buf_states and turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state)
			assert.is_table(state.current_extmark)
			assert.is_not_nil(state.cached_completion)

			-- Mock buf_del_extmark to ensure it is invoked
			local original_buf_del_extmark = vim.api.nvim_buf_del_extmark
			local del_called = false
			vim.api.nvim_buf_del_extmark = function(_, ns, id)
				if ns == state.current_extmark.ns_id and id == state.current_extmark.id then
					del_called = true
				end
				return true
			end

			assert.has_no.errors(function()
				turbo_needle.clear_ghost_text()
			end)
			assert.is_true(del_called)
			assert.is_nil(state.current_extmark)
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.cursor_position)

			-- Restore
			vim.api.nvim_get_mode = original_get_mode
			vim.api.nvim_create_namespace = original_create_ns
			vim.api.nvim_win_get_cursor = original_win_get_cursor
			vim.api.nvim_buf_set_extmark = original_buf_set_extmark
			vim.api.nvim_buf_del_extmark = original_buf_del_extmark
		end)

		it("should set ghost text and update state", function()
			-- Force insert mode
			local original_get_mode = vim.api.nvim_get_mode
			vim.api.nvim_get_mode = function()
				return { mode = "i" }
			end
			-- Mock vim.api functions
			local original_create_ns = vim.api.nvim_create_namespace
			local original_win_get_cursor = vim.api.nvim_win_get_cursor
			local original_buf_set_extmark = vim.api.nvim_buf_set_extmark

			vim.api.nvim_create_namespace = function()
				return 55
			end
			vim.api.nvim_win_get_cursor = function()
				return { 1, 2 }
			end
			local captured_opts
			vim.api.nvim_buf_set_extmark = function(_, ns, row, col, opts)
				captured_opts = { ns = ns, row = row, col = col, opts = opts }
				return 999
			end

			assert.has_no.errors(function()
				turbo_needle.set_ghost_text("test text")
			end)
			local bufnr = vim.api.nvim_get_current_buf()
			local state = turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state.current_extmark)
			assert.are.equal("test text", state.cached_completion)
			assert.are.same({ row = 0, col = 2 }, state.cursor_position)
			assert.is_table(captured_opts)
			assert.are.equal(0, captured_opts.row) -- row stored at 0-based internally
			assert.is_truthy(captured_opts.opts.virt_text)

			-- Restore
			vim.api.nvim_get_mode = original_get_mode
			vim.api.nvim_create_namespace = original_create_ns
			vim.api.nvim_win_get_cursor = original_win_get_cursor
			vim.api.nvim_buf_set_extmark = original_buf_set_extmark
		end)

		it("should not set ghost text for empty text", function()
			local original_create_ns = vim.api.nvim_create_namespace
			vim.api.nvim_create_namespace = function()
				return 1
			end

			local called = false
			local original_buf_set_extmark = vim.api.nvim_buf_set_extmark
			vim.api.nvim_buf_set_extmark = function()
				called = true
			end

			turbo_needle.set_ghost_text("")
			assert.is_false(called)

			turbo_needle.set_ghost_text(nil)
			assert.is_false(called)

			vim.api.nvim_create_namespace = original_create_ns
			vim.api.nvim_buf_set_extmark = original_buf_set_extmark
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
			-- Force insert mode
			local original_get_mode = vim.api.nvim_get_mode
			vim.api.nvim_get_mode = function()
				return { mode = "i" }
			end

			-- Create a scratch buffer to observe inserted text
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })
			-- Place cursor exactly at end of line: col is length of line
			local line = "local x = 1"
			vim.api.nvim_win_set_cursor(0, { 1, #line })

			-- Mock minimal APIs for ghost text
			local original_create_ns = vim.api.nvim_create_namespace
			local original_buf_set_extmark = vim.api.nvim_buf_set_extmark
			vim.api.nvim_create_namespace = function()
				return 42
			end
			vim.api.nvim_buf_set_extmark = function()
				return 777
			end

			-- Set ghost text and accept
			turbo_needle.set_ghost_text(" -- appended")
			local state = turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state.cached_completion)
			local ret = turbo_needle.accept_completion()
			assert.are.equal("", ret, "Accepting a ghost completion should return empty string to suppress <Tab>")

			-- Validate buffer content updated & cursor moved to end of inserted text
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			assert.are.equal("local x = 1 -- appended", lines[1])
			local cur = vim.api.nvim_win_get_cursor(0)
			-- Row should remain first line, column at end of new text
			assert.are.equal(1, cur[1])
			assert.are.equal(#"local x = 1 -- appended" - 1, cur[2])
			-- State cleared
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.current_extmark)

			-- Cleanup
			vim.api.nvim_create_namespace = original_create_ns
			vim.api.nvim_buf_set_extmark = original_buf_set_extmark
			vim.api.nvim_get_mode = original_get_mode
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should position cursor at end after multi-line insertion", function()
			local original_get_mode = vim.api.nvim_get_mode
			vim.api.nvim_get_mode = function() return { mode = "i" } end

			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "function test()" })
			vim.api.nvim_win_set_cursor(0, {1, #"function test()"})

			local original_create_ns = vim.api.nvim_create_namespace
			local original_buf_set_extmark = vim.api.nvim_buf_set_extmark
			vim.api.nvim_create_namespace = function() return 101 end
			vim.api.nvim_buf_set_extmark = function() return 202 end

			local completion = "\n  local x = 1\n  return x"
			-- Provide a multi-line ghost text starting with a newline to mimic FIM middle insert tail
			-- For display we just set it directly
			turbo_needle.set_ghost_text(completion)
			local state = turbo_needle._buf_states[bufnr]
			assert.is_not_nil(state.cached_completion)

			-- Accept
			local ret = turbo_needle.accept_completion()
			assert.are.equal("", ret)

			-- Validate lines and cursor
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			assert.are.same({
				"function test()", -- first line merged (no change since first line of completion empty before leading newline)
				"  local x = 1",
				"  return x",
			}, lines)
			local cur = vim.api.nvim_win_get_cursor(0)
			assert.are.equal(3, cur[1]) -- third line
			assert.are.equal(#"  return x" - 1, cur[2])

			vim.api.nvim_create_namespace = original_create_ns
			vim.api.nvim_buf_set_extmark = original_buf_set_extmark
			vim.api.nvim_get_mode = original_get_mode
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)
end)
