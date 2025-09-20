local logging = require("turbo-needle.logging")

local M = {}

local logger_instance

local function get_instance()
	if not logger_instance then
		logger_instance = logging.Logger.new({
			log_level = vim.log.levels.DEBUG,
			prefix = "turbo-needle",
			echo_messages = true,
		})
	end

	return logger_instance
end

function M.trace(...)
	get_instance():trace(...)
end

function M.debug(...)
	get_instance():debug(...)
end

function M.info(...)
	get_instance():info(...)
end

function M.warn(...)
	get_instance():warn(...)
end

function M.error(...)
	get_instance():error(...)
end

function M.setup(config)
	local logger = get_instance()

	if config.log_level then
		local log_level = logging.parse_log_level(config.log_level)
		if log_level ~= nil then
			logger:set_log_level(log_level)
		end
	end

	if config.echo_messages ~= nil then
		logger:set_echo_messages(config.echo_messages)
	end
end

return M
