---@diagnostic disable: undefined-field, need-check-nil

local context = require("turbo-needle.context")
local templates = require("turbo-needle.templates")

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

		it("should apply configurable max_chars and trim far context first", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"old1",
				"old2",
				"near_prefix",
				"cursor_here_suffix",
				"near_suffix",
				"far1",
				"far2",
			})

			local result = context.extract_context(bufnr, 3, 6, {
				max_chars = 32,
				prefix_ratio = 0.5,
				include_filename = false,
				include_language = false,
			})

			assert.matches("cursor$", result.prefix)
			assert.matches("^_here", result.suffix)
			assert.is_nil(result.prefix:find("old1", 1, true))
			assert.is_nil(result.suffix:find("far2", 1, true))

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should allocate context budget using prefix_ratio", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"a1",
				"a2",
				"a3",
				"current",
				"b1",
				"b2",
				"b3",
			})

			local even = context.extract_context(bufnr, 3, 3, {
				max_chars = 14,
				prefix_ratio = 0.5,
				include_filename = false,
				include_language = false,
			})
			local prefix_heavy = context.extract_context(bufnr, 3, 3, {
				max_chars = 14,
				prefix_ratio = 0.75,
				include_filename = false,
				include_language = false,
			})

			assert.are.equal("a3\ncur", even.prefix)
			assert.are.equal("rent", even.suffix)
			assert.are.equal("a2\na3\ncur", prefix_heavy.prefix)
			assert.are.equal("rent", prefix_heavy.suffix)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("get_current_context", function()
		it("should get context and metadata from current buffer and cursor", function()
			local turbo_needle = require("turbo-needle")
			turbo_needle.setup({
				context = {
					max_chars = 12000,
					prefix_ratio = 0.75,
					include_filename = true,
					include_language = true,
				},
			})

			local previous_buf = vim.api.nvim_get_current_buf()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, "/tmp/turbo-needle-context.lua")
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"local x = 1",
				"print(x)",
			})
			vim.api.nvim_set_current_buf(bufnr)
			vim.bo[bufnr].filetype = "lua"
			vim.api.nvim_win_set_cursor(0, { 2, 6 })

			local result = context.get_current_context()

			assert.are.equal("local x = 1\nprint(", result.prefix)
			assert.are.equal("x)", result.suffix)
			assert.are.equal("turbo-needle-context.lua", result.filename)
			assert.are.equal("lua", result.language)

			vim.api.nvim_set_current_buf(previous_buf)
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should render filename and language placeholders from real context", function()
			local turbo_needle = require("turbo-needle")
			turbo_needle.setup()

			local previous_buf = vim.api.nvim_get_current_buf()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, "/tmp/template-context.lua")
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"local value =",
				"print(value)",
			})
			vim.api.nvim_set_current_buf(bufnr)
			vim.bo[bufnr].filetype = "lua"
			vim.api.nvim_win_set_cursor(0, { 1, 14 })

			local ctx = context.get_current_context()
			local rendered = templates.render({
				prompt = "file={filename} lang={language} {prefix}<hole>{suffix}",
			}, ctx)

			assert.are.equal("file=template-context.lua lang=lua local value <hole>=\nprint(value)", rendered)

			vim.api.nvim_set_current_buf(previous_buf)
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("is_filetype_supported", function()
		it("should return true for enabled filetype", function()
			local turbo_needle = require("turbo-needle")

			-- Setup turbo-needle with custom config
			turbo_needle.setup({
				filetypes = { lua = true, python = true },
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
				filetypes = { lua = true, python = false },
			})

			vim.bo.filetype = "python"
			assert.is_false(context.is_filetype_supported())
		end)

		it("should return true for unspecified filetype when not disabled", function()
			local turbo_needle = require("turbo-needle")

			-- Setup turbo-needle with custom config
			turbo_needle.setup({
				filetypes = { lua = true },
			})

			vim.bo.filetype = "javascript"
			assert.is_true(context.is_filetype_supported())
		end)
	end)
end)
