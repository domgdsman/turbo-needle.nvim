local config = require("turbo-needle.config")
local cache = require("turbo-needle.cache")
local cleanup = require("turbo-needle.cleanup")
local ghost = require("turbo-needle.ghost")
local keymaps = require("turbo-needle.keymaps")
local lifecycle = require("turbo-needle.lifecycle")
local logger = require("turbo-needle.logger")
local postprocess = require("turbo-needle.postprocess")
local state_store = require("turbo-needle.state")
local version = require("turbo-needle.version")

local M = {}
M.version = version.version
M._VERSION = version.version

-- Module-scoped enabled state (private)
local enabled = true

-- Completion cache
local completion_cache = cache.new({ max_size = 50, ttl_ms = 2000 })

-- Buffer-local state
M._buf_states = {}
local function get_buf_state()
	return state_store.get(M._buf_states)
end

local function should_retry_postprocess(result, retry_config, attempt)
	retry_config = retry_config or {}
	if retry_config.enabled == false then
		return false
	end
	if attempt >= (retry_config.max_attempts or 0) then
		return false
	end
	if not result.rejected or not result.retryable then
		return false
	end
	local on_reasons = retry_config.on_reasons or {}
	return on_reasons[result.reason] == true
end

-- Private config storage
local _config = config.defaults

-- Public getter for config
function M.get_config()
	return vim.deepcopy(_config)
end

function M.setup(opts)
	local next_config = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), opts or {})

	-- Substitute environment variables in config
	local config_module = require("turbo-needle.config")
	local success, err = pcall(config_module.substitute_config_values_from_env, next_config)
	if not success then
		logger.error("Configuration substitution failed: " .. err)
		return
	end

	-- Validate configuration after substitution
	success, err = pcall(config_module.validate, next_config)
	if not success then
		logger.error("Configuration validation failed: " .. err)
		return
	end

	_config = next_config

	-- Set up logging
	logger.setup(M.get_config().logging)

	-- Setup completion triggering
	M.setup_completion_trigger()

	-- Setup keymaps
	M.setup_keymaps()

	logger.info("setup complete")
end

function M.setup_keymaps()
	keymaps.setup(_config.keymaps, function()
		return M.accept_completion()
	end)
end

function M.setup_completion_trigger()
	lifecycle.setup({
		config = _config,
		states = M._buf_states,
		get_state = get_buf_state,
		complete = M.complete,
		clear_ghost = M.clear_ghost_text,
		sync_ghost = function()
			return ghost.sync_with_typed_text(get_buf_state())
		end,
		is_enabled = function()
			return enabled
		end,
	})
end

-- Enable completions
function M.enable()
	enabled = true
	logger.info("completions enabled")
end

-- Disable completions
function M.disable()
	enabled = false
	logger.info("completions disabled")
end

-- Completion function: extract context and request completion
function M.complete()
	-- Only trigger completions in insert mode
	-- Also respect global enabled toggle
	if not M.enabled then
		return
	end
	if vim.api.nvim_get_mode().mode ~= "i" then
		return
	end

	local context = require("turbo-needle.context")
	if not context.is_filetype_supported() then
		return
	end

	local ctx = context.get_current_context()
	local api = require("turbo-needle.api")
	local state = get_buf_state()
	local cache_ctx = vim.tbl_extend("force", ctx, {
		cache_fingerprint = api.cache_fingerprint(_config.api),
	})

	-- Check cache first
	local cached_completion = completion_cache:get(cache_ctx)
	if cached_completion then
		M.set_ghost_text(cached_completion)
		return
	end

	-- Cancel any existing job before starting a new request
	if state.active_job then
		cleanup.shutdown_job(state.active_job)
		state.active_job = nil
	end

	-- Create a unique request ID to track this request
	state.request_counter = state.request_counter + 1
	local request_id = state.request_counter
	state.active_request_id = request_id

	local function request_completion(attempt)
		state.active_job = api.get_completion(
			ctx,
			vim.schedule_wrap(function(err, result)
				-- Check if this request was cancelled (newer request started)
				if state.active_request_id ~= request_id then
					return -- Request was cancelled, ignore result
				end

				-- Clear the active request and job
				state.active_request_id = nil
				state.active_job = nil

				if err then
					logger.error("Completion error: " .. err)
					return
				end

				-- Parse the completion text from API response
				local raw_completion_text = api.parse_response(result, _config.api)
				local postprocess_result = postprocess.classify(raw_completion_text, {
					config = _config.postprocess,
					api = _config.api,
					prefix = ctx.prefix,
					suffix = ctx.suffix,
				})
				local completion_text = postprocess_result.text
				if not completion_text then
					if should_retry_postprocess(postprocess_result, _config.postprocess.retry, attempt) then
						state.active_request_id = request_id
						request_completion(attempt + 1)
					end
					return
				end

				-- Cache the valid completion
				completion_cache:set(cache_ctx, completion_text)

				-- Set ghost text for the completion
				M.set_ghost_text(completion_text)
			end),
			_config.api.api_key
		)
	end

	-- Start the new request and store the job for potential cancellation
	request_completion(0)
end

-- Clear ghost text
function M.clear_ghost_text()
	ghost.clear(get_buf_state())
end

-- Set ghost text at cursor
function M.set_ghost_text(text)
	ghost.set(get_buf_state(), text)
end

-- Accept completion: insert ghost text if present, else return tab
function M.accept_completion()
	return ghost.accept(get_buf_state(), ghost.clear)
end

-- Metatable for read-only 'enabled' property
local mt = {
	__index = function(t, k)
		if k == "enabled" then
			return enabled -- Return the private enabled value
		end
		return rawget(t, k) -- Normal table access for other keys
	end,
	__newindex = function(t, k, v)
		if k == "enabled" then
			error("Cannot set 'enabled' directly. Use enable() or disable() functions.", 2)
		end
		rawset(t, k, v) -- Normal table assignment for other keys
	end,
}

return setmetatable(M, mt)
