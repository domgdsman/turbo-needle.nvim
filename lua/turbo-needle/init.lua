local config = require("turbo-needle.config")
local utils = require("turbo-needle.utils")

local M = {}

M.config = config.defaults

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	if M.config.keymaps.enabled then
		M.setup_keymaps()
	end

	utils.notify("turbo-needle setup complete", vim.log.levels.INFO)
end

function M.setup_keymaps()
	for action, keymap in pairs(M.config.keymaps.mappings) do
		if keymap ~= "" then
			vim.keymap.set("n", keymap, function()
				M[action]()
			end, { desc = "turbo-needle: " .. action })
		end
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
