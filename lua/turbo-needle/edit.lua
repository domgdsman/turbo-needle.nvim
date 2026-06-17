local M = {}

function M.insert_at_cursor(text, stored_pos)
	if not text or not stored_pos then
		return nil
	end

	local cur = vim.api.nvim_win_get_cursor(0)
	local row = cur[1] - 1
	local col = cur[2]
	if row ~= stored_pos.row then
		return nil
	end

	local line_text = vim.api.nvim_get_current_line()
	local line_len = #line_text
	if col > line_len then
		col = line_len
	end

	local lines = vim.split(text, "\n", { plain = true })
	if not pcall(vim.api.nvim_buf_set_text, 0, row, col, row, col, lines) then
		return nil
	end

	if #lines == 1 then
		return { row = row, col = col + #lines[1] }
	end

	return { row = row + (#lines - 1), col = #lines[#lines] }
end

return M
