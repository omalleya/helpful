# Global Claude Code Instructions

- Prefer self-documenting code vs. verbose comments. Comments are often ignored and end up out-of-date quickly.

## Skill authoring

- When creating or updating a Claude Code / agent skill that is generic and
  reusable — not tied to an employer's proprietary code, i.e. safe to be public
  and useful across my personal machines — author it in the `helpful` repo at
  `~/Documents/dev/helpful/skills/<name>/`, then run
  `~/Documents/dev/helpful/scripts/install-skills.sh` to symlink it into
  `~/.claude/skills/` and `~/.agents/skills/`. Because skills are symlinked from
  that repo, edits to an already-linked skill take effect on this computer
  immediately; re-run the installer only when adding a brand-new skill. This
  keeps skills version-controlled and portable to my other computers.
- Work/employer-specific or proprietary skills do NOT belong in the public
  `helpful` repo — keep those in the relevant org/work skills location (e.g. an
  org skills marketplace repo).

## Dotfiles (Claude/Codex global config)

- Portable, non-secret global config lives in the `helpful` repo under `claude/`
  and `codex/`, symlinked into place by
  `~/Documents/dev/helpful/scripts/install-dotfiles.sh` (run once per new
  machine; edits to already-linked files take effect immediately). Symlinked:
  `~/.claude/CLAUDE.md`, `~/.claude/hooks/notify-desktop.sh`,
  `~/.codex/AGENTS.md`, `~/.codex/hooks.json`.
- `~/.claude/settings.json` and `~/.codex/config.toml` are NOT symlinked — they
  hold work-specific and machine state and are rewritten by the apps (atomic
  writes break symlinks). `helpful/claude/settings.json` is a portable template
  (hooks + personal settings) to merge by hand; keep secrets and work-specific
  entries only in the live local files.
- Same public-safe bar as skills: no secrets, no work/employer references.
