# Changelog

## v0.0.25

- Reconcile completion indentation with whitespace already present before the cursor.
- Preserve relative indentation in multiline completions during preview and acceptance.
- Render the exact normalized completion text that will be inserted.

## v0.0.24

- Add configurable completion context budgeting with prefix/suffix allocation.
- Preserve nearby cursor context while trimming distant prefix and suffix text first.
- Add a language-aware filepath comment hint to completion context and template rendering.
- Add language-aware ellipsis comments when prefix or suffix context is truncated.
- Add `context.include_ellipsis` to control truncated-context marker comments.
- Cover redistribution of unused prefix budget to suffix context near the top of a file.

## v0.0.23

- Keep visible ghost completions synchronized while typing matching text.
- Accept only the remaining synchronized completion suffix at the current cursor.
- Resume normal debounce and request behavior when typed text no longer matches the suggestion.

## v0.0.22

- Add structured completion postprocess classification for rejected inline completions.
- Clean markdown code fences and thinking artifacts, and reject stop-token-only, line-rewrite, repeated-line, duplicate-prefix, duplicate-suffix, and optionally too-short completions.
- Retry completed API responses up to three times by default when postprocessing classifies the response as retryable.
- Keep rejected completions out of the cache and ghost text display path.
- Document and validate `postprocess.retry` settings.

## v0.0.21

- Add completion postprocessing for whitespace rejection, sentinel cleanup, overlap trimming, and optional length caps.
- Cache and display postprocessed completion text instead of raw API output.
- Add validated `postprocess` configuration defaults and unit coverage for cleanup behavior.

## v0.0.20

- Add model-specific autocomplete template selection with built-in FIM formats and model-name matching for common code completion model families.
- Add `api.template`, `api.custom_template`, and `api.stop` configuration for explicit template and stop-token control.
- Include template stop tokens in request bodies and merge them with user stop tokens without duplicates.
- Document autocomplete template configuration and add unit coverage for rendering, matching, validation, and stop-token merging.

## v0.0.19

- Add provider and request-mode API configuration for OpenAI-compatible FIM prompts, suffix-aware FIM, llama.cpp infill, LiteLLM path overrides, and chat fallback requests.
- Add mode-specific request body builders and response parsing.
- Include API request-shape fingerprints in completion cache keys to avoid stale completions after provider, model, mode, path, stream, extra body, or header changes.
- Document the optional provider/mode API shape.

## v0.0.18

- Add a curl-backed transport facade for completion requests.
- Add conservative streaming support for Server-Sent Events `data:` chunks with OpenAI-compatible text and delta decoding.
- Add validated `api.stream` configuration, defaulting to streaming unless explicitly disabled.
- Keep existing non-streaming completion behavior and cancellation compatibility.

## v0.0.17

- Remove duplicate `max_tokens` and `temperature` validation paths from configuration validation.
- Add focused module-level coverage for extracted state, cleanup, cache, edit, ghost, and keymap primitives.
- Harden primitive behavior tests around cache TTL/LRU eviction, cleanup idempotency, insertion cursor rules, and keymap replacement.

## v0.0.16

- Extract ghost text rendering, clearing, and acceptance into `turbo-needle.ghost`.
- Extract autocmd, debounce, and buffer lifecycle wiring into `turbo-needle.lifecycle`.
- Extract accept keymap replacement into `turbo-needle.keymaps`.
- Keep public runtime wrappers in `init.lua` for compatibility.
- Quiet expected stale extmark cleanup errors.

## v0.0.15

- Extract core runtime primitives for completion cache, buffer state, cleanup, and edit insertion.
- Keep completion behavior unchanged while reducing duplication in the main runtime module.
- Add plugin version metadata.

## v0.0.14

- Fix audited runtime issues around setup validation, keymap replacement, multiline acceptance, and JSON response parsing.
- Preserve the previous valid configuration when setup substitution or validation fails.
- Replace stale insert-mode accept mappings when `setup()` is called repeatedly with a different accept key.
- Preserve literal escape sequences returned by decoded JSON completion responses.
- Pin the Plenary test dependency and add CI checks through a Nix development shell.
- Add regression coverage for setup failure handling, accept key replacement, literal `\n` completion text, and middle-of-line multiline acceptance.

## v0.0.13

- Add structured logging modules and route plugin messages through the logger.
- Add logging configuration validation and setup wiring.
- Support API key substitution from environment variables.
- Build runtime configuration from defaults plus user options on each `setup()` call.
- Remove request retry behavior to keep completion request handling simpler and more predictable.

## v0.0.12

- Expand the automated test suite across API parsing, context extraction, caching, init behavior, ghost text, and expression-mapping acceptance.
- Rework tests to use `luassert` stubs, snapshots, and deterministic scheduling.
- Add coverage for scheduled insertion to avoid Neovim textlock errors.
- Simplify filetype configuration and update related tests.
- Clean up unused test artifacts and LSP warnings.

## v0.0.11

- Stabilize ghost text positioning and acceptance behavior.
- Add request cancellation for running Plenary jobs.
- Cache completion text for later acceptance.
- Store and validate cursor position before accepting a displayed completion.
- Insert accepted completions asynchronously with `vim.schedule()` to avoid `E565` textlock failures.
- Move the cursor to the end of accepted completion text.
- Add an augroup for plugin autocmd lifecycle management.
- Add lazy.nvim usage documentation.

## v0.0.10

- Add the initial Neovim plugin structure with runtime, plugin entrypoint, configuration, and tests.
- Add completion context extraction and API request modules.
- Send completion requests to an OpenAI-compatible `/v1/completions` endpoint.
- Execute curl requests through Plenary jobs and report curl errors.
- Add completion enable/disable commands and a read-only enabled state.
- Remove the earlier `completions.enabled` configuration setting in favor of runtime commands.
