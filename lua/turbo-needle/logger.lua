local logging = require("turbo-needle.logging")

local M = {}

local logger_instance

local function get_instance()
	if not logger_instance then
		logger_instance = logging.Logger.new({
			log_level = vim.log.levels.INFO,
			prefix = "turbo-needle",
			echo_messages = true,
		})
	end

	return logger_instance
end

--- @param config table
function M.setup(config)
	if config.log_level then
		local log_level = logging.parse_log_level(config.log_level)
		if log_level ~= nil then
			logger_instance:set_log_level(log_level)
		end
	end

	if config.echo_messages ~= nil then
		logger_instance:set_echo_messages(config.echo_messages)
	end
end

setmetatable(M, {
	__index = function(_, key)
		local logger = get_instance()
		return logger[key]
	end,
})

return M
