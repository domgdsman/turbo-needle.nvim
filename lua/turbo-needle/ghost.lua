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

local function clear_extmark(state)
	if state.current_extmark then
		local ok, err = pcall(vim.api.nvim_buf_del_extmark, 0, state.current_extmark.ns_id, state.current_extmark.id)
		if not ok and not is_stale_extmark_error(err) then
			logger.warn("Failed to clear ghost text extmark")
		end
		state.current_extmark = nil
	end
end

local function render(state, text, position)
	if not text or text == "" or type(text) ~= "string" then
		return false
	end

	local row, col = position.row, position.col

	if text:find("\n") then
		local lines = vim.split(text, "\n", { plain = true })
		if #lines == 0 then
			return false
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
			for _, line in ipairs(tail) do
				table.insert(virt_lines, { { truncate(line), "Comment" } })
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
			return false
		end
		state.current_extmark = { ns_id = ns_id, id = id }
		return true
	end

	local ns_id = namespace()
	local ok, id = pcall(vim.api.nvim_buf_set_extmark, 0, ns_id, row, col, {
		virt_text = { { truncate(text), "Comment" } },
		virt_text_pos = "inline",
		priority = 4096,
	})
	if not ok then
		logger.error("Failed to set ghost text extmark")
		return false
	end
	state.current_extmark = { ns_id = ns_id, id = id }
	return true
end

function M.clear(state)
	clear_extmark(state)

	state.cached_completion = nil
	state.original_completion = nil
	state.cursor_position = nil
	state.original_cursor_position = nil
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
	state.original_completion = text

	local cursor = vim.api.nvim_win_get_cursor(0)
	if not cursor or #cursor < 2 then
		return
	end

	local row, col = cursor[1] - 1, cursor[2]
	state.cursor_position = { row = row, col = col }
	state.original_cursor_position = { row = row, col = col }

	render(state, text, state.cursor_position)
end

function M.sync_with_typed_text(state)
	if not state.original_completion or not state.original_cursor_position then
		return false
	end

	local current_cursor = vim.api.nvim_win_get_cursor(0)
	if not current_cursor or #current_cursor < 2 then
		return false
	end

	local current_position = { row = current_cursor[1] - 1, col = current_cursor[2] }
	local original = state.original_cursor_position
	if current_position.row < original.row then
		return false
	end
	if current_position.row == original.row and current_position.col < original.col then
		return false
	end

	local ok, typed_lines =
		pcall(vim.api.nvim_buf_get_text, 0, original.row, original.col, current_position.row, current_position.col, {})
	if not ok or not typed_lines then
		return false
	end

	local typed_text = table.concat(typed_lines, "\n")
	if typed_text == "" then
		return true
	end

	if state.original_completion:sub(1, #typed_text) ~= typed_text then
		return false
	end

	local remaining = state.original_completion:sub(#typed_text + 1)
	clear_extmark(state)
	if remaining == "" then
		M.clear(state)
		return true
	end

	state.cached_completion = remaining
	state.cursor_position = current_position
	return render(state, remaining, current_position)
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
