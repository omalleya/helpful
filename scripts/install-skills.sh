#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$HOME/.claude/skills" "$HOME/.agents/skills"

for skill in "$ROOT"/skills/*; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  ln -sfn "$skill" "$HOME/.claude/skills/$name"
  ln -sfn "$skill" "$HOME/.agents/skills/$name"
done
