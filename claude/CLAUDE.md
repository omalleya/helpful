# Global Claude Code Instructions

## Implementations
- Prefer the smallest change that solves the request
- Prefer self-documenting code over comments
- Identify and follow existing patterns before introducing new ones
- Before finishing, inspect the diff for unrelated edits and explain any remaining uncertainty

## Skill authoring

- When creating or updating a Claude Code / agent skill that is generic and
  reusable — not tied to an employer's proprietary code, i.e. safe to be public
  and useful across my personal machines — author it in the `helpful` repo at
  `~/.helpful/skills/<name>/`, then run
  `~/.helpful/scripts/install-skills.sh` to symlink it into
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
  `~/.helpful/scripts/install-dotfiles.sh` (run once per new
  machine; edits to already-linked files take effect immediately). Symlinked:
  `~/.claude/CLAUDE.md`, `~/.claude/hooks/notify-desktop.sh`,
  `~/.codex/AGENTS.md`, `~/.codex/hooks.json`.
- `~/.claude/settings.json` and `~/.codex/config.toml` are NOT symlinked — they
  hold work-specific and machine state and are rewritten by the apps (atomic
  writes break symlinks). `helpful/claude/settings.json` is a portable template
  (hooks + personal settings) to merge by hand; keep secrets and work-specific
  entries only in the live local files.
- Same public-safe bar as skills: no secrets, no work/employer references.
- `~/.helpful` is a symlink to wherever this repo is actually cloned (created by
  `install-dotfiles.sh`/`install-skills.sh`), so hardcoded paths in hooks work
  no matter where the repo lives on a given machine.

## Banned Vocabulary

Never use trendy internet slang, dramatic metaphors, or tech-bro idioms. Strictly forbid words or phrases like: footgun, smoking gun, seams, gates, belt-and-suspenders or tap into.
Be as concise as possible while still getting the most important information across.
