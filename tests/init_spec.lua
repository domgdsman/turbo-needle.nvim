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
				callback(nil, { content = "completed code" })
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

			-- Restore mocks
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

			context.is_filetype_supported = original_is_supported
			context.get_current_context = original_get_context
			api.get_completion = original_get_completion
			utils.notify = original_notify

			assert.is_true(notify_called)
		end)

		it("should use custom parse_response when provided", function()
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

			-- Restore mocks
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

		it("should clear ghost text without error", function()
			assert.has_no.errors(function()
				turbo_needle.clear_ghost_text()
			end)
		end)

		it("should set ghost text without error", function()
			-- Mock vim.api functions
			local original_create_ns = vim.api.nvim_create_namespace
			local original_win_get_cursor = vim.api.nvim_win_get_cursor
			local original_buf_set_extmark = vim.api.nvim_buf_set_extmark

			vim.api.nvim_create_namespace = function()
				return 1
			end
			vim.api.nvim_win_get_cursor = function()
				return { 1, 0 }
			end
			vim.api.nvim_buf_set_extmark = function()
				return 1
			end

			assert.has_no.errors(function()
				turbo_needle.set_ghost_text("test text")
			end)

			-- Restore
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

		it("should insert ghost text and return empty when ghost text present", function()
			-- Mock set_ghost_text to set current_extmark
			turbo_needle.set_ghost_text("test")

			-- Mock vim.api functions
			local original_get_extmark = vim.api.nvim_buf_get_extmark_by_id
			local original_put = vim.api.nvim_put
			local original_clear = turbo_needle.clear_ghost_text

			local put_called = false
			local clear_called = false
			vim.api.nvim_buf_get_extmark_by_id = function()
				return { 0, 0, { virt_text = { { "inserted text", "Comment" } } } }
			end
			vim.api.nvim_put = function(text)
				put_called = true
				assert.are.equal("inserted text", text[1])
			end
			turbo_needle.clear_ghost_text = function()
				clear_called = true
			end

			local result = turbo_needle.accept_completion()
			assert.are.equal("", result)
			assert.is_true(put_called)
			assert.is_true(clear_called)

			-- Restore
			vim.api.nvim_buf_get_extmark_by_id = original_get_extmark
			vim.api.nvim_put = original_put
			turbo_needle.clear_ghost_text = original_clear
		end)
	end)
end)
