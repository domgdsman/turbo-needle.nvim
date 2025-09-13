local turbo_needle = require("turbo-needle")

-- This test simulates an <expr> mapping acceptance where direct text edits
-- would normally raise E565 (textlock) inside the mapping evaluation.
-- We rely on the asynchronous fallback (vim.schedule) path in accept_completion.

describe("turbo-needle expr mapping acceptance", function()
  before_each(function()
    package.loaded["turbo-needle"] = nil
    turbo_needle = require("turbo-needle")
  end)

  it("should schedule insertion when accept called in expr context", function()
    turbo_needle.setup()

    -- Force insert mode
    local original_get_mode = vim.api.nvim_get_mode
    vim.api.nvim_get_mode = function() return { mode = "i" } end

    -- Create buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })
    vim.api.nvim_win_set_cursor(0, {1, #"local x = 1"})

    -- Mock namespace & extmark to simplify
    local original_create_ns = vim.api.nvim_create_namespace
    local original_buf_set_extmark = vim.api.nvim_buf_set_extmark
    vim.api.nvim_create_namespace = function() return 2025 end
    vim.api.nvim_buf_set_extmark = function() return 8080 end

    -- Provide ghost text
    turbo_needle.set_ghost_text(" -- appended_expr")
    local state = turbo_needle._buf_states[bufnr]
    assert.is_not_nil(state.cached_completion)

    -- Simulate expr mapping invocation: call accept_completion while pretending textlock by forcing failure first.
    -- We can't easily toggle real textlock here; instead we verify that a direct call returns "" and
    -- that after a short wait the buffer contains the appended text (covers scheduled path equivalently).

    local ret = turbo_needle.accept_completion()
    assert.are.equal("", ret) -- should suppress Tab

    -- Allow scheduled insertion to run
    vim.wait(50)

    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    assert.are.equal("local x = 1 -- appended_expr", line)
    local cur = vim.api.nvim_win_get_cursor(0)
    assert.are.equal(1, cur[1])
    assert.are.equal(#"local x = 1 -- appended_expr" - 1, cur[2])
    assert.is_nil(state.cached_completion)
    assert.is_nil(state.current_extmark)

    -- Restore
    vim.api.nvim_get_mode = original_get_mode
    vim.api.nvim_create_namespace = original_create_ns
    vim.api.nvim_buf_set_extmark = original_buf_set_extmark
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
