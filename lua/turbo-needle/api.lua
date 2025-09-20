local logger = require("turbo-needle.logger")

local M = {}

-- Import plenary.job for async HTTP requests
local Job = require("plenary.job")

-- Optional user hook for customizing curl args
M.custom_curl_args_hook = nil



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

-- Default curl args builder for llama.cpp completion API
function M.build_curl_args(provider_opts, code_opts, api_key)
	local headers = {
		["Content-Type"] = "application/json",
	}

	-- Handle optional API key
	if api_key and api_key ~= "" then
		headers["Authorization"] = "Bearer " .. api_key
	end

	local body = {
		model = provider_opts.model,
		prompt = build_fim_prompt(code_opts),
		max_tokens = provider_opts.max_tokens or 256,
		stream = false,
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
	}
end

-- Execute HTTP request using plenary.job + curl
function M.request_completion(curl_args, callback)
	-- Build curl command arguments for plenary.job
	local args = { "-s", "-X", "POST" }

	-- Add headers
	for k, v in pairs(curl_args.headers) do
		table.insert(args, "-H")
		table.insert(args, k .. ": " .. v)
	end

	-- Add timeout (convert from milliseconds to seconds for curl)
	table.insert(args, "--max-time")
	table.insert(args, tostring(curl_args.timeout / 1000))

	-- Add data and URL
	table.insert(args, "-d")
	table.insert(args, vim.json.encode(curl_args.body))
	table.insert(args, curl_args.url)

	-- Execute with plenary.job
	local job = Job:new({
		command = "curl",
		args = args,
		on_exit = vim.schedule_wrap(function(job, return_val)
			if return_val == 0 then
				-- Get stdout from the job
				local stdout = job:result()
				local output = table.concat(stdout, "\n")

				-- Check if output exists and is not empty
				if not output or output == "" then
					callback("Empty response from server", nil)
					return
				end

				local success, result = pcall(vim.json.decode, output)
				if success and result then
					callback(nil, result)
				else
					-- Try to provide more context about the JSON error
					local error_detail = "Invalid JSON response"
					if not success and result then
						error_detail = error_detail .. ": " .. tostring(result)
					end
					callback(error_detail, nil)
				end
			else
				local error_msg = "HTTP error: " .. tostring(return_val or "unknown")

				-- Get stderr from the job
				local stderr = job:stderr_result()
				if stderr and #stderr > 0 then
					local stderr_msg = table.concat(stderr, "\n"):match("^%s*(.-)%s*$") or table.concat(stderr, "\n")
					error_msg = error_msg .. " - " .. stderr_msg
				end

				callback(error_msg, nil)
			end
		end),
	})

	job:start()
	return job
end

-- Main completion request function
function M.get_completion(prompt_data, callback, api_key)
	local turbo_needle = require("turbo-needle")
	local config = turbo_needle.get_config()

	-- Use custom hook if provided (either from set_curl_args_hook or config.parse_curl_args)
	local curl_args
	local custom_hook = M.custom_curl_args_hook or config.api.parse_curl_args

	if custom_hook then
		curl_args = custom_hook(config.api, prompt_data)
	else
		curl_args = M.build_curl_args(config.api, prompt_data, api_key)
	end

	-- Make the request with retry logic
	local attempt = 0
	local max_retries = config.api.max_retries
	local active_job = nil -- Track the current job for cancellation

	local function attempt_request()
		attempt = attempt + 1
		active_job = M.request_completion(curl_args, function(err, result)
			if err and attempt <= max_retries then
				-- Retry on error with exponential backoff
				local delay = 1000 * (2 ^ (attempt - 1))
				vim.defer_fn(attempt_request, delay)
			else
				callback(err, result)
			end
		end)
	end

	attempt_request()
	return active_job
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

	-- Handle escape sequences in the completion text
	if completion_text ~= "" then
		-- Process escape sequences safely
		local success, processed = pcall(function()
			local text = completion_text
			text = text:gsub("\\n", "\n")
			text = text:gsub("\\t", "\t")
			text = text:gsub('\\"', '"')
			text = text:gsub("\\\\", "\\")
			return text
		end)

		if success then
			completion_text = processed
		end
	end

	return completion_text
end

return M
