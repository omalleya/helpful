---
name: plan-ticket
description: Spin up an isolated worktree + tmux session for a ticket and boot Claude read-only in plan mode, seeded with a handoff brief, so it produces an implementation plan and waits for your go — the "think first, don't ship yet" counterpart to ship-ticket. Use when the user says "plan-ticket", "/plan-ticket <ISSUE-…>", "start a planning session for <ticket>", "spin up a ws and plan <ticket>", or wants a reviewed plan (not a PR) before committing to an approach.
---

# plan-ticket

Spin up a dedicated workspace for a ticket and leave Claude parked on a
**plan** — read-only, brief in hand, awaiting your go-ahead. It's `ship-ticket`
stopped at the planning gate: the same isolated worktree + tmux session, but
instead of running straight to a PR the Claude pane boots in plan mode
(`claude --permission-mode plan`) and produces an approach for you to review.

Argument: `$ARGUMENTS` — an issue id or issue URL (or empty to derive from the
current branch), plus an optional `--here` flag.

## Two modes

- **Dispatch (default).** From the main checkout with no `--here`: draft a
  brief, create the ws with Claude booted in plan mode reading it, move the
  ticket to In Progress, tell the user how to attach, then stop. The planning
  runs in the ws — that's what the user attaches to.
- **In-place (`--here`).** Plan in the current session: read the ticket, produce
  the plan, wait. **Recursion guard:** if the cwd is under `.worktrees/` (already
  inside a worktree), behave as `--here` even without the flag — never nest a ws
  inside a ws.

---

## Dispatch mode

1. **Resolve the ticket** — issue id / URL from `$ARGUMENTS`, else the current
   branch's issue key, else ask. Read the issue and its comments (the real spec
   and scope calls live there).
2. **Derive the branch** — `aidan/proj-1234-<short-slug>` (a few kebab-case words
   from the title).
3. **Draft the brief** — write a short brief to a temp file: the ticket id +
   title, the goal in a sentence or two, the key constraints / spec points from
   the issue and its comments, and any obvious starting files or open questions.
   Keep it tight — it's a launch brief, not the plan itself.
4. **Spin up the planning ws** — run the bundled `create-ws.sh` from the
   `create-ws` skill in plan mode, seeding the brief:

   ```bash
   bash ~/.claude/skills/create-ws/create-ws.sh \
     --plan --brief <tmp-brief.md> "aidan/proj-1234-<slug>"
   ```

   The script creates the worktree off the repo's default branch, opens the tmux
   session (shell + Claude/Codex panes), seeds the brief as `.handoff.md`
   (git-ignored), and boots the Claude pane as `claude --permission-mode plan`
   reading `.handoff.md` — so it plans without touching anything.

5. **Move the ticket to In Progress** — transition the resolved Linear issue to
   its team's _started_ workflow state, same as the `create-ws` skill's ticket
   step (dispatch calls `create-ws.sh` directly, so it doesn't inherit it). Skip
   if it's already started/completed; never fail the dispatch on a Linear error.
6. **Report and stop** — relay the worktree path, branch, session name, and
   `tmux attach -t <slug>`. Tell the user the planning session is up and Claude
   is parked on a plan awaiting review. Do **not** plan in this (main) session.

---

## In-place mode (`--here`)

Run in the current worktree — this is also what you do when already under
`.worktrees/`.

1. **Resolve the ticket** — as above; fetch the issue and its comments.
2. **Plan, don't build.** Investigate the code and produce a concrete
   implementation plan. Prefer `propose-changes` for the heavy lifting — it
   returns a high-confidence plan with the relevant files and code snippets.
3. **Present and wait.** Surface the plan and stop for the user's go-ahead. Make
   no code changes.

> plan-ticket ends at a reviewed approach. To take a ticket all the way to a
> draft PR autonomously, use `ship-ticket`; to just create a bare ws with no
> task, use `create-ws`.
