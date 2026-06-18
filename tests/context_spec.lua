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
				include_filepath = false,
			})

			assert.matches("cursor$", vim.split(result.prefix, "\n")[2])
			assert.are.equal("# …", vim.split(result.prefix, "\n")[1])
			assert.matches("^_here", result.suffix)
			assert.matches("# …$", result.suffix)
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
				include_filepath = false,
			})
			local prefix_heavy = context.extract_context(bufnr, 3, 3, {
				max_chars = 14,
				prefix_ratio = 0.75,
				include_filepath = false,
			})

			assert.are.equal("# …\na3\ncur", even.prefix)
			assert.are.equal("rent\n# …", even.suffix)
			assert.are.equal("# …\na2\na3\ncur", prefix_heavy.prefix)
			assert.are.equal("rent\n# …", prefix_heavy.suffix)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should add filepath and truncation hints with buffer comment syntax", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, "/tmp/context-hints.py")
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"before_one()",
				"before_two()",
				"result = call_here()",
				"after_one()",
				"after_two()",
			})
			vim.bo[bufnr].filetype = "python"
			vim.bo[bufnr].commentstring = "# %s"

			local result = context.extract_context(bufnr, 2, 8, {
				max_chars = 30,
				prefix_ratio = 0.5,
				include_filepath = true,
			})

			assert.matches("^# /tmp/context%-hints%.py\n# …\n", result.prefix)
			assert.matches("\n# …$", result.suffix)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should reallocate unused prefix budget to suffix near the top of the file", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"line1",
				"line2",
				"line3",
				"line4",
				"line5",
			})

			local result = context.extract_context(bufnr, 0, 0, {
				max_chars = 24,
				prefix_ratio = 0.75,
				include_filepath = false,
			})

			assert.are.equal("", result.prefix)
			assert.are.equal("line1\nline2\nline3\nline4\n# …", result.suffix)

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should omit truncation hints when include_ellipsis is false", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
				"old1",
				"old2",
				"cursor_suffix",
				"after1",
				"after2",
			})

			local result = context.extract_context(bufnr, 2, 6, {
				max_chars = 18,
				prefix_ratio = 0.5,
				include_filepath = false,
				include_ellipsis = false,
			})

			assert.is_nil(result.prefix:find("…", 1, true))
			assert.is_nil(result.suffix:find("…", 1, true))
			assert.matches("cursor$", result.prefix)
			assert.matches("^_suffix", result.suffix)

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
					include_filepath = true,
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
			vim.bo[bufnr].commentstring = "-- %s"
			vim.api.nvim_win_set_cursor(0, { 2, 6 })

			local result = context.get_current_context()

			assert.are.equal("-- /tmp/turbo-needle-context.lua\nlocal x = 1\nprint(", result.prefix)
			assert.are.equal("x)", result.suffix)
			assert.are.equal("/tmp/turbo-needle-context.lua", result.filepath)

			vim.api.nvim_set_current_buf(previous_buf)
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)

		it("should render filepath placeholders from real context", function()
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
			vim.bo[bufnr].commentstring = "-- %s"
			vim.api.nvim_win_set_cursor(0, { 1, 14 })

			local ctx = context.get_current_context()
			local rendered = templates.render({
				prompt = "path={filepath}\n{prefix}<hole>{suffix}",
			}, ctx)

			assert.are.equal(
				"path=/tmp/template-context.lua\n-- /tmp/template-context.lua\nlocal value <hole>=\nprint(value)",
				rendered
			)

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
