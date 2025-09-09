local M = {}

M.defaults = {
	api = {
		base_url = "http://localhost:8000",
		model = "codellama:7b-code",
		api_key_name = nil, -- Environment variable name for API key (optional)
		max_tokens = nil, -- Optional: Maximum tokens to generate
		temperature = nil, -- Optional: Sampling temperature (0.0 to 2.0)
		timeout = 5000,
		max_retries = 2,
		parse_curl_args = nil, -- Optional custom curl args function
	},
	completions = {
		debounce_ms = 300,
		throttle_ms = 600,
	},
	keymaps = {
		accept = "<Tab>",
	},
	filetypes = {
		enabled = { "lua", "python", "javascript", "typescript", "rust", "go", "c", "cpp" },
		disabled = { "markdown", "text", "gitcommit", "help" },
	},
}

function M.validate(config)
	vim.validate({
		api = { config.api, "table" },
		completions = { config.completions, "table" },
		keymaps = { config.keymaps, "table" },
		filetypes = { config.filetypes, "table" },
	})

	vim.validate({
		["api.base_url"] = { config.api.base_url, "string" },
		["api.model"] = { config.api.model, "string" },
		["api.timeout"] = { config.api.timeout, "number" },
		["api.max_retries"] = { config.api.max_retries, "number" },
	})

	-- Validate api_key_name is string when set
	if config.api.api_key_name ~= nil then
		vim.validate({
			["api.api_key_name"] = { config.api.api_key_name, "string" },
		})
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

	return true
end

return M
