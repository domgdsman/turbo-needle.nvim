local config = require("turbo-needle.config")
local utils = require("turbo-needle.utils")

local M = {}

M.config = config.defaults

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Validate API key configuration
	local api = require("turbo-needle.api")
	api.validate_api_key_config()

	utils.notify("turbo-needle setup complete", vim.log.levels.INFO)
end

function M.setup_keymaps()
	if M.config.keymaps.accept and M.config.keymaps.accept ~= "" then
		vim.keymap.set("i", M.config.keymaps.accept, function()
			-- TODO: Implement completion acceptance
			return M.config.keymaps.accept
		end, { desc = "turbo-needle: accept completion" })
	end
end

function M.run(args)
	utils.notify("Running turbo-needle with args: " .. (args or "none"), vim.log.levels.INFO)
end

function M.toggle()
	utils.notify("Toggle functionality not yet implemented", vim.log.levels.WARN)
end

function M.open()
	utils.notify("Open functionality not yet implemented", vim.log.levels.WARN)
end

function M.close()
	utils.notify("Close functionality not yet implemented", vim.log.levels.WARN)
end

return M
