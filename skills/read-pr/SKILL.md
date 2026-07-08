---
name: read-pr
description: Review a large PR fast — spin off agents to map the changed code paths and read the linked ticket when available, run grumpy-review (or a normal review if unavailable), then report the changes vs. the ticket, list Critical/Warning/Nit findings with files, and rank the files worth reviewing manually. Use when the user says "read pr", "/read-pr <url|number>", "review this PR for me", or wants help getting through thousands of lines of diff.
---

# read-pr

Make a huge PR reviewable by a human in minutes. The deliverable is a **report
in chat** — do **not** edit code, do **not** post comments to the PR, and do
**not** push anything. Investigate and report only.

The argument `$ARGUMENTS` can be a PR URL, a PR number, or empty (review the
current branch against `origin/master`).

## Operating principles

- **Delegate the reading, keep the conclusions.** The whole point is that the
  user should not have to read thousands of lines. Push the heavy file-reading
  into subagents; bring back only structured findings.
- **Evidence over recall.** Every claim in the final report cites `file:line`
  that was actually read this run. Label anything inferred as inference. "I
  don't know, here's how to find out" is a valid finding.
- **Be honest about blast radius and gaps.** A clean-looking diff that touches a
  trigger surface (hooks, events, jobs, cascades) is more dangerous than a noisy
  one that doesn't.

## Step 1 — Resolve the PR and get the *canonical* diff

Identify the PR and pull its metadata + the real changed-file set.

```bash
gh pr view $ARGUMENTS --json title,author,state,body,baseRefName,headRefName,additions,deletions,changedFiles,url
gh pr diff $ARGUMENTS --name-only
```

**Gotcha — do not trust `git diff master...HEAD`.** Local `master` is often
stale, which inflates the diff to thousands of unrelated files. Use the PR's own
file list (`gh pr diff --name-only`) or, if a `grumpy-review` skill exists in
this repo, its diff script which computes against `origin/master`:

```bash
# if present in the repo:
bash .claude/skills/grumpy-review/scripts/pr-diff.sh $ARGUMENTS
```

Optionally check out the branch (`gh pr checkout $ARGUMENTS`) so subagents can
read full files for context — but only if the working tree is clean.

## Step 2 — Find the linked ticket

Extract the ticket id from the PR title or body (look for an issue tracker URL
or an issue-key token such as `PROJ-23285`). Fetch it so the review can judge
the diff *against the requirement*, not in a vacuum:

- Prefer the available issue tracker tool with the id.
- If no ticket id is present, say so in the report and review against the PR
  description's stated intent instead. Do not fabricate a ticket.

## Step 3 — Spin off agents to understand the change (parallel)

Launch subagents **in one message** so they run concurrently. Tailor the count
to the diff size — one understanding agent for a small PR, several partitioned
by subsystem for a large one. Use `Explore` or `general-purpose` agents.

For each understanding agent, instruct it to:

1. Read the heavily-changed files **in full** (not just the diff hunks) for the
   slice of the codebase it owns.
2. Trace the **data/control flow end to end** for the key code paths — where a
   value originates, what triggers a side effect, where it lands. Follow it into
   unchanged files when needed (callers, resolvers, stores, sandbox, queues).
3. Return a structured brief: what each file does, the new code paths, any
   server-side **trigger/cascade surface** touched (data-access hooks, queues,
   events, cascade rules, workflows, jobs, search indexers) and its blast
   radius, and anything that looks off — with `file:line` citations.
4. Explicitly hunt for and report, for its slice: **missing tests** (which new
   path/branch/error path has no coverage and the scenario it would catch),
   **missing instrumentation** (silent-failure paths with no log/breadcrumb/
   analytics), **missing edge cases** (null/empty/boundary/ordering/concurrency/
   flag-off inputs the code doesn't handle), **missing component examples** for
   new/changed frontend components, and **duplicate code** (logic that
   duplicates something already in the codebase — name the existing thing).

Give each agent the ticket summary so it can note where the code diverges from
the requirement.

## Step 4 — Run the review

Invoke the **`grumpy-review`** skill via the Skill tool, passing the same PR
argument. If `grumpy-review` is **not** in the available-skills list, fall back
to any available review skill (`code-review`, `pr-review`, `review`); if none
exist, perform the review inline against this rubric:

- **Bugs & logic:** null/undefined access, off-by-one, races (esp. ordering of
  async writes vs. consumers), boolean logic, swallowed errors.
- **Security:** authz checks, injection, secrets, PII leaving the system, agent-
  or user-controlled input driving side effects (navigation, writes, uploads).
- **Performance:** N+1s, unbounded refetches, missing batching, missing
  indexes/pagination.
- **Trigger & cascade surface:** any hook/event/job/cascade/workflow change that
  could fan out over **existing** production data — flag as Critical unless
  obviously a no-op, and demand a backfill/gating story.
- **Type safety:** `any`, unsafe `as` casts, narrowing gaps.
- **Missing tests:** every *new* code path, branch, and error path. Go deeper
  than "is it covered" — name the specific scenario that's untested and what it
  would catch ("what happens if X returns null here? no test for it"). Demand
  both happy-path and failure-mode coverage, and integration tests where unit
  tests alone can't prove the path works.
- **Missing instrumentation:** silent-failure paths with no breadcrumb — bare
  `throw new Error("failed")` with no context, catch blocks that swallow,
  async/external calls with no logging on failure, agent/user-driven side
  effects (navigation, writes, uploads) with no analytics event to confirm they
  fired or were dropped. When it breaks in prod, can someone tell what happened
  from logs + Sentry alone?
- **Missing edge cases:** the inputs the happy path forgot — null/empty/missing
  values, zero/negative/boundary numbers, ordering races between async writes
  and their consumers, concurrent/duplicate submits, stale references after
  navigation/refetch, flag-on vs. flag-off behavior, and "all/every/any" paths
  that silently only handle the first page.
- **Missing component examples:** new or materially-changed frontend components
  should ship Storybook stories, examples, previews, or the repo's equivalent.
  Flag components added without the expected coverage for that codebase.
- **Duplicate code:** logic copy-pasted instead of shared, a second
  implementation of something that already exists in the codebase, parallel
  branches that should be one helper, or a hardcoded value/path repeated on both
  sides of a boundary instead of a shared constant. Point at the existing thing
  that should have been reused.
- **Rollout & observability:** feature-flag gating, kill-switch, and whether a
  prod failure would be diagnosable from logs/Sentry alone (breadcrumbs on the
  silent-failure paths).
- **Dead code, naming, consistency, stale docs/skills/diagrams.**

## Step 5 — Synthesize the report

Reconcile the subagents' briefs with the review output, de-duplicate, and
**verify any finding you're unsure of yourself** before including it (read the
cited lines). Then respond in chat in this exact shape:

```
## 📋 What this PR does (vs. <ticket id or "PR intent">)
<3–8 bullets: the change in plain language, mapped to what the ticket asked for.
Call out anything the ticket asked for that the PR does NOT do, and anything the
PR does that the ticket did not ask for.>

## 🚨 Critical (launch-blocking)
1. [file:line] What's wrong, why it blocks launch, and the fix direction.
(If none: say so plainly — don't invent.)

## ⚠️ Warnings (should fix)
1. [file:line] Issue + why it matters + fix hint.

## 🔧 Nits (consider)
1. [file:line] Minor issue.

## 🔍 Files worth reviewing manually (ranked)
A short table or list, highest-value first. For each: the path and the
*specific thing to check there* — not "read this file" but "confirm the
extraction is semantically identical to the old X" / "this is the only gate on
agent-driven navigation". End with a one-line "if you only have time for two,
read these and why."

## ✅ What's good
<Brief credit where due — patterns done well, careful touches.>
```

## Guardrails

- Read-only. No code edits, no PR comments, no pushes, no CI triggers.
- Severity discipline: **Critical = data loss, security/authz breach, or a
  fan-out over existing data with no backfill plan.** Everything else is Warning
  or Nit. Don't inflate.
- Prefer fewer, verified findings over a long list of speculation. If a finding
  rests on an assumption you couldn't confirm, label it as such and say how to
  confirm it.
- Keep the report skimmable — the user is using this *instead of* reading the
  diff, so every line should earn its place.
