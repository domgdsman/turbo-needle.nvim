# Changelog

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
