local api = require("turbo-needle.api")

describe("turbo-needle.api", function()
	describe("build_curl_args", function()
		it("should build default curl args without API key", function()
			local provider_opts = {
				base_url = "http://localhost:8000",
				model = "test-model",
				api_key_name = nil, -- nil, so no auth header
				max_tokens = nil, -- nil, so not included
				temperature = nil, -- nil, so not included
				timeout = 5000,
			}
			local code_opts = {
				prefix = "function test() {",
				suffix = "}",
			}

			local result = api.build_curl_args(provider_opts, code_opts)

			assert.are.equal("http://localhost:8000/v1/chat/completions", result.url)
			assert.is_nil(result.headers["Authorization"]) -- No API key set
			assert.are.equal("application/json", result.headers["Content-Type"])
			assert.are.equal("test-model", result.body.model)
			assert.is_table(result.body.messages)
			assert.are.equal(2, #result.body.messages)
			assert.are.equal("system", result.body.messages[1].role)
			assert.are.equal("user", result.body.messages[2].role)
			assert.is_not_nil(string.find(result.body.messages[2].content, "<|fim_prefix|>"))
			assert.is_nil(result.body.max_tokens) -- Not included when nil
			assert.is_nil(result.body.temperature) -- Not included when nil
			assert.are.equal(5000, result.timeout)
		end)

		it("should handle environment variable API key", function()
			-- Mock os.getenv for testing
			local original_getenv = os.getenv
			os.getenv = function(key)
				if key == "TEST_API_KEY" then
					return "env-key"
				end
				return original_getenv(key)
			end

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
			assert.are.equal("http://localhost:8000/v1/chat/completions", result.url)
			assert.is_table(result.body.messages)

			-- Restore original getenv
			os.getenv = original_getenv
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
			assert.are.equal("http://localhost:8000/v1/chat/completions", result.url)
			assert.is_table(result.body.messages)
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
			local config = require("turbo-needle.config")
			local original_defaults = config.defaults
			local original_getenv = os.getenv

			-- Mock missing environment variable
			os.getenv = function(key)
				if key == "MISSING_API_KEY" then
					return nil
				end
				return original_getenv(key)
			end

			config.defaults = vim.tbl_deep_extend("force", config.defaults, {
				api = { api_key_name = "MISSING_API_KEY" },
			})

			-- Mock utils.warn to capture the warning
			local utils = require("turbo-needle.utils")
			local original_warn = utils.warn
			local warning_called = false
			local warning_message = ""
			utils.warn = function(msg)
				warning_called = true
				warning_message = msg
			end

			api.validate_api_key_config()

			assert.is_true(warning_called)
			assert.is_not_nil(string.find(warning_message, "MISSING_API_KEY"))

			-- Restore
			os.getenv = original_getenv
			utils.warn = original_warn
			config.defaults = original_defaults
		end)
	end)

	describe("parse_response", function()
		it("should parse completion text from valid response", function()
			local result = {
				choices = {
					{
						message = {
							content = "completed code"
						}
					}
				}
			}
			local text = api.parse_response(result)
			assert.are.equal("completed code", text)
		end)

		it("should return empty string for invalid response", function()
			local text = api.parse_response(nil)
			assert.are.equal("", text)

			text = api.parse_response({})
			assert.are.equal("", text)

			text = api.parse_response({choices = {}})
			assert.are.equal("", text)

			text = api.parse_response({choices = {{message = {}}}})
			assert.are.equal("", text)
		end)
	end)
end)
