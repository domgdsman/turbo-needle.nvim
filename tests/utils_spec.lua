local utils = require("turbo-needle.utils")

describe("turbo-needle.utils", function()
	describe("notification functions", function()
		it("should have notify function", function()
			assert.is_function(utils.notify)
		end)

		it("should have error function", function()
			assert.is_function(utils.error)
		end)

		it("should have warn function", function()
			assert.is_function(utils.warn)
		end)

		it("should have info function", function()
			assert.is_function(utils.info)
		end)

		it("should have debug function", function()
			assert.is_function(utils.debug)
		end)
	end)

	describe("utility functions", function()
		it("should check if value is empty", function()
			assert.is_true(utils.is_empty(nil))
			assert.is_true(utils.is_empty(""))
			assert.is_true(utils.is_empty({}))
			assert.is_false(utils.is_empty("text"))
			assert.is_false(utils.is_empty({ 1, 2, 3 }))
		end)

		it("should trim whitespace", function()
			assert.are.equal("hello", utils.trim("  hello  "))
			assert.are.equal("hello world", utils.trim("hello world"))
			assert.are.equal("", utils.trim("   "))
		end)
	end)


end)
