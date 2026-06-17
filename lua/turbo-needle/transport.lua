local Job = require("plenary.job")

local M = {}

local function trim(str)
	return str:match("^%s*(.-)%s*$")
end

local function decode_json(str)
	local ok, result = pcall(vim.json.decode, str)
	if ok then
		return result
	end
	return nil, result
end

local function extract_choice_text(payload)
	if not payload or not payload.choices or not payload.choices[1] then
		return nil
	end

	local choice = payload.choices[1]
	if type(choice.text) == "string" then
		return choice.text
	end
	if choice.delta and type(choice.delta.content) == "string" then
		return choice.delta.content
	end
	if choice.message and type(choice.message.content) == "string" then
		return choice.message.content
	end

	return nil
end

function M.parse_stream_line(line)
	if type(line) ~= "string" then
		return nil, false
	end

	local data = line:match("^%s*data:%s*(.*)$")
	if not data then
		return nil, false
	end

	data = trim(data)
	if data == "" then
		return nil, false
	end
	if data == "[DONE]" then
		return nil, true
	end

	local payload = decode_json(data)
	if not payload then
		return nil, false
	end

	return extract_choice_text(payload), false
end

function M.build_curl_args(request)
	local args = { "-s", "-X", "POST" }

	if request.stream then
		table.insert(args, "-N")
	end

	for k, v in pairs(request.headers or {}) do
		table.insert(args, "-H")
		table.insert(args, k .. ": " .. v)
	end

	if request.timeout then
		table.insert(args, "--max-time")
		table.insert(args, tostring(request.timeout / 1000))
	end

	table.insert(args, "-d")
	table.insert(args, vim.json.encode(request.body or {}))
	table.insert(args, request.url)

	return args
end

local function parse_full_response(output)
	if not output or output == "" then
		return "Empty response from server", nil
	end

	local result, err = decode_json(output)
	if result then
		return nil, result
	end

	local error_detail = "Invalid JSON response"
	if err then
		error_detail = error_detail .. ": " .. tostring(err)
	end
	return error_detail, nil
end

local function curl_error(job, return_val)
	local error_msg = "Curl error: " .. tostring(return_val or "unknown")
	local stderr = job:stderr_result()
	if stderr and #stderr > 0 then
		local stderr_msg = trim(table.concat(stderr, "\n"))
		error_msg = error_msg .. " - " .. stderr_msg
	end
	return error_msg
end

function M.request(request, callbacks)
	callbacks = callbacks or {}
	local chunks = {}

	local job = Job:new({
		command = "curl",
		args = M.build_curl_args(request),
		on_stdout = vim.schedule_wrap(function(_, data)
			if not request.stream then
				return
			end

			local text, done = M.parse_stream_line(data)
			if text then
				table.insert(chunks, text)
				if callbacks.on_chunk then
					callbacks.on_chunk(text)
				end
			end
			if done and callbacks.on_stream_done then
				callbacks.on_stream_done()
			end
		end),
		on_exit = vim.schedule_wrap(function(job_handle, return_val)
			if return_val ~= 0 then
				callbacks.on_done(curl_error(job_handle, return_val), nil)
				return
			end

			if request.stream then
				callbacks.on_done(nil, {
					choices = {
						{
							text = table.concat(chunks),
						},
					},
				})
				return
			end

			local stdout = job_handle:result()
			local output = table.concat(stdout, "\n")
			local err, result = parse_full_response(output)
			callbacks.on_done(err, result)
		end),
	})

	job:start()
	return job
end

return M
