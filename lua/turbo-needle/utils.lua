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
