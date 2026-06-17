local M = {}

function M.stop_timer(timer)
	if not timer then
		return
	end

	if type(timer) == "userdata" then
		timer:stop()
		timer:close()
		return
	end

	pcall(function()
		vim.fn.timer_stop(timer)
	end)
end

function M.shutdown_job(job)
	if not job then
		return
	end

	pcall(function()
		job:shutdown()
	end)
end

function M.invalidate_request(state)
	state.request_counter = state.request_counter + 1
	state.active_request_id = nil
end

function M.cancel_request(state)
	M.invalidate_request(state)
	M.shutdown_job(state.active_job)
	state.active_job = nil
end

function M.cleanup_state(state)
	if state.debounce_timer then
		M.stop_timer(state.debounce_timer)
		state.debounce_timer = nil
	end

	M.cancel_request(state)
end

return M
