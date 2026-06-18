---@diagnostic disable: undefined-field

local stub = require("luassert.stub")

describe("turbo-needle extracted primitives", function()
	local snapshot

	before_each(function()
		snapshot = assert:snapshot()
	end)

	after_each(function()
		if snapshot then
			snapshot:revert()
		end
	end)

	describe("state", function()
		local state = require("turbo-needle.state")

		it("creates, reuses, and deletes buffer-local state", function()
			local states = {}
			local bufnr = vim.api.nvim_get_current_buf()

			local first = state.get(states, bufnr)
			local second = state.get(states, bufnr)

			assert.are.same(first, second)
			assert.are.equal(0, first.request_counter)
			assert.is_nil(first.active_job)
			assert.is_nil(first.cached_completion)

			state.delete(states, bufnr)
			assert.is_nil(states[bufnr])
		end)

		it("returns a set of currently valid buffers", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			local valid = state.valid_buffers()

			assert.is_true(valid[bufnr])

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
	end)

	describe("cleanup", function()
		local cleanup = require("turbo-needle.cleanup")

		it("stops timer ids through vim.fn.timer_stop", function()
			local stop_stub = stub(vim.fn, "timer_stop")

			cleanup.stop_timer(123)

			assert.stub(stop_stub).was_called_with(123)
		end)

		it("cancels requests idempotently and clears active jobs", function()
			local shutdown_calls = 0
			local state = {
				request_counter = 7,
				active_request_id = 7,
				active_job = {
					shutdown = function()
						shutdown_calls = shutdown_calls + 1
					end,
				},
			}

			cleanup.cancel_request(state)
			cleanup.cancel_request(state)

			assert.are.equal(9, state.request_counter)
			assert.is_nil(state.active_request_id)
			assert.is_nil(state.active_job)
			assert.are.equal(1, shutdown_calls)
		end)

		it("cleans timers and requests from state", function()
			local stop_stub = stub(vim.fn, "timer_stop")
			local state = {
				debounce_timer = 55,
				request_counter = 1,
				active_request_id = 1,
				active_job = {},
			}

			cleanup.cleanup_state(state)

			assert.stub(stop_stub).was_called_with(55)
			assert.is_nil(state.debounce_timer)
			assert.is_nil(state.active_request_id)
			assert.is_nil(state.active_job)
			assert.are.equal(2, state.request_counter)
		end)
	end)

	describe("cache", function()
		local cache = require("turbo-needle.cache")

		it("returns cached completions before TTL expiry and removes them after expiry", function()
			local now = 1000
			stub(vim.loop, "now").invokes(function()
				return now
			end)

			local completions = cache.new({ ttl_ms = 100, max_size = 2 })
			local ctx = { prefix = "local value = ", suffix = "" }

			completions:set(ctx, "42")
			assert.are.equal("42", completions:get(ctx))

			now = 1200
			assert.is_nil(completions:get(ctx))
		end)

		it("evicts the least recently accessed entry when full", function()
			local now = 1000
			stub(vim.loop, "now").invokes(function()
				return now
			end)

			local completions = cache.new({ ttl_ms = 1000, max_size = 2 })
			local first = { prefix = "first", suffix = "" }
			local second = { prefix = "second", suffix = "" }
			local third = { prefix = "third", suffix = "" }

			completions:set(first, "one")
			now = now + 10
			completions:set(second, "two")
			now = now + 10
			assert.are.equal("one", completions:get(first))
			now = now + 10
			completions:set(third, "three")

			assert.are.equal("one", completions:get(first))
			assert.is_nil(completions:get(second))
			assert.are.equal("three", completions:get(third))
		end)
	end)

	describe("edit", function()
		local edit = require("turbo-needle.edit")

		it("inserts single-line text at the stored cursor row", function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "return" })
			stub(vim.api, "nvim_win_get_cursor").returns({ 1, 6 })

			local final = edit.insert_at_cursor(" value", { row = 0, col = 6 })

			assert.are.same({ "return value" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
			assert.are.same({ row = 0, col = 12 }, final)
		end)

		it("preserves suffix text when inserting multiple lines", function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foobar" })
			vim.api.nvim_win_set_cursor(0, { 1, 3 })

			local final = edit.insert_at_cursor("A\nB", { row = 0, col = 3 })

			assert.are.same({ "fooA", "Bbar" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
			assert.are.same({ row = 1, col = 1 }, final)
		end)

		it("does not insert when the cursor row changed", function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
			vim.api.nvim_win_set_cursor(0, { 2, 0 })

			local final = edit.insert_at_cursor("x", { row = 0, col = 0 })

			assert.is_nil(final)
			assert.are.same({ "one", "two" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		end)
	end)

	describe("ghost", function()
		local ghost = require("turbo-needle.ghost")

		it("sets and clears ghost completion state", function()
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(88)
			stub(vim.api, "nvim_win_get_cursor").returns({ 1, 2 })
			stub(vim.api, "nvim_buf_set_extmark").returns(99)
			local del_stub = stub(vim.api, "nvim_buf_del_extmark")

			local state = {}
			ghost.set(state, "completion")

			assert.are.equal("completion", state.cached_completion)
			assert.are.equal("completion", state.original_completion)
			assert.are.same({ row = 0, col = 2 }, state.cursor_position)
			assert.are.same({ row = 0, col = 2 }, state.original_cursor_position)
			assert.are.same({ ns_id = 88, id = 99 }, state.current_extmark)

			ghost.clear(state)

			assert.stub(del_stub).was_called_with(0, 88, 99)
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.original_completion)
			assert.is_nil(state.cursor_position)
			assert.is_nil(state.original_cursor_position)
			assert.is_nil(state.current_extmark)
		end)

		it("syncs matching typed text to the remaining completion", function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "return" })
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(88)
			stub(vim.api, "nvim_buf_del_extmark")
			local extmarks = {}
			stub(vim.api, "nvim_buf_set_extmark").invokes(function(_, ns, row, col, opts)
				table.insert(extmarks, { ns = ns, row = row, col = col, opts = opts })
				return #extmarks
			end)

			local cursor = { 1, 6 }
			stub(vim.api, "nvim_win_get_cursor").invokes(function()
				return cursor
			end)

			local state = {}
			ghost.set(state, " value")
			vim.api.nvim_buf_set_text(0, 0, 6, 0, 6, { " v" })
			cursor = { 1, 8 }

			local synced = ghost.sync_with_typed_text(state)

			assert.is_true(synced)
			assert.are.equal("alue", state.cached_completion)
			assert.are.equal(" value", state.original_completion)
			assert.are.same({ row = 0, col = 8 }, state.cursor_position)
			assert.are.equal("alue", extmarks[#extmarks].opts.virt_text[1][1])
		end)

		it("accepts only the remaining completion after typed-text sync", function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "return" })
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(88)
			stub(vim.api, "nvim_buf_del_extmark")
			stub(vim.api, "nvim_buf_set_extmark").returns(99)

			local cursor = { 1, 6 }
			stub(vim.api, "nvim_win_get_cursor").invokes(function()
				return cursor
			end)

			local state = {}
			ghost.set(state, " value")
			vim.api.nvim_buf_set_text(0, 0, 6, 0, 6, { " v" })
			cursor = { 1, 8 }

			assert.is_true(ghost.sync_with_typed_text(state))
			assert.are.equal("", ghost.accept(state, ghost.clear))
			vim.wait(20)

			assert.are.same({ "return value" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
			assert.is_nil(state.cached_completion)
		end)

		it("returns false for mismatched typed text and leaves normal clearing to lifecycle", function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "return" })
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(88)
			stub(vim.api, "nvim_buf_set_extmark").returns(99)

			local cursor = { 1, 6 }
			stub(vim.api, "nvim_win_get_cursor").invokes(function()
				return cursor
			end)

			local state = {}
			ghost.set(state, " value")
			vim.api.nvim_buf_set_text(0, 0, 6, 0, 6, { " x" })
			cursor = { 1, 8 }

			assert.is_false(ghost.sync_with_typed_text(state))
			assert.are.equal(" value", state.cached_completion)
		end)

		it("syncs multiline typed text and renders the remaining suffix", function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "call()" })
			stub(vim.api, "nvim_get_mode").returns({ mode = "i" })
			stub(vim.api, "nvim_create_namespace").returns(88)
			stub(vim.api, "nvim_buf_del_extmark")
			local extmarks = {}
			stub(vim.api, "nvim_buf_set_extmark").invokes(function(_, ns, row, col, opts)
				table.insert(extmarks, { ns = ns, row = row, col = col, opts = opts })
				return #extmarks
			end)

			local cursor = { 1, 6 }
			stub(vim.api, "nvim_win_get_cursor").invokes(function()
				return cursor
			end)

			local state = {}
			ghost.set(state, "\n  next()\nend")
			vim.api.nvim_buf_set_text(0, 0, 6, 0, 6, { "", "  " })
			cursor = { 2, 2 }

			local synced = ghost.sync_with_typed_text(state)

			assert.is_true(synced)
			assert.are.equal("next()\nend", state.cached_completion)
			assert.are.same({ row = 1, col = 2 }, state.cursor_position)
			assert.are.equal("next()", extmarks[#extmarks].opts.virt_text[1][1])
			assert.are.equal("end", extmarks[#extmarks].opts.virt_lines[1][1][1])
		end)

		it("does not sync when the cursor moves before the original ghost position", function()
			stub(vim.api, "nvim_win_get_cursor").returns({ 1, 3 })

			local result = ghost.sync_with_typed_text({
				original_completion = "text",
				original_cursor_position = { row = 0, col = 4 },
			})

			assert.is_false(result)
		end)

		it("returns tab when accepting stale cursor state", function()
			stub(vim.api, "nvim_win_get_cursor").returns({ 1, 5 })

			local result = ghost.accept({
				cached_completion = "text",
				cursor_position = { row = 0, col = 4 },
			}, function() end)

			assert.are.equal("\t", result)
		end)
	end)

	describe("lifecycle", function()
		local lifecycle = require("turbo-needle.lifecycle")

		it("does not clear, invalidate, or debounce when ghost sync succeeds", function()
			stub(vim.api, "nvim_create_augroup").returns(1)

			local cursor_moved_callback
			stub(vim.api, "nvim_create_autocmd").invokes(function(events, opts)
				if type(events) == "table" and vim.tbl_contains(events, "CursorMovedI") then
					cursor_moved_callback = opts.callback
				end
			end)

			local timer_created = false
			stub(vim.loop, "new_timer").invokes(function()
				timer_created = true
			end)

			local state = { request_counter = 3 }
			local clear_calls = 0
			local complete_calls = 0

			lifecycle.setup({
				config = { completions = { debounce_ms = 10 } },
				get_state = function()
					return state
				end,
				complete = function()
					complete_calls = complete_calls + 1
				end,
				clear_ghost = function()
					clear_calls = clear_calls + 1
				end,
				sync_ghost = function()
					return true
				end,
				is_enabled = function()
					return true
				end,
			})

			cursor_moved_callback()

			assert.are.equal(0, clear_calls)
			assert.are.equal(0, complete_calls)
			assert.are.equal(3, state.request_counter)
			assert.is_false(timer_created)
		end)
	end)

	describe("keymaps", function()
		it("replaces the previous accept keymap", function()
			package.loaded["turbo-needle.keymaps"] = nil
			local keymaps = require("turbo-needle.keymaps")
			local accept = function()
				return ""
			end

			keymaps.setup({ accept = "<C-g>" }, accept)
			assert.is_not_nil(vim.fn.maparg("<C-g>", "i"))

			keymaps.setup({ accept = "<C-h>" }, accept)
			assert.are.equal("", vim.fn.maparg("<C-g>", "i"))
			assert.is_not_nil(vim.fn.maparg("<C-h>", "i"))

			vim.keymap.del("i", "<C-h>")
			package.loaded["turbo-needle.keymaps"] = nil
		end)
	end)
end)
