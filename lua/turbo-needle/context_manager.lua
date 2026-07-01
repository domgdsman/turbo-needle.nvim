local M = {}

local ContextManager = {}
ContextManager.__index = ContextManager

local function char_len(value)
	return vim.fn.strcharlen(value or "")
end

local function char_part(value, start, length)
	return vim.fn.strcharpart(value or "", start, length)
end

local function comment_content(content, commentstring)
	local lines = vim.split(content, "\n", { plain = true })
	for index, line in ipairs(lines) do
		lines[index] = string.format(commentstring, line)
	end
	return table.concat(lines, "\n")
end

local function configured_source(source, source_config)
	local override = (source_config or {})[source.source] or {}
	if override.enabled == false then
		return nil
	end

	local configured = vim.deepcopy(source)
	configured.priority = override.priority or configured.priority
	configured.sort_order = override.sort_order or configured.sort_order
	return configured
end

local function validate_source(source)
	return type(source) == "table"
		and type(source.source) == "string"
		and source.source ~= ""
		and type(source.priority) == "number"
		and type(source.sort_order) == "number"
		and type(source.can_truncate) == "boolean"
		and type(source.content) == "table"
end

local function selection_order(left, right)
	if left.priority ~= right.priority then
		return left.priority > right.priority
	end
	if left.sort_order ~= right.sort_order then
		return left.sort_order < right.sort_order
	end
	return left.source < right.source
end

local function placement_order(left, right)
	if left.sort_order ~= right.sort_order then
		return left.sort_order < right.sort_order
	end
	return left.source < right.source
end

function ContextManager.new(opts)
	opts = opts or {}
	return setmetatable({
		max_chars = opts.max_chars or 12000,
		commentstring = opts.commentstring or "# %s",
		source_config = opts.sources or {},
	}, ContextManager)
end

function ContextManager:build(current, additional_sources)
	current = vim.deepcopy(current or { prefix = "", suffix = "" })
	current.prefix = current.prefix or ""
	current.suffix = current.suffix or ""

	local used = char_len(current.prefix) + char_len(current.suffix)
	local remaining = math.max(0, self.max_chars - used)
	if remaining == 0 then
		return current
	end

	local sources = {}
	for _, source in ipairs(additional_sources or {}) do
		if validate_source(source) then
			local configured = configured_source(source, self.source_config)
			if configured then
				table.insert(sources, configured)
			end
		end
	end
	table.sort(sources, selection_order)

	local selected = {}
	for _, source in ipairs(sources) do
		local selected_source = {
			source = source.source,
			sort_order = source.sort_order,
			content = {},
		}
		for _, content in ipairs(source.content) do
			if remaining == 0 then
				break
			end
			if type(content) == "string" and content:match("%S") then
				local formatted = comment_content(content, self.commentstring)
				local separator_len = 1
				local required = separator_len + char_len(formatted)
				if required <= remaining then
					table.insert(selected_source.content, formatted)
					remaining = remaining - required
				elseif source.can_truncate and remaining > separator_len then
					local truncated = char_part(formatted, 0, remaining - separator_len)
					if truncated ~= "" then
						table.insert(selected_source.content, truncated)
						remaining = 0
					end
				end
			end
		end
		if #selected_source.content > 0 then
			table.insert(selected, selected_source)
		end
		if remaining == 0 then
			break
		end
	end

	table.sort(selected, placement_order)
	local blocks = {}
	for _, source in ipairs(selected) do
		table.insert(blocks, table.concat(source.content, "\n"))
	end
	if #blocks > 0 then
		local additional = table.concat(blocks, "\n")
		current.prefix = additional .. "\n" .. current.prefix
	end
	return current
end

M.ContextManager = ContextManager

function M.new(opts)
	return ContextManager.new(opts)
end

return M
