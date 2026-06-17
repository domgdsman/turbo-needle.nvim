---@diagnostic disable: undefined-field

local transport = require("turbo-needle.transport")

describe("turbo-needle.transport", function()
	describe("build_curl_args", function()
		it("should build non-streaming curl args", function()
			local args = transport.build_curl_args({
				url = "http://localhost:8000/v1/completions",
				headers = {
					["Content-Type"] = "application/json",
					Authorization = "Bearer test",
				},
				body = { model = "test", prompt = "hello", stream = false },
				timeout = 5000,
				stream = false,
			})

			assert.is_false(vim.tbl_contains(args, "-N"))
			assert.is_true(vim.tbl_contains(args, "--max-time"))
			assert.is_true(vim.tbl_contains(args, "5"))
			assert.are.equal("http://localhost:8000/v1/completions", args[#args])
		end)

		it("should build streaming curl args", function()
			local args = transport.build_curl_args({
				url = "http://localhost:8000/v1/completions",
				headers = {},
				body = { stream = true },
				timeout = 5000,
				stream = true,
			})

			assert.is_true(vim.tbl_contains(args, "-N"))
		end)
	end)

	describe("parse_stream_line", function()
		it("should parse OpenAI completion text chunks", function()
			local text, done = transport.parse_stream_line([[data: {"choices":[{"text":"abc"}]}]])

			assert.are.equal("abc", text)
			assert.is_false(done)
		end)

		it("should parse OpenAI delta content chunks", function()
			local text, done = transport.parse_stream_line([[data: {"choices":[{"delta":{"content":"def"}}]}]])

			assert.are.equal("def", text)
			assert.is_false(done)
		end)

		it("should recognize done chunks", function()
			local text, done = transport.parse_stream_line("data: [DONE]")

			assert.is_nil(text)
			assert.is_true(done)
		end)

		it("should ignore non-data and invalid JSON lines", function()
			local text, done = transport.parse_stream_line("event: ping")
			assert.is_nil(text)
			assert.is_false(done)

			text, done = transport.parse_stream_line("data: not-json")
			assert.is_nil(text)
			assert.is_false(done)
		end)
	end)

	describe("request", function()
		local original_job
		local original_schedule_wrap
		local job_spec

		before_each(function()
			original_job = package.loaded["plenary.job"]
			original_schedule_wrap = vim.schedule_wrap
			job_spec = nil
			vim.schedule_wrap = function(callback)
				return callback
			end

			package.loaded["turbo-needle.transport"] = nil
			package.loaded["plenary.job"] = {
				new = function(_, spec)
					job_spec = spec
					return {
						start = function() end,
						shutdown = function() end,
						result = function()
							return { [[{"choices":[{"text":"done"}]}]] }
						end,
						stderr_result = function()
							return {}
						end,
					}
				end,
			}

			transport = require("turbo-needle.transport")
		end)

		after_each(function()
			package.loaded["turbo-needle.transport"] = nil
			package.loaded["plenary.job"] = original_job
			vim.schedule_wrap = original_schedule_wrap
			transport = require("turbo-needle.transport")
		end)

		it("should decode non-streaming responses on completion", function()
			local result
			transport.request({
				url = "http://localhost",
				headers = {},
				body = {},
				timeout = 5000,
				stream = false,
			}, {
				on_done = function(err, decoded)
					assert.is_nil(err)
					result = decoded
				end,
			})

			job_spec.on_exit({
				result = function()
					return { [[{"choices":[{"text":"done"}]}]] }
				end,
				stderr_result = function()
					return {}
				end,
			}, 0)

			assert.are.equal("done", result.choices[1].text)
		end)

		it("should accumulate streaming chunks into a completion result", function()
			local chunks = {}
			local result

			transport.request({
				url = "http://localhost",
				headers = {},
				body = { stream = true },
				timeout = 5000,
				stream = true,
			}, {
				on_chunk = function(text)
					table.insert(chunks, text)
				end,
				on_done = function(err, decoded)
					assert.is_nil(err)
					result = decoded
				end,
			})

			job_spec.on_stdout(nil, [[data: {"choices":[{"text":"hel"}]}]])
			job_spec.on_stdout(nil, [[data: {"choices":[{"delta":{"content":"lo"}}]}]])
			job_spec.on_stdout(nil, "data: [DONE]")
			job_spec.on_exit({
				result = function()
					return {}
				end,
				stderr_result = function()
					return {}
				end,
			}, 0)

			assert.are.same({ "hel", "lo" }, chunks)
			assert.are.equal("hello", result.choices[1].text)
		end)
	end)
end)
