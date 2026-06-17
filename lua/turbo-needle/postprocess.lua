local M = {}

local builtin_stop_tokens = {
	"<|fim_prefix|>",
	"<|fim_suffix|>",
	"<|fim_middle|>",
	"<fim_prefix>",
	"<fim_suffix>",
	"<fim_middle>",
	"<PRE>",
	"<SUF>",
	"<MID>",
	"[PREFIX]",
	"[SUFFIX]",
	"<｜fim▁begin｜>",
	"<｜fim▁hole｜>",
	"<｜fim▁end｜>",
	"<|endoftext|>",
	"<｜end▁of▁sentence｜>",
	"<eos>",
	"</s>",
	"<|im_start|>",
	"<|im_end|>",
}

local function escape_pattern(text)
	return (text:gsub("([^%w])", "%%%1"))
end

local function trim_trailing_whitespace(text)
	return (text:gsub("%s+$", ""))
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_tokens(text, tokens)
	for _, token in ipairs(tokens or {}) do
		if token ~= "" then
			text = text:gsub(escape_pattern(token), "")
		end
	end
	return text
end

local function collect_stop_tokens(opts)
	local tokens = vim.deepcopy(builtin_stop_tokens)
	local seen = {}
	for _, token in ipairs(tokens) do
		seen[token] = true
	end

	local function append(value)
		if type(value) == "string" and value ~= "" and not seen[value] then
			seen[value] = true
			table.insert(tokens, value)
		end
	end

	for _, token in ipairs(opts.stop_tokens or {}) do
		append(token)
	end

	local api_stop = opts.api and opts.api.stop
	if type(api_stop) == "string" and api_stop ~= "auto" then
		append(api_stop)
	elseif type(api_stop) == "table" then
		for _, token in ipairs(api_stop) do
			append(token)
		end
	end

	return tokens
end

local function common_overlap(left, right, max_len)
	max_len = math.min(max_len or math.huge, #left, #right)
	for len = max_len, 1, -1 do
		if left:sub(-len) == right:sub(1, len) then
			return len
		end
	end
	return 0
end

local function limit_lines(text, max_lines)
	if not max_lines then
		return text
	end

	local lines = vim.split(text, "\n", { plain = true })
	if #lines <= max_lines then
		return text
	end
	return table.concat(vim.list_slice(lines, 1, max_lines), "\n")
end

local function limit_chars(text, max_chars)
	if not max_chars or #text <= max_chars then
		return text
	end
	return text:sub(1, max_chars)
end

local function strip_code_fence(text)
	local fence, body = text:match("^%s*(```+)[^\n]*\n(.-)\n%1%s*$")
	if fence and body then
		return body
	end

	fence, body = text:match("^%s*(~~~+)[^\n]*\n(.-)\n%1%s*$")
	if fence and body then
		return body
	end

	return text
end

local function strip_thinking_artifacts(text)
	local changed = false
	local next_text, count = text:gsub("<think>.-</think>", "")
	if count > 0 then
		changed = true
		text = next_text
	end

	next_text, count = text:gsub("</?think>", "")
	if count > 0 then
		changed = true
		text = next_text
	end

	return text, changed
end

local function last_non_empty_line(text)
	local lines = vim.split(text or "", "\n", { plain = true })
	for index = #lines, 1, -1 do
		local line = trim(lines[index])
		if line ~= "" then
			return line
		end
	end
	return nil
end

local function last_non_empty_line_above_cursor(prefix)
	local before_current_line = (prefix or ""):gsub("[^\n]*$", "")
	return last_non_empty_line(before_current_line)
end

local function repeated_line_reason(text)
	local counts = {}
	local non_empty = 0
	for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
		local normalized = trim(line)
		if normalized ~= "" then
			non_empty = non_empty + 1
			counts[normalized] = (counts[normalized] or 0) + 1
			if counts[normalized] >= 4 and non_empty >= 4 then
				return "repetition"
			end
		end
	end
	return nil
end

local function starts_with_line(text, line)
	return line and line ~= "" and trim(text):sub(1, #line) == line
end

local function result(text, rejected, reason, retryable)
	return {
		text = text,
		rejected = rejected,
		reason = reason,
		retryable = retryable == true,
	}
end

function M.classify(raw_text, opts)
	opts = opts or {}
	local cfg = opts.config or {}
	if cfg.enabled == false then
		return result(raw_text, false, nil, false)
	end
	if type(raw_text) ~= "string" then
		return result(nil, true, "empty", true)
	end
	if raw_text:match("^%s*$") then
		return result(nil, true, "whitespace", true)
	end

	local text = raw_text
	text = strip_code_fence(text)
	local thinking_stripped
	text, thinking_stripped = strip_thinking_artifacts(text)
	if thinking_stripped then
		text = text:gsub("^%s*\n", "")
	end

	local previous_line = last_non_empty_line_above_cursor(opts.prefix)
	if starts_with_line(text, previous_line) then
		return result(nil, true, "line_rewrite", true)
	end

	if cfg.strip_stop_tokens ~= false then
		local before = text
		text = strip_tokens(text, collect_stop_tokens(opts))
		if before ~= "" and text:match("^%s*$") then
			return result(nil, true, "stop_token_only", true)
		end
	end

	if cfg.trim_prefix_overlap ~= false then
		local prefix = opts.prefix or ""
		local overlap = common_overlap(prefix, text, #text)
		if overlap > 0 then
			text = text:sub(overlap + 1)
		end
	end

	if cfg.trim_suffix_overlap ~= false then
		local suffix = opts.suffix or ""
		local overlap = common_overlap(text, suffix, #text)
		if overlap > 0 then
			text = text:sub(1, #text - overlap)
		end
	end

	local current_line_prefix = (opts.prefix or ""):match("([^\n]*)$") or ""
	if cfg.trim_prefix_overlap ~= false and current_line_prefix ~= "" and trim(text) == trim(current_line_prefix) then
		return result(nil, true, "duplicate_prefix", false)
	end

	local current_line_suffix = (opts.suffix or ""):match("^([^\n]*)") or ""
	if cfg.trim_suffix_overlap ~= false and current_line_suffix ~= "" and trim(text) == trim(current_line_suffix) then
		return result(nil, true, "duplicate_suffix", false)
	end

	text = trim_trailing_whitespace(text)
	text = limit_lines(text, cfg.max_lines)
	text = limit_chars(text, cfg.max_chars)
	text = trim_trailing_whitespace(text)

	if text == "" or text:match("^%s*$") then
		if thinking_stripped then
			return result(nil, true, "thinking", true)
		end
		return result(nil, true, "whitespace", true)
	end

	local repetition = repeated_line_reason(text)
	if repetition then
		return result(nil, true, repetition, true)
	end

	if cfg.min_chars ~= nil and #trim(text) < cfg.min_chars then
		return result(nil, true, "too_short", false)
	end

	return result(text, false, nil, false)
end

function M.apply(raw_text, opts)
	return M.classify(raw_text, opts).text
end

return M
