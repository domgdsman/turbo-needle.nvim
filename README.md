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
      },
      completions = {
        debounce_ms = 300,
      },
      keymaps = {
        accept = "<Tab>",
      },
      filetypes = {
        enabled = { "lua", "python", "javascript", "typescript", "rust", "go" },
        disabled = { "help", "gitcommit", "gitrebase", "hgcommit" },
      },
    })
  end,
}
```
