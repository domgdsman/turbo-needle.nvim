-- Example configuration showing how to use parse_curl_args hook
-- Similar to avante.nvim's configuration pattern
-- Note: Removed questionable defaults (max_tokens, temperature, stop)

require('turbo-needle').setup({
  api = {
    base_url = "http://192.168.0.61",
    model = "qwen3-coder:30b-a3b-instruct-gguf",
    api_key_name = "LLAMACPP_API_KEY",  -- Environment variable for API key
    max_tokens = 100,                   -- Optional: Limit completion length
    temperature = 0.1,                  -- Optional: Control randomness (0.0-2.0)
    timeout = 10000,
    max_retries = 2,

    -- Custom curl args hook (avante-style)
    parse_curl_args = function(provider_opts, code_opts)
      -- Adapted from avante config - now simplified since we handle this in the default
      local prefix_code = code_opts.prefix or "" -- Code before cursor
      local suffix_code = code_opts.suffix or "" -- Code after cursor
      local prompt = "<|fim_prefix|>" .. prefix_code .. "<|fim_suffix|>" .. suffix_code .. "<|fim_middle|>"

      local headers = {
        ["Content-Type"] = "application/json",
      }

      -- Handle API key from environment variable
      if provider_opts.api_key_name then
        local env_key = os.getenv(provider_opts.api_key_name)
        if env_key then
          headers["Authorization"] = "Bearer " .. env_key
        end
      end

      local body = {
        model = provider_opts.model,
        messages = {
          {
            role = "system",
            content = "You are Qwen3 Coder, an expert AI coding assistant. Complete the code between <|fim_prefix|> and <|fim_suffix|> with the most appropriate continuation or infill. Output only the completed code without additional text, explanations, or wrappers unless explicitly asked.",
          },
          { role = "user", content = prompt },
        },
        stream = false,  -- No streaming for ghost text
      }

      return {
        url = provider_opts.base_url .. "/v1/chat/completions",
        headers = headers,
        body = body,
        timeout = provider_opts.timeout,
      }
    end
      end

      local body = {
        model = provider_opts.model,
        messages = {
          {
            role = "system",
            content = "You are Qwen3 Coder, an expert AI coding assistant. Complete the code between <|fim_prefix|> and <|fim_suffix|> with the most appropriate continuation.",
          },
          { role = "user", content = prompt },
        },
        stream = false,  -- No streaming for ghost text
        max_tokens = 100,
        temperature = 0.1,
        stop = { "<|im_end|>", "<|endoftext|>" },
      }

      return {
        url = provider_opts.base_url .. "/v1/chat/completions",
        headers = headers,
        body = body,
        timeout = provider_opts.timeout,
      }
    end
  },

  completions = {
    debounce_ms = 300,
    throttle_ms = 1000,
  },

  keymaps = {
    accept = "<Tab>",
  },

  filetypes = {
    enabled = { "lua", "python", "javascript", "typescript", "rust", "go" },
    disabled = { "markdown", "text", "gitcommit", "help" },
  },
})

-- For local models without authentication:
-- require('turbo-needle').setup({
--   api = {
--     base_url = "http://localhost:8000",
--     model = "codellama:7b-code",
--     -- api_key_name = nil,  -- Leave nil for no auth (default)
--   }
-- })

-- Alternative: Set hook programmatically
-- local api = require('turbo-needle.api')
-- api.set_curl_args_hook(function(provider_opts, code_opts)
--   -- Custom implementation here
-- end)