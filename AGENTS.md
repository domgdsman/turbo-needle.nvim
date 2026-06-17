# AGENTS.md

## Codebase Summary

turbo-needle.nvim is a Neovim inline completion plugin written in Lua.
Runtime code lives under `lua/turbo-needle`, with `init.lua` as the public orchestration layer.
Tests live under `tests` and run through Plenary in a Nix-provided Neovim environment.

## Agent Instructions

- Prefer small follow-up commits on pull request branches; do not force push unless explicitly asked.
- Keep public API wrappers in `init.lua` stable unless a task explicitly changes compatibility.
- Run `make check` before sharing a PR or marking work complete.
- Keep desired behavior covered by tests, especially around ghost text, keymaps, lifecycle cleanup, cache behavior, and expression mappings.
- Use the existing module boundaries: config, context, api, cache, state, cleanup, edit, ghost, lifecycle, keymaps, logger, and version.

## Code Style

- Write idiomatic Lua formatted with Stylua.
- Keep modules small and focused, returning a table of functions.
- Prefer explicit state passed into helper modules over new global/module-local mutable state.
- Use `pcall` around Neovim cleanup paths that can race with buffer, namespace, job, or timer teardown.
- Keep comments short and reserved for behavior that is not obvious from the code.
