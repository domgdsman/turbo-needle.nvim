# turbo-needle.nvim

AI code completions for Neovim.

## Lazy.nvim

```lua
{
  "domgdsman/turbo-needle.nvim",
  event = "InsertEnter",
  config = function()
    require("turbo-needle").setup({
      api = {
        base_url = "http://localhost:8080",
        model = "qwen3-coder:30b-a3b-instruct-gguf",
        provider = "openai_compatible",
        mode = "fim_prompt",
        -- template = "qwen_coder",
        -- custom_template = "{prefix}<cursor>{suffix}",
        -- stop = "auto",
        -- path = "/v1/fim/completions",
        -- stream = true, -- default; set false for non-streaming providers
        -- extra_body = {},
        -- headers = {},
      },
      completions = {
        debounce_ms = 300,
      },
      postprocess = {
        enabled = true,
        trim_suffix_overlap = true,
        trim_prefix_overlap = true,
        strip_stop_tokens = true,
        max_lines = nil,
        max_chars = nil,
      },
      keymaps = {
        accept = "<Tab>",
      },
       filetypes = {
         help = false,
         gitcommit = false,
         gitrebase = false,
         hgcommit = false,
       },
    })
  end,
}
```

## Provider Modes

Completion requests stream by default. Set `api.stream = false` if your provider does not return Server-Sent Events chunks or if you prefer the older full-response request path.

The default `openai_compatible` + `fim_prompt` mode sends a FIM-rendered `prompt` to `/v1/completions`, which works for vLLM-style OpenAI-compatible completion servers that do not support OpenAI's separate `suffix` parameter. Use `provider = "llamacpp"` with `mode = "llamacpp_infill"` for llama.cpp's native `/infill` endpoint. Use `provider = "litellm"` with `mode = "fim_suffix"` and `path = "/v1/fim/completions"` for LiteLLM-compatible FIM routes that expect `prompt` plus `suffix`. `provider = "chat"` with `mode = "chat_fallback"` is available for chat/instruct models, but FIM-trained models remain the recommended autocomplete path.

Additional request fields can be passed through `api.extra_body`, and provider-specific headers can be added with `api.headers`.

## Autocomplete Templates

`api.template` selects the FIM prompt format used for `fim_prompt` requests. When it is unset, turbo-needle picks a default from `api.model`. Built-in templates include `qwen_coder`, `stable_code`, `starcoder`, `codellama`, `codestral`, `deepseek_coder`, `codegemma`, `generic_fim`, and `hole_filler_chat`.

Use `api.custom_template` for a literal prompt template. Custom templates must include `{prefix}` and `{suffix}` placeholders. `api.stop` defaults to `"auto"`, which sends stop tokens from the selected template. Set it to a string or list to add explicit stop tokens; duplicates are removed deterministically.

## Completion Postprocessing

`postprocess` cleans API output before it is cached or displayed as ghost text. By default it rejects whitespace-only completions, strips common FIM/chat sentinel tokens, trims duplicated text around the cursor, and removes trailing whitespace while preserving leading indentation. Set `max_lines` or `max_chars` to cap inserted completion size.
