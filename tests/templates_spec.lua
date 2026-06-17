---@diagnostic disable: undefined-field

local templates = require("turbo-needle.templates")

describe("turbo-needle.templates", function()
	describe("render", function()
		it("renders built-in autocomplete prompt shapes", function()
			local ctx = { prefix = "local x = ", suffix = "\nprint(x)" }

			assert.are.equal(
				"<|fim_prefix|>local x = <|fim_suffix|>\nprint(x)<|fim_middle|>",
				templates.render(
					templates.resolve({
						template = "qwen_coder",
						model = "ignored",
					}),
					ctx
				)
			)
			assert.are.equal(
				"<fim_prefix>local x = <fim_suffix>\nprint(x)<fim_middle>",
				templates.render(
					templates.resolve({
						template = "starcoder",
						model = "ignored",
					}),
					ctx
				)
			)
			assert.are.equal(
				"<PRE> local x =  <SUF>\nprint(x) <MID>",
				templates.render(
					templates.resolve({
						template = "codellama",
						model = "ignored",
					}),
					ctx
				)
			)
			assert.are.equal(
				"[PREFIX]local x = [SUFFIX]\nprint(x)",
				templates.render(
					templates.resolve({
						template = "codestral",
						model = "ignored",
					}),
					ctx
				)
			)
			assert.are.equal(
				"<｜fim▁begin｜>local x = <｜fim▁hole｜>\nprint(x)<｜fim▁end｜>",
				templates.render(
					templates.resolve({
						template = "deepseek_coder",
						model = "ignored",
					}),
					ctx
				)
			)
			assert.are.equal(
				"<|fim_prefix|>local x = <|fim_suffix|>\nprint(x)<|fim_middle|>",
				templates.render(
					templates.resolve({
						template = "codegemma",
						model = "ignored",
					}),
					ctx
				)
			)
			assert.are.equal(
				"<|fim_prefix|>local x = <|fim_suffix|>\nprint(x)<|fim_middle|>",
				templates.render(
					templates.resolve({
						template = "generic_fim",
						model = "ignored",
					}),
					ctx
				)
			)
		end)

		it("renders custom templates with structured fields", function()
			local template = templates.resolve({
				model = "qwen",
				custom_template = "before {prefix} middle {suffix} lang {language} file {filename}",
			})

			assert.are.equal(
				"before a middle b lang lua file init.lua",
				templates.render(template, {
					prefix = "a",
					suffix = "b",
					language = "lua",
					filename = "init.lua",
				})
			)
		end)
	end)

	describe("chat_messages", function()
		it("includes filename and language metadata when present", function()
			local messages = templates.chat_messages({
				prefix = "local x = ",
				suffix = "\nprint(x)",
				filename = "init.lua",
				language = "lua",
			})

			assert.are.equal(
				"Filename: init.lua\nLanguage: lua\n\nPrefix:\nlocal x = \n\nSuffix:\n\nprint(x)",
				messages[2].content
			)
		end)
	end)

	describe("resolve_name", function()
		it("matches common model names", function()
			assert.are.equal("qwen_coder", templates.resolve_name({ model = "Qwen2.5-Coder-7B" }))
			assert.are.equal("starcoder", templates.resolve_name({ model = "bigcode/starcoder2-15b" }))
			assert.are.equal("codellama", templates.resolve_name({ model = "CodeLlama-13b-hf" }))
			assert.are.equal("codestral", templates.resolve_name({ model = "Codestral-22B-v0.1" }))
			assert.are.equal("deepseek_coder", templates.resolve_name({ model = "deepseek-coder-v2" }))
			assert.are.equal("codegemma", templates.resolve_name({ model = "codegemma-7b" }))
		end)

		it("lets api.template override model matching", function()
			assert.are.equal(
				"codellama",
				templates.resolve_name({
					model = "qwen3-coder",
					template = "codellama",
				})
			)
		end)
	end)

	describe("validation", function()
		it("rejects custom templates without prefix and suffix placeholders", function()
			assert.has_error(function()
				templates.validate_custom_template("{prefix}")
			end)
			assert.has_error(function()
				templates.validate_custom_template("{suffix}")
			end)
		end)
	end)

	describe("merge_stop", function()
		it("uses template stop tokens for auto stop", function()
			local template = templates.resolve({ template = "qwen_coder", model = "ignored" })
			assert.are.same(
				{ "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<|endoftext|>" },
				templates.merge_stop(template, "auto")
			)
		end)

		it("merges user and template stop tokens without duplicates", function()
			local template = templates.resolve({ template = "qwen_coder", model = "ignored" })
			assert.are.same(
				{ "\n\n", "<|fim_middle|>", "<|fim_prefix|>", "<|fim_suffix|>", "<|endoftext|>" },
				templates.merge_stop(template, { "\n\n", "<|fim_middle|>" })
			)
		end)
	end)
end)
