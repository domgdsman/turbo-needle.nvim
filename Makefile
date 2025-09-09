.PHONY: test lint format clean install-dev check-deps

# Test configuration
TEST_DIR = tests
NVIM_CMD = nvim --headless --noplugin

# Dependency detection
HAS_BREW := $(shell command -v brew 2> /dev/null)
HAS_CARGO := $(shell command -v cargo 2> /dev/null)
HAS_NPM := $(shell command -v npm 2> /dev/null)
HAS_LUACHECK := $(shell command -v luacheck 2> /dev/null)
HAS_STYLUA := $(shell command -v stylua 2> /dev/null)

test:
	@echo "Running tests..."
	@$(NVIM_CMD) -u tests/minimal_init.lua -c "PlenaryBustedDirectory $(TEST_DIR) {minimal_init = 'tests/minimal_init.lua'}"

test-file:
	@echo "Running single test file: $(FILE)"
	@$(NVIM_CMD) -u tests/minimal_init.lua -c "PlenaryBustedFile $(FILE)"

lint:
	@echo "Linting Lua files..."
ifndef HAS_LUACHECK
	@echo "Error: luacheck not found. Run 'make install-dev' first."
	@exit 1
endif
	@luacheck lua/ --globals vim

format:
	@echo "Formatting Lua files..."
ifndef HAS_STYLUA
	@echo "Error: stylua not found. Run 'make install-dev' first."
	@exit 1
endif
	@stylua lua/ tests/

clean:
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name "*.log" -delete

check-deps:
	@echo "Checking available package managers..."
ifdef HAS_BREW
	@echo "✓ Homebrew found"
endif
ifdef HAS_CARGO
	@echo "✓ Cargo found"
endif
ifdef HAS_NPM
	@echo "✓ npm found"
endif
ifdef HAS_LUACHECK
	@echo "✓ luacheck found"
else
	@echo "✗ luacheck not found"
endif
ifdef HAS_STYLUA
	@echo "✓ stylua found"
else
	@echo "✗ stylua not found"
endif

install-dev: check-deps
	@echo "Installing development dependencies..."
ifndef HAS_LUACHECK
	@echo "Installing luacheck..."
ifdef HAS_BREW
	@brew install luarocks && luarocks install luacheck
else ifdef HAS_CARGO
	@echo "Installing luacheck via cargo..."
	@cargo install --git https://github.com/mpeterv/luacheck
else ifdef HAS_NPM
	@echo "Installing luacheck via npm..."
	@npm install -g luacheck
else
	@echo "Error: No package manager found. Please install brew, cargo, or npm first."
	@echo "Or manually install luacheck: https://github.com/mpeterv/luacheck"
	@exit 1
endif
endif
ifndef HAS_STYLUA
	@echo "Installing stylua..."
ifdef HAS_CARGO
	@cargo install stylua
else ifdef HAS_BREW
	@brew install stylua
else ifdef HAS_NPM
	@npm install -g @johnnymorganz/stylua-bin
else
	@echo "Error: No package manager found. Please install brew, cargo, or npm first."
	@echo "Or manually install stylua: https://github.com/JohnnyMorganz/StyLua"
	@exit 1
endif
endif
	@echo "Development dependencies installed successfully!"

help:
	@echo "Available commands:"
	@echo "  test        - Run all tests"
	@echo "  test-file   - Run single test file (use FILE=path/to/test.lua)"
	@echo "  lint        - Lint Lua files with luacheck"
	@echo "  format      - Format Lua files with stylua"
	@echo "  clean       - Clean temporary files"
	@echo "  check-deps  - Check status of development dependencies"
	@echo "  install-dev - Install development dependencies"
	@echo "  help        - Show this help message"