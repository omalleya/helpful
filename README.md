# helpful

A grab-bag of personal dev configs and tools (Neovim, tmux, zsh, a worktree
helper, and Claude/Codex skills), copied or symlinked onto each machine.

## Neovim

A Neovim configuration using Lua and [lazy.nvim](https://github.com/folke/lazy.nvim) as the plugin manager.

## Shared Skills

Reusable, non-work-specific Claude/Codex skills live in `skills/`.

Install or refresh local symlinks with:

```sh
./scripts/install-skills.sh
```

The installer links each skill into both `~/.claude/skills` and `~/.agents/skills`.

## Setup

1. Copy `init.lua` to your Neovim config directory:

   ```sh
   mkdir -p ~/.config/nvim
   cp init.lua ~/.config/nvim/init.lua
   ```

2. Open Neovim — lazy.nvim will bootstrap itself and install all plugins automatically on first launch.

3. Treesitter parsers will also install automatically on first use.

## What's Included

| Plugin              | Purpose                                               |
| ------------------- | ----------------------------------------------------- |
| **nvim-tree**       | File explorer (opens automatically on startup)        |
| **nvim-treesitter** | Syntax highlighting and indentation                   |
| **conform.nvim**    | Format on save (eslint_d/eslint for JS/TS)            |
| **nvim-lint**       | Linting on save and insert leave (eslint_d for JS/TS) |
| **emmet-vim**       | Emmet expansion in HTML/CSS/JSX (`<Tab>,`)            |

## Key Settings

- **Leader key**: `<Space>`
- **Tabs**: 2 spaces, auto/smart indent
- **Clipboard**: uses system clipboard
- **Search**: case-insensitive unless uppercase is used

## Keybindings

| Key        | Action                    |
| ---------- | ------------------------- |
| `<Space>f` | Format current buffer     |
| `<Tab>,`   | Expand Emmet abbreviation |

## Prerequisites

- [Neovim](https://neovim.io/) >= 0.9
- A [Nerd Font](https://www.nerdfonts.com/) (for file icons in nvim-tree)
- `eslint_d` or `eslint` on your PATH (for JS/TS formatting and linting)

## tmux session switcher

`tmux/tmux.conf` plus `tmux/session-switcher.sh` — an fzf-popup session
switcher bound to `prefix + s`, with a vim-style `/` search, per-session status
emojis, a live pane preview, and drag-free reordering.

### Setup

```sh
mkdir -p ~/.config/tmux
cp tmux/tmux.conf tmux/session-switcher.sh ~/.config/tmux/
chmod +x ~/.config/tmux/session-switcher.sh
tmux source-file ~/.config/tmux/tmux.conf   # or restart tmux
```

### Prerequisites

| Tool               | Why                                       | Notes                                                                                                                                                                  |
| ------------------ | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **fzf ≥ 0.73**     | the `prefix + s` popup and its `/` search | the search mode uses `enable-search`/`change-header`/`rebind`/`backward-eof`/`$FZF_INPUT_STATE`; older fzf errors out. `brew install fzf`.                             |
| **tmux ≥ 3.2**     | `display-popup` used by `bind s`          | `brew install tmux`.                                                                                                                                                   |
| **TPM** (optional) | `tmux-resurrect` + `tmux-continuum`       | `git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm`, then `prefix + I`. Without it the switcher still works; only session save/restore is lost. |

### Keys (inside the `prefix + s` popup)

| Key                         | Action                                                   |
| --------------------------- | -------------------------------------------------------- |
| digits                      | jump to that row                                         |
| `j` / `k`                   | move cursor                                              |
| `C-j` / `C-k`               | reorder the session up / down                            |
| `p` / `a` / `e` / `r` / `d` | set PR / active / experimental / review / clear status   |
| `Tab`                       | cycle the previewed pane                                 |
| `/`                         | vim-style search: type to filter; empty ⌫ or `Esc` exits |
| `↵`                         | switch to the session                                    |

## zsh

`.zshrc` is the shared shell config. **Secrets and work-specific settings are
not in it** — they live in `~/.zshrc.local` (per-machine, never committed),
which `.zshrc` sources at the end.

### Setup

```sh
ln -sf "$PWD/.zshrc" ~/.zshrc   # from the repo root (or `cp` if the repo lives elsewhere)
```

Then create `~/.zshrc.local` with this machine's secrets / work bits, e.g.:

```sh
export GITHUB_PAT_TOKEN="…"
AWS_PROFILE=…
alias dev='…'
```

## Ghostty

`ghostty/config.ghostty` — terminal config (opacity, blur, working-directory
inheritance, URL linking). On macOS, Ghostty loads it from the app-support
directory:

```sh
ln -sf "$PWD/ghostty/config.ghostty" \
  ~/Library/"Application Support"/com.mitchellh.ghostty/config.ghostty
```
