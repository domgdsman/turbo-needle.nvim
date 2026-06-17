local edit = require("turbo-needle.edit")
local logger = require("turbo-needle.logger")

local M = {}

local function truncate(text)
	if #text <= 100 then
		return text
	end
	return text:sub(1, 97) .. "..."
end

local function namespace()
	return vim.api.nvim_create_namespace("turbo-needle-ghost")
end

local function is_stale_extmark_error(err)
	local msg = tostring(err):lower()
	return msg:match("invalid") and (msg:match("extmark") or msg:match("namespace") or msg:match("ns_id"))
end

function M.clear(state)
	if state.current_extmark then
		local ok, err = pcall(vim.api.nvim_buf_del_extmark, 0, state.current_extmark.ns_id, state.current_extmark.id)
		if not ok and not is_stale_extmark_error(err) then
			logger.warn("Failed to clear ghost text extmark")
		end
		state.current_extmark = nil
	end

	state.cached_completion = nil
	state.cursor_position = nil
end

function M.set(state, text)
	if vim.api.nvim_get_mode().mode ~= "i" then
		return
	end

	M.clear(state)

	if not text or text == "" or type(text) ~= "string" then
		return
	end

	state.cached_completion = text

	local cursor = vim.api.nvim_win_get_cursor(0)
	if not cursor or #cursor < 2 then
		return
	end

	local row, col = cursor[1] - 1, cursor[2]
	state.cursor_position = { row = row, col = col }

	if text:find("\n") then
		local lines = vim.split(text, "\n", { plain = true })
		if #lines == 0 then
			return
		end

		local max_lines = 10
		if #lines > max_lines then
			lines = vim.list_slice(lines, 1, max_lines)
			lines[#lines] = lines[#lines] .. "..."
		end

		local head = lines[1]
		local tail = {}
		for i = 2, #lines do
			tail[#tail + 1] = lines[i]
		end

		local virt_lines = nil
		if #tail > 0 then
			virt_lines = {}
			local current_line = vim.api.nvim_get_current_line()
			local base_indent = (current_line and current_line:match("^%s*")) or ""
			for _, line in ipairs(tail) do
				local display_line = line
				if line:match("^%s*") then
					display_line = base_indent .. line:gsub("^%s*", "")
				end
				table.insert(virt_lines, { { truncate(display_line), "Comment" } })
			end
		end

		local ns_id = namespace()
		local ok, id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
			virt_text = { { head, "Comment" } },
			virt_text_pos = "inline",
			virt_lines = virt_lines,
			priority = 4096,
		})
		if not ok then
			logger.error("Failed to set multi-line hybrid ghost")
			return
		end
		state.current_extmark = { ns_id = ns_id, id = id }
		return
	end

	local ns_id = namespace()
	local ok, id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
		virt_text = { { truncate(text), "Comment" } },
		virt_text_pos = "inline",
		priority = 4096,
	})
	if not ok then
		logger.error("Failed to set ghost text extmark")
		return
	end
	state.current_extmark = { ns_id = ns_id, id = id }
end

function M.accept(state, clear)
	if not state.cached_completion then
		return "\t"
	end

	local current_cursor = vim.api.nvim_win_get_cursor(0)
	local current_row, current_col = current_cursor[1] - 1, current_cursor[2]

	if
		not state.cursor_position
		or state.cursor_position.row ~= current_row
		or state.cursor_position.col ~= current_col
	then
		return "\t"
	end

	local cached = state.cached_completion
	local stored_pos = {
		row = state.cursor_position.row,
		col = state.cursor_position.col,
	}

	vim.schedule(function()
		local sched_final = edit.insert_at_cursor(cached, stored_pos)
		clear(state)
		if sched_final then
			pcall(vim.api.nvim_win_set_cursor, 0, { sched_final.row + 1, sched_final.col })
		end
	end)

	return ""
end

return M
