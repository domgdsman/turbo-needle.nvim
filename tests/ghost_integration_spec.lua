---@diagnostic disable: undefined-field

local turbo_needle = require("turbo-needle")
local async = require("plenary.async")
local stub = require("luassert.stub")
local spy = require("luassert.spy")

-- Integration-style test for end-to-end ghost text display and acceptance
-- Verifies:
-- 1. Completion returned by mocked API is shown as ghost text at correct position
-- 2. Accepting the completion inserts it into the buffer without altering pre-existing text
-- 3. State (extmark + cached_completion) is cleared after acceptance

-- Helper: Setup test buffer with content and cursor
local function setup_test_buffer(lines, cursor_line, cursor_col)
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, { cursor_line, cursor_col })
	return bufnr
end

-- Helper: Setup common mocks for integration tests
local function setup_integration_mocks()
	-- Mock vim mode
	stub(vim.api, "nvim_get_mode").returns({ mode = "i" })

	-- Mock namespace creation
	stub(vim.api, "nvim_create_namespace").returns(444)

	-- Mock extmark operations
	local extmark_calls = {}
	stub(vim.api, "nvim_buf_set_extmark").invokes(function(buf, ns, row, col, opts)
		table.insert(extmark_calls, { buf = buf, ns = ns, row = row, col = col, opts = opts })
		return 2024
	end)

	return {
		extmark_calls = extmark_calls,
		get_last_extmark = function()
			return extmark_calls[#extmark_calls]
		end,
	}
end

-- Helper: Setup context mocks
local function setup_context_mocks(context_module, prefix, suffix)
	stub(context_module, "get_current_context").returns({ prefix = prefix, suffix = suffix })

	stub(context_module, "is_filetype_supported").returns(true)
end

-- Helper: Setup API mocks
local function setup_api_mocks(api_module, completion_text)
	local api_stub = stub(api_module, "get_completion")
	api_stub.invokes(function(_, callback)
		callback(nil, { choices = { { text = completion_text } } })
	end)
	return api_stub
end

async.tests.describe("turbo-needle ghost integration", function()
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
		"should display and accept a mocked single-line completion",
		async.void(function()
			turbo_needle.setup()

			-- Setup test environment
			local lines = { "function add(a, b)", "  return a + b", "end" }
			local bufnr = setup_test_buffer(lines, 2, 12) -- cursor after "return a +"

			-- Setup mocks
			local mock_state = setup_integration_mocks()
			local context = require("turbo-needle.context")
			setup_context_mocks(context, "function add(a, b)\n  return a +", " b\nend")

			local api = require("turbo-needle.api")
			local mocked_completion = " b -- sum"
			local api_spy = setup_api_mocks(api, mocked_completion)

			-- Mock cursor position for extmark
			stub(vim.api, "nvim_win_get_cursor").returns({ 2, 12 })

			-- Trigger completion with async handling
			local async_complete = async.wrap(turbo_needle.complete, 1)
			async_complete()
			async.util.sleep(10) -- Allow async operations to complete

			-- Assertions for ghost text display
			assert.stub(api_spy).was_called(1)
			assert.is_true(#mock_state.extmark_calls >= 1, "Ghost text extmark should be set")

			local ghost = mock_state.get_last_extmark()
			assert.are.equal(1, ghost.row, "Ghost extmark row mismatch (0-based)")
			assert.are.equal(12, ghost.col, "Ghost extmark col mismatch (0-based)")

			local virt = ghost.opts.virt_text
			assert.is_table(virt)
			assert.are.equal(mocked_completion, virt[1][1], "Displayed ghost text should match completion text")

			-- Validate internal state cached completion
			local state = turbo_needle._buf_states[bufnr]
			assert.are.equal(mocked_completion, state.cached_completion)

			-- Accept the completion
			local accept_result = turbo_needle.accept_completion()
			assert.are.equal("", accept_result, "Accepting should suppress default <Tab>")

			-- Buffer content validation
			local updated_line = vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1]
			local expected_line = "  return a + b -- sum"
			assert.are.equal(expected_line, updated_line, "Buffer line content mismatch after acceptance")

			-- State cleared
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.current_extmark)

			-- Cleanup
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	)

	async.tests.it(
		"should display and accept a mocked multi-line completion",
		async.void(function()
			turbo_needle.setup()

			-- Setup test environment
			local original_lines = {
				"function process(items)",
				"  local total = 0",
				"  for _, v in ipairs(items) do",
				"    total = total + v",
				"  end",
				"  return total",
				"end",
			}
			local bufnr = setup_test_buffer(original_lines, 4, 13) -- cursor after "total = total"

			-- Setup mocks
			local mock_state = setup_integration_mocks()
			local context = require("turbo-needle.context")

			-- Multi-line completion
			local mocked_completion = " + v -- accumulate"
				.. "\n    if v > 100 then"
				.. "\n      total = total + 1 -- bonus"
				.. "\n    end"

			-- Setup context with proper prefix/suffix
			local prefix = table.concat({
				original_lines[1],
				original_lines[2],
				original_lines[3],
				"    total = total",
			}, "\n")
			local suffix = " + v\n  end\n  return total\nend"
			setup_context_mocks(context, prefix, suffix)

			local api = require("turbo-needle.api")
			local api_spy = setup_api_mocks(api, mocked_completion)

			-- Mock cursor position for extmark
			stub(vim.api, "nvim_win_get_cursor").returns({ 4, 13 })

			-- Trigger completion with async handling
			local async_complete = async.wrap(turbo_needle.complete, 1)
			async_complete()
			async.util.sleep(10)

			-- Assertions for multi-line ghost text display
			assert.stub(api_spy).was_called(1)
			assert.is_true(#mock_state.extmark_calls > 0, "Ghost extmark expected")

			local ghost = mock_state.get_last_extmark()

			-- Verify virt_text for first line
			assert.is_table(ghost.opts.virt_text, "virt_text expected for first line")
			assert.is_true(#ghost.opts.virt_text > 0, "virt_text should contain at least the head line")
			assert.are.equal(" + v -- accumulate", ghost.opts.virt_text[1][1], "Inline head line mismatch")

			-- Verify virt_lines for continuation lines
			assert.is_table(ghost.opts.virt_lines, "virt_lines expected for continuation lines")

			-- Expected continuation lines
			local expected_virt_lines = {
				{ { "    if v > 100 then", "Comment" } },
				{ { "      total = total + 1 -- bonus", "Comment" } },
				{ { "    end", "Comment" } },
			}
			assert.are.equal(#expected_virt_lines, #ghost.opts.virt_lines, "virt_lines length mismatch")

			-- Accept multi-line completion
			local accept_result = turbo_needle.accept_completion()
			assert.are.equal("", accept_result, "Accepting multi-line should suppress tab")

			-- Verify buffer content after multi-line insertion
			local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local expected_lines = {
				"function process(items)",
				"  local total = 0",
				"  for _, v in ipairs(items) do",
				"    total = total + v -- accumulate",
				"    if v > 100 then",
				"      total = total + 1 -- bonus",
				"    end",
				"  end",
				"  return total",
				"end",
			}
			assert.are.same(expected_lines, new_lines, "Buffer content mismatch after multi-line acceptance")

			-- State cleared
			local state = turbo_needle._buf_states[bufnr]
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.current_extmark)

			-- Cleanup
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	)
end)
