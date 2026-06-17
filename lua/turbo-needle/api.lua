local M = {}

-- Build FIM (Fill-in-the-Middle) prompt
local function build_fim_prompt(code_opts)
	local prefix = code_opts.prefix or ""
	local suffix = code_opts.suffix or ""
	return string.format("<|fim_prefix|>%s<|fim_suffix|>%s<|fim_middle|>", prefix, suffix)
end

-- Default request builder for llama.cpp completion API
function M.build_curl_args(provider_opts, code_opts, api_key)
	local stream = provider_opts.stream ~= false
	local headers = {
		["Content-Type"] = "application/json",
	}

	-- Handle optional API key
	if api_key then
		headers["Authorization"] = "Bearer " .. api_key
	end

	local body = {
		model = provider_opts.model,
		prompt = build_fim_prompt(code_opts),
		max_tokens = provider_opts.max_tokens or 256,
		stream = stream,
	}

	-- Add optional parameters if they are set
	if provider_opts.temperature then
		body.temperature = provider_opts.temperature
	end
	if provider_opts.top_p then
		body.top_p = provider_opts.top_p
	end
	if provider_opts.top_k then
		body.top_k = provider_opts.top_k
	end
	if provider_opts.repetition_penalty then
		body.repetition_penalty = provider_opts.repetition_penalty
	end

	return {
		url = provider_opts.base_url .. "/v1/completions",
		headers = headers,
		body = body,
		timeout = provider_opts.timeout,
		stream = stream,
	}
end

-- Execute HTTP request through the configured transport
function M.request_completion(request_opts, callback)
	local transport = require("turbo-needle.transport")

	return transport.request(request_opts, {
		on_done = callback,
	})
end

-- Main completion request function
function M.get_completion(prompt_data, callback, api_key)
	local turbo_needle = require("turbo-needle")
	local config = turbo_needle.get_config()

	-- Build curl arguments
	local curl_args = M.build_curl_args(config.api, prompt_data, api_key)

	-- Make the request
	return M.request_completion(curl_args, callback)
end

-- Parse API response to extract completion text (llama.cpp format only)
function M.parse_response(result)
	if not result then
		return ""
	end

	-- Handle OpenAI completion response format
	local completion_text = nil
	if result.choices and result.choices[1] and result.choices[1].text then
		completion_text = result.choices[1].text
	end

	-- Ensure completion_text is a string before processing
	if not completion_text or type(completion_text) ~= "string" then
		return ""
	end

	return completion_text
end

return M
