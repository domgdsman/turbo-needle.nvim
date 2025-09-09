local M = {}

-- Optional user hook for customizing curl args
M.custom_curl_args_hook = nil

-- Check API key configuration and warn if needed
function M.validate_api_key_config()
	local config = require("turbo-needle.config")
	local api_key_name = config.defaults.api.api_key_name

	if api_key_name then
		local api_key = os.getenv(api_key_name)
		if not api_key or api_key == "" then
			local utils = require("turbo-needle.utils")
			utils.warn(
				string.format(
					"API key environment variable '%s' is not set or empty. " .. "Set it with: export %s='your-api-key'",
					api_key_name,
					api_key_name
				)
			)
		end
	end
end

-- Set custom curl args hook
function M.set_curl_args_hook(hook_fn)
	M.custom_curl_args_hook = hook_fn
end

-- Build FIM (Fill-in-the-Middle) prompt
local function build_fim_prompt(code_opts)
	local prefix = code_opts.prefix or ""
	local suffix = code_opts.suffix or ""
	return string.format("<|fim_prefix|>%s<|fim_suffix|>%s<|fim_middle|>", prefix, suffix)
end

-- Default curl args builder for OpenAI-compatible API
function M.build_curl_args(provider_opts, code_opts)
	local headers = {
		["Content-Type"] = "application/json",
	}

	-- Handle optional API key from environment variable
	if provider_opts.api_key_name then
		local api_key = os.getenv(provider_opts.api_key_name)
		if api_key and api_key ~= "" then
			headers["Authorization"] = "Bearer " .. api_key
		else
			local utils = require("turbo-needle.utils")
			utils.warn(
				string.format(
					"API key for '%s' not found in environment. " .. "Request will be sent without authorization.",
					provider_opts.api_key_name
				)
			)
		end
	end

	local body = {
		model = provider_opts.model,
		messages = {
			{
				role = "system",
				content = [[You are an expert AI coding assistant specialized in generating precise code completions.
Focus on filling in the code between <|fim_prefix|> and <|fim_suffix|> with the most appropriate continuation.
Output only the completed code without additional text, explanations, or wrappers.]],
			},
			{
				role = "user",
				content = build_fim_prompt(code_opts),
			},
		},
	}

	-- Conditionally add optional fields
	if provider_opts.max_tokens ~= nil then
		body.max_tokens = provider_opts.max_tokens
	end

	if provider_opts.temperature ~= nil then
		body.temperature = provider_opts.temperature
	end

	return {
		url = provider_opts.base_url .. "/v1/chat/completions",
		headers = headers,
		body = body,
		timeout = provider_opts.timeout,
	}
end

-- Execute HTTP request using vim.system() + curl
function M.request_completion(curl_args, callback)
	-- Build curl command array
	local cmd = { "curl", "-s", "-X", "POST" }

	-- Add headers
	for k, v in pairs(curl_args.headers) do
		table.insert(cmd, "-H")
		table.insert(cmd, k .. ": " .. v)
	end

	-- Add timeout
	table.insert(cmd, "--max-time")
	table.insert(cmd, tostring(curl_args.timeout / 1000))

	-- Add URL and data
	table.insert(cmd, "-d")
	table.insert(cmd, vim.json.encode(curl_args.body))
	table.insert(cmd, curl_args.url)

	-- Execute with vim.system()
	vim.system(cmd, {
		text = true,
		timeout = curl_args.timeout,
	}, function(obj)
		if obj.code == 0 then
			local success, result = pcall(vim.json.decode, obj.stdout)
			if success then
				callback(nil, result)
			else
				callback("Invalid JSON response", nil)
			end
		else
			callback("HTTP error: " .. obj.code, nil)
		end
	end)
end

-- Main completion request function
function M.get_completion(prompt_data, callback)
	local config = require("turbo-needle.config")

	-- Use custom hook if provided (either from set_curl_args_hook or config.parse_curl_args)
	local curl_args
	local custom_hook = M.custom_curl_args_hook or config.defaults.api.parse_curl_args

	if custom_hook then
		curl_args = custom_hook(config.defaults.api, prompt_data)
	else
		curl_args = M.build_curl_args(config.defaults.api, prompt_data)
	end

	-- Make the request with retry logic
	local attempt = 0
	local max_retries = config.defaults.api.max_retries

	local function attempt_request()
		attempt = attempt + 1
		M.request_completion(curl_args, function(err, result)
			if err and attempt <= max_retries then
				-- Retry on error
				vim.defer_fn(attempt_request, 1000 * attempt) -- Exponential backoff
			else
				callback(err, result)
			end
		end)
	end

	attempt_request()
end

-- Parse API response to extract completion text
function M.parse_response(result)
	local completion_text = ""
	if result and result.choices and result.choices[1] and result.choices[1].message then
		completion_text = result.choices[1].message.content or ""
	end
	return completion_text
end

return M
