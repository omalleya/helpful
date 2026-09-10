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
It also (re)creates `~/.helpful`, a symlink to wherever this repo is actually
cloned — hardcoded paths inside hooks reference `~/.helpful/...` so they work
no matter where you keep the repo. `install-dotfiles.sh` creates the same
symlink, so running either installer is enough.

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

## tmux session switcher & board

Two views over the same sessions, both tmux popups:

- **`prefix + s`** — `tmux/session-switcher.sh`, an fzf list with a vim-style
  `/` search, a live pane preview, and drag-free reordering.
- **`prefix + b`** — `tmux/session-board.sh`, a kanban board: one card per
  session, in stage columns you move them between.

### Stages

Every session sits in one stage, shown as the list's emoji and the board's
column. It is **derived from the worktree's GitHub PR**, so the board mostly
keeps itself in order:

| Stage          |     | Derived when                   |
| -------------- | --- | ------------------------------ |
| `unclassified` | `·` | no branch, or the repo's trunk |
| `in-progress`  | ✏️  | a feature branch with no PR    |
| `self-review`  | 🔎  | a draft PR                     |
| `in-review`    | 👀  | an open, non-draft PR          |
| `merged`       | ✅  | a merged or closed PR          |
| `experimental` | 🧪  | never derived — set it by hand |

Moving a card (or pressing a stage key in the list) writes an override to the
session's `@state` option, which wins from then on; `d` clears it and hands the
session back to derivation. Two exceptions keep the two rules from fighting: a
**merged PR is terminal** and outranks a pipeline override, so a landed branch
can't sit in `in-review` on a stale keypress — and **`experimental` is exempt**
from that, since it parks a session outside the pipeline rather than placing it
inside one.

Stage logic lives only in `session-switcher.sh`, which the board reads via
`--json`; the board is a renderer, so the two views cannot disagree.

### Setup

```sh
mkdir -p ~/.config/tmux
ln -sfn "$PWD/tmux/tmux.conf"           ~/.config/tmux/tmux.conf
ln -sfn "$PWD/tmux/session-switcher.sh" ~/.config/tmux/session-switcher.sh
ln -sfn "$PWD/tmux/session-board.sh"    ~/.config/tmux/session-board.sh
tmux source-file ~/.config/tmux/tmux.conf   # or restart tmux
```

`scripts/install-dotfiles.sh` does exactly this, so on a new machine just run
that. Symlinks rather than copies: `session-board.sh` resolves its own path back
to this repo to find the board bundle (falling back to `~/.helpful`), and edits
here then take effect immediately.

The board ships as a committed, self-contained bundle
(`tmux/board/dist/session-board.mjs`), so a machine needs only `node` — no
install, no network. Rebuild it after editing `tmux/board/src`:

```sh
cd tmux/board && npm install && npm run build
```

For the `l` key, name your Linear workspace — the slug in your issue URLs,
`https://linear.app/<slug>/issue/…`. Like `~/.zshrc.local`, this file is
per-machine and never committed:

```sh
echo your-workspace-slug > ~/.config/tmux/linear-workspace
```

`$LINEAR_WORKSPACE` overrides it, but exporting it from `~/.zshrc.local` won't
reach the popup — `display-popup` runs a non-interactive shell that never sources
`.zshrc`, so use the file.

### Prerequisites

| Tool               | Why                                       | Notes                                                                                                                                                                  |
| ------------------ | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **fzf ≥ 0.73**     | the `prefix + s` popup and its `/` search | the search mode uses `enable-search`/`change-header`/`rebind`/`backward-eof`/`$FZF_INPUT_STATE`; older fzf errors out. `brew install fzf`.                             |
| **tmux ≥ 3.2**     | `display-popup` used by `bind s`          | `brew install tmux`.                                                                                                                                                   |
| **node ≥ 20**      | the `prefix + b` board                    | only to run the committed bundle. tmux inherits `PATH` from the shell that started the server, so a node installed since then needs `tmux kill-server` to be seen.     |
| **gh**             | PR chips, and every derived stage         | authenticated (`gh auth login`). Without it stages fall back to branch-only: `unclassified` or `in-progress`.                                                          |
| **TPM** (optional) | `tmux-resurrect` + `tmux-continuum`       | `git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm`, then `prefix + I`. Without it the switcher still works; only session save/restore is lost. |

### Keys — list (`prefix + s`)

| Key                               | Action                                                                                  |
| --------------------------------- | --------------------------------------------------------------------------------------- |
| digits                            | jump to that row                                                                        |
| `j` / `k`                         | move cursor                                                                             |
| `C-j` / `C-k`                     | reorder the session up / down                                                           |
| `u` / `a` / `s` / `r` / `m` / `e` | set stage: unclassified / in-progress / self-review / in-review / merged / experimental |
| `d`                               | clear the override — back to the PR-derived stage                                       |
| `b`                               | switch to the board view                                                                |
| `Tab`                             | cycle the previewed pane                                                                |
| `o`                               | open the session's GitHub PR — or its branch, if no PR                                  |
| `l`                               | open the session's Linear issue                                                         |
| `C-x`                             | clean the work session: worktree, branch, tmux session                                  |
| `/`                               | vim-style search: type to filter; empty ⌫ or `Esc` exits                                |
| `↵`                               | switch to the session                                                                   |

### Keys — board (`prefix + b`)

| Key                    | Action                                                 |
| ---------------------- | ------------------------------------------------------ |
| `h` / `l` or `←` / `→` | move between columns                                   |
| `j` / `k` or `↑` / `↓` | move between cards                                     |
| `H` / `L`              | **move the card** to the previous / next column        |
| `d`                    | clear the override — back to the PR-derived stage      |
| `p`                    | toggle a live preview strip of the selected session    |
| `o`                    | open the session's GitHub PR — or its branch, if no PR |
| `i`                    | open the session's Linear issue                        |
| `C-x` / `X`            | clean the work session: worktree, branch, tmux session |
| `/`                    | search: type to filter across all columns; `Esc` exits |
| `Tab`                  | switch to the list view                                |
| `↵`                    | switch to the session                                  |
| `q` / `Esc`            | close the board                                        |

The cursor is anchored to a session, not a slot: when a PR lands and its card
jumps columns under you, the cursor follows it.

### Stage keys outside the popups

`prefix + C-u` / `C-a` / `C-p` / `C-v` / `C-g` / `C-e` set the **attached**
session's stage (unclassified / in-progress / self-review / in-review / merged /
experimental) and `prefix + C-d` clears the override. Self-review is `C-p`
because `C-s` belongs to tmux-resurrect's save.

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
