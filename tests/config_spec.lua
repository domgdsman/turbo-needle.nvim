---@diagnostic disable: undefined-field

local config = require("turbo-needle.config")

describe("turbo-needle.config", function()
	describe("defaults", function()
		it("should have default configuration", function()
			assert.is_not_nil(config.defaults)
			assert.is_table(config.defaults.api)
			assert.is_table(config.defaults.completions)
			assert.is_table(config.defaults.keymaps)
			assert.is_table(config.defaults.filetypes)
		end)

		it("should have default API settings", function()
			local api = config.defaults.api
			assert.are.equal("http://localhost:8080", api.base_url)
			assert.are.equal("qwen3-coder", api.model)
			assert.are.equal("openai_compatible", api.provider)
			assert.are.equal("fim_prompt", api.mode)
			assert.is_nil(api.template)
			assert.is_nil(api.custom_template)
			assert.are.equal("auto", api.stop)
			assert.is_nil(api.path)
			assert.is_nil(api.api_key) -- Optional field, defaults to nil
			assert.are.equal(256, api.max_tokens) -- Default value
			assert.is_nil(api.temperature) -- Optional field, defaults to nil
			assert.is_true(api.stream)
			assert.is_table(api.extra_body)
			assert.is_table(api.headers)
			assert.are.equal(5000, api.timeout)
		end)

		it("should have default completions settings", function()
			local completions = config.defaults.completions
			assert.are.equal(600, completions.debounce_ms)
		end)

		it("should have default keymaps", function()
			local keymaps = config.defaults.keymaps
			assert.are.equal("<Tab>", keymaps.accept)
		end)

		it("should have default filetypes", function()
			local filetypes = config.defaults.filetypes
			assert.is_false(filetypes.help)
			assert.is_false(filetypes.gitcommit)
			assert.is_false(filetypes.gitrebase)
			assert.is_false(filetypes.hgcommit)
			assert.is_nil(filetypes.lua) -- unspecified filetypes should not be in defaults
		end)
	end)

	describe("validate", function()
		it("should validate correct configuration", function()
			assert.is_true(config.validate(config.defaults))
		end)

		it("should use old-compatible vim.validate table calls", function()
			local original_validate = vim.validate
			local calls = 0
			vim.validate = function(spec)
				calls = calls + 1
				assert.is_table(spec)
			end

			local ok, err = pcall(function()
				config.validate(config.defaults)
			end)

			vim.validate = original_validate
			assert.is_true(ok, err)
			assert.is_true(calls > 0)
		end)

		it("should reject invalid configuration", function()
			assert.has_error(function()
				config.validate({
					api = "invalid",
				})
			end)
		end)

		it("should validate api_key is string when set", function()
			assert.is_true(config.validate({
				api = {
					base_url = "http://localhost:8000",
					model = "test",
					api_key = "TEST_KEY", -- Valid string
					timeout = 5000,
				},
				completions = { debounce_ms = 300, throttle_ms = 1000 },
				keymaps = { accept = "<Tab>" },
				filetypes = {},
			}))
		end)

		it("should reject non-string api_key", function()
			assert.has_error(function()
				config.validate({
					api = {
						base_url = "http://localhost:8000",
						model = "test",
						api_key = 123, -- Invalid: number instead of string
						timeout = 5000,
					},
					completions = { debounce_ms = 300, throttle_ms = 600 },
					keymaps = { accept = "<Tab>" },
					filetypes = {},
				})
			end)
		end)

		it("should validate max_tokens and temperature when set", function()
			assert.is_true(config.validate({
				api = {
					base_url = "http://localhost:8000",
					model = "test",
					max_tokens = 100, -- Valid number
					temperature = 0.7, -- Valid number
					timeout = 5000,
				},
				completions = { debounce_ms = 300, throttle_ms = 600 },
				keymaps = { accept = "<Tab>" },
				filetypes = {},
			}))
		end)

		it("should validate stream when set", function()
			assert.is_true(config.validate({
				api = {
					base_url = "http://localhost:8000",
					model = "test",
					stream = true,
					timeout = 5000,
				},
				completions = { debounce_ms = 300 },
				keymaps = { accept = "<Tab>" },
				filetypes = {},
			}))
		end)

		it("should validate provider, mode, path, headers, and extra body", function()
			local valid = vim.deepcopy(config.defaults)
			valid.api.provider = "litellm"
			valid.api.mode = "fim_suffix"
			valid.api.path = "/v1/fim/completions"
			valid.api.template = "codestral"
			valid.api.stop = { "</s>", "[SUFFIX]" }
			valid.api.headers = { ["X-Test"] = "enabled" }
			valid.api.extra_body = { stop = { "\n\n" } }

			assert.is_true(config.validate(valid))
		end)

		it("should validate custom templates", function()
			local valid = vim.deepcopy(config.defaults)
			valid.api.custom_template = "a {prefix} b {suffix}"
			assert.is_true(config.validate(valid))

			local invalid = vim.deepcopy(config.defaults)
			invalid.api.custom_template = "missing suffix {prefix}"
			assert.has_error(function()
				config.validate(invalid)
			end)
		end)

		it("should reject invalid provider and mode", function()
			local invalid_provider = vim.deepcopy(config.defaults)
			invalid_provider.api.provider = "bogus"
			assert.has_error(function()
				config.validate(invalid_provider)
			end)

			local invalid_mode = vim.deepcopy(config.defaults)
			invalid_mode.api.mode = "bogus"
			assert.has_error(function()
				config.validate(invalid_mode)
			end)
		end)

		it("should reject invalid template and stop config", function()
			local invalid_template = vim.deepcopy(config.defaults)
			invalid_template.api.template = "bogus"
			assert.has_error(function()
				config.validate(invalid_template)
			end)

			local invalid_stop = vim.deepcopy(config.defaults)
			invalid_stop.api.stop = { "\n\n", 12 }
			assert.has_error(function()
				config.validate(invalid_stop)
			end)
		end)

		it("should reject non-string custom headers", function()
			local invalid = vim.deepcopy(config.defaults)
			invalid.api.headers = { ["X-Test"] = 12 }
			assert.has_error(function()
				config.validate(invalid)
			end)
		end)

		it("should reject non-boolean stream", function()
			assert.has_error(function()
				config.validate({
					api = {
						base_url = "http://localhost:8000",
						model = "test",
						stream = "true",
						timeout = 5000,
					},
					completions = { debounce_ms = 300 },
					keymaps = { accept = "<Tab>" },
					filetypes = {},
				})
			end)
		end)

		it("should reject non-number max_tokens", function()
			assert.has_error(function()
				config.validate({
					api = {
						base_url = "http://localhost:8000",
						model = "test",
						max_tokens = "invalid", -- Invalid: string instead of number
						timeout = 5000,
					},
					completions = { debounce_ms = 300, throttle_ms = 600 },
					keymaps = { accept = "<Tab>" },
					filetypes = {},
				})
			end)
		end)

		it("should reject non-number temperature", function()
			assert.has_error(function()
				config.validate({
					api = {
						base_url = "http://localhost:8000",
						model = "test",
						temperature = "invalid", -- Invalid: string instead of number
						timeout = 5000,
					},
					completions = { debounce_ms = 300, throttle_ms = 600 },
					keymaps = { accept = "<Tab>" },
					filetypes = {},
				})
			end)
		end)

		it("should substitute hardcoded API key", function()
			local test_config = {
				api = { api_key = "sk-test123" },
			}
			assert.has_no_errors(function()
				config.substitute_config_values_from_env(test_config)
			end)
			assert.are.equal("sk-test123", test_config.api.api_key)
		end)

		it("should substitute environment variables in API key", function()
			-- Mock os.getenv
			local original_getenv = os.getenv
			os.getenv = function(var)
				if var == "TEST_API_KEY" then
					return "sk-from-env"
				end
				return original_getenv(var)
			end

			local test_config = {
				api = { api_key = "{env:TEST_API_KEY}" },
			}
			assert.has_no_errors(function()
				config.substitute_config_values_from_env(test_config)
			end)
			assert.are.equal("sk-from-env", test_config.api.api_key)

			-- Restore
			os.getenv = original_getenv
		end)

		it("should error for missing environment variable", function()
			local test_config = {
				api = { api_key = "{env:NONEXISTENT_VAR}" },
			}
			assert.has_error(function()
				config.substitute_config_values_from_env(test_config)
			end)
		end)

		it("should reject empty string API key", function()
			local test_config = {
				api = { api_key = "" },
			}
			assert.has_error(function()
				config.validate(test_config)
			end)
		end)
	end)
end)
