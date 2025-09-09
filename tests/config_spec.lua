local config = require("turbo-needle.config")

describe("turbo-needle.config", function()
	describe("defaults", function()
		it("should have default configuration", function()
			assert.is_not_nil(config.defaults)
			assert.is_table(config.defaults.keymaps)
			assert.is_table(config.defaults.ui)
			assert.is_table(config.defaults.behavior)
			assert.is_table(config.defaults.notifications)
		end)

		it("should have default keymaps", function()
			local keymaps = config.defaults.keymaps
			assert.is_true(keymaps.enabled)
			assert.is_table(keymaps.mappings)
			assert.are.equal("<leader>tn", keymaps.mappings.toggle)
		end)

		it("should have default UI settings", function()
			local ui = config.defaults.ui
			assert.are.equal("rounded", ui.border)
			assert.are.equal(0.8, ui.width)
			assert.are.equal(0.8, ui.height)
			assert.are.equal("Turbo Needle", ui.title)
		end)
	end)

	describe("validate", function()
		it("should validate correct configuration", function()
			assert.is_true(config.validate(config.defaults))
		end)

		it("should reject invalid configuration", function()
			assert.has_error(function()
				config.validate({
					keymaps = "invalid",
				})
			end)
		end)
	end)
end)
