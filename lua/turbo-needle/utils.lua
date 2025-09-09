local M = {}

function M.notify(msg, level)
	level = level or vim.log.levels.INFO
	-- Defer notification to avoid fast event context issues
	vim.schedule(function()
		vim.notify("[turbo-needle] " .. msg, level)
	end)
end

function M.is_empty(value)
	if value == nil then
		return true
	end

	if type(value) == "string" then
		return value == ""
	end

	if type(value) == "table" then
		return next(value) == nil
	end

	return false
end

function M.trim(str)
	return str:match("^%s*(.-)%s*$")
end

-- Validate completion text quality
function M.validate_completion(completion_text, context)
	if not completion_text or type(completion_text) ~= "string" then
		return false, "Invalid completion format"
	end

	-- Filter empty or whitespace-only completions
	local trimmed = M.trim(completion_text)
	if trimmed == "" then
		return false, "Empty completion"
	end

	-- Check minimum length (at least 2 characters)
	if #trimmed < 2 then
		return false, "Completion too short"
	end

	-- Check maximum length (prevent extremely long completions)
	if #completion_text > 1000 then
		return false, "Completion too long"
	end

	-- Check for duplicate lines (basic check)
	if context and context.prefix then
		local prefix_lines = vim.split(context.prefix, "\n", { plain = true })
		local completion_lines = vim.split(completion_text, "\n", { plain = true })

		-- Check if completion starts with exact duplicate of last prefix line
		if #prefix_lines > 0 and #completion_lines > 0 then
			local last_prefix_line = M.trim(prefix_lines[#prefix_lines])
			local first_completion_line = M.trim(completion_lines[1])
			if last_prefix_line == first_completion_line and last_prefix_line ~= "" then
				return false, "Duplicate line completion"
			end
		end
	end

	return true, nil
end

return M
