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
			assert.are.same({ row = 0, col = 2 }, state.cursor_position)
			assert.are.same({ ns_id = 88, id = 99 }, state.current_extmark)

			ghost.clear(state)

			assert.stub(del_stub).was_called_with(0, 88, 99)
			assert.is_nil(state.cached_completion)
			assert.is_nil(state.cursor_position)
			assert.is_nil(state.current_extmark)
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
