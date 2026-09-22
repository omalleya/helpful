---
name: address-comments
description: Act on the review comments you left on your own PR. For each of your unresolved threads it reads the referenced code and either replies (when it only needs clarification, or the concern doesn't hold) or designs a high-quality fix, implements it, verifies, and commits — then posts the reply and resolves the thread. Commits per comment, never pushes; ends with a report of what changed and why. The acting counterpart to comment-report. Use when the user says "address-comments", "/address-comments", "address my PR comments", "handle the comments I left", "go resolve my review comments", or hands over their self-reviewed PR to act on.
---

# address-comments

You reviewed your own PR and left comments — questions and change requests. This
skill works through **your unresolved review threads** and, for each one, either
**replies** (clarification, or you read the code and the concern doesn't hold) or
**implements a high-quality fix**, then **replies citing the fix and resolves the
thread**. It's the acting counterpart to `comment-report` (which only triages).

**Deliverable:** replies posted + threads resolved on the PR, code changes
**committed per comment but not pushed**, and a chat report of what changed and
why.

**Scope:** only unresolved threads **authored by you** (your self-review). It
skips resolved threads, teammates' threads, and bots — the helper enforces this.

## Step 1 — Fetch your unresolved threads

```bash
bash ~/.claude/skills/address-comments/scripts/list-my-threads.sh
```

(The script lives next to this SKILL.md in `scripts/`; the path above is the
symlink.) It prints a JSON array; each element has `threadId` (for resolving),
`firstCommentId` (for replying), `path`, `line`, `isOutdated`, and the thread's
`comments`. If it errors (no PR, `gh`/`jq` missing, not authenticated), stop and
say so — don't guess at the comments. Empty array → nothing to address; report
that and stop.

Capture the PR coordinates once for the reply/resolve calls below:

```bash
N=$(gh pr view --json number -q .number)
NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner)   # owner/name
```

## Step 2 — Triage all threads before changing code

For each thread, **read the referenced code this session** — open `path` around
`line` and enough surrounding context to understand what you were pointing at;
check callers/tests when the comment is about behavior. Cite `file:line` for
factual claims, label inference as inference, and follow the repo's evidence
rules if it has them (e.g. `.claude/rules/`). If `isOutdated` is true the line
may have moved — find the current location of the code the comment is about.

Read the repo's applicable guidance and check the working-tree state once; keep
unrelated local changes out of commits. Reuse overlapping reads across threads.
Keep a compact map of each thread, its classification, affected packages/tests,
and likely dependencies. Stay focused on the comments rather than starting a
new whole-PR review.

Then classify each thread as exactly one of:

- **Clarify-only** — a question you can answer, or a concern that doesn't hold
  once you read the code. No code change.
- **Valid change** — a request, or a question whose honest answer is "yes, that's
  a real problem." Needs a code change.
- **Needs your decision** — genuinely ambiguous, conflicts with an intentional
  design choice (e.g. a test asserts the current behavior), or is a large/risky
  change you shouldn't make unilaterally. Do **not** implement or resolve these.

## Step 3 — Act on the class

Group valid changes into small verification batches when they touch the same
packages and can remain separate, coherent commits. Design and implement those
fixes together, verify the batch once (Step 4), then commit and reply per comment.
For overlapping or dependent fixes, order the commits so each remains valid;
use a smaller batch if staging separate changes safely is difficult. Never let
one blocked thread prevent progress on independent, authorized fixes.

### Clarify-only → reply, then resolve
Draft a tight, direct answer (cite `file:line`). Post it and resolve:

```bash
gh api "repos/$NWO/pulls/$N/comments" -f body="<your answer>" -F in_reply_to=<firstCommentId>
gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -f id="<threadId>"
```

### Valid change → design, implement, verify, commit, then reply + resolve
1. **Design a high-quality solution first.** Fix the root cause, not the symptom.
   Reuse existing helpers/patterns rather than adding parallel implementations
   (search the repo before writing new code), keep the change minimal, and match
   surrounding style. If the fix needs a new code path, add a test for it.
2. **Implement** the change.
3. **Verify the completed batch** (Step 4) — required checks for affected packages.
4. **Commit** just this comment's change (Step 4). One commit per addressed
   comment so the reply can cite it; do not combine the batch into one commit.
5. **Reply citing the fix + commit, then resolve:**
   ```bash
   gh api "repos/$NWO/pulls/$N/comments" -f body="Done in <sha>: <what changed and why>." -F in_reply_to=<firstCommentId>
   gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -f id="<threadId>"
   ```

### Needs your decision → leave open, surface it
Do not edit, reply, or resolve. Collect it for the report with a recommendation
and the reason it's your call. Leaving a thread open is the correct outcome here.

> Don't blindly "fix" intentional code. Comments on your own recent work are
> often deliberate. When something looks like a design decision or needs a
> product call, treat it as **Needs your decision**, not a defect to edit away.

## Step 4 — Verify, then commit (never push)

Every committed fix must be covered by passing verification, and every commit
must remain buildable. Verification belongs at batch boundaries, not automatically
at every thread: do not repeat the same expensive checks for compatible fixes.
Follow the repo's required checks and scope them to the affected packages.

1. **Preflight before expensive checks.** Check changed imports/exports, actual
   caller/query shapes, generated-type prerequisites, and test-fixture contracts.
   Use the repo's cheap formatting or targeted lint commands in the correct
   package context. Build required dependencies once before targeted tests.
2. **Check service readiness before service-backed suites.** Confirm the test
   environment is isolated as the repo requires and its schema is current. If
   setup fails, fix that prerequisite before rerunning the suite. Do not bypass
   migration guards or modify unrelated development data to unblock tests.
3. **Verify the batch.** Run focused regression tests plus required scoped
   build/typecheck/lint checks. Combine compatible package filters where the
   runner supports it. Keep test file arguments out of dependency build tasks.
   Do not run concurrent build graphs that can delete or overwrite shared
   outputs; parallelize only independent checks with stable prerequisites.
4. **Repeat only what changed.** After a failure, rerun the failed check and
   checks affected by the fix. Preserve successful results for unchanged code;
   avoid another full round just to finish the workflow. If generation or commit
   hooks change behavior or types, rerun the relevant checks before replying.

Commit only the intended files or hunks for each comment. Keep dependent commits
in a valid order; never commit broken intermediate work. Do not claim an
intermediate commit was tested in isolation when only the completed batch was
verified. If a batch cannot be separated safely, shrink it and verify again.

While checks run, wait for output with bounded waits rather than repeatedly
polling processes or rereading unchanged files. Send a useful progress update
at least every 60 seconds, identifying the active check or blocker.

Commit with a message matching the branch's convention (check `git log`) —
lowercase, imperative, no conventional-commit prefix — and reference the comment
(short quote or `file:line`). Then capture the SHA (`git rev-parse --short HEAD`)
for the reply.

- **Never** `--no-verify` / `HUSKY=0`; let hooks run.
- **Never** amend or force-push; always new commits.
- **Never push.** Commits stay local; the user pushes.

## Step 5 — Report

Respond in chat:

```
## 💬 Addressed <k> of <n> comments on PR #<N>

### ✅ Replied (no change)
- `file:line` — <your comment, trimmed> → <one-line answer>. (resolved)

### 🔧 Changed
- `file:line` — <your comment, trimmed>
  Fix: <what changed and why>. Commit `<sha>`. (replied + resolved)

### 🕓 Left open — your call
- `file:line` — <your comment> → <why it's a decision + recommendation>

### Verification
- build/lint/test: <result, or skipped + why>
```

End with the **push prompt**: commits are local and **not pushed** — ask for the
go-ahead. The go-ahead authorizes only this batch.

## Guardrails

- **Only your unresolved threads.** Never touch resolved threads, teammates'
  threads, or bot comments (the helper filters to yours).
- **Post + resolve only what you fully addressed.** A thread you replied to with
  a real answer or a committed fix gets resolved; a "needs your decision" thread
  stays open.
- **Evidence before action.** Read the cited code and confirm the concern is real
  before changing anything; a wrong "fix" is worse than an open thread.
- **Reuse over reinvention.** Search for existing functionality before adding new
  code (DRY); keep changes minimal and in the repo's style.
- **Commit per comment, never push.** Verified commits, local only.
- **Stop cleanly** if `gh`/`jq` is missing, `gh` is unauthenticated, or there's
  no PR for the branch.
