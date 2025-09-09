local turbo_needle = require("turbo-needle")

describe("turbo-needle", function()
	before_each(function()
		turbo_needle.config = require("turbo-needle.config").defaults
	end)

	describe("setup", function()
		it("should setup with default configuration", function()
			turbo_needle.setup()
			assert.is_not_nil(turbo_needle.config)
			assert.is_true(turbo_needle.config.keymaps.enabled)
		end)

		it("should merge custom configuration", function()
			turbo_needle.setup({
				keymaps = { enabled = false },
			})
			assert.is_false(turbo_needle.config.keymaps.enabled)
		end)
	end)

	describe("run", function()
		it("should run without arguments", function()
			assert.has_no.errors(function()
				turbo_needle.run()
			end)
		end)

		it("should run with arguments", function()
			assert.has_no.errors(function()
				turbo_needle.run("test args")
			end)
		end)
	end)

	describe("api functions", function()
		it("should have toggle function", function()
			assert.is_function(turbo_needle.toggle)
		end)

		it("should have open function", function()
			assert.is_function(turbo_needle.open)
		end)

		it("should have close function", function()
			assert.is_function(turbo_needle.close)
		end)
	end)
end)
