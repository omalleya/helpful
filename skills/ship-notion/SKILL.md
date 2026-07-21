---
name: ship-notion
description: Take a ticket, research the codebase, and produce a review-ready implementation plan as a private Notion page — the planning counterpart to ship-ticket, but the deliverable is a Notion doc you review and iterate on instead of a PR. Runs in its own isolated worktree + tmux session. Use when the user says "ship-notion", "/ship-notion <ISSUE-…>", "create-ws <branch> ship-notion", "plan <ticket> into a Notion page", "write up a plan in Notion for review", or hands over a ticket to be planned (not implemented). To revise an existing plan, pass its Notion page URL.
---

# ship-notion

Take a single ticket and turn it into a **review-ready implementation plan on a
private Notion page** — no code, no PR. It's `ship-ticket` stopped at the
planning gate, with the plan persisted somewhere you can read, comment on, and
iterate on instead of an ephemeral in-chat answer. Like `ship-ticket`, the whole
thing runs inside its own git worktree + tmux session so you can attach and
steer if the research goes sideways.

Argument: `$ARGUMENTS` — an issue id or issue URL (or empty to derive from the
current branch), plus an optional `--here` flag. To **revise** an existing plan
instead of creating a new one, include the plan's Notion page URL.

## Two modes

- **Dispatch (default).** Invoked from the main checkout with no `--here`:
  create the ws (worktree + tmux session with a shell pane and a Claude pane),
  launch the planning pipeline **inside that ws's Claude pane**, tell the user
  how to attach, then stop. The main session is just a launcher — the research
  runs in the ws, which is what the user attaches to.
- **In-place (`--here`).** Run the actual pipeline in the current session, no
  ws. This is what the dispatched ws Claude runs, and what
  `create-ws <branch> ship-notion` boots into. **Recursion guard:** if the
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
   as the initial prompt so the ws's Claude starts planning immediately:

   ```bash
   bash ~/.claude/skills/create-ws/create-ws.sh \
     "aidan/proj-1234-<slug>" origin/master "/ship-notion PROJ-1234 --here"
   ```

   The script creates the worktree off `origin/master`, opens the tmux session
   (shell pane + Claude/Codex panes), and the Claude pane boots straight into
   `/ship-notion PROJ-1234 --here`. (Equivalently, `create-ws <branch>
ship-notion` produces the same launch.)

4. **Move the ticket to In Progress.** Transition the resolved Linear issue to
   its team's _started_ workflow state ("In Progress") — same as the `create-ws`
   skill's ticket step (dispatch calls `create-ws.sh` directly, so it doesn't
   inherit that step). Skip if it's already started/completed; never fail the
   dispatch on a Linear error — just report it.
5. **Report and stop** — relay what the script printed: worktree path, branch,
   session name, and `tmux attach -t <slug>`. Tell the user the planning session
   is running in that session and they can attach anytime to watch or take over.
   Do **not** do the research in this (main) session.

> Note: planning is read-only, so a fresh worktree usually needs no
> `pnpm install` — but if the research wants to type-check a snippet, the
> in-place run installs deps on demand.

---

## In-place mode (`--here`) — the pipeline

### Contract

- **Fully autonomous.** Do not stop to ask "want me to keep going?" Run straight
  to the published-plan report. Legitimate stops only per _When to break
  autonomy_.
- **Plan, don't build.** The only side effect is the Notion page. Investigate
  read-only; make **no** code changes, no commits, no PR. If you need to
  compile-check an idea, do it in a scratch space and discard it.
- **Definition of done (the gate).** Not done until a private Notion page exists
  holding a concrete, review-ready implementation plan (the sections in step 4),
  and its URL has been reported.
- **Follow the repo.** Ground the plan in `CLAUDE.md`, `.claude/rules/*`, and the
  existing patterns you actually read — cite real files, not guesses.

### 1. Resolve the ticket

Issue id / URL from `$ARGUMENTS`, else the current branch, else ask. Fetch the
issue and its comments/discussion using the available issue tracker tools
(comments carry the real spec and scope calls). If `$ARGUMENTS` includes a
**Notion page URL**, this is a revision — see _Revise mode_ below.

### 2. Confirm the branch

In a dispatched ws you're already on `aidan/proj-1234-<slug>` — verify with
`git branch --show-current` and stay on it. If somehow on the default branch,
create the ticket branch off the default remote branch. No deps install is
needed just to plan.

### 3. Investigate and plan

Invoke `propose-changes` with the ticket id — it returns a high-confidence plan
with the relevant files and concrete code snippets. Read its output as the spine
of the plan; deepen anything thin (edge cases, migrations, tests, rollout).
**Do not wait for approval.** If the ticket is genuinely ambiguous such that
guessing risks the wrong outcome, stop and surface that (see _When to break
autonomy_).

### 4. Write the plan to a private Notion page

1. **Read the Notion Markdown spec first.** Before composing any page content,
   read the MCP resource `notion://docs/enhanced-markdown-spec` (via the
   Notion MCP's resource-reading interface). Don't guess Notion-flavored
   Markdown syntax.
2. **Compose the plan** as Notion-flavored Markdown. Aim for a doc a reviewer
   can act on and comment on inline:
   - **Goal** — the outcome in a sentence or two, plus a link to the ticket.
   - **Context & constraints** — the real spec/scope points from the issue and
     its comments; relevant repo conventions.
   - **Approach** — the chosen strategy and why, noting alternatives considered.
   - **Changes** — file-by-file, with concrete code snippets and the `file:line`
     anchors you actually read.
   - **Tests & verification** — what to add/run to prove it works.
   - **Risks & open questions** — anything you want the reviewer to weigh in on.
   - **Scope** — the branch and worktree this plan is scoped to.
     Don't put the title in the content; it goes in `properties.title`.
3. **Create the private page.** Call `notion-create-pages` with the **parent
   omitted** — omitting the parent creates a workspace-level _private_ page only
   you can see, which the reviewer organizes later. Title it
   `PROJ-1234 <ticket title> — Implementation Plan`; give it a fitting icon.
4. **Report the page URL** (see step 5). If you created the page earlier in this
   same session, prefer updating it over creating a duplicate.

### 5. Report — "ready for review"

Post a chat summary in the ws pane: ticket + goal, the shape of the plan (a few
bullets), any judgment calls or open questions you want weighed, the **Notion
page URL**, and an explicit **"Plan ready for review in Notion."** Then stop —
do not start implementing. (When you're ready to build it, hand the branch to
`ship-ticket`, or say "go" in this ws.)

### Revise mode (existing page)

When `$ARGUMENTS` includes a Notion page URL (or you're iterating on a page you
made earlier this session):

1. `notion-fetch` the page and its open comments/discussions
   (`include_discussions: true`, then read the comments) to see what the
   reviewer asked for.
2. Re-investigate as needed and revise the plan to address every comment.
3. **Update the same page in place** via `notion-update-page` — don't create a
   duplicate. Preserve the reviewer's structure and voice; weave changes in as a
   minimal diff rather than wholesale-replacing their doc.
4. Report what changed and re-link the page.

### When to break autonomy

Stop and ask only for: an unresolvable ticket; a spec ambiguous enough that
guessing the plan risks the wrong direction; or being stuck after ~3 genuine
attempts to understand the code (document what failed, then ask). A plan with
clearly-flagged open questions is still a valid deliverable — prefer publishing
it with the questions called out over stopping.

---

## Running several tickets at once

Each dispatch isolates one ticket in its own ws. To fan several out, invoke
dispatch once per ticket — each gets its own worktree, branch, tmux session, and
private Notion plan page. For heavier orchestration, use the `coordinator` /
`workmux` tooling.

> ship-notion ends at a published, reviewable plan. To take a ticket all the way
> to a draft PR autonomously, use `ship-ticket`; to just create a bare ws with
> no task, use `create-ws`.
