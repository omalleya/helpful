---
name: create-ws
description: Create a git worktree for a branch and open a tmux session with a shell pane and Claude + Codex panes. Works in whatever repo you're in (or one you name). Use when the user says "create-ws", "/create-ws branch", "spin up a worktree", "new worktree + tmux for a branch", or wants an isolated workspace to start work in.
---

# create-ws

Spin up an isolated workspace for a branch: a git worktree under
`<repo>/.worktrees/<slug>` plus a detached tmux session — left pane is a
shell, the right pane is split with **Claude on top and Codex on bottom**.

Repo-agnostic: it operates on the git repo you're currently in unless you
name another with `--repo`. Nothing is hardcoded to a particular project.

## The work happens in the new pane — never in the invoking session

create-ws exists to run work in an **isolated agent**: the Claude pane of the
new tmux session, inside the new worktree. The session that _invokes_
create-ws must **never perform the requested work itself** — no edits, no
builds, no research, not even "just the quick part." Its whole job is to
(1) create the workspace and (2) route the task into the new pane. When the
invocation carries a task, **initialize that task in the new pane** (`--prompt`,
plus a self-contained brief in the worktree when you hold context a cold pane
would lack — see step 3). Leave the pane idle only for a bare "make me a
workspace" with no task attached.

Argument: `$ARGUMENTS` — a **branch name** _or_ a short **task description**,
optionally followed by an action keyword (`ship-ticket` or `ship-notion`) that
boots the Claude pane straight into that skill. Shapes to support:

- `/create-ws aidan/proj-1234-widget` — make the ws; Claude pane sits **idle**.
- `/create-ws add a retry to the webhook sync` — derive a branch from the
  description, make the ws, and **boot the Claude pane on that task** (via
  `--prompt`; seed a brief first if it needs more than a one-liner). The
  invoking session never implements it.
- `/create-ws aidan/proj-1234-widget ship-ticket` — make the ws and **immediately
  run `/ship-ticket`** in the Claude pane (implement to a draft PR).
- `/create-ws aidan/proj-1234-widget ship-notion` — make the ws and **immediately
  run `/ship-notion`** in the Claude pane (research + publish a plan to Notion,
  no code).

## Steps

1. **Parse `$ARGUMENTS`.** If empty, ask what to create; do not guess.
   - **Action keyword.** If the text ends with `ship-ticket` or `ship-notion`
     (with or without the leading `/`), that's a directive to auto-run that
     skill — strip it off and remember which one for step 3. Any other trailing
     word is just part of the branch/description.
   - **Branch vs. description.** From the remaining text:
     - Contains a `/`, or is a single token with no spaces → treat it as the
       **branch name**, verbatim.
     - Free text (multiple words / a sentence) → derive a branch
       `aidan/<slug>`, where `<slug>` is a few kebab-case words that say what
       the task accomplishes (include any issue key if the text names a ticket
       — it stays in the branch but is dropped from the worktree/session name).

2. **Resolve the target repo.** Default is the current repo. If the user named
   a different repo in their message, pass it with `--repo <path>`.

3. **Decide the Claude-pane prompt.**
   - **`ship-ticket` directive present** → pass
     `--prompt "/ship-ticket [ISSUE-1234] --here"`. Include the ticket if the
     branch encodes one (`aidan/proj-1234-…` → `PROJ-1234`); otherwise just
     `/ship-ticket --here` and it resolves the ticket from the branch. `--here`
     keeps it in this worktree (never nests a ws inside a ws).
   - **`ship-notion` directive present** → same as above but with
     `--prompt "/ship-notion [ISSUE-1234] --here"` — research the ticket and
     publish an implementation plan to a private Notion page (no code, no PR).
   - **No directive, but a task description was given** → the invocation
     carries work, so initialize it in the new pane. Pass
     `--prompt "<the task>"`; when you already hold context the cold pane would
     lack (a diagnosis, a plan, findings from this conversation), first write a
     self-contained brief into the worktree (`PLAN.md`/`TASK.md`, or use
     `--brief`) and `--prompt` the pane to read it and begin. **Never implement
     the task in the invoking session.**
   - **No directive and only a bare branch name** → omit `--prompt`; the pane
     stays idle for the user to drive. There is nothing to run.

4. **Run the bundled script** — it does everything (slug, worktree, env,
   tmux) deterministically:

   ```bash
   bash "<skill base dir>/create-ws.sh" [--repo <path>] [--setup <cmd>] \
     [--prompt "<cmd>"] <branch>
   ```

   (`<skill base dir>` is the directory this SKILL.md lives in.)

   Flags (all optional, may precede the branch):
   - `--repo <path>` — repo to create the worktree in (default: current repo).
   - `--setup <cmd>` — command to run in the shell pane after creation, in the
     new worktree (e.g. `--setup "pnpm install"`). Runs asynchronously so the
     session is usable immediately.
   - `--prompt <cmd>` — boot the Claude pane running this command (step 3).
     Omit it for an idle pane. Prefer this over the legacy positional
     `initial-prompt` since it doesn't force you to also pass a base-ref.
   - `--plan` — boot the Claude pane read-only in plan mode
     (`claude --permission-mode plan`), for a "think first, don't touch"
     session. Usually paired with `--brief`.
   - `--brief <file>` — seed `<file>` into the worktree as `.handoff.md`,
     git-ignored locally (per-worktree `info/exclude`, not the tracked
     `.gitignore`). With `--plan` and no explicit `--prompt`, the Claude pane
     boots reading `.handoff.md` and producing a plan without making changes —
     a "think first, don't touch" launch that seeds Claude with a brief.

   Positionals after the flags: `<branch>` and, rarely, an explicit
   `[base-ref]` start point for a _new_ branch. Omit the base-ref to default to
   the repo's own default branch (`origin/HEAD`, falling back to `origin/main`
   then `origin/master`); it's ignored when the branch already exists.

   The script:
   - derives a worktree slug from the branch — drops any `owner/` prefix and
     any leading/trailing issue key, lowercases, keeps `[a-z0-9-]`, collapses
     hyphens, and trims to ~32 chars on a hyphen boundary. The slug names the
     **task**, not the ticket (e.g. `aidan/PROJ-24909-ob-pricing` →
     `ob-pricing`). A branch that is _only_ an issue key keeps it, since
     there's nothing else to name it by;
   - fetches `origin` and creates the worktree at `<repo>/.worktrees/<slug>`,
     reusing the branch if it already exists or creating it off the base ref
     otherwise;
   - auto-discovers and copies untracked local `.env*` files from the repo
     into the worktree, preserving their relative paths (pruning
     `node_modules`/`.git`/`.worktrees`, skipping committed templates like
     `.env.example`);
   - opens a detached tmux session named `<slug>`: pane 0 = shell,
     top-right = `claude` (seeded with the initial prompt if one was passed),
     bottom-right = `codex` — all cwd'd into the worktree;
   - runs the `--setup` command in the shell pane if one was given;
   - fails fast (no clobber) if the worktree path or tmux session already
     exists.

5. **Relay the result** the script prints — repo, worktree path, branch,
   session name, and the `tmux attach -t <slug>` command. Don't auto-attach
   (the session is intentionally detached so it works from inside another tmux
   session).

6. **Move the ticket to In Progress (only if one is identifiable).** If the
   branch or description encodes an issue key (`aidan/proj-1234-…` → `PROJ-1234`,
   or a key named in the description) **and** the session was created, transition
   that Linear issue to its team's _started_ workflow state. Fetch the issue for
   its team and current state; if it isn't already in a started/completed state,
   set it to the team's started-type status (e.g. "In Progress") via the Linear
   tools (`get_issue` → `list_issue_statuses` for its team → `save_issue`). Skip
   silently when no key is present or it doesn't resolve to a real issue, and
   never fail the command on a Linear error — just report it.

## Notes

- **Keep windows sized to the attached terminal.** The launcher sets
  `window-size latest` and installs a window-local `after-resize-window` hook
  that restores it after an explicit resize. `resize-window -x/-y` silently
  switches tmux to manual sizing, which leaves dotted unused space when the
  user attaches from a larger terminal. Inspect panes with
  `tmux capture-pane -p -J -t <pane>` without resizing the window for readability.
  Before handing off, verify `tmux show-options -wv -t <pane> window-size`
  returns `latest`; restore it with `tmux set-option -w -t <pane> window-size latest`
  if needed.
- Without `--prompt`, this only creates the workspace and ready agent REPLs —
  it starts no task; use that for a bare branch with no work attached. With
  `--prompt` (e.g. the `ship-ticket` flow) the Claude pane boots straight into
  that work. To start any _other_ task, pass it via `--prompt`, or — when you
  hold context the fresh pane would lack — write a self-contained brief into
  the worktree (`PLAN.md`/`TASK.md`) and `--prompt` the pane to read it and
  begin. Either way the work runs in the new pane, **never** in the session
  that invoked create-ws.
- A fresh worktree may need dependencies installed before builds/tests pass —
  use `--setup "pnpm install"` (or the repo's equivalent) to kick that off.
- Some projects need an extra per-worktree setup command to run multiple app
  instances side-by-side. Pass that through `--setup` when needed; it is not
  required to create the workspace or edit code.
