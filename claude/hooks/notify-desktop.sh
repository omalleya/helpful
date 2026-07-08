#!/bin/sh
# Desktop notification that prefixes the tmux session name when Claude runs inside tmux.
# Usage: notify-desktop.sh <message> [sound]
message=$1
sound=${2:-Ping}

title="Claude Code"
if [ -n "$TMUX" ]; then
  session=$(tmux display-message -p '#S' 2>/dev/null)
  [ -n "$session" ] && title="Claude Code · $session"
fi

terminal-notifier -title "$title" -message "$message" -sound "$sound"
