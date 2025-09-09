# turbo-needle.nvim

A fast and intuitive Neovim plugin for navigation and search.

## Features

- Fast navigation and search capabilities
- Configurable keymaps and UI
- Floating window interface
- Extensible Lua API
- Comprehensive help documentation

## Requirements

- Neovim >= 0.7.0
- Lua support

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'your-username/turbo-needle.nvim',
  config = function()
    require('turbo-needle').setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'your-username/turbo-needle.nvim',
  config = function()
    require('turbo-needle').setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'your-username/turbo-needle.nvim'

" Add to your init.lua or in a vim script file
lua require('turbo-needle').setup()
```

## Configuration

The plugin comes with sensible defaults, but you can customize it:

```lua
require('turbo-needle').setup({
  keymaps = {
    enabled = true,
    mappings = {
      toggle = '<leader>tn',
      open = '<leader>to',
      close = '<leader>tc',
    }
  },
  ui = {
    border = 'rounded',
    width = 0.8,
    height = 0.8,
    title = 'Turbo Needle',
  },
  behavior = {
    auto_close = false,
    save_position = true,
    restore_cursor = true,
  },
  notifications = {
    enabled = true,
    level = vim.log.levels.INFO,
  }
})
```

## Usage

### Commands

- `:TurboNeedle [args]` - Run the plugin with optional arguments
- `:TurboNeedleSetup` - Setup the plugin with default configuration

### Default Keymaps

- `<leader>tn` - Toggle turbo-needle interface
- `<leader>to` - Open turbo-needle interface  
- `<leader>tc` - Close turbo-needle interface

You can disable default keymaps by setting `keymaps.enabled = false` in your configuration.

### API

```lua
local turbo_needle = require('turbo-needle')

-- Setup with custom configuration
turbo_needle.setup({
  -- your config here
})

-- Programmatically control the plugin
turbo_needle.toggle()
turbo_needle.open()
turbo_needle.close()
turbo_needle.run('some args')
```

## Help

Run `:help turbo-needle` in Neovim to see the full documentation.

## Development

### Project Structure

```
├── lua/
│   └── turbo-needle/
│       ├── init.lua        # Main module and public API
│       ├── config.lua      # Configuration and defaults
│       └── utils.lua       # Utility functions
├── plugin/
│   └── turbo-needle.lua    # Plugin entry point
├── doc/
│   └── turbo-needle.txt    # Help documentation
└── tests/                  # Test files
```

### Testing

```bash
# Run tests (once implemented)
make test
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License. See [LICENSE](LICENSE) for details.