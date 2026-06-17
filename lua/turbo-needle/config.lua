local M = {}

local function validate(name, value, expected)
	vim.validate({
		[name] = { value, expected },
	})
end

-- Substitute environment variables in strings like "{env:VAR_NAME}"
local function substitute_env(str)
	return (str:gsub("{env:([%w_]+)}", function(var)
		return os.getenv(var) or ""
	end))
end

M.defaults = {
	api = {
		base_url = "http://localhost:8080",
		model = "qwen3-coder",
		provider = "openai_compatible",
		mode = "fim_prompt",
		path = nil,
		api_key = nil, -- API key or env var reference like "{env:VAR_NAME}" (optional)
		max_tokens = 256, -- Maximum tokens to generate
		temperature = nil, -- Optional: Sampling temperature (0.0 to 2.0)
		top_p = nil, -- Optional: Top-p sampling parameter
		top_k = nil, -- Optional: Top-k sampling parameter
		repetition_penalty = nil, -- Optional: Repetition penalty parameter
		stream = true, -- Use curl's streaming response path unless explicitly disabled
		extra_body = {},
		headers = {},
		timeout = 5000,
	},
	completions = {
		debounce_ms = 600,
	},
	keymaps = {
		accept = "<Tab>",
	},
	filetypes = {
		help = false,
		gitcommit = false,
		gitrebase = false,
		hgcommit = false,
	},
	logging = {
		log_level = nil,
		echo_messages = nil,
	},
}

function M.validate(config)
	validate("config", config, "table")
	validate("config.api", config.api, "table")
	validate("config.completions", config.completions, "table")
	validate("config.keymaps", config.keymaps, "table")
	validate("config.filetypes", config.filetypes, "table")
	if config.logging then
		validate("config.logging", config.logging, "table")
	end

	validate("api.base_url", config.api.base_url, "string")
	validate("api.model", config.api.model, "string")
	validate("api.timeout", config.api.timeout, "number")
	local provider = config.api.provider or M.defaults.api.provider
	local mode = config.api.mode or M.defaults.api.mode
	validate("api.provider", provider, "string")
	validate("api.mode", mode, "string")
	if config.api.stream ~= nil then
		validate("api.stream", config.api.stream, "boolean")
	end
	if config.api.path ~= nil then
		validate("api.path", config.api.path, "string")
	end
	local extra_body = config.api.extra_body or {}
	local headers = config.api.headers or {}
	validate("api.extra_body", extra_body, "table")
	validate("api.headers", headers, "table")
	validate("completions.debounce_ms", config.completions.debounce_ms, "number")

	local valid_providers = {
		openai_compatible = true,
		vllm = true,
		llamacpp = true,
		litellm = true,
		chat = true,
	}
	if not valid_providers[provider] then
		error("api.provider must be one of: openai_compatible, vllm, llamacpp, litellm, chat", 0)
	end

	local valid_modes = {
		fim_prompt = true,
		fim_suffix = true,
		llamacpp_infill = true,
		chat_fallback = true,
	}
	if not valid_modes[mode] then
		error("api.mode must be one of: fim_prompt, fim_suffix, llamacpp_infill, chat_fallback", 0)
	end

	for header, value in pairs(headers) do
		validate("api.headers." .. tostring(header), value, "string")
	end

	-- Validate api_key is string when set and not empty
	if config.api.api_key ~= nil then
		validate("api.api_key", config.api.api_key, "string")
		if config.api.api_key == "" then
			error("api.api_key cannot be an empty string", 0)
		end
	end

	-- Validate max_tokens is number when set
	if config.api.max_tokens ~= nil then
		validate("api.max_tokens", config.api.max_tokens, "number")
	end

	-- Validate temperature is number when set
	if config.api.temperature ~= nil then
		validate("api.temperature", config.api.temperature, "number")
	end

	-- Validate top_p is number when set
	if config.api.top_p ~= nil then
		validate("api.top_p", config.api.top_p, "number")
	end

	-- Validate top_k is number when set
	if config.api.top_k ~= nil then
		validate("api.top_k", config.api.top_k, "number")
	end

	-- Validate repetition_penalty is number when set
	if config.api.repetition_penalty ~= nil then
		validate("api.repetition_penalty", config.api.repetition_penalty, "number")
	end

	-- Validate filetypes table values are booleans
	if config.filetypes then
		for filetype, enabled in pairs(config.filetypes) do
			validate("filetypes." .. filetype, enabled, "boolean")
		end
	end

	-- Validate logging fields when logging config is present
	if config.logging then
		-- Validate log_level is string when set
		if config.logging.log_level ~= nil then
			validate("logging.log_level", config.logging.log_level, "string")
		end

		-- Validate echo_messages is boolean when set
		if config.logging.echo_messages ~= nil then
			validate("logging.echo_messages", config.logging.echo_messages, "boolean")
		end
	end

	return true
end

-- Substitute environment variables in config
function M.substitute_config_values_from_env(config)
	-- Substitute environment variables in API key
	if config.api.api_key then
		local substituted = substitute_env(config.api.api_key)
		if substituted == config.api.api_key then
			-- No substitution occurred, treat as literal value
			return
		end

		-- Check if environment variable was found
		if substituted == "" then
			error(
				string.format(
					"Environment variable in API key configuration '%s' is not set or empty",
					config.api.api_key
				),
				0
			)
		end

		-- Successful substitution
		config.api.api_key = substituted
	end
end

return M
