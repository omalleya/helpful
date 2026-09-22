---
name: spec-review
description: Review a branch's diff against its ticket — does it implement the acceptance criteria, and where does it fall down on correctness, unnecessary complexity, inefficient queries, or reuse (DRY)? Handles branches stacked on other branches, not just master. The deliverable is a chat report; it does not edit code, comment, or push. Use when the user says "spec-review", "/spec-review <TICKET>", "review this branch against the ticket", "does this branch meet the acceptance criteria", "one agent built this, review it against <TICKET>", or hands over a branch to check against its spec.
---

# spec-review

One agent implemented a ticket; you are the second agent reviewing that work
**against the ticket's spec**. The deliverable is a **report in chat** — do
**not** edit code, do **not** comment on the PR, do **not** push. Investigate
and report only.

The whole point is one question first — *does this branch actually implement
what the ticket asked for?* — followed by four quality lenses the user cares
about: correctness, unnecessary complexity, inefficient queries, and reuse
(DRY). Everything else is secondary.

`$ARGUMENTS` may contain a ticket id (e.g. `PROJ-1234`) and/or a base ref. Both
are optional — resolve them from context (below) when absent.

## Operating principles

- **Spec compliance is the headline.** A branch that is clean, fast, and elegant
  but doesn't do what the ticket asked is a failing review. Lead with the
  acceptance-criteria verdict; the quality lenses come after.
- **Delegate the reading, keep the conclusions.** Push heavy file-reading into
  subagents so the main context stays clean for judgment.
- **Evidence over recall.** Every claim cites `file:line` you actually read this
  run. Label inference as inference. "I couldn't verify X, here's how" is a
  valid finding — don't paper over it with confident prose.
- **Get the base right or the whole review is wrong.** The diff is only
  meaningful against the correct base (see Step 2). A branch stacked on another
  feature branch reviewed against `master` shows the parent's changes too — you
  will review code that isn't this ticket's.

## Step 1 — Resolve the ticket and its owning project

Resolve the ticket id in this priority order:

1. **Explicit argument** — an id (`PROJ-1234`) or issue URL in `$ARGUMENTS`.
2. **Current branch** — `git branch --show-current`, extract the first
   issue-key match (e.g. `aidan/proj-22865-agent-wiring` → `PROJ-22865`).
3. **Ask the user** — if neither yields an id, stop and ask which ticket.

Then fetch, using the available issue tracker tool (e.g. Linear's `get_issue`):

- The **issue** body **and its comments** — comments routinely hold the real
  acceptance criteria, edge cases, and "actually let's not do X" decisions that
  the description doesn't.
- The **owning project** (`get_project`) when the issue belongs to one. Projects
  carry cross-cutting requirements the individual ticket assumes. **Caveat:**
  some projects are catch-alls with no real spec — if the project adds nothing
  to the acceptance bar, note that and move on; don't invent requirements from a
  bucket project.
- Any **attachment or linked issue** that looks load-bearing for the spec. Stop
  once you have enough to judge "done" — don't drown in adjacent tickets.

If there is genuinely no ticket (or `$ARGUMENTS` points at a PR with only a
description), review against the stated intent and **say so** — don't fabricate
acceptance criteria.

## Step 2 — Resolve the base and get the diff

The base is `master` **or** the branch this one was forked off / stacked on. Use
the helper — it fetches, auto-detects the base (explicit arg → the PR's base
branch → default trunk), prints the merge-base SHA and the changed-file set, and
warns when the file count suggests a wrong base:

```bash
bash ~/.claude/skills/spec-review/scripts/resolve-base.sh [base-ref]
```

(The script lives next to this SKILL.md in `scripts/`; the path above is where
it's symlinked. Pass a `base-ref` only when you already know the parent branch.)

- **When the user named a base**, or said the branch is stacked on `X`, pass `X`
  as the arg.
- **When the file count looks too large** (the script warns above ~150), the
  branch is probably stacked and the base is wrong. Check for a parent branch
  (`gh pr view <branch> --json baseRefName`, or ask the user) and re-run with it.
- Pull hunks with the printed command: `git diff <merge-base> HEAD -- <path>`.
  Optionally `gh pr checkout <branch>` (only if the tree is clean) so subagents
  can read full files, not just hunks.

State the resolved base in the report so the user can sanity-check it.

## Step 3 — Turn the ticket into an acceptance checklist

Before reading code, extract from the issue + comments + project a concrete
checklist of what "done" requires — one line per requirement / acceptance
criterion, phrased so each is independently verifiable against the diff. Keep it
internal for now; it becomes the first section of the report. If the ticket's
criteria are vague, write the checklist as your best reading and flag the
ambiguity rather than guessing silently.

## Step 4 — Spin off agents to review against the checklist (parallel)

Launch subagents **in one message** so they run concurrently. Size to the diff —
one agent for a small branch, several partitioned by subsystem for a large one.
Use `Explore` or `general-purpose`. Give **every** agent the acceptance
checklist and the merge-base SHA, and have each return `file:line`-cited
findings for its slice under these five lenses:

1. **Acceptance criteria — met / missing / partial.** For each checklist item:
   is it implemented? Cite the code that satisfies it, or state precisely what's
   missing or only half-done. This is the primary output.
2. **Correctness.** Null/undefined access, off-by-one, boolean/condition
   mistakes, races (async write vs. its consumer), swallowed errors, wrong
   defaults, mishandled edge cases (empty/boundary/duplicate/flag-off), auth
   checks the ticket implies. Give a concrete failing scenario per finding.
3. **Unnecessary complexity.** Code more convoluted than the problem needs —
   an abstraction with one caller, a hand-rolled thing the language/stdlib/repo
   already gives you, needless indirection, dead branches, state that could be
   derived. Name the simpler form.
4. **Inefficient queries.** N+1s, queries inside loops, unbounded fetches with
   no pagination/limit, missing `where`/`select` narrowing, over-fetching then
   filtering in code, a missing index for a new filtered/sorted column, repeated
   identical queries that should be batched or cached.
5. **Reuse / DRY.** Functionality reimplemented that **already exists in the
   repo** — this needs an active search, not just reading the diff. Instruct the
   agent to grep for existing helpers/utilities/services matching the new code's
   purpose (by name, by signature, by the domain noun) and, when found, cite the
   existing thing at `file:line` that should have been reused. Also flag
   copy-paste within the diff and constants/paths duplicated across a boundary.

If a `grumpy-review` or `code-review` skill is available and the user wants a
second engine, you may invoke it via the Skill tool for an independent pass and
reconcile its findings — but this skill's own lenses above are the spine.

## Step 5 — Verify, then synthesize the report

Reconcile the subagents' briefs, de-duplicate, and **re-read the cited lines for
any finding you're not sure of** before including it. Drop anything you can't
stand behind. Then respond in chat in this exact shape:

```
## <TICKET> — <title>
`branch` vs `base` · <N> files

### ✅ Acceptance criteria
Verdict in one line: does this branch implement the ticket? What's missing?
Then the checklist:
- ✅ <criterion> — `file:line` (what satisfies it)
- ❌ <criterion> — not implemented / <what's missing>
- ⚠️ <criterion> — partial: <what's there vs. what's not> — `file:line`

### 🐛 Correctness
1. `file:line` — what's wrong + a concrete failing scenario + fix direction.
(If none: say so plainly. Don't invent.)

### 🧯 Unnecessary complexity
1. `file:line` — what's over-built + the simpler form.

### 🐌 Inefficient queries
1. `file:line` — the query problem + why it costs + the fix (batch, index, limit…).

### ♻️ Reuse / DRY
1. `file:line` (new code) duplicates `file:line` (existing) — reuse that instead.

### 🔍 Worth a manual look (ranked)
Highest-value first. For each: the path and the *specific thing to check* —
not "read this file" but "confirm the new tax calc matches the existing one in
billing.ts". End with "if you only have time for one, read X, because …".

### 👍 What's good
Brief credit — criteria cleanly met, careful edge-case handling, good reuse.
```

## Guardrails

- **Read-only.** No code edits, no PR comments, no pushes, no CI triggers.
- **Spec verdict is non-negotiable and honest.** If criteria are unmet, the
  headline says so, even when the code quality is high.
- **Don't inflate.** Prefer fewer verified findings over a long speculative
  list. A finding resting on an assumption you couldn't confirm is labeled as
  such, with how to confirm it.
- **Every path is one you resolved this run** via the correct base — a finding
  about code that belongs to the parent branch (wrong base) is worse than no
  finding. If unsure the base is right, say so.
- Keep the report skimmable — the user is reviewing *through* you. Every line
  earns its place.
