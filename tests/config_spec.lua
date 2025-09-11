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
			assert.are.equal("http://localhost:8000", api.base_url)
			assert.are.equal("codellama:7b-code", api.model)
			assert.is_nil(api.api_key_name) -- Optional field, defaults to nil
			assert.are.equal(256, api.max_tokens) -- Default value
			assert.is_nil(api.temperature) -- Optional field, defaults to nil
			assert.are.equal(5000, api.timeout)
			assert.are.equal(2, api.max_retries)
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
			assert.is_table(filetypes.enabled)
			assert.is_table(filetypes.disabled)
			assert.are.equal("lua", filetypes.enabled[1])
			assert.are.equal("markdown", filetypes.disabled[1])
		end)
	end)

	describe("validate", function()
		it("should validate correct configuration", function()
			assert.is_true(config.validate(config.defaults))
		end)

		it("should reject invalid configuration", function()
			assert.has_error(function()
				config.validate({
					api = "invalid",
				})
			end)
		end)

		it("should validate api_key_name is string when set", function()
			assert.is_true(config.validate({
				api = {
					base_url = "http://localhost:8000",
					model = "test",
					api_key_name = "TEST_KEY", -- Valid string
					timeout = 5000,
					max_retries = 2,
				},
				completions = { debounce_ms = 300, throttle_ms = 1000 },
				keymaps = { accept = "<Tab>" },
				filetypes = { enabled = {}, disabled = {} },
			}))
		end)

		it("should reject non-string api_key_name", function()
			assert.has_error(function()
				config.validate({
					api = {
						base_url = "http://localhost:8000",
						model = "test",
						api_key_name = 123, -- Invalid: number instead of string
						timeout = 5000,
						max_retries = 2,
					},
					completions = { debounce_ms = 300, throttle_ms = 600 },
					keymaps = { accept = "<Tab>" },
					filetypes = { enabled = {}, disabled = {} },
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
					max_retries = 2,
				},
				completions = { debounce_ms = 300, throttle_ms = 600 },
				keymaps = { accept = "<Tab>" },
				filetypes = { enabled = {}, disabled = {} },
			}))
		end)

		it("should reject non-number max_tokens", function()
			assert.has_error(function()
				config.validate({
					api = {
						base_url = "http://localhost:8000",
						model = "test",
						max_tokens = "invalid", -- Invalid: string instead of number
						timeout = 5000,
						max_retries = 2,
					},
					completions = { debounce_ms = 300, throttle_ms = 600 },
					keymaps = { accept = "<Tab>" },
					filetypes = { enabled = {}, disabled = {} },
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
						max_retries = 2,
					},
					completions = { debounce_ms = 300, throttle_ms = 600 },
					keymaps = { accept = "<Tab>" },
					filetypes = { enabled = {}, disabled = {} },
				})
			end)
		end)

		it("should validate parse_response is function when set", function()
			assert.has_no.errors(function()
				config.validate({
					api = {
						base_url = "http://localhost:8000",
						model = "test",
						timeout = 5000,
						max_retries = 2,
						parse_response = function(result)
							return result.content or ""
						end, -- Valid function
					},
					completions = { debounce_ms = 300 },
					keymaps = { accept = "<Tab>" },
					filetypes = { enabled = {}, disabled = {} },
				})
			end)
		end)

		it("should reject non-function parse_response", function()
			assert.has_error(function()
				config.validate({
					api = {
						base_url = "http://localhost:8000",
						model = "test",
						timeout = 5000,
						max_retries = 2,
						parse_response = "invalid", -- Invalid: string instead of function
					},
					completions = { debounce_ms = 300 },
					keymaps = { accept = "<Tab>" },
					filetypes = { enabled = {}, disabled = {} },
				})
			end)
		end)
	end)
end)
