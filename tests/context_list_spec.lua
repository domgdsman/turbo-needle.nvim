local context_list = require("turbo-needle.context_list")

describe("turbo-needle.context_list", function()
	local function item(id, captured_at)
		return { id = id, captured_at = captured_at }
	end

	it("keeps newest entries and evicts the oldest", function()
		local list = context_list.new({
			keep_last = 2,
			key = function(value)
				return value.id
			end,
		})
		list:insert(item("one", 1))
		list:insert(item("two", 2))
		list:insert(item("three", 3))
		assert.are.same(
			{ "three", "two" },
			vim.tbl_map(function(value)
				return value.id
			end, list:items())
		)
	end)

	it("replaces exact keys as the most recent entry", function()
		local list = context_list.new({
			key = function(value)
				return value.id
			end,
		})
		list:insert({ id = "same", value = 1 })
		list:insert({ id = "other" })
		list:upsert({ id = "same", value = 2 })
		assert.are.equal("same", list:items()[1].id)
		assert.are.equal(2, list:items()[1].value)
		assert.are.equal(2, #list:items())
	end)

	it("expires entries using injected time", function()
		local now = 100
		local list = context_list.new({
			ttl_ms = 10,
			now = function()
				return now
			end,
		})
		list:insert({ id = "old", captured_at = 95 })
		now = 106
		assert.are.equal(0, #list:items())
	end)

	it("runs policies in order and allows mutation through removal", function()
		local calls = {}
		local list = context_list.new({
			key = function(value)
				return value.id
			end,
			policies = {
				function(new_item)
					table.insert(calls, "first")
					new_item.id = "changed"
				end,
				function(_, values)
					table.insert(calls, "second")
					values:remove("old")
				end,
			},
		})
		list:insert({ id = "old" })
		list:insert({ id = "new" })
		assert.are.same({ "first", "second", "first", "second" }, calls)
		assert.are.equal("changed", list:items()[1].id)
		assert.are.equal(1, #list:items())
	end)

	it("supports touch, predicate removal, clear, and defensive copies", function()
		local list = context_list.new({
			key = function(value)
				return value.id
			end,
		})
		list:insert({ id = "one" })
		list:insert({ id = "two" })
		assert.is_true(list:touch("one"))
		assert.are.equal("one", list:items()[1].id)
		local copy = list:items()
		copy[1].id = "mutated"
		assert.are.equal("one", list:items()[1].id)
		list:remove(function(value)
			return value.id == "two"
		end)
		assert.are.equal(1, #list:items())
		list:clear()
		assert.are.equal(0, #list:items())
	end)

	it("rejects recursive insertion from policies", function()
		local list
		list = context_list.new({ policies = {
			function()
				list:insert({ id = "nested" })
			end,
		} })
		assert.has_error(function()
			list:insert({ id = "outer" })
		end, "ContextList policies cannot insert entries")
	end)
end)
