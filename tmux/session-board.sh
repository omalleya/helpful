#!/usr/bin/env bash
#
# Launcher for the kanban board view of tmux sessions, bound to `prefix + b`.
#
# The board itself is an Ink app (board/dist/session-board.mjs) that renders
# `session-switcher.sh --json`. This wrapper exists because the board owns the
# whole screen while it runs and so cannot prompt: it leaves any follow-up in an
# action file, which is carried out here once the board has exited and the tty is
# free again.
#
#   list            hand off to the `prefix + s` fzf list switcher
#   clean <name>    tear the session down via the switcher's confirmed cleanup
#
set -euo pipefail

# Resolve through symlinks: this script is installed as a link into
# ~/.config/tmux, and it needs the repo's own directory to find board/dist —
# unlike session-switcher.sh, which only ever needs to re-invoke itself. Plain
# `readlink` in a loop rather than `readlink -f`, which BSD only learned late.
SOURCE="$0"
while [ -L "$SOURCE" ]; do
  LINK_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in
    /*) ;;
    *) SOURCE="$LINK_DIR/$SOURCE" ;;
  esac
done
HERE="$(cd -P "$(dirname "$SOURCE")" && pwd)"

export SESSION_SWITCHER="$HERE/session-switcher.sh"
BOARD="$HERE/board/dist/session-board.mjs"

# A copied (rather than symlinked) install has no board/ beside it; ~/.helpful is
# the stable symlink both installers create, so fall back through it.
if [ ! -f "$BOARD" ] && [ -f "$HOME/.helpful/tmux/board/dist/session-board.mjs" ]; then
  BOARD="$HOME/.helpful/tmux/board/dist/session-board.mjs"
fi

if [ ! -f "$BOARD" ]; then
  printf 'session-board: %s is missing.\n\n' "$BOARD"
  printf 'Build it once from the repo:\n\n  cd %s/board && npm install && npm run build\n\n' "$HERE"
  read -rsn1 -p 'Press any key… ' </dev/tty || true
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  printf 'session-board: node is not on PATH.\n\n'
  printf 'tmux inherits PATH from the shell that started the server, so a node\n'
  printf 'installed since then needs `tmux kill-server` (or a fresh login) to be seen.\n\n'
  read -rsn1 -p 'Press any key… ' </dev/tty || true
  exit 1
fi

BOARD_ACTION_FILE="$(mktemp "${TMPDIR:-/tmp}/tmux-session-board.action.XXXXXX")"
export BOARD_ACTION_FILE
trap 'rm -f "$BOARD_ACTION_FILE"' EXIT

node "$BOARD"

action=""
target=""
IFS=$'\t' read -r action target < "$BOARD_ACTION_FILE" 2>/dev/null || true

case "$action" in
  list)
    exec "$SESSION_SWITCHER"
    ;;
  clean)
    [ -n "$target" ] || exit 0
    "$SESSION_SWITCHER" --clean "$target"
    ;;
esac
