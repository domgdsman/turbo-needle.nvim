local M = {}

function M.notify(msg, level)
	level = level or vim.log.levels.INFO
	vim.notify("[turbo-needle] " .. msg, level)
end

function M.error(msg)
	M.notify(msg, vim.log.levels.ERROR)
end

function M.warn(msg)
	M.notify(msg, vim.log.levels.WARN)
end

function M.info(msg)
	M.notify(msg, vim.log.levels.INFO)
end

function M.debug(msg)
	M.notify(msg, vim.log.levels.DEBUG)
end

function M.get_cursor_pos()
	return vim.api.nvim_win_get_cursor(0)
end

function M.set_cursor_pos(pos)
	vim.api.nvim_win_set_cursor(0, pos)
end

function M.get_buf_lines(buf, start, end_)
	return vim.api.nvim_buf_get_lines(buf or 0, start or 0, end_ or -1, false)
end

function M.set_buf_lines(buf, start, end_, lines)
	vim.api.nvim_buf_set_lines(buf or 0, start or 0, end_ or -1, false, lines)
end

function M.create_buf(opts)
	opts = opts or {}
	local buf = vim.api.nvim_create_buf(opts.listed or false, opts.scratch or true)

	if opts.name then
		vim.api.nvim_buf_set_name(buf, opts.name)
	end

	if opts.filetype then
		vim.bo[buf].filetype = opts.filetype
	end

	return buf
end

function M.create_win(buf, opts)
	opts = opts or {}

	local width = opts.width or math.floor(vim.o.columns * 0.8)
	local height = opts.height or math.floor(vim.o.lines * 0.8)

	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local win_opts = {
		relative = opts.relative or "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		border = opts.border or "rounded",
		title = opts.title or "Turbo Needle",
		title_pos = "center",
	}

	return vim.api.nvim_open_win(buf, true, win_opts)
end

function M.close_win(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, false)
	end
end

function M.is_empty(value)
	if value == nil then
		return true
	end

	if type(value) == "string" then
		return value == ""
	end

	if type(value) == "table" then
		return next(value) == nil
	end

	return false
end

function M.trim(str)
	return str:match("^%s*(.-)%s*$")
end

return M
