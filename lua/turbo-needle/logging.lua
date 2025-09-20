local M = {}

local LOG_LEVELS = {
	TRACE = vim.log.levels.TRACE,
	DEBUG = vim.log.levels.DEBUG,
	INFO = vim.log.levels.INFO,
	WARN = vim.log.levels.WARN,
	ERROR = vim.log.levels.ERROR,
	OFF = vim.log.levels.OFF,
}

--------------------------------------------------------------------------------
-- Logger Class
--------------------------------------------------------------------------------

---Logger class for logging messages via vim.notify and :messages.
---Usage: `local logger = require("logging").Logger.new({ log_level = vim.log.levels.DEBUG, prefix = "my_prefix" })`
---@class Logger
---@field log_level number The current log level
---@field prefix string? Optional prefix for log messages
---@field echo_messages boolean Whether to echo to :messages buffer
local Logger = {}
Logger.__index = Logger

---Function that handles vararg printing for consistent logs
---@vararg any
---@return string
local function to_print(...)
	local args = { ... }
	if #args == 1 then
		local arg = args[1]
		if type(arg) == "table" then
			return vim.inspect(arg)
		end
		return tostring(arg)
	end

	local result = {}
	for i, value in ipairs(args) do
		result[i] = type(value) == "table" and vim.inspect(value) or tostring(value)
	end
	return table.concat(result, " ")
end

---Helper function to log both via vim.notify and to :messages
---@param message string The message to log
---@param level number The log level (vim.log.levels)
---@param self Logger The logger instance
local function log_message(message, level, self)
	vim.notify(message, level)

	if self.echo_messages then
		local hl_group = ({
			[LOG_LEVELS.ERROR] = "ErrorMsg",
			[LOG_LEVELS.WARN] = "WarningMsg",
			[LOG_LEVELS.INFO] = "None",
			[LOG_LEVELS.DEBUG] = "Comment",
			[LOG_LEVELS.TRACE] = "Comment",
		})[level] or "Normal"

		vim.api.nvim_echo({ { message, hl_group } }, true, {})
	end
end

---Constructor for Logger class
---@param config? {log_level?: number, prefix?: string, echo_messages?: boolean} Configuration table
---@return Logger
function Logger.new(config)
	config = config or {}

	local self = setmetatable({
		log_level = config.log_level or LOG_LEVELS.INFO,
		prefix = config.prefix or "",
		echo_messages = config.echo_messages or false,
	}, Logger)

	return self
end

---Set the log level for the logger
---@param level number Log level from vim.log.levels
function Logger:set_log_level(level)
	if type(level) ~= "number" then
		error("Log level must be a number from vim.log.levels")
	end
	self.log_level = level
end

---Set the prefix for the logger
---@param prefix string
function Logger:set_prefix(prefix)
	self.prefix = prefix or ""
end

---Set whether to echo messages to :messages buffer
---@param echo boolean
function Logger:set_echo_messages(echo)
	self.echo_messages = echo
end

---Format message with prefix and level
---@param level_name string
---@param ... any
---@return string
local function format_message(self, level_name, ...)
	local content = to_print(...)
	if self.prefix and self.prefix ~= "" then
		return string.format("%s %s: %s", self.prefix, level_name, content)
	end
	return string.format("%s: %s", level_name, content)
end

---Log a trace message
---@vararg any
function Logger:trace(...)
	if self.log_level <= LOG_LEVELS.TRACE then
		local message = format_message(self, "TRACE", ...)
		log_message(message, LOG_LEVELS.TRACE, self)
	end
end

---Log a debug message
---@vararg any
function Logger:debug(...)
	if self.log_level <= LOG_LEVELS.DEBUG then
		local message = format_message(self, "DEBUG", ...)
		log_message(message, LOG_LEVELS.DEBUG, self)
	end
end

---Log an info message
---@vararg any
function Logger:info(...)
	if self.log_level <= LOG_LEVELS.INFO then
		local message = format_message(self, "INFO", ...)
		log_message(message, LOG_LEVELS.INFO, self)
	end
end

---Log a warning message
---@vararg any
function Logger:warn(...)
	if self.log_level <= LOG_LEVELS.WARN then
		local message = format_message(self, "WARN", ...)
		log_message(message, LOG_LEVELS.WARN, self)
	end
end

---Log an error message
---@vararg any
function Logger:error(...)
	if self.log_level <= LOG_LEVELS.ERROR then
		local message = format_message(self, "ERROR", ...)
		log_message(message, LOG_LEVELS.ERROR, self)
	end
end

M.Logger = Logger

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

---Parse log level from string or number
---@param level string | number | nil The log level name (e.g., "DEBUG", "warn") or number.
---@return number | nil The corresponding number from `vim.log.levels`, or `nil` if the input is invalid.
function M.parse_log_level(level)
	if type(level) == "number" then
		return level
	end

	if type(level) ~= "string" or level == "" then
		return nil
	end

	return LOG_LEVELS[level:upper()]
end

return M
