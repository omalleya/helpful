---
name: fix-loop
description: Run grumpy-review on a PR or the current branch, fix every Critical and Warning finding, verify, commit the batch, then re-review — looping until no Critical or Warning findings remain. Use when the user says "fix-loop", "/fix-loop <pr>", "review and fix until clean", "grumpy-review and fix the criticals", or wants an autonomous review→fix→re-review cycle.
---

# fix-loop

Drive a PR (or the current branch) to a clean grumpy-review by looping:
**review → fix Critical + Warning → verify → commit → re-review**, until a
review pass surfaces no Critical and no Warning findings.

The argument `$ARGUMENTS` is whatever `grumpy-review` accepts — a PR URL, a PR
number, a base branch, or empty (current branch vs `origin/master`). Pass it
straight through.

## Contract

- **Auto-fix tier: Critical + Warning.** The loop is not done until a fresh
  review pass reports zero Critical and zero Warning findings. Nits are
  reported, never auto-fixed.
- **Commit each batch, never push.** After each round of fixes is verified,
  commit it (following the repo's commit standards). **Do not push** — when
  the loop finishes, tell the user it's ready and ask before pushing. A push
  triggers CI and costs a build.
- **Fix defects, surface judgment calls.** Some findings on the user's own
  commits are intentional design choices, not bugs (see _Don't blindly
  "fix" intentional code_ below). Fix clear defects autonomously; for anything
  that looks like a deliberate decision or needs a product call, **stop and
  ask** rather than forcing an edit.
- **Evidence-based.** Re-read the actual files before fixing; verify the
  finding is real before acting on it. A grumpy-review finding is a strong
  lead, not gospel — if you read the code and the finding is wrong, say so and
  skip it (this counts as "addressed").

## Loop

### 1. Review

Invoke the `grumpy-review` skill with `$ARGUMENTS`. Let it produce the
Critical / Warning / Nit breakdown. Note the changed-file set (grumpy-review's
diff script computes against `origin/master`).

### 2. Triage the findings

For each **Critical** and **Warning** finding, before touching code:

- Re-read the cited `file:line` and enough surrounding context to confirm the
  finding is real and you understand the fix.
- Classify it:
  - **Clear defect** (missing dependency, type error, null deref, N+1, missing
    `onDelete: Cascade`, untested new code path, swallowed error, etc.) → fix
    it.
  - **Judgment call / intentional** (a design decision, a deliberate tradeoff,
    something that needs product/owner input) → don't edit; collect it to
    surface in chat.
  - **False positive** (you read it and the finding is wrong) → note why,
    skip.

### 3. Fix the batch

Apply fixes for the clear defects. Keep changes minimal and match surrounding
code style. Follow the project's code-style and engineering rules.

### 4. Verify before committing

Every commit must compile and pass tests (repo rule). Determine the affected
packages from the changed files and run the repo's normal build, lint, and test
commands. For a turbo monorepo, scope them to the changed packages:

```bash
npx turbo run build --filter=<pkg>
npx turbo run lint  --filter=<pkg>
# tests for the package (vitest/jest as the package uses)
```

If a fix added a new code path, add a test that covers it — an untested new
path is itself a Warning the loop should close.

If verification fails, fix forward within the same round; don't commit broken
work.

### 5. Commit the batch

Commit with a message matching the branch's convention. Check `git log` on the
branch and follow the surrounding style. One coherent commit per round is fine.

- **Never** `--no-verify` / `HUSKY=0`; let hooks run.
- **Never** amend or force-push; always new commits.
- **Do not push.**

### 6. Re-review (the loop)

Go back to step 1: run `grumpy-review` again on the same target. The fixes
change the diff, so this is a genuine fresh pass.

- If the new pass has **no Critical and no Warning** → the loop is done.
- Otherwise repeat with the new findings.

## Stop conditions

Stop the loop and report when **any** of these holds:

1. **Clean** — a review pass reports zero Critical and zero Warning. (Success.)
2. **No progress** — a round produces no new fixes (every remaining
   Critical/Warning is a judgment call or false positive), or the same finding
   survives a fix attempt twice. Don't spin; report what's left and why.
3. **Needs a decision** — a remaining finding requires the user's input
   (product call, ambiguous intent, risky change). Surface it and ask.
4. **Iteration guard** — you've run ~5 rounds. Stop, report state, and ask
   whether to continue. (Prevents runaway loops.)

## Don't blindly "fix" intentional code

Findings raised on the user's own recent commits are frequently deliberate.
Before editing, ask whether the "issue" might be the intended behavior. When in
doubt, surface it in chat as a question rather than silently rewriting the
user's decision. Forcing edits onto intentional code is worse than leaving a
Warning open.

## Final report

When the loop ends, report in chat:

- **Fixed** — each Critical/Warning addressed, with the `file:line` and a
  one-line description of the fix. Cite the commit(s).
- **Verification** — what you ran (build/lint/test) and that it's green. If
  something is still failing, say so plainly with the output.
- **Left open** — judgment calls, false positives (with reasoning), and any
  Nits, so the user can decide.
- **Push prompt** — state that commits are local and **not pushed**, and ask
  for the go-ahead. The go-ahead authorizes only the current batch.
