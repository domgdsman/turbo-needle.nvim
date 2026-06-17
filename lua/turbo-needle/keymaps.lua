local M = {}

local current_accept_keymap = nil

function M.setup(keymaps, accept)
	if current_accept_keymap then
		pcall(vim.keymap.del, "i", current_accept_keymap)
		current_accept_keymap = nil
	end

	if keymaps.accept and keymaps.accept ~= "" then
		vim.keymap.set("i", keymaps.accept, accept, { expr = true, desc = "turbo-needle: accept completion" })
		current_accept_keymap = keymaps.accept
	end
end

return M
