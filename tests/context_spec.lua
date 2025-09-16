---@diagnostic disable: undefined-field, need-check-nil

local context = require("turbo-needle.context")
local mock = require("luassert.mock")

describe("turbo-needle.context", function()
	describe("extract_context", function()
		it("should extract prefix and suffix correctly with cursor in middle of line", function()
			-- Create a test buffer
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"function test() {",
				"    print('hello')",
				"    return true",
				"}",
			})

			-- Cursor after "    prin" in line 2 (0-based: row=1, col=8)
			local row, col = 1, 8
			local result = context.extract_context(bufnr, row, col)

			assert.are.equal("function test() {\n    prin", result.prefix)
			assert.are.equal("t('hello')\n    return true\n}", result.suffix)

			-- Clean up
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should extract prefix and suffix with cursor at start of line", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"line1",
				"line2",
				"line3",
			})

			local row, col = 1, 0
			local result = context.extract_context(bufnr, row, col)

			assert.are.equal("line1\n", result.prefix)
			assert.are.equal("line2\nline3", result.suffix)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should extract prefix and suffix with cursor at end of line", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"line1",
				"line2",
				"line3",
			})

			local row, col = 1, 5 -- "line2" has 5 chars
			local result = context.extract_context(bufnr, row, col)

			assert.are.equal("line1\nline2", result.prefix)
			assert.are.equal("\nline3", result.suffix)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should handle empty buffer", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

			local row, col = 0, 0
			local result = context.extract_context(bufnr, row, col)

			assert.are.equal("", result.prefix)
			assert.are.equal("", result.suffix)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("get_current_context", function()
		it("should get context from current buffer and cursor", function()
			-- Mock vim.api for testing
			local api = mock(vim.api, true)

			-- Create test buffer content
			local test_lines = {
				"local x = 1",
				"print(x)",
			}

			-- Setup mock expectations
			api.nvim_get_current_buf.returns(1)
			api.nvim_win_get_cursor.returns({ 2, 6 }) -- 1-based: line 2, col 6 (0-based)
			api.nvim_buf_get_lines.invokes(function(bufnr, start, end_, strict)
				return test_lines
			end)

			local result = context.get_current_context()

			assert.are.equal("local x = 1\nprint(", result.prefix)
			assert.are.equal("x)", result.suffix)

			-- Verify functions were called with expected arguments
			assert.stub(api.nvim_get_current_buf).was_called()
			assert.stub(api.nvim_win_get_cursor).was_called()
			assert.stub(api.nvim_buf_get_lines).was_called_with(1, 0, -1, false)

			mock.revert(api)
		end)
	end)

	describe("is_filetype_supported", function()
		it("should return true for enabled filetype", function()
			local turbo_needle = require("turbo-needle")

			-- Setup turbo-needle with custom config
			turbo_needle.setup({
				filetypes = { enabled = { "lua", "python" }, disabled = {} },
			})

			vim.bo.filetype = "lua"
			assert.is_true(context.is_filetype_supported())

			vim.bo.filetype = "python"
			assert.is_true(context.is_filetype_supported())
		end)

		it("should return false for disabled filetype", function()
			local turbo_needle = require("turbo-needle")

			-- Setup turbo-needle with custom config
			turbo_needle.setup({
				filetypes = { enabled = { "lua" }, disabled = { "python" } },
			})

			vim.bo.filetype = "python"
			assert.is_false(context.is_filetype_supported())
		end)

		it("should return true for unspecified filetype when not disabled", function()
			local turbo_needle = require("turbo-needle")

			-- Setup turbo-needle with custom config
			turbo_needle.setup({
				filetypes = { enabled = { "lua" }, disabled = {} },
			})

			vim.bo.filetype = "javascript"
			assert.is_true(context.is_filetype_supported())
		end)
	end)
end)
