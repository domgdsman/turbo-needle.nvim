local recently_edited = require("turbo-needle.sources.recently_edited")

describe("turbo-needle.sources.recently_edited", function()
	local buffers = {}

	local function make_buffer(name, lines)
		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(bufnr, name)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		table.insert(buffers, bufnr)
		return bufnr
	end

	after_each(function()
		for _, bufnr in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end
		buffers = {}
	end)

	it("records whole-line ranges and exposes the additional context contract", function()
		local bufnr = make_buffer("/tmp/recent-edit.lua", { "one", "two", "three" })
		local source = recently_edited.new({ priority = 90, sort_order = 20 })
		source:record(bufnr, 1, 2)
		local result = source:get_context(-1, 0)
		assert.are.equal("recently_edited", result.source)
		assert.are.equal(90, result.priority)
		assert.are.equal(20, result.sort_order)
		assert.is_true(result.can_truncate)
		assert.matches("Path:.*recent%-edit%.lua\ntwo", result.content[1])
	end)

	it("merges adjacent edits in the same file and refreshes live content", function()
		local bufnr = make_buffer("/tmp/merge-edit.lua", { "one", "two", "three" })
		local source = recently_edited.new({ merge_adjacent = true })
		source:record(bufnr, 0, 1)
		vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "changed" })
		source:record(bufnr, 1, 2)
		local items = source.list:items()
		assert.are.equal(1, #items)
		assert.are.equal(0, items[1].start_line)
		assert.are.equal(2, items[1].end_line)
		assert.are.same({ "one", "changed" }, items[1].content)
	end)

	it("does not merge ranges across files and enforces max ranges", function()
		local first = make_buffer("/tmp/first-edit.lua", { "one", "two" })
		local second = make_buffer("/tmp/second-edit.lua", { "one", "two" })
		local source = recently_edited.new({ max_ranges = 2, merge_adjacent = false })
		source:record(first, 0, 1)
		source:record(second, 0, 1)
		source:record(first, 1, 2)
		assert.are.equal(2, #source.list:items())
	end)

	it("excludes the range surrounding the current cursor", function()
		local bufnr = make_buffer("/tmp/cursor-edit.lua", { "one", "two" })
		local source = recently_edited.new({})
		source:record(bufnr, 0, 1)
		assert.is_nil(source:get_context(bufnr, 0))
		assert.is_not_nil(source:get_context(bufnr, 1))
	end)

	it("integrates with ContextManager before the current prefix", function()
		local bufnr = make_buffer("/tmp/manager-edit.lua", { "local edited = true" })
		vim.bo[bufnr].filetype = "lua"
		vim.bo[bufnr].commentstring = "-- %s"
		local source = recently_edited.new({})
		source:record(bufnr, 0, 1)
		local additional = source:get_context(-1, 0)
		local manager = require("turbo-needle.context_manager").new({
			max_chars = 200,
			commentstring = "-- %s",
		})
		local result = manager:build({ prefix = "local current = ", suffix = "" }, { additional })
		assert.matches("^%-%- Path:.*manager%-edit%.lua\n%-%- local edited = true\nlocal current = ", result.prefix)
	end)

	it("ignores unnamed and special buffers", function()
		local unnamed = vim.api.nvim_create_buf(true, false)
		table.insert(buffers, unnamed)
		local special = make_buffer("/tmp/special", { "line" })
		vim.bo[special].buftype = "nofile"
		local source = recently_edited.new({})
		source:record(unnamed, 0, 1)
		source:record(special, 0, 1)
		assert.are.equal(0, #source.list:items())
	end)
end)
