---@diagnostic disable: undefined-field

local turbo_needle = require("turbo-needle")
local stub = require("luassert.stub")
local spy = require("luassert.spy")
local async = require("plenary.async")

-- Tests focused on completion caching and request cancellation logic

-- Helper: Setup common mocks for caching tests
local function setup_caching_mocks()
	local mocks = {}

	-- Mock vim mode
	mocks.mode_stub = stub(vim.api, "nvim_get_mode")
	vim.api.nvim_get_mode.returns({ mode = "i" })

	-- Mock context
	local context = require("turbo-needle.context")
	mocks.context_supported_stub = stub(context, "is_filetype_supported")
	context.is_filetype_supported.returns(true)

	return context, mocks
end

-- Helper: Setup API mocks with completion text
local function setup_api_mocks(api_module, completion_text)
	local api_spy = spy.on(api_module, "get_completion")
	stub(api_module, "get_completion")
	api_module.get_completion.invokes(function(_, callback)
		callback(nil, { choices = { { text = completion_text } } })
	end)
	return api_spy
end

-- Helper: Setup ghost text spy
local function setup_ghost_text_spy()
	local ghost_spy = spy.on(turbo_needle, "set_ghost_text")
	stub(turbo_needle, "set_ghost_text")
	turbo_needle.set_ghost_text.invokes(function(text)
		-- Simulate setting ghost text state
		local bufnr = vim.api.nvim_get_current_buf()
		turbo_needle._buf_states = turbo_needle._buf_states or {}
		turbo_needle._buf_states[bufnr] = {
			cached_completion = text,
			current_extmark = { ns_id = 2025, id = 8080 },
			cursor_position = { row = 0, col = 0 },
		}
		return true
	end)
	return ghost_spy
end

async.tests.describe("turbo-needle caching and cancellation", function()
	async.tests.before_each(function()
		package.loaded["turbo-needle"] = nil
		turbo_needle = require("turbo-needle")
	end)

	async.tests.it(
		"should cache a completion and reuse it for identical context",
		async.void(function()
			-- Setup mocks
			local context, mocks = setup_caching_mocks()
			local context_spy = spy.on(context, "get_current_context")
			stub(context, "get_current_context")
			context.get_current_context.returns({ prefix = "print(", suffix = ")" })

			local api = require("turbo-needle.api")
			local api_spy = setup_api_mocks(api, "'cached'")
			local ghost_spy = setup_ghost_text_spy()

			-- First completion (triggers API)
			local async_complete = async.wrap(turbo_needle.complete, 1)
			async_complete()
			async.util.sleep(10)

			-- Second completion (should use cache, not call API again)
			async_complete()
			async.util.sleep(10)

			-- Assertions
			assert.spy(api_spy).was_called(1)
			assert.spy(ghost_spy).was_called(2)
			assert.spy(ghost_spy).was_called_with("'cached'")
			assert.spy(context_spy).was_called(1) -- Context should only be called once due to caching
		end)
	)

	async.tests.it(
		"should cancel earlier completion responses when a newer request is made",
		async.void(function()
			-- Setup mocks
			local context, mocks = setup_caching_mocks()
			local prefix_variant = 0
			stub(context, "get_current_context")
			context.get_current_context.invokes(function()
				prefix_variant = prefix_variant + 1
				return { prefix = "v" .. prefix_variant, suffix = "" }
			end)

			local api = require("turbo-needle.api")
			local api_spy = spy.on(api, "get_completion")
			stub(api, "get_completion")
			api.get_completion.invokes(function(data, callback)
				-- Defer invocation to simulate async responses arriving out of order
				local this_prefix = data.prefix
				vim.defer_fn(function()
					callback(nil, { choices = { { text = this_prefix .. "_resp" } } })
				end, this_prefix == "v1" and 40 or 10) -- First call delayed longer
			end)

			local ghost_spy = setup_ghost_text_spy()

			-- Fire two completes rapidly; second should cancel first
			local async_complete = async.wrap(turbo_needle.complete, 1)
			async_complete() -- v1
			async.util.sleep(5)
			async_complete() -- v2 (should cancel v1)
			async.util.sleep(80) -- wait long enough for both callbacks

			-- Latest request's response should win
			assert.spy(ghost_spy).was_called_with("v2_resp")
			assert.spy(api_spy).was_called(2)
		end)
	)

	async.tests.it(
		"should respect enable/disable toggling",
		async.void(function()
			-- Setup mocks
			local context, mocks = setup_caching_mocks()
			stub(context, "get_current_context")
			context.get_current_context.returns({ prefix = "A", suffix = "" })

			local api = require("turbo-needle.api")
			local api_spy = setup_api_mocks(api, "A_resp")

			local async_complete = async.wrap(turbo_needle.complete, 1)

			-- Disable completions and call
			turbo_needle.disable()
			async_complete()
			async.util.sleep(10)

			-- Re-enable and call again
			turbo_needle.enable()
			async_complete()
			async.util.sleep(10)

			-- API should be called only after re-enabled
			assert.spy(api_spy).was_called(1)
		end)
	)
end)
