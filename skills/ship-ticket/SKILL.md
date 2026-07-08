---
name: ship-ticket
description: Autonomously take a ticket to a review-ready draft PR, running in its own isolated worktree + tmux session so you can hop in if needed. Spins up the ws, then inside it plans, implements to completion, verifies (build + typecheck + tests + clean grumpy-review), pushes once, and opens a draft PR. Use when the user says "ship-ticket", "/ship-ticket <ISSUE-…>", "take this ticket to review", "implement and open a PR for <ticket>", or hands over a ticket to run end to end.
---

# ship-ticket

Take a single ticket from nothing to a review-ready draft PR **without
checking in along the way**, running the whole thing inside its own git
worktree + tmux session so the user can attach and intervene if something goes
sideways.

Argument: `$ARGUMENTS` — an issue id or issue URL (or empty to
derive from the current branch), plus an optional `--here` flag.

## Two modes

- **Dispatch (default).** Invoked from the main checkout with no `--here`:
  create the ws (worktree + tmux session with a shell pane and a Claude pane),
  launch the pipeline **inside that ws's Claude pane**, tell the user how to
  attach, then stop. The main session is just a launcher — the real work runs
  in the ws, which is exactly what the user attaches to if there are issues.
- **In-place (`--here`).** Run the actual pipeline in the current session, no
  ws. This is what the dispatched ws Claude runs. **Recursion guard:** if the
  current working directory is under `.worktrees/` (i.e. already inside a
  worktree), behave as `--here` even if the flag is absent — never create a ws
  inside a ws.

---

## Dispatch mode

1. **Resolve the ticket** — issue id / URL from `$ARGUMENTS`, else the current
   branch's issue key, else ask. Do a light issue tracker read to get the title
   for a branch slug.
2. **Derive the branch** — `aidan/proj-1234-<short-slug>` (a few kebab-case words
   from the title).
3. **Spin up the ws and launch the pipeline in it** — run the bundled
   `create-ws.sh` from the `create-ws` skill, passing the pipeline invocation
   as the initial prompt so the ws's Claude starts shipping immediately:

   ```bash
   bash ~/.claude/skills/create-ws/create-ws.sh \
     "aidan/proj-1234-<slug>" origin/master "/ship-ticket PROJ-1234 --here"
   ```

   The script creates the worktree off `origin/master`, opens the tmux session
   (shell pane + Claude/Codex panes), and the Claude pane boots straight into
   `/ship-ticket PROJ-1234 --here`.
4. **Report and stop** — relay what the script printed: worktree path, branch,
   session name, and `tmux attach -t <slug>`. Tell the user the pipeline is
   running in that session and they can attach anytime to watch or take over.
   Do **not** do the implementation work in this (main) session.

> Note: a fresh worktree may need `pnpm install` before builds/tests pass — the
> in-place run handles that in its verify step.

---

## In-place mode (`--here`) — the pipeline

### Contract

- **Fully autonomous.** Do not stop to ask "want me to continue?" Run straight
  to the ready-for-review report. Legitimate stops only per _When to break
  autonomy_.
- **Definition of done (the gate).** Not done until all hold on a fresh pass:
  `build` passes (also type-checks), lint passes on changed files, the relevant
  tests pass, and a fresh `grumpy-review` reports **zero Critical and zero
  Warning**.
- **One push, at the very end.** Never push mid-work (a push costs a CI build).
  Commit batches locally; push once when the gate is green, then open the PR.
- **Commit standards.** Every commit compiles and passes tests. Never
  `--no-verify` / `HUSKY=0`. Never amend or force-push.
- **Follow the repo.** Honor `CLAUDE.md`, `.claude/rules/*`, existing patterns;
  write tests for new functionality.

> Optional hardening: the user can set `/goal implementation done; build +
> tests + lint pass; grumpy-review shows zero Critical/Warning` in the ws pane
> for a Stop-hook second net. The contract already enforces this.

### 1. Resolve the ticket

Issue id / URL from `$ARGUMENTS`, else the current branch, else ask. Fetch the
issue and its comments/discussion using the available issue tracker tools
(comments carry the real spec and scope calls).

### 2. Confirm the branch

In a dispatched ws you're already on `aidan/proj-1234-<slug>` — verify with
`git branch --show-current` and stay on it. If somehow on the default branch,
create the ticket branch off the default remote branch. Run the repo's dependency
install command if the worktree deps are missing.

### 3. Plan

Invoke `propose-changes` with the ticket id. Read its plan; **do not wait for
approval**. If it reports the ticket is genuinely ambiguous such that guessing
risks the wrong outcome, stop and surface that (see _When to break autonomy_).

### 4. Implement

Execute the plan in small, sequenceable steps, each leaving the repo compiling.
Add/update tests. Commit coherent batches. Match surrounding code.

### 5. Verify — the gate

Loop until green:

1. **Deterministic gates**, turbo-filtered for speed:
   - `npx turbo run build --filter=<changed pkgs>` (compiles + type-checks)
   - `npx turbo run lint --filter=<changed pkgs>`
   - the relevant tests (per-package task, or `pnpm test` if broad)
   Fix failures and re-run; follow the repo's "stuck after 3 attempts" rule.
2. **Clean review**: invoke `fix-loop` on the current branch — it drives
   `grumpy-review` to zero Critical/Warning, committing batches and stopping to
   ask on judgment calls / intentional code.
3. **Re-run the deterministic gates** after fix-loop's edits.

Met when a fresh pass of (1) and (2) is clean with no new edits.

### 6. Ship

1. Push once: `git push -u origin HEAD`.
2. Open a **draft** PR against `master` with a real, review-ready body (not the
   repo's placeholder template):
   ```bash
   gh pr create --draft --base master \
     --title "PROJ-1234 <concise title>" \
     --body "<Summary / Changes / Testing; Closes PROJ-1234>"
   ```
3. Do **not** watch CI (the endpoint is push + draft PR). Mention CI is running.

### 7. Report — "ready for review"

Post a chat summary in the ws pane: ticket + goal, what shipped, the gate
(build / lint / tests / grumpy-review all clean), the PR link, any judgment
calls or unfixed Nits, and an explicit **"Ready for review."**

### When to break autonomy

Stop and ask only for: an unresolvable ticket; a spec ambiguous enough that
guessing risks the wrong outcome; a judgment call fix-loop surfaces; or being
stuck after ~3 genuine attempts (document what failed, then ask). Otherwise
keep going.

---

## Running several tickets at once

Each dispatch already isolates one ticket in its own ws. To fan several out,
invoke dispatch once per ticket — each gets its own worktree, branch, and tmux
session running in parallel. To also run apps side-by-side across those
worktrees, run whatever per-worktree setup your repo needs. For heavier
orchestration (status tracking, cross-agent messaging, coordinated merges), use
the `coordinator` / `workmux` tooling instead.
