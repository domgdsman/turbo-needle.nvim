local M = {}

local default_paths = {
	fim_prompt = "/v1/completions",
	fim_suffix = "/v1/completions",
	llamacpp_infill = "/infill",
	chat_fallback = "/v1/chat/completions",
}

-- Build FIM (Fill-in-the-Middle) prompt
local function build_fim_prompt(code_opts)
	local prefix = code_opts.prefix or ""
	local suffix = code_opts.suffix or ""
	return string.format("<|fim_prefix|>%s<|fim_suffix|>%s<|fim_middle|>", prefix, suffix)
end

local function resolve_path(provider_opts)
	if provider_opts.path then
		return provider_opts.path
	end
	if provider_opts.provider == "llamacpp" then
		return default_paths.llamacpp_infill
	end
	if provider_opts.provider == "chat" then
		return default_paths.chat_fallback
	end
	return default_paths[provider_opts.mode] or default_paths.fim_prompt
end

local function build_headers(provider_opts, api_key)
	local headers = vim.tbl_extend("force", {
		["Content-Type"] = "application/json",
	}, provider_opts.headers or {})

	if api_key then
		headers["Authorization"] = "Bearer " .. api_key
	end

	return headers
end

local function add_sampling(provider_opts, body)
	body.max_tokens = provider_opts.max_tokens or 256
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
	return body
end

local function merge_extra_body(provider_opts, body)
	return vim.tbl_deep_extend("force", body, provider_opts.extra_body or {})
end

local function build_fim_prompt_body(provider_opts, code_opts, stream)
	local body = {
		model = provider_opts.model,
		prompt = build_fim_prompt(code_opts),
		stream = stream,
	}
	return merge_extra_body(provider_opts, add_sampling(provider_opts, body))
end

local function build_fim_suffix_body(provider_opts, code_opts, stream)
	local body = {
		model = provider_opts.model,
		prompt = code_opts.prefix or "",
		suffix = code_opts.suffix or "",
		stream = stream,
	}
	return merge_extra_body(provider_opts, add_sampling(provider_opts, body))
end

local function build_llamacpp_infill_body(provider_opts, code_opts, stream)
	local body = {
		input_prefix = code_opts.prefix or "",
		input_suffix = code_opts.suffix or "",
		stream = stream,
	}
	if provider_opts.model then
		body.model = provider_opts.model
	end
	return merge_extra_body(provider_opts, add_sampling(provider_opts, body))
end

local function build_chat_fallback_body(provider_opts, code_opts, stream)
	local prefix = code_opts.prefix or ""
	local suffix = code_opts.suffix or ""
	local body = {
		model = provider_opts.model,
		messages = {
			{
				role = "system",
				content = "Complete the user's code at the cursor. Return only the inserted code.",
			},
			{
				role = "user",
				content = "Prefix:\n" .. prefix .. "\n\nSuffix:\n" .. suffix,
			},
		},
		stream = stream,
	}
	return merge_extra_body(provider_opts, add_sampling(provider_opts, body))
end

function M.build_request_body(provider_opts, code_opts)
	local stream = provider_opts.stream ~= false
	local mode = provider_opts.mode or "fim_prompt"
	if mode == "fim_suffix" then
		return build_fim_suffix_body(provider_opts, code_opts, stream)
	end
	if mode == "llamacpp_infill" then
		return build_llamacpp_infill_body(provider_opts, code_opts, stream)
	end
	if mode == "chat_fallback" then
		return build_chat_fallback_body(provider_opts, code_opts, stream)
	end
	return build_fim_prompt_body(provider_opts, code_opts, stream)
end

-- Build transport request options for the configured provider/mode.
function M.build_curl_args(provider_opts, code_opts, api_key)
	local stream = provider_opts.stream ~= false
	local path = resolve_path(provider_opts)

	return {
		url = provider_opts.base_url .. path,
		headers = build_headers(provider_opts, api_key),
		body = M.build_request_body(provider_opts, code_opts),
		timeout = provider_opts.timeout,
		stream = stream,
	}
end

local function stable_encode(value)
	if type(value) ~= "table" then
		return tostring(value)
	end

	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, tostring(key) .. "=" .. stable_encode(value[key]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function M.cache_fingerprint(provider_opts)
	return table.concat({
		provider_opts.base_url or "",
		provider_opts.provider or "",
		provider_opts.model or "",
		provider_opts.mode or "",
		resolve_path(provider_opts),
		tostring(provider_opts.stream ~= false),
		stable_encode(provider_opts.extra_body or {}),
		stable_encode(provider_opts.headers or {}),
	}, "|")
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

local function parse_completion_choice(result)
	if not result then
		return ""
	end

	if result.choices and result.choices[1] and result.choices[1].text then
		return result.choices[1].text
	end

	return ""
end

local function parse_chat_choice(result)
	if not result or not result.choices or not result.choices[1] then
		return ""
	end

	local choice = result.choices[1]
	if choice.message and type(choice.message.content) == "string" then
		return choice.message.content
	end
	if choice.delta and type(choice.delta.content) == "string" then
		return choice.delta.content
	end
	if type(choice.text) == "string" then
		return choice.text
	end
	return ""
end

local function parse_llamacpp_infill(result)
	if type(result) == "table" and type(result.content) == "string" then
		return result.content
	end
	if type(result) == "table" and type(result.text) == "string" then
		return result.text
	end
	return parse_completion_choice(result)
end

function M.parse_response(result, provider_opts)
	local mode = provider_opts and provider_opts.mode or "fim_prompt"
	if mode == "chat_fallback" then
		return parse_chat_choice(result)
	end
	if mode == "llamacpp_infill" then
		return parse_llamacpp_infill(result)
	end
	return parse_completion_choice(result)
end

return M
