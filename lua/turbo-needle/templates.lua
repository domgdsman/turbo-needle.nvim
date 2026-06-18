local M = {}

local builtin_templates = {
	qwen_coder = {
		prompt = "<|fim_prefix|>{prefix}<|fim_suffix|>{suffix}<|fim_middle|>",
		stop = { "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<|endoftext|>" },
	},
	stable_code = {
		prompt = "<fim_prefix>{prefix}<fim_suffix>{suffix}<fim_middle>",
		stop = { "<fim_prefix>", "<fim_suffix>", "<fim_middle>", "<|endoftext|>" },
	},
	starcoder = {
		prompt = "<fim_prefix>{prefix}<fim_suffix>{suffix}<fim_middle>",
		stop = { "<fim_prefix>", "<fim_suffix>", "<fim_middle>", "<|endoftext|>" },
	},
	codellama = {
		prompt = "<PRE> {prefix} <SUF>{suffix} <MID>",
		stop = { "<PRE>", "<SUF>", "<MID>", "</s>" },
	},
	codestral = {
		prompt = "[PREFIX]{prefix}[SUFFIX]{suffix}",
		stop = { "[PREFIX]", "[SUFFIX]", "</s>" },
	},
	deepseek_coder = {
		prompt = "<｜fim▁begin｜>{prefix}<｜fim▁hole｜>{suffix}<｜fim▁end｜>",
		stop = { "<｜fim▁begin｜>", "<｜fim▁hole｜>", "<｜fim▁end｜>", "<｜end▁of▁sentence｜>" },
	},
	codegemma = {
		prompt = "<|fim_prefix|>{prefix}<|fim_suffix|>{suffix}<|fim_middle|>",
		stop = { "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<eos>" },
	},
	generic_fim = {
		prompt = "<|fim_prefix|>{prefix}<|fim_suffix|>{suffix}<|fim_middle|>",
		stop = { "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>" },
	},
	hole_filler_chat = {
		chat = true,
		stop = {},
	},
}

local model_patterns = {
	{ pattern = "qwen.*coder", template = "qwen_coder" },
	{ pattern = "qwen", template = "qwen_coder" },
	{ pattern = "stable.*code", template = "stable_code" },
	{ pattern = "starcoder", template = "starcoder" },
	{ pattern = "code.*llama", template = "codellama" },
	{ pattern = "codellama", template = "codellama" },
	{ pattern = "codestral", template = "codestral" },
	{ pattern = "deepseek.*coder", template = "deepseek_coder" },
	{ pattern = "deepseek", template = "deepseek_coder" },
	{ pattern = "codegemma", template = "codegemma" },
}

local function list_template_names()
	local names = {}
	for name in pairs(builtin_templates) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function normalize_stop(stop)
	if stop == nil or stop == "auto" then
		return nil
	end
	if type(stop) == "string" then
		return { stop }
	end
	return stop
end

local function append_unique(result, seen, values)
	for _, value in ipairs(values or {}) do
		if not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end
end

function M.names()
	return list_template_names()
end

function M.resolve_name(provider_opts)
	if provider_opts.template then
		if not builtin_templates[provider_opts.template] then
			error("api.template must be one of: " .. table.concat(list_template_names(), ", "), 0)
		end
		return provider_opts.template
	end

	local model = string.lower(provider_opts.model or "")
	for _, entry in ipairs(model_patterns) do
		if model:find(entry.pattern) then
			return entry.template
		end
	end

	return "qwen_coder"
end

function M.resolve(provider_opts)
	if provider_opts.custom_template then
		return {
			name = "custom",
			prompt = provider_opts.custom_template,
			stop = {},
		}
	end

	local name = M.resolve_name(provider_opts)
	local template = vim.deepcopy(builtin_templates[name])
	template.name = name
	return template
end

function M.validate_custom_template(template)
	if type(template) ~= "string" or template == "" then
		error("api.custom_template must be a non-empty string", 0)
	end
	if not template:find("{prefix}", 1, true) or not template:find("{suffix}", 1, true) then
		error("api.custom_template must include {prefix} and {suffix}", 0)
	end
end

function M.render(template, context)
	if template.chat then
		return nil
	end

	local prompt = template.prompt or ""
	prompt = prompt:gsub("{prefix}", context.prefix or "")
	prompt = prompt:gsub("{suffix}", context.suffix or "")
	prompt = prompt:gsub("{language}", context.language or "")
	prompt = prompt:gsub("{filename}", context.filename or "")
	prompt = prompt:gsub("{filepath}", context.filepath or "")
	return prompt
end

function M.chat_messages(context)
	return {
		{
			role = "system",
			content = "Complete the user's code at the cursor. Return only the inserted code.",
		},
		{
			role = "user",
			content = "Prefix:\n" .. (context.prefix or "") .. "\n\nSuffix:\n" .. (context.suffix or ""),
		},
	}
end

function M.merge_stop(template, user_stop)
	local result = {}
	local seen = {}
	if user_stop == "auto" or user_stop == nil then
		append_unique(result, seen, template.stop)
	else
		append_unique(result, seen, normalize_stop(user_stop))
	end

	if user_stop ~= nil and user_stop ~= "auto" then
		append_unique(result, seen, template.stop)
	end

	if #result == 0 then
		return nil
	end
	return result
end

return M
