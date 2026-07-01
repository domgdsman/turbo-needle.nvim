local M = {}

function M.is_normal_file(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr)
		and vim.api.nvim_buf_is_loaded(bufnr)
		and vim.bo[bufnr].buflisted
		and vim.bo[bufnr].buftype == ""
		and vim.api.nvim_buf_get_name(bufnr) ~= ""
end

return M
