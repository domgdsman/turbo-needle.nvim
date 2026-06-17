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

function M.apply(raw_text, opts)
	opts = opts or {}
	local cfg = opts.config or {}
	if cfg.enabled == false then
		return raw_text
	end
	if type(raw_text) ~= "string" then
		return nil
	end
	if raw_text:match("^%s*$") then
		return nil
	end

	local text = raw_text
	if cfg.strip_stop_tokens ~= false then
		text = strip_tokens(text, collect_stop_tokens(opts))
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

	text = trim_trailing_whitespace(text)
	text = limit_lines(text, cfg.max_lines)
	text = limit_chars(text, cfg.max_chars)
	text = trim_trailing_whitespace(text)

	if text == "" or text:match("^%s*$") then
		return nil
	end

	return text
end

return M
