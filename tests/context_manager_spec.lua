local context_manager = require("turbo-needle.context_manager")

describe("turbo-needle.context_manager", function()
	local function source(id, priority, sort_order, can_truncate, content)
		return {
			source = id,
			priority = priority,
			sort_order = sort_order,
			can_truncate = can_truncate,
			content = content,
		}
	end

	it("comments additional content and prepends it to the current prefix", function()
		local manager = context_manager.new({ max_chars = 100, commentstring = "-- %s" })
		local result = manager:build({ prefix = "local value = ", suffix = "end" }, {
			source("opened", 50, 10, true, { "local other = 1\nreturn other" }),
		})

		assert.are.equal("-- local other = 1\n-- return other\nlocal value = ", result.prefix)
		assert.are.equal("end", result.suffix)
	end)

	it("selects by priority and places selected sources by sort order", function()
		local manager = context_manager.new({ max_chars = 100, commentstring = "# %s" })
		local result = manager:build({ prefix = "cursor", suffix = "" }, {
			source("high", 100, 20, false, { "high" }),
			source("low", 10, 10, false, { "low" }),
		})

		assert.are.equal("# low\n# high\ncursor", result.prefix)
	end)

	it("keeps the current buffer and truncates allowed content to capacity", function()
		local manager = context_manager.new({ max_chars = 14, commentstring = "# %s" })
		local result = manager:build({ prefix = "CUR", suffix = "SOR" }, {
			source("extra", 10, 10, true, { "abcdefghij" }),
		})

		assert.are.equal("# abcde\nCUR", result.prefix)
		assert.are.equal("SOR", result.suffix)
	end)

	it("skips oversized non-truncatable parts and continues through all parts and sources", function()
		local manager = context_manager.new({ max_chars = 16, commentstring = "# %s" })
		local result = manager:build({ prefix = "CUR", suffix = "" }, {
			source("first", 100, 10, false, { "far too large", "ok" }),
			source("second", 50, 20, false, { "yes" }),
		})

		assert.are.equal("# ok\n# yes\nCUR", result.prefix)
	end)

	it("applies enablement and priority overrides from config", function()
		local manager = context_manager.new({
			max_chars = 13,
			commentstring = "# %s",
			sources = {
				disabled = { enabled = false },
				promoted = { priority = 200 },
			},
		})
		local result = manager:build({ prefix = "CUR", suffix = "" }, {
			source("normal", 100, 10, false, { "normal" }),
			source("promoted", 10, 20, false, { "win" }),
			source("disabled", 300, 1, false, { "bad" }),
		})

		assert.are.equal("# win\nCUR", result.prefix)
	end)

	it("ignores malformed, empty, and whitespace-only content", function()
		local manager = context_manager.new({ max_chars = 100, commentstring = "# %s" })
		local result = manager:build({ prefix = "CUR", suffix = "" }, {
			{},
			source("empty", 10, 10, true, { "", "  ", 12 }),
		})

		assert.are.equal("CUR", result.prefix)
	end)
end)
