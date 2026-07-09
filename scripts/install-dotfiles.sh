#!/usr/bin/env bash
# Symlink portable Claude/Codex global config from this repo into place, so the
# repo is the single source of truth and edits here take effect immediately.
# Run once per new machine; re-run after adding a new linked file.
#
# Only non-secret, non-work-specific, rarely-app-rewritten files live here.
# NOT symlinked: ~/.claude/settings.json and ~/.codex/config.toml — they carry
# work-specific and machine state and are rewritten by the apps (atomic writes
# would break a symlink). claude/settings.json here is a portable template to
# merge by hand.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Stable path so hardcoded hook commands (e.g. tmux/set-agent-state.sh) work
# regardless of where this repo is actually cloned on a given machine.
ln -sfn "$ROOT" "$HOME/.helpful"

link() {
  local src="$ROOT/$1" dest="$2"
  if [ ! -e "$src" ]; then
    echo "skip (missing in repo): $1" >&2
    return
  fi
  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  echo "linked: $dest -> $src"
}

link claude/CLAUDE.md               "$HOME/.claude/CLAUDE.md"
link claude/hooks/notify-desktop.sh "$HOME/.claude/hooks/notify-desktop.sh"
link codex/AGENTS.md                "$HOME/.codex/AGENTS.md"
link codex/hooks.json               "$HOME/.codex/hooks.json"

echo
echo "note: ~/.claude/settings.json is not symlinked — merge claude/settings.json by hand."
echo "      Codex re-verifies hooks.json on next launch (expect a one-time trust prompt)."
