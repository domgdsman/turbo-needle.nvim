local turbo_needle = require("turbo-needle")

-- Tests focused on completion caching and request cancellation logic

describe("turbo-needle caching and cancellation", function()
	before_each(function()
		package.loaded["turbo-needle"] = nil
		turbo_needle = require("turbo-needle")
	end)

	it("should cache a completion and reuse it for identical context", function()
		-- Force insert mode
		local original_get_mode = vim.api.nvim_get_mode
		vim.api.nvim_get_mode = function()
			return { mode = "i" }
		end

		-- Mock context
		local context = require("turbo-needle.context")
		local original_get_ctx = context.get_current_context
		local original_is_supported = context.is_filetype_supported
		context.is_filetype_supported = function()
			return true
		end
		local ctx_call_count = 0
		context.get_current_context = function()
			ctx_call_count = ctx_call_count + 1
			return { prefix = "print(", suffix = ")" }
		end

		-- Mock API to return result only first time
		local api = require("turbo-needle.api")
		local original_get_completion = api.get_completion
		local api_calls = 0
		api.get_completion = function(data, callback)
			api_calls = api_calls + 1
			callback(nil, { choices = { { text = "'cached'" } } })
			return nil
		end

		-- Mock set_ghost_text to capture value
		local original_set_ghost = turbo_needle.set_ghost_text
		local ghost_calls = {}
		turbo_needle.set_ghost_text = function(text)
			table.insert(ghost_calls, text)
			original_set_ghost(text)
		end

		-- First completion (triggers API)
		turbo_needle.complete()
		vim.wait(50)
		-- Second completion (should use cache, not call API again)
		turbo_needle.complete()
		vim.wait(50)

		assert.are.equal(1, api_calls, "API should have been called only once for identical context")
		assert.is_true(#ghost_calls >= 2, "Ghost text should be set twice (first + cached)")
		assert.are.equal("'cached'", ghost_calls[1])
		assert.are.equal("'cached'", ghost_calls[#ghost_calls])

		-- Restore
		vim.api.nvim_get_mode = original_get_mode
		context.get_current_context = original_get_ctx
		context.is_filetype_supported = original_is_supported
		api.get_completion = original_get_completion
		turbo_needle.set_ghost_text = original_set_ghost
	end)

	it("should cancel earlier completion responses when a newer request is made", function()
		local original_get_mode = vim.api.nvim_get_mode
		vim.api.nvim_get_mode = function()
			return { mode = "i" }
		end

		local context = require("turbo-needle.context")
		local original_get_ctx = context.get_current_context
		local original_is_supported = context.is_filetype_supported
		context.is_filetype_supported = function()
			return true
		end
		local prefix_variant = 0
		context.get_current_context = function()
			prefix_variant = prefix_variant + 1
			return { prefix = "v" .. prefix_variant, suffix = "" }
		end

		local api = require("turbo-needle.api")
		local original_get_completion = api.get_completion
		local callbacks = {}
		api.get_completion = function(data, callback)
			-- Defer invocation to simulate async responses arriving out of order
			local this_prefix = data.prefix
			vim.defer_fn(function()
				callback(nil, { choices = { { text = this_prefix .. "_resp" } } })
			end, this_prefix == "v1" and 40 or 10) -- First call delayed longer to simulate late arrival
			return nil
		end

		local original_set_ghost = turbo_needle.set_ghost_text
		local last_set
		turbo_needle.set_ghost_text = function(text)
			last_set = text
			original_set_ghost(text)
		end

		-- Fire two completes rapidly; second should cancel first
		turbo_needle.complete() -- v1
		vim.wait(5)
		turbo_needle.complete() -- v2 (should cancel v1)
		vim.wait(80) -- wait long enough for both callbacks

		assert.are.equal("v2_resp", last_set, "Latest request's response should win; earlier should be ignored")

		-- Restore
		vim.api.nvim_get_mode = original_get_mode
		context.get_current_context = original_get_ctx
		context.is_filetype_supported = original_is_supported
		api.get_completion = original_get_completion
		turbo_needle.set_ghost_text = original_set_ghost
	end)

	it("should respect enable/disable toggling", function()
		local original_get_mode = vim.api.nvim_get_mode
		vim.api.nvim_get_mode = function()
			return { mode = "i" }
		end

		local context = require("turbo-needle.context")
		local original_get_ctx = context.get_current_context
		local original_is_supported = context.is_filetype_supported
		context.is_filetype_supported = function()
			return true
		end
		context.get_current_context = function()
			return { prefix = "A", suffix = "" }
		end

		local api = require("turbo-needle.api")
		local original_get_completion = api.get_completion
		local api_called = 0
		api.get_completion = function(_, callback)
			api_called = api_called + 1
			callback(nil, { choices = { { text = "A_resp" } } })
		end

		-- Disable completions and call
		turbo_needle.disable()
		-- Directly invoke complete; should early return because not in insert or disabled state gating occurs in trigger logic
		turbo_needle.complete()
		vim.wait(20)
		-- Re-enable and call again
		turbo_needle.enable()
		turbo_needle.complete()
		vim.wait(20)

		assert.are.equal(1, api_called, "API should be called only after re-enabled")

		-- Restore
		vim.api.nvim_get_mode = original_get_mode
		context.get_current_context = original_get_ctx
		context.is_filetype_supported = original_is_supported
		api.get_completion = original_get_completion
	end)
end)
