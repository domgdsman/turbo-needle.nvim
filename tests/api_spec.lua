---@diagnostic disable: undefined-field

local api = require("turbo-needle.api")
local stub = require("luassert.stub")

describe("turbo-needle.api", function()
	describe("build_curl_args", function()
		it("should build default curl args without API key", function()
			local provider_opts = {
				base_url = "http://localhost:8000",
				model = "test-model",
				provider = "openai_compatible",
				mode = "fim_prompt",
				api_key_name = nil, -- will be updated later
				max_tokens = 200,
				temperature = 0.7,
				top_p = 0.8,
				top_k = 20,
				repetition_penalty = 1.05,
				timeout = 5000,
			}
			local code_opts = {
				prefix = "function test() {",
				suffix = "}",
			}

			local result = api.build_curl_args(provider_opts, code_opts, nil)

			assert.are.equal(0.8, result.body.top_p)
			assert.are.equal(20, result.body.top_k)
			assert.are.equal(1.05, result.body.repetition_penalty)
			assert.is_true(result.body.stream)
			assert.is_true(result.stream)
			assert.are.equal("http://localhost:8000/v1/completions", result.url)
			assert.is_nil(result.body.suffix)
		end)

		it("should disable streaming mode when explicitly disabled", function()
			local provider_opts = {
				base_url = "http://localhost:8000",
				model = "test-model",
				timeout = 5000,
				stream = false,
			}

			local result = api.build_curl_args(provider_opts, { prefix = "", suffix = "" }, nil)

			assert.is_false(result.body.stream)
			assert.is_false(result.stream)
		end)

		it("should build llama.cpp infill requests with native prefix and suffix fields", function()
			local result = api.build_curl_args({
				base_url = "http://localhost:8080",
				model = "local-model",
				provider = "llamacpp",
				mode = "llamacpp_infill",
				timeout = 5000,
				stream = false,
			}, { prefix = "local a = ", suffix = "\nprint(a)" }, nil)

			assert.are.equal("http://localhost:8080/infill", result.url)
			assert.are.equal("local a = ", result.body.input_prefix)
			assert.are.equal("\nprint(a)", result.body.input_suffix)
			assert.is_nil(result.body.prompt)
		end)

		it("should allow LiteLLM FIM path overrides with suffix-aware body", function()
			local result = api.build_curl_args({
				base_url = "http://litellm.local",
				model = "inception-model",
				provider = "litellm",
				mode = "fim_suffix",
				path = "/v1/fim/completions",
				timeout = 5000,
				extra_body = { stop = { "<|end|>" } },
			}, { prefix = "foo(", suffix = ")" }, nil)

			assert.are.equal("http://litellm.local/v1/fim/completions", result.url)
			assert.are.equal("foo(", result.body.prompt)
			assert.are.equal(")", result.body.suffix)
			assert.are.same({ "<|end|>" }, result.body.stop)
		end)

		it("should build chat fallback request bodies", function()
			local result = api.build_curl_args({
				base_url = "http://chat.local",
				model = "chat-model",
				provider = "chat",
				mode = "chat_fallback",
				timeout = 5000,
				headers = { ["X-Provider"] = "chat" },
			}, { prefix = "before", suffix = "after" }, "secret")

			assert.are.equal("http://chat.local/v1/chat/completions", result.url)
			assert.are.equal("Bearer secret", result.headers.Authorization)
			assert.are.equal("chat", result.headers["X-Provider"])
			assert.are.equal("chat-model", result.body.model)
			assert.are.equal("system", result.body.messages[1].role)
			assert.matches("before", result.body.messages[2].content, 1, true)
			assert.matches("after", result.body.messages[2].content, 1, true)
		end)

		it("should produce different cache fingerprints for request shape changes", function()
			local base = {
				base_url = "http://localhost:8080",
				model = "m1",
				provider = "openai_compatible",
				mode = "fim_prompt",
				stream = true,
				extra_body = {},
			}
			local changed_model = vim.tbl_extend("force", base, { model = "m2" })
			local changed_mode = vim.tbl_extend("force", base, { mode = "fim_suffix" })
			local changed_path = vim.tbl_extend("force", base, { path = "/v1/fim/completions" })

			assert.are_not.equal(api.cache_fingerprint(base), api.cache_fingerprint(changed_model))
			assert.are_not.equal(api.cache_fingerprint(base), api.cache_fingerprint(changed_mode))
			assert.are_not.equal(api.cache_fingerprint(base), api.cache_fingerprint(changed_path))
		end)
	end)

	describe("parse_response", function()
		it("should parse completion text from valid OpenAI response", function()
			local result = {
				choices = {
					{
						text = "completed code",
					},
				},
			}
			local text = api.parse_response(result)
			assert.are.equal("completed code", text)
		end)

		it("should preserve literal escape sequences from decoded JSON text", function()
			local result = {
				choices = {
					{
						text = [[literal \n text]],
					},
				},
			}

			local text = api.parse_response(result)
			assert.are.equal([[literal \n text]], text)
		end)

		it("should return empty string for invalid response", function()
			local text = api.parse_response(nil)
			assert.are.equal("", text)

			text = api.parse_response({})
			assert.are.equal("", text)

			text = api.parse_response({ choices = {} })
			assert.are.equal("", text)

			text = api.parse_response({ text = "some text" })
			assert.are.equal("", text)
		end)

		it("should parse chat fallback and llama.cpp infill responses", function()
			assert.are.equal(
				"chat code",
				api.parse_response({
					choices = {
						{ message = { content = "chat code" } },
					},
				}, { mode = "chat_fallback" })
			)

			assert.are.equal(
				"native code",
				api.parse_response({ content = "native code" }, { mode = "llamacpp_infill" })
			)
		end)
	end)
end)
