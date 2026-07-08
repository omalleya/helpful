#!/usr/bin/env bash
# Reflect an agent's run state onto its tmux session as a user option that the
# session-switcher renders as a glyph after the session name. Called from the
# Claude / Codex lifecycle hooks, which inherit $TMUX_PANE from the pane the
# agent runs in, so the option lands on that pane's session. No-op outside tmux.
#
#   set-agent-state.sh <@key> <state>
#     <@key>   tmux user option to write, one per agent (e.g. @claude, @codex)
#     <state>  working | waiting | done | idle
#              working/waiting are rendered; done/idle/empty clear the option
#              (idle and finished show nothing, matching the manual @state axis)
set -euo pipefail

key="${1:?usage: set-agent-state.sh <@key> <state>}"
state="${2:-}"

[ -n "${TMUX_PANE:-}" ] || exit 0

case "$state" in
  working | waiting)
    tmux set-option -t "$TMUX_PANE" "$key" "$state" 2>/dev/null || true
    ;;
  *)
    tmux set-option -t "$TMUX_PANE" -u "$key" 2>/dev/null || true
    ;;
esac
