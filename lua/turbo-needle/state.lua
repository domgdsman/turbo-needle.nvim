local M = {}

function M.get(states, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not states[bufnr] then
		states[bufnr] = {
			debounce_timer = nil,
			current_extmark = nil,
			active_request_id = nil,
			active_job = nil,
			request_counter = 0,
			cached_completion = nil,
			original_completion = nil,
			cursor_position = nil,
			original_cursor_position = nil,
		}
	end
	return states[bufnr]
end

function M.delete(states, bufnr)
	states[bufnr] = nil
end

function M.valid_buffers()
	local valid_bufs = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			valid_bufs[buf] = true
		end
	end
	return valid_bufs
end

return M
