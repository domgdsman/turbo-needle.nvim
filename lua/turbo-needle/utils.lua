local M = {}

function M.notify(msg, level)
	level = level or vim.log.levels.INFO
	-- Defer notification to avoid fast event context issues
	vim.schedule(function()
		vim.notify("[turbo-needle] " .. msg, level)
	end)
end

return M
