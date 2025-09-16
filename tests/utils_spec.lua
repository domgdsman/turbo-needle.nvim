---@diagnostic disable: undefined-field

local utils = require("turbo-needle.utils")

-- Helper: Test completion validation with context
local function test_completion_validation(completion, context, expected_valid, expected_error)
	local valid, err = utils.validate_completion(completion, context)
	assert.are.equal(expected_valid, valid)
	if expected_error then
		assert.are.equal(expected_error, err)
	else
		assert.is_nil(err)
	end
end

describe("turbo-needle.utils", function()
	describe("notification functions", function()
		it("should have notify function", function()
			assert.is_function(utils.notify)
		end)
	end)

	describe("utility functions", function()
		it("should check if value is empty", function()
			-- Test nil values
			assert.is_true(utils.is_empty(nil))

			-- Test empty strings
			assert.is_true(utils.is_empty(""))
			assert.is_false(utils.is_empty("   ")) -- Non-empty string with spaces

			-- Test empty tables
			assert.is_true(utils.is_empty({}))

			-- Test non-empty values
			assert.is_false(utils.is_empty("text"))
			assert.is_false(utils.is_empty({ 1, 2, 3 }))
			assert.is_false(utils.is_empty(0)) -- Numbers are not empty
			assert.is_false(utils.is_empty(false)) -- Booleans are not empty
			assert.is_false(utils.is_empty(true))
		end)

		it("should trim whitespace", function()
			-- Test leading/trailing spaces
			assert.are.equal("hello", utils.trim("  hello  "))
			assert.are.equal("hello world", utils.trim("  hello world  "))

			-- Test no trimming needed
			assert.are.equal("hello world", utils.trim("hello world"))

			-- Test only whitespace
			assert.are.equal("", utils.trim("   "))
			assert.are.equal("", utils.trim("\t\n  \t"))

			-- Test edge cases
			assert.are.equal("text", utils.trim("text"))
			assert.are.equal("", utils.trim(""))
		end)
	end)

	describe("completion validation", function()
		it("should validate good completions", function()
			test_completion_validation("function test() {", nil, true)
			test_completion_validation("const x = 42;", nil, true)
			test_completion_validation("if (condition) {\n    return true;\n}", nil, true)
		end)

		it("should reject empty completions", function()
			test_completion_validation("", nil, false, "Empty completion")
			test_completion_validation("   ", nil, false, "Empty completion")
			test_completion_validation("\t\n  \t", nil, false, "Empty completion")
		end)

		it("should reject invalid types", function()
			test_completion_validation(nil, nil, false, "Invalid completion format")
			test_completion_validation(123, nil, false, "Invalid completion format")
			test_completion_validation({}, nil, false, "Invalid completion format")
			test_completion_validation(true, nil, false, "Invalid completion format")
		end)

		it("should reject too short completions", function()
			test_completion_validation("x", nil, false, "Completion too short")
			test_completion_validation("a", nil, false, "Completion too short")
			test_completion_validation("", nil, false, "Empty completion")
		end)

		it("should reject too long completions", function()
			local long_completion = string.rep("a", 1001)
			test_completion_validation(long_completion, nil, false, "Completion too long")

			local very_long = string.rep("long text ", 200)
			test_completion_validation(very_long, nil, false, "Completion too long")
		end)

		it("should detect duplicate lines", function()
			-- Test with context where completion duplicates last line of prefix
			local context = {
				prefix = "function test() {\n    console.log('hello')",
				suffix = "\n}"
			}
			test_completion_validation("console.log('hello')\n    return true", context, false, "Duplicate line completion")

			-- Test with multi-line context - should detect duplicate
			local multiline_context = {
				prefix = "function foo() {\n    var x = 1;\n    var y = 2",
				suffix = "\n    return x + y;\n}"
			}
			test_completion_validation("var y = 2\n    var z = 3", multiline_context, false, "Duplicate line completion")

			-- Test with no duplicate - should pass
			local no_duplicate_context = {
				prefix = "function foo() {\n    var x = 1",
				suffix = "\n}"
			}
			test_completion_validation("var y = 2", no_duplicate_context, true)
		end)

		it("should handle edge cases", function()
			-- Test with empty context
			test_completion_validation("valid completion", {}, true)

			-- Test with nil context
			test_completion_validation("valid completion", nil, true)

			-- Test boundary length completions
			local min_valid = "ab" -- exactly 2 chars (minimum valid)
			test_completion_validation(min_valid, nil, true)

			local boundary_long = string.rep("a", 1000) -- exactly 1000 chars (maximum valid)
			test_completion_validation(boundary_long, nil, true)

			local too_long = string.rep("a", 1001) -- over maximum
			test_completion_validation(too_long, nil, false, "Completion too long")
		end)
	end)
end)
