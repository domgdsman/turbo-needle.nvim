local postprocess = require("turbo-needle.postprocess")

describe("turbo-needle.postprocess", function()
	it("rejects nil, non-string, and whitespace-only completions", function()
		assert.is_nil(postprocess.apply(nil, { config = {} }))
		assert.is_nil(postprocess.apply(12, { config = {} }))
		assert.is_nil(postprocess.apply(" \n\t", { config = {} }))
	end)

	it("trims completion suffix that duplicates text after the cursor", function()
		local result = postprocess.apply("bar)\nend", {
			config = {},
			prefix = "foo(",
			suffix = ")\nend",
		})

		assert.are.equal("bar", result)
	end)

	it("trims completion prefix that duplicates text before the cursor", function()
		local result = postprocess.apply("local value = compute()", {
			config = {},
			prefix = "local value = ",
			suffix = "",
		})

		assert.are.equal("compute()", result)
	end)

	it("keeps prefix overlap when disabled", function()
		local result = postprocess.apply("local value = compute()", {
			config = { trim_prefix_overlap = false },
			prefix = "local value = ",
			suffix = "",
		})

		assert.are.equal("local value = compute()", result)
	end)

	it("strips known FIM and chat sentinels", function()
		local result = postprocess.apply("<|fim_middle|>print(value)<|im_end|>", {
			config = {},
			prefix = "",
			suffix = "",
		})

		assert.are.equal("print(value)", result)
	end)

	it("classifies completions that only contain stop tokens", function()
		local result = postprocess.classify("<|fim_middle|><|im_end|>", {
			config = {},
			prefix = "",
			suffix = "",
		})

		assert.is_true(result.rejected)
		assert.are.equal("stop_token_only", result.reason)
		assert.is_true(result.retryable)
	end)

	it("unwraps markdown code fences around returned code", function()
		local result = postprocess.apply("```lua\nprint(value)\n```", {
			config = {},
			prefix = "",
			suffix = "",
		})

		assert.are.equal("print(value)", result)
	end)

	it("removes thinking artifacts and rejects thinking-only responses", function()
		local cleaned = postprocess.apply("<think>considering</think>\nreturn value", {
			config = {},
			prefix = "",
			suffix = "",
		})
		local rejected = postprocess.classify("<think>considering</think>", {
			config = {},
			prefix = "",
			suffix = "",
		})

		assert.are.equal("return value", cleaned)
		assert.is_true(rejected.rejected)
		assert.are.equal("thinking", rejected.reason)
		assert.is_true(rejected.retryable)
	end)

	it("rejects completions that rewrite the last non-empty line above the cursor", function()
		local result = postprocess.classify("local value = input\nlocal value = compute()", {
			config = {},
			prefix = "local value = input\n",
			suffix = "",
		})

		assert.is_true(result.rejected)
		assert.are.equal("line_rewrite", result.reason)
		assert.is_true(result.retryable)
	end)

	it("rejects extreme repeated-line output", function()
		local result = postprocess.classify("again\nagain\nagain\nagain", {
			config = {},
			prefix = "",
			suffix = "",
		})

		assert.is_true(result.rejected)
		assert.are.equal("repetition", result.reason)
		assert.is_true(result.retryable)
	end)

	it("classifies duplicate current line prefix and suffix responses without retry", function()
		local duplicate_prefix = postprocess.classify("  local value = ", {
			config = {},
			prefix = "local value = ",
			suffix = "",
		})
		local duplicate_suffix = postprocess.classify(" ) ", {
			config = {},
			prefix = "print(",
			suffix = ")",
		})

		assert.are.equal("duplicate_prefix", duplicate_prefix.reason)
		assert.is_false(duplicate_prefix.retryable)
		assert.are.equal("duplicate_suffix", duplicate_suffix.reason)
		assert.is_false(duplicate_suffix.retryable)
	end)

	it("strips configured stop tokens", function()
		local result = postprocess.apply("print(value)<STOP>", {
			config = {},
			api = { stop = "<STOP>" },
			prefix = "",
			suffix = "",
		})

		assert.are.equal("print(value)", result)
	end)

	it("preserves intentional leading whitespace and normalizes trailing whitespace", function()
		local result = postprocess.apply("  return value  \n", {
			config = {},
			prefix = "",
			suffix = "",
		})

		assert.are.equal("  return value", result)
	end)

	it("caps multiline completions by configured lines and characters", function()
		local by_lines = postprocess.apply("one\ntwo\nthree", {
			config = { max_lines = 2 },
			prefix = "",
			suffix = "",
		})
		local by_chars = postprocess.apply("abcdef", {
			config = { max_chars = 3 },
			prefix = "",
			suffix = "",
		})

		assert.are.equal("one\ntwo", by_lines)
		assert.are.equal("abc", by_chars)
	end)
end)
