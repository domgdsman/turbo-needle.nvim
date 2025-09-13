local turbo_needle = require("turbo-needle")

-- Integration-style test for end-to-end ghost text display and acceptance
-- Verifies:
-- 1. Completion returned by mocked API is shown as ghost text at correct position
-- 2. Accepting the completion inserts it into the buffer without altering pre-existing text
-- 3. State (extmark + cached_completion) is cleared after acceptance

describe("turbo-needle ghost integration", function()
	before_each(function()
		package.loaded["turbo-needle"] = nil
		turbo_needle = require("turbo-needle")
	end)

	it("should display and accept a mocked single-line completion", function()
		-- Setup configuration (keep defaults)
		turbo_needle.setup()

		-- Force insert mode environment
		local original_get_mode = vim.api.nvim_get_mode
		vim.api.nvim_get_mode = function()
			return { mode = "i" }
		end

		-- Create scratch buffer and seed content
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(bufnr)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "function add(a, b)", "  return a + b", "end" })
		-- Place cursor after the 'return a + b' line's plus sign (simulate mid-line insertion)
		local target_line = 2
		local line_text = vim.api.nvim_buf_get_lines(bufnr, target_line - 1, target_line, false)[1]
		local plus_col = line_text:find("+", 1, true) -- 1-based
		assert.is_truthy(plus_col, "Test precondition: plus sign not found")
		-- Convert to 0-based col index for nvim_win_set_cursor
		vim.api.nvim_win_set_cursor(0, { target_line, plus_col })

		-- Mock context to reflect expected extraction; we only care prefix/suffix framing
		local context = require("turbo-needle.context")
		local original_get_ctx = context.get_current_context
		context.get_current_context = function()
			-- Simulate prefix up to cursor and suffix remainder
			local prefix = "function add(a, b)\n  return a +"
			local suffix = " b" .. "\nend" -- mimic real extraction remainder
			return { prefix = prefix, suffix = suffix }
		end
		local original_is_supported = context.is_filetype_supported
		context.is_filetype_supported = function()
			return true
		end

		-- Mock API to return deterministic completion
		local api = require("turbo-needle.api")
		local original_get_completion = api.get_completion
		local mocked_completion = " b -- sum"
		local api_called = 0
		api.get_completion = function(data, callback)
			api_called = api_called + 1
			callback(nil, { choices = { { text = mocked_completion } } })
			return nil
		end

		-- Intercept ghost text application: capture extmark arguments
		local original_buf_set_extmark = vim.api.nvim_buf_set_extmark
		local original_create_ns = vim.api.nvim_create_namespace
		local original_win_get_cursor = vim.api.nvim_win_get_cursor
		local ghost_calls = {}
		vim.api.nvim_create_namespace = function()
			return 444
		end
		vim.api.nvim_win_get_cursor = function()
			-- Ensure cursor stable during ghost set
			return { target_line, plus_col }
		end
		vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
			table.insert(ghost_calls, { buf = buf, ns = ns, row = row, col = col, opts = opts })
			return 2024
		end

		-- Trigger completion
		turbo_needle.complete()
		vim.wait(60)

		-- Assertions for ghost text display
		assert.are.equal(1, api_called, "API should have been called once")
		assert.is_true(#ghost_calls >= 1, "Ghost text extmark should be set")
		local ghost = ghost_calls[#ghost_calls]
		assert.are.equal(target_line - 1, ghost.row, "Ghost extmark row mismatch (0-based)")
		assert.are.equal(plus_col, ghost.col, "Ghost extmark col mismatch (0-based)")
		local virt = ghost.opts.virt_text
		assert.is_table(virt)
		assert.are.equal(mocked_completion, virt[1][1], "Displayed ghost text should match completion text")

		-- Validate internal state cached completion
		local state = turbo_needle._buf_states[bufnr]
		assert.are.equal(mocked_completion, state.cached_completion)

		-- Accept the completion
		local accept_result = turbo_needle.accept_completion()
		assert.are.equal("", accept_result, "Accepting should suppress default <Tab>")

		-- Buffer content validation: the second line should now contain inserted completion after '+' sign
		local updated_line = vim.api.nvim_buf_get_lines(bufnr, target_line - 1, target_line, false)[1]
		local expected_line = line_text:sub(1, plus_col) .. mocked_completion .. line_text:sub(plus_col + 1)
		assert.are.equal(expected_line, updated_line, "Buffer line content mismatch after acceptance")

		-- State cleared
		assert.is_nil(state.cached_completion)
		assert.is_nil(state.current_extmark)

		-- Cleanup restores
		vim.api.nvim_get_mode = original_get_mode
		context.get_current_context = original_get_ctx
		context.is_filetype_supported = original_is_supported
		api.get_completion = original_get_completion
		vim.api.nvim_buf_set_extmark = original_buf_set_extmark
		vim.api.nvim_create_namespace = original_create_ns
		vim.api.nvim_win_get_cursor = original_win_get_cursor
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)

	it("should display and accept a mocked multi-line completion", function()
		-- Setup configuration
		turbo_needle.setup()

		-- Force insert mode
		local original_get_mode = vim.api.nvim_get_mode
		vim.api.nvim_get_mode = function()
			return { mode = "i" }
		end

		-- Buffer with context near middle of function
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(bufnr)
		local original_lines = {
			"function process(items)",
			"  local total = 0",
			"  for _, v in ipairs(items) do",
			"    total = total + v",
			"  end",
			"  return total",
			"end",
		}
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original_lines)

		-- Place cursor after 'total = total' (before ' + v') on line 4 (1-based)
		local target_line = 4
		local line_text = vim.api.nvim_buf_get_lines(bufnr, target_line - 1, target_line, false)[1]
		local anchor_str = "total = total"
		local anchor_col_1based = line_text:find(anchor_str, 1, true)
		assert.is_truthy(anchor_col_1based, "Anchor not found in line")
		local insertion_col_0based = anchor_col_1based - 1 + #anchor_str
		vim.api.nvim_win_set_cursor(0, { target_line, insertion_col_0based })

		-- Multi-line completion (first line continues current, next lines extend logic)
		local mocked_completion = " + v -- accumulate" ..
			"\n    if v > 100 then" ..
			"\n      total = total + 1 -- bonus" ..
			"\n    end"

		-- Mock context (simplified) to allow completion request
		local context = require("turbo-needle.context")
		local original_get_ctx = context.get_current_context
		context.get_current_context = function()
			local prefix = table.concat({ original_lines[1], original_lines[2], original_lines[3], line_text:sub(1, insertion_col_0based) }, "\n")
			local suffix = line_text:sub(insertion_col_0based + 1) .. "\n" .. table.concat({ original_lines[5], original_lines[6], original_lines[7] }, "\n")
			return { prefix = prefix, suffix = suffix }
		end
		local original_is_supported = context.is_filetype_supported
		context.is_filetype_supported = function()
			return true
		end

		local api = require("turbo-needle.api")
		local original_get_completion = api.get_completion
		local api_called = 0
		api.get_completion = function(_, cb)
			api_called = api_called + 1
			cb(nil, { choices = { { text = mocked_completion } } })
			return nil
		end

		-- Capture virt_lines from extmark
		local original_buf_set_extmark = vim.api.nvim_buf_set_extmark
		local original_create_ns = vim.api.nvim_create_namespace
		local original_win_get_cursor = vim.api.nvim_win_get_cursor
		local ghost_calls = {}
		vim.api.nvim_create_namespace = function()
			return 9999
		end
		vim.api.nvim_win_get_cursor = function()
			return { target_line, insertion_col_0based }
		end
		vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
			ghost_calls[#ghost_calls + 1] = { buf = buf, ns = ns, row = row, col = col, opts = opts }
			return 4242
		end

		-- Trigger completion
		turbo_needle.complete()
		vim.wait(80)

		assert.are.equal(1, api_called, "API should be called exactly once")
		assert.is_true(#ghost_calls > 0, "Ghost extmark expected")
		local ghost = ghost_calls[#ghost_calls]
		-- Hybrid rendering: first line should be inline via virt_text, remainder via virt_lines
		assert.is_table(ghost.opts.virt_text, "virt_text expected for first line inline in multi-line completion")
		assert.is_true(#ghost.opts.virt_text > 0, "virt_text should contain at least the head line")
		assert.are.equal(mocked_completion:match("^[^\n]+"), ghost.opts.virt_text[1][1], "Inline head line mismatch")
		assert.is_table(ghost.opts.virt_lines, "virt_lines expected for continuation lines in multi-line completion")

		-- Build expected virt_lines (tail only, since head rendered inline)
		local all_lines = vim.split(mocked_completion, "\n", { plain = true })
		local indent = string.match(line_text, "^%s*") or ""
		local expected_tail = {}
		for i = 2, #all_lines do
			local l = all_lines[i]
			local display_line = l
			if l:match("^%s*") then
				-- Implementation re-indents continuation lines with current line indent
				display_line = indent .. l:gsub("^%s*", "")
			end
			if #display_line > 100 then
				display_line = display_line:sub(1, 97) .. "..."
			end
			expected_tail[#expected_tail + 1] = { { display_line, "Comment" } }
		end
		assert.are.equal(#expected_tail, #ghost.opts.virt_lines, "virt_lines length mismatch (tail lines)")
		-- Optionally verify each tail line text (keeps test precise but resilient to highlight group consistency)
		for i, seg in ipairs(expected_tail) do
			assert.are.equal(seg[1][1], ghost.opts.virt_lines[i][1][1], string.format("virt_lines tail line %d mismatch", i))
		end

		-- Accept multi-line completion
		local accept_result = turbo_needle.accept_completion()
		assert.are.equal("", accept_result, "Accepting multi-line should suppress tab")

		-- Verify buffer lines after insertion
		local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		-- Construct expected buffer manually
		local before_fragment = line_text:sub(1, insertion_col_0based)
		local after_fragment = line_text:sub(insertion_col_0based + 1)
		local inserted_lines = vim.split(mocked_completion, "\n", { plain = true })
		local expected_buffer = {}
		for i = 1, target_line - 1 do
			expected_buffer[#expected_buffer + 1] = original_lines[i]
		end
		-- First inserted line merges with existing target line prefix and keeps remainder after insertion on same line tail of first inserted line
		expected_buffer[#expected_buffer + 1] = before_fragment .. inserted_lines[1] .. after_fragment
		-- Subsequent inserted lines added directly after
		for i = 2, #inserted_lines do
			expected_buffer[#expected_buffer + 1] = inserted_lines[i]
		end
		-- Remaining original lines after target line
		for i = target_line + 1, #original_lines do
			expected_buffer[#expected_buffer + 1] = original_lines[i]
		end

		assert.are.same(expected_buffer, new_lines, "Buffer content mismatch after multi-line acceptance")

		local state = turbo_needle._buf_states[bufnr]
		assert.is_nil(state.cached_completion)
		assert.is_nil(state.current_extmark)

		-- Cleanup
		vim.api.nvim_get_mode = original_get_mode
		context.get_current_context = original_get_ctx
		context.is_filetype_supported = original_is_supported
		api.get_completion = original_get_completion
		vim.api.nvim_buf_set_extmark = original_buf_set_extmark
		vim.api.nvim_create_namespace = original_create_ns
		vim.api.nvim_win_get_cursor = original_win_get_cursor
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)
