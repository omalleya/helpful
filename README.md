# Neovim Config

A Neovim configuration using Lua and [lazy.nvim](https://github.com/folke/lazy.nvim) as the plugin manager.

## Setup

1. Copy `init.lua` to your Neovim config directory:

   ```sh
   mkdir -p ~/.config/nvim
   cp init.lua ~/.config/nvim/init.lua
   ```

2. Open Neovim — lazy.nvim will bootstrap itself and install all plugins automatically on first launch.

3. Treesitter parsers will also install automatically on first use.

## What's Included

| Plugin | Purpose |
|---|---|
| **nvim-tree** | File explorer (opens automatically on startup) |
| **nvim-treesitter** | Syntax highlighting and indentation |
| **conform.nvim** | Format on save (eslint_d/eslint for JS/TS) |
| **nvim-lint** | Linting on save and insert leave (eslint_d for JS/TS) |
| **emmet-vim** | Emmet expansion in HTML/CSS/JSX (`<Tab>,`) |

## Key Settings

- **Leader key**: `<Space>`
- **Tabs**: 2 spaces, auto/smart indent
- **Clipboard**: uses system clipboard
- **Search**: case-insensitive unless uppercase is used

## Keybindings

| Key | Action |
|---|---|
| `<Space>f` | Format current buffer |
| `<Tab>,` | Expand Emmet abbreviation |

## Prerequisites

- [Neovim](https://neovim.io/) >= 0.9
- A [Nerd Font](https://www.nerdfonts.com/) (for file icons in nvim-tree)
- `eslint_d` or `eslint` on your PATH (for JS/TS formatting and linting)
