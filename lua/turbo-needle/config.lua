local M = {}

M.defaults = {
	keymaps = {
		enabled = true,
		mappings = {
			toggle = "<leader>tn",
			open = "<leader>to",
			close = "<leader>tc",
		},
	},
	ui = {
		border = "rounded",
		width = 0.8,
		height = 0.8,
		title = "Turbo Needle",
	},
	behavior = {
		auto_close = false,
		save_position = true,
		restore_cursor = true,
	},
	notifications = {
		enabled = true,
		level = vim.log.levels.INFO,
	},
}

function M.validate(config)
	vim.validate({
		keymaps = { config.keymaps, "table" },
		ui = { config.ui, "table" },
		behavior = { config.behavior, "table" },
		notifications = { config.notifications, "table" },
	})

	vim.validate({
		["keymaps.enabled"] = { config.keymaps.enabled, "boolean" },
		["keymaps.mappings"] = { config.keymaps.mappings, "table" },
		["ui.border"] = { config.ui.border, "string" },
		["ui.width"] = { config.ui.width, "number" },
		["ui.height"] = { config.ui.height, "number" },
		["notifications.enabled"] = { config.notifications.enabled, "boolean" },
	})

	return true
end

return M
