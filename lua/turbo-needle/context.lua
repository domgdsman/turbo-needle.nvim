local M = {}

-- Extract code context around cursor for FIM completion
function M.extract_context(bufnr, cursor_row, cursor_col)
  -- Get all lines in the buffer
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total_lines = #all_lines

  -- Convert 0-based cursor position to 1-based for string operations
  local cursor_line_1based = cursor_row + 1
  local cursor_col_1based = cursor_col + 1

  -- Extract prefix: all content before cursor
  local prefix_lines = {}
  for i = 1, cursor_line_1based - 1 do
    table.insert(prefix_lines, all_lines[i])
  end

  local prefix = table.concat(prefix_lines, "\n")
  if #prefix_lines > 0 then
    prefix = prefix .. "\n"
  end

  -- Add the current line up to cursor position
  if cursor_line_1based <= total_lines then
    local current_line = all_lines[cursor_line_1based]
    if cursor_col_1based > 1 then
      -- Extract substring up to cursor column
      local prefix_part = string.sub(current_line, 1, cursor_col_1based - 1)
      prefix = prefix .. prefix_part
    end
  end

  -- Extract suffix: all content after cursor
  local suffix_lines = {}
  local has_suffix_part = false
  if cursor_line_1based <= total_lines then
    local current_line = all_lines[cursor_line_1based]
    if cursor_col_1based <= #current_line then
      -- Extract substring from cursor column to end of line
      local suffix_part = string.sub(current_line, cursor_col_1based)
      table.insert(suffix_lines, suffix_part)
      has_suffix_part = true
    end
  end

  -- Add remaining lines after current line
  for i = cursor_line_1based + 1, total_lines do
    table.insert(suffix_lines, all_lines[i])
  end

  -- If no suffix part but there are remaining lines, add empty string to start with \n
  if not has_suffix_part and #suffix_lines > 0 then
    table.insert(suffix_lines, 1, "")
  end

  return {
    prefix = prefix,
    suffix = table.concat(suffix_lines, "\n")
  }
end

-- Get current cursor position and extract context
function M.get_current_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0) -- Returns {row, col} 0-based
  local row, col = cursor[1] - 1, cursor[2] -- Convert to 0-based

  return M.extract_context(bufnr, row, col)
end

-- Check if current file type is supported
function M.is_filetype_supported()
  local config = require("turbo-needle.config")
  local filetype = vim.bo.filetype

  -- Check if filetype is in enabled list
  for _, enabled_type in ipairs(config.defaults.filetypes.enabled) do
    if filetype == enabled_type then
      return true
    end
  end

  -- Check if filetype is in disabled list
  for _, disabled_type in ipairs(config.defaults.filetypes.disabled) do
    if filetype == disabled_type then
      return false
    end
  end

  -- Default: allow if not explicitly disabled
  return true
end

return M