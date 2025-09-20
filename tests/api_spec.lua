---@diagnostic disable: undefined-field

local api = require("turbo-needle.api")
local stub = require("luassert.stub")

describe("turbo-needle.api", function()
	describe("build_curl_args", function()
		it("should build default curl args without API key", function()
			local provider_opts = {
				base_url = "http://localhost:8000",
				model = "test-model",
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
			assert.are.equal("http://localhost:8000/v1/completions", result.url)
		end)
	end)

	describe("set_curl_args_hook", function()
		it("should allow setting custom curl args hook", function()
			local custom_hook = function(provider_opts, code_opts)
				return {
					url = "custom-url",
					headers = { ["Custom"] = "header" },
					body = { custom = "body" },
					timeout = 1000,
				}
			end

			api.set_curl_args_hook(custom_hook)
			assert.are.equal(custom_hook, api.custom_curl_args_hook)

			-- Clean up
			api.custom_curl_args_hook = nil
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
	end)
end)
