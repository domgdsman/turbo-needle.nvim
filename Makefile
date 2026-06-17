SHELL := /bin/bash

.PHONY: check lint format test

check: lint format test ## Run all checks

lint: ## Run Luacheck
	@nix develop .#ci-check --command luacheck lua/ --globals vim

format: ## Check Lua formatting
	@nix develop .#ci-check --command stylua --check lua/ tests/

test: ## Run tests
	@nix develop .#ci-check --command nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests {minimal_init = 'tests/minimal_init.lua'}"
