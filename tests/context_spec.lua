local context = require("turbo-needle.context")

describe("turbo-needle.context", function()
	describe("extract_context", function()
		it("should extract prefix and suffix correctly with cursor in middle of line", function()
			-- Create a test buffer
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"function test() {",
				"    print('hello')",
				"    return true",
				"}"
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
				"line3"
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
				"line3"
			})

			local row, col = 1, 5  -- "line2" has 5 chars
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
			-- Create a test buffer and window
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"local x = 1",
				"print(x)"
			})

			local win = vim.api.nvim_open_win(bufnr, true, {
				relative = "editor",
				width = 10,
				height = 5,
				row = 1,
				col = 1
			})

			-- Set cursor
			vim.api.nvim_win_set_cursor(win, {2, 6})  -- "print(" has 6 chars

			local result = context.get_current_context()

			assert.are.equal("local x = 1\nprint(", result.prefix)
			assert.are.equal("x)", result.suffix)

			-- Clean up
			vim.api.nvim_win_close(win, true)
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("is_filetype_supported", function()
		it("should return true for enabled filetype", function()
			local config = require("turbo-needle.config")
			local original_defaults = config.defaults
			config.defaults = vim.tbl_deep_extend("force", config.defaults, {
				filetypes = { enabled = { "lua", "python" }, disabled = {} }
			})

			vim.bo.filetype = "lua"
			assert.is_true(context.is_filetype_supported())

			vim.bo.filetype = "python"
			assert.is_true(context.is_filetype_supported())

			config.defaults = original_defaults
		end)

		it("should return false for disabled filetype", function()
			local config = require("turbo-needle.config")
			local original_defaults = config.defaults
			config.defaults = vim.tbl_deep_extend("force", config.defaults, {
				filetypes = { enabled = { "lua" }, disabled = { "python" } }
			})

			vim.bo.filetype = "python"
			assert.is_false(context.is_filetype_supported())

			config.defaults = original_defaults
		end)

		it("should return true for unspecified filetype when not disabled", function()
			local config = require("turbo-needle.config")
			local original_defaults = config.defaults
			config.defaults = vim.tbl_deep_extend("force", config.defaults, {
				filetypes = { enabled = { "lua" }, disabled = {} }
			})

			vim.bo.filetype = "javascript"
			assert.is_true(context.is_filetype_supported())

			config.defaults = original_defaults
		end)
	end)
end)