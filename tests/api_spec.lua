---@diagnostic disable: undefined-field

local api = require("turbo-needle.api")
local stub = require("luassert.stub")

describe("turbo-needle.api", function()
	describe("build_curl_args", function()
		it("should build default curl args without API key", function()
			local provider_opts = {
				base_url = "http://localhost:8000",
				model = "test-model",
				api_key_name = nil, -- nil, so no auth header
				max_tokens = 256, -- Use default value
				temperature = 0.1, -- Use default value
				timeout = 5000,
			}
			local code_opts = {
				prefix = "function test() {",
				suffix = "}",
			}

			local result = api.build_curl_args(provider_opts, code_opts)

			assert.are.equal("http://localhost:8000/v1/completions", result.url)
			assert.is_nil(result.headers["Authorization"]) -- No API key set
			assert.are.equal("application/json", result.headers["Content-Type"])
			assert.is_not_nil(string.find(result.body.prompt, "<|fim_prefix|>"))
			assert.are.equal("test-model", result.body.model)
			assert.are.equal(256, result.body.max_tokens) -- Default value
			assert.are.equal(0.1, result.body.temperature) -- Default value
			assert.are.equal(false, result.body.stream)
			assert.are.equal(5000, result.timeout)
		end)

		it("should handle environment variable API key", function()
			-- Mock os.getenv for testing
			stub(os, "getenv")
			os.getenv.returns("env-key")

			local provider_opts = {
				base_url = "http://localhost:8000",
				model = "test-model",
				api_key_name = "TEST_API_KEY",
				timeout = 5000,
			}
			local code_opts = {
				prefix = "function test() {",
				suffix = "}",
			}

			local result = api.build_curl_args(provider_opts, code_opts)

			assert.are.equal("Bearer env-key", result.headers["Authorization"])
			assert.are.equal("http://localhost:8000/v1/completions", result.url)
			assert.is_not_nil(result.body.prompt)

			-- Verify the function was called with the expected argument
			assert.stub(os.getenv).was_called_with("TEST_API_KEY")
		end)

		it("should include max_tokens and temperature when set", function()
			local provider_opts = {
				base_url = "http://localhost:8000",
				model = "test-model",
				api_key_name = nil,
				max_tokens = 150, -- Set to include in body
				temperature = 0.8, -- Set to include in body
				timeout = 5000,
			}
			local code_opts = {
				prefix = "function test() {",
				suffix = "}",
			}

			local result = api.build_curl_args(provider_opts, code_opts)

			assert.are.equal(150, result.body.max_tokens)
			assert.are.equal(0.8, result.body.temperature)
			assert.are.equal("http://localhost:8000/v1/completions", result.url)
			assert.is_not_nil(result.body.prompt)
		end)

		it("should include optional parameters when set", function()
			local provider_opts = {
				base_url = "http://localhost:8000",
				model = "test-model",
				api_key_name = nil,
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

			local result = api.build_curl_args(provider_opts, code_opts)

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

	describe("validate_api_key_config", function()
		it("should not warn when api_key_name is nil", function()
			local config = require("turbo-needle.config")
			local original_defaults = config.defaults
			config.defaults = vim.tbl_deep_extend("force", config.defaults, {
				api = { api_key_name = nil },
			})

			-- This should not produce any warnings
			assert.has_no.errors(function()
				api.validate_api_key_config()
			end)

			-- Restore
			config.defaults = original_defaults
		end)

		it("should warn when api_key_name is set but env var is missing", function()
			local turbo_needle = require("turbo-needle")

			-- Mock missing environment variable
			stub(os, "getenv")
			os.getenv.returns(nil)

			-- Setup turbo-needle with custom config
			turbo_needle.setup({
				api = { api_key_name = "MISSING_API_KEY" },
			})

			-- Mock logger.warn
			local logger = require("turbo-needle.logger")
			stub(logger, "warn")

			api.validate_api_key_config()

			-- Verify functions were called with expected arguments
			assert.stub(os.getenv).was_called_with("MISSING_API_KEY")
			assert.stub(logger.warn).was_called()
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
