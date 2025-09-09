local M = {}

function M.notify(msg, level)
	level = level or vim.log.levels.INFO
	-- Defer notification to avoid fast event context issues
	vim.schedule(function()
		vim.notify("[turbo-needle] " .. msg, level)
	end)
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
