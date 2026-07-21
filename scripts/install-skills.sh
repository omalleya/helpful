#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Stable path so hardcoded hook commands work regardless of where this repo
# is actually cloned on a given machine.
ln -sfn "$ROOT" "$HOME/.helpful"

mkdir -p "$HOME/.claude/skills" "$HOME/.agents/skills"

link_skill() {
  local dest="$1" skill="$2" name="$3"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$dest.pre-symlink-backup"
    echo "backed up existing dir: $dest -> $dest.pre-symlink-backup"
  fi
  ln -sfn "$skill" "$dest"
}

for skill in "$ROOT"/skills/*; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  link_skill "$HOME/.claude/skills/$name" "$skill" "$name"
  link_skill "$HOME/.agents/skills/$name" "$skill" "$name"
done
