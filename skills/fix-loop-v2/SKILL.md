---
name: fix-loop-v2
description: Cross-agent variant of fix-loop. Runs grumpy-review in the OTHER coding agent, headless (Codex reviews when kicked off in Claude, Claude reviews when kicked off in Codex), then fixes every Critical and Warning finding, verifies, commits the batch, and re-reviews — looping until no Critical or Warning findings remain. Use when the user says "fix-loop-v2", "/fix-loop-v2 <pr>", or wants the review cross-checked by the other agent.
---

# fix-loop-v2

Same loop as `fix-loop` — **review → fix Critical + Warning → verify → commit →
re-review**, until a review pass surfaces no Critical and no Warning findings —
but the **review runs in the _other_ coding agent, headless**: when the host is
Claude the review is delegated to Codex, and when the host is Codex it's
delegated to Claude. The reviewer is therefore a different model than the one
that wrote the fixes, which is the whole point. Everything else — triage, fix,
verify, commit — stays in the host agent.

The argument `$ARGUMENTS` is whatever `grumpy-review` accepts — a PR URL, a PR
number, a base branch, or empty (current branch vs `origin/master`). Pass it
straight through to the delegated reviewer.

## Contract

- **Cross-agent, non-interactive review.** The review is always produced by the
  counterpart agent running headless; the host blocks on that subprocess and
  consumes its full output. If the counterpart agent isn't available, fall back
  to reviewing in the host and say so in the final report.
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

## Run the review (cross-agent, headless)

Both the initial review (step 1) and every re-review (step 6) go through here.

**1. Pick the reviewer by host agent:**

- `$CLAUDECODE` is set → host is **Claude Code** → reviewer is **Codex**.
- otherwise → host is **Codex** → reviewer is **Claude Code**.

**2. Locate grumpy-review and a scratch file** (keeps this skill repo-agnostic):

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
GR_DIR="$REPO_ROOT/.claude/skills/grumpy-review"
REVIEW_OUT="$(mktemp)"
```

**3. Delegate the review** and wait for it to finish.

Claude host → Codex reviewer:

```bash
codex exec --skip-git-repo-check -C "$REPO_ROOT" -s read-only -o "$REVIEW_OUT" \
  "Perform a grumpy code review. Read $GR_DIR/SKILL.md and follow it exactly for target: ${ARGUMENTS:-origin/master}. Wherever it references \${CLAUDE_SKILL_DIR}, use the literal path $GR_DIR. Output ONLY the findings, in the exact section format that skill specifies."
```

If `$ARGUMENTS` is a **PR URL or number**, the reviewer needs network access for
`gh`; swap `-s read-only` for
`-s workspace-write -c sandbox_workspace_write.network_access=true`.

Codex host → Claude reviewer:

```bash
claude -p "/grumpy-review ${ARGUMENTS}" --permission-mode auto > "$REVIEW_OUT"
```

`auto` mode auto-approves grumpy-review's read-only git/gh/rg/script commands
headless without prompting — no `--dangerously-skip-permissions` needed. It's
passed explicitly so the reviewer behaves the same regardless of which
worktree's settings launched it.

**Codex sandbox requirement.** Claude Code's Claude.ai OAuth credentials may be
stored in the macOS Keychain, which is unavailable to a sandboxed Codex
subprocess. A sandboxed `claude auth status` can therefore report
`"loggedIn": false` even though Claude works in a normal terminal.

When the host is Codex, run the Claude reviewer command with the execution
tool's unsandboxed/escalated mode from the start
(`sandbox_permissions: "require_escalated"` for Codex `exec_command`). Use a
concise justification such as: "Allow the read-only Claude grumpy-review
subprocess to access its macOS Keychain credentials." Do not treat a sandboxed
`Not logged in` response as reviewer unavailability. If diagnosis is needed,
compare `claude auth status` inside and outside the sandbox.

**4. Fallback.** If `$GR_DIR` doesn't exist, the reviewer binary isn't on
`PATH` (`command -v codex` / `command -v claude`), or the required unsandboxed
execution is denied or still unauthenticated, run `grumpy-review` in the host
agent instead and record in the final report that the review was **not**
cross-checked.

**5. Consume the output.** Read `$REVIEW_OUT` — that's the review. Triage its
Critical / Warning / Nit findings exactly as a normal grumpy-review pass; treat
each finding as a lead to verify against the real code, not gospel.

## Loop

### 1. Review

Run the review via **Run the review (cross-agent, headless)** above with
`$ARGUMENTS`. Use the resulting Critical / Warning / Nit breakdown. Note the
changed-file set (grumpy-review's diff script computes against `origin/master`).

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

Go back to step 1: run the review again via **Run the review (cross-agent,
headless)** on the same target. Because the fixes are now committed, the
delegated reviewer sees them via `git diff origin/master...HEAD`, so this is a
genuine fresh pass.

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

- **Reviewer** — which agent ran the review (Codex or Claude), or that it fell
  back to reviewing in the host because the counterpart wasn't available.
- **Fixed** — each Critical/Warning addressed, with the `file:line` and a
  one-line description of the fix. Cite the commit(s).
- **Verification** — what you ran (build/lint/test) and that it's green. If
  something is still failing, say so plainly with the output.
- **Left open** — judgment calls, false positives (with reasoning), and any
  Nits, so the user can decide.
- **Push prompt** — state that commits are local and **not pushed**, and ask
  for the go-ahead. The go-ahead authorizes only the current batch.
