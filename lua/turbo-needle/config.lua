local M = {}

M.defaults = {
	api = {
		base_url = "http://localhost:8080",
		model = "qwen3-coder",
		api_key_name = nil, -- Environment variable name for API key (optional)
		max_tokens = 256, -- Maximum tokens to generate
		temperature = nil, -- Optional: Sampling temperature (0.0 to 2.0)
		top_p = nil, -- Optional: Top-p sampling parameter
		top_k = nil, -- Optional: Top-k sampling parameter
		repetition_penalty = nil, -- Optional: Repetition penalty parameter
		timeout = 5000,
		max_retries = 2,
		parse_curl_args = nil, -- Optional custom curl args function
		parse_response = nil, -- Optional custom response parser function
		-- Example custom parser for different API formats:
		-- parse_response = function(result)
		--   if result.content then return result.content end
		--   if result.choices and result.choices[1] then return result.choices[1].text or "" end
		--   return ""
		-- end
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
}

function M.validate(config)
	vim.validate("config", config, "table")
	vim.validate("config.api", config.api, "table")
	vim.validate("config.completions", config.completions, "table")
	vim.validate("config.keymaps", config.keymaps, "table")
	vim.validate("config.filetypes", config.filetypes, "table")

	vim.validate("api.base_url", config.api.base_url, "string")
	vim.validate("api.model", config.api.model, "string")
	vim.validate("api.timeout", config.api.timeout, "number")
	vim.validate("api.max_retries", config.api.max_retries, "number")
	vim.validate("completions.debounce_ms", config.completions.debounce_ms, "number")

	-- Validate api_key_name is string when set
	if config.api.api_key_name ~= nil then
		vim.validate("api.api_key_name", config.api.api_key_name, "string")
	end

	-- Validate max_tokens is number when set
	if config.api.max_tokens ~= nil then
		vim.validate("api.max_tokens", config.api.max_tokens, "number")
	end

	-- Validate temperature is number when set
	if config.api.temperature ~= nil then
		vim.validate("api.temperature", config.api.temperature, "number")
	end

	-- Validate max_tokens is number when set
	if config.api.max_tokens ~= nil then
		vim.validate({
			["api.max_tokens"] = { config.api.max_tokens, "number" },
		})
	end

	-- Validate temperature is number when set
	if config.api.temperature ~= nil then
		vim.validate({
			["api.temperature"] = { config.api.temperature, "number" },
		})
	end

	-- Validate top_p is number when set
	if config.api.top_p ~= nil then
		vim.validate("api.top_p", config.api.top_p, "number")
	end

	-- Validate top_k is number when set
	if config.api.top_k ~= nil then
		vim.validate("api.top_k", config.api.top_k, "number")
	end

	-- Validate repetition_penalty is number when set
	if config.api.repetition_penalty ~= nil then
		vim.validate("api.repetition_penalty", config.api.repetition_penalty, "number")
	end

	-- Validate parse_response is function when set
	if config.api.parse_response ~= nil then
		vim.validate("api.parse_response", config.api.parse_response, "function")
	end

	-- Validate filetypes table values are booleans
	if config.filetypes then
		for filetype, enabled in pairs(config.filetypes) do
			vim.validate("filetypes." .. filetype, enabled, "boolean")
		end
	end

	return true
end

return M
