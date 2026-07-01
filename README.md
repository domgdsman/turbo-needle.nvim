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
      context = {
        max_chars = 12000,
        prefix_ratio = 0.75,
        include_filepath = true,
        include_ellipsis = true,
        sources = {
          recently_edited = {
            enabled = true,
            priority = 100,
            sort_order = 10,
            max_ranges = 3,
            ttl_ms = 120000,
            merge_adjacent = true,
          },
        },
      },
      postprocess = {
        enabled = true,
        trim_suffix_overlap = true,
        trim_prefix_overlap = true,
        strip_stop_tokens = true,
        max_lines = nil,
        max_chars = nil,
        min_chars = nil,
        retry = {
          enabled = true,
          max_attempts = 3,
          on_reasons = {
            empty = true,
            whitespace = true,
            stop_token_only = true,
            thinking = true,
            repetition = true,
            line_rewrite = true,
          },
        },
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

Templates can also use `{filepath}`. By default, turbo-needle prepends the full current buffer path to the prefix as a language-aware comment using `vim.bo.commentstring`, for example `-- /tmp/init.lua` in Lua or `# /tmp/example.py` in Python. When context is truncated and `context.include_ellipsis` is enabled, turbo-needle adds a matching `…` comment before the retained prefix or after the retained suffix to signal hidden buffer content.

## Completion Context

`context.max_chars` controls the total prefix plus suffix character budget sent to the completion provider. `context.prefix_ratio` controls how that budget is split when both sides exceed the limit; nearby cursor text is kept first, with older prefix text and farther suffix text truncated before local context. Filepath context is included by default because it usually implies language, framework, and project location without adding a separate metadata block.

The `ContextManager` can prepend additional context sources before the current-buffer FIM prefix. A source has the following contract:

```lua
{
  source = "recently_opened",
  priority = 80,
  sort_order = 20,
  can_truncate = true,
  content = { "first block", "second\nmultiline block" },
}
```

The current buffer always receives budget first. Enabled additional sources are considered by descending `priority`, and each content part is included whole when it fits. Oversized parts are truncated only when `can_truncate` is true; otherwise they are skipped and collection continues. Selected sources are placed by ascending `sort_order`, with every content line converted to the active buffer's comment syntax. `context.sources.<source>` can disable a source or override its `priority` and `sort_order`.

### Recently Edited Context

Recently edited whole-line ranges are included as additional context by default. The source keeps the three newest ranges for two minutes, merges overlapping or adjacent edits in the same file, and excludes a range containing the active cursor because the current-buffer prefix and suffix already cover it. Configure it through `context.sources.recently_edited`; set `enabled = false` to disable collection.

The underlying `ContextList` is an in-memory bounded list with exact-key replacement, newest-first ordering, optional TTL expiry, and ordered source-defined policies. Policies can mutate an incoming item and remove existing entries, which keeps range overlap behavior out of the generic storage primitive.

## Completion Postprocessing

`postprocess` cleans API output before it is cached or displayed as ghost text. By default it rejects whitespace-only completions, strips common FIM/chat sentinel tokens, unwraps markdown code fences, removes `<think>` artifacts, trims duplicated text around the cursor, rejects repeated-line output, and removes trailing whitespace while preserving leading indentation. Set `max_lines` or `max_chars` to cap inserted completion size, or `min_chars` to reject very short completions.

`postprocess.retry` retries useless model responses after a completed API response is classified as retryable. It does not retry network or transport failures. Rejected completions are not cached or displayed as ghost text, and `max_attempts` limits the number of retry requests.
