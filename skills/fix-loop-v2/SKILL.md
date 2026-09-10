---
name: fix-loop-v2
description: Cross-agent variant of fix-loop. Runs grumpy-review in the OTHER coding agent, verifies findings against concrete evidence and prior review decisions, fixes confirmed Critical and Warning defects, then re-reviews until no unaddressed verified blockers remain. Use when the user says "fix-loop-v2", "/fix-loop-v2 PR", or wants a convergent cross-check by the other coding agent.
---

# fix-loop-v2

Same loop as `fix-loop` — **review → adjudicate → fix verified Critical +
Warning defects → verify → commit → re-review** — but the **review runs in the
_other_ coding agent, headless**: when the host is Claude the review is
delegated to Codex, and when the host is Codex it's delegated to Claude. The
reviewer is therefore a different model than the one that wrote the fixes.
Triage, fixing, verification, and commits stay in the host agent.

The goal is convergence, not repeatedly satisfying a stochastic reviewer. A
finding blocks completion only when it survives evidence-based triage. Accepted
tradeoffs, false positives, and out-of-scope hardening are recorded and do not
become blockers merely because a later review phrases them differently.

The argument `$ARGUMENTS` is whatever `grumpy-review` accepts — a PR URL, a PR
number, a base branch, or empty (current branch vs `origin/master`). Pass it
straight through to the delegated reviewer.

## Contract

- **Cross-agent, non-interactive review.** The review is always produced by the
  counterpart agent running headless; the host blocks on that subprocess and
  consumes its full output. If the counterpart agent isn't available, fall back
  to reviewing in the host and say so in the final report.
- **Auto-fix tier: verified Critical + Warning defects.** Severity labels are
  leads, not commands. The loop is done when there are no **unaddressed,
  verified** Critical or Warning defects. Accepted risks, rejected findings,
  and out-of-scope hardening do not keep the loop open. Nits are reported,
  never auto-fixed.
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
- **Stable decisions.** Maintain a finding ledger across rounds. Do not reopen
  an accepted or rejected finding without materially new evidence. A new label,
  wording, or hypothetical variant is not new evidence.
- **No architecture churn without proof.** Before making a cross-layer refactor,
  changing a public contract, adding a schema constraint, or splitting the PR,
  require a concrete failing path and, when practical, a failing test. Stop for
  user input if the change would materially broaden the PR.

## Establish the review contract

Before the initial delegated review:

1. Read the PR/ticket description, changed-file set, recent branch commits, and
   relevant local docs. Extract the intended behavior and scope.
2. Record a short review brief containing:
   - behavioral invariants the change must preserve;
   - explicit product or engineering tradeoffs already accepted in the PR;
   - constraints such as rollout expectations and backwards compatibility;
   - uncertainties that still require owner input.
3. Create a finding ledger with columns: `ID`, `finding`, `status`, `evidence`,
   and `commit`. Valid statuses are `open`, `fixed`, `accepted`, `rejected`, and
   `deferred`.
4. Do not invent acceptance. If a consequential tradeoff is not clear from the
   source material, classify it as a judgment call and ask the user.

Keep the brief and ledger in a scratch file such as `$REVIEW_CONTEXT`; update it
after every round and pass it to every delegated re-review. This gives later
reviewers the decisions needed to converge instead of restarting from zero.

## Run the review (cross-agent, headless)

Both the initial review (step 1) and every re-review (step 6) go through here.

### Authorize the cross-provider handoff

When the host is Codex, before the first Claude delegation in each invocation:

1. Tell the user that the review sends the repository source and diff needed for
   review to Anthropic Claude and requires unsandboxed access to Claude's macOS
   Keychain credentials.
2. Ask for explicit approval and do not launch Claude until the user grants it.
   One approval covers the initial review and all re-reviews in that invocation,
   but not future invocations.
3. Do not send credentials, secrets, environment files, or unrelated user data.
   If the user declines, fall back to reviewing in the host and report that the
   review was not cross-checked.

**1. Pick the reviewer by host agent:**

- `$CLAUDECODE` is set → host is **Claude Code** → reviewer is **Codex**.
- otherwise → host is **Codex** → reviewer is **Claude Code**.

**2. Locate grumpy-review and scratch files** (keeps this skill repo-agnostic):

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
GR_DIR="$REPO_ROOT/.claude/skills/grumpy-review"
REVIEW_OUT="$(mktemp)"
REVIEW_CONTEXT="$(mktemp)"
```

Populate `$REVIEW_CONTEXT` with the review brief and finding ledger. On the
initial pass the ledger may be empty. Use a safe file-writing tool; do not
interpolate repository content into an executable shell command.

**3. Delegate the review** and wait for it to finish.

Claude host → Codex reviewer:

```bash
codex exec --skip-git-repo-check -C "$REPO_ROOT" -s read-only -o "$REVIEW_OUT" \
  "Perform a grumpy code review. Read $GR_DIR/SKILL.md and follow it for target: ${ARGUMENTS:-origin/master}. Wherever it references \${CLAUDE_SKILL_DIR}, use the literal path $GR_DIR. Read the review brief and prior adjudications at $REVIEW_CONTEXT. Before assigning Critical or Warning, identify a concrete execution path introduced by this diff and state the evidence; provide a reproduction or failing test when practical. Do not reopen accepted or rejected findings without materially new evidence. Output ONLY the findings, in the exact section format that skill specifies."
```

If `$ARGUMENTS` is a **PR URL or number**, the reviewer needs network access for
`gh`; swap `-s read-only` for
`-s workspace-write -c sandbox_workspace_write.network_access=true`.

Codex host → Claude reviewer:

```bash
claude -p "Read $GR_DIR/SKILL.md and perform its grumpy review for ${ARGUMENTS:-origin/master}. Read the review brief and prior adjudications at $REVIEW_CONTEXT. Before assigning Critical or Warning, identify a concrete execution path introduced by this diff and state the evidence; provide a reproduction or failing test when practical. Do not reopen accepted or rejected findings without materially new evidence. Output only the skill's required review sections." --permission-mode auto > "$REVIEW_OUT"
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
concise justification that discloses both boundaries, such as: "Allow the
requested Claude review to access its macOS Keychain credentials and send this
repository's source/diff to Anthropic for review." Do not treat a sandboxed `Not
logged in` response as reviewer unavailability. If diagnosis is needed, compare
`claude auth status` inside and outside the sandbox.

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

Establish the review contract, then run the review via **Run the review
(cross-agent, headless)** above with `$ARGUMENTS`. Use the resulting Critical /
Warning / Nit breakdown. Note the changed-file set (grumpy-review's diff script
computes against `origin/master`).

### 2. Triage the findings

For each **Critical** and **Warning** finding, before touching code:

- Re-read the cited `file:line` and enough surrounding context to confirm the
  finding is real and you understand the fix.
- Confirm the finding is caused by the branch or materially worsened by it. Do
  not turn unrelated pre-existing debt into a blocker.
- Trace a concrete execution path to the claimed impact. For architectural or
  concurrency claims, reproduce the failure or add a failing test when
  practical before changing the design. Static proof is sufficient for defects
  such as a missing authorization check or an impossible type contract.
- Classify it:
  - **Clear defect** (missing dependency, type error, null deref, N+1, missing
    `onDelete: Cascade`, untested new code path, swallowed error, etc.) → fix
    it.
  - **Judgment call / intentional** (a design decision, a deliberate tradeoff,
    something that needs product/owner input) → don't edit; mark it `accepted`
    only when the intent is documented, otherwise stop and surface it in chat.
  - **False positive** (you read it and the finding is wrong) → note why,
    mark it `rejected`, and skip.
  - **Out-of-scope hardening** (real improvement without a demonstrated branch
    regression) → mark it `deferred`; report it without expanding the PR.
- Update the finding ledger with the evidence and decision. Reuse the same ID
  when a later review restates the same underlying concern.

A Critical or Warning is **verified** only when the code supports a concrete
failure path and the impact matches the severity. “Could theoretically hang,”
“might race,” or “would be safer with” is insufficient by itself.

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
headless)** on the same target, passing the updated review brief and ledger.
Because the fixes are now committed, the delegated reviewer sees them via
`git diff origin/master...HEAD`.

Re-review is a convergence pass, not a blank-slate hunt. Ask the reviewer to:

- verify that the fixed findings are actually closed;
- identify regressions introduced by the latest fix batch;
- report a previously missed Critical/Warning only with materially new,
  concrete evidence;
- honor accepted, rejected, and deferred decisions unless that evidence changes.

- If there are **no unaddressed, verified Critical or Warning defects** → the
  loop is done, even if the reviewer repeats adjudicated findings.
- Otherwise repeat with the remaining verified findings.

## Stop conditions

Stop the loop and report when **any** of these holds:

1. **Clean** — no unaddressed, verified Critical or Warning defects remain.
   Repeated accepted/rejected/deferred findings do not prevent success.
2. **No progress** — a round produces no new fixes (every remaining
   Critical/Warning is a judgment call or false positive), or the same finding
   survives a fix attempt twice. Don't spin; report what's left and why.
3. **Needs a decision** — a remaining finding requires the user's input
   (product call, ambiguous intent, risky change). Surface it and ask.
4. **Iteration guard** — you've completed 3 fix rounds. Stop, report the ledger,
   and ask whether to continue. Do not let stochastic new findings create an
   unbounded loop.
5. **Churn guard** — a proposed fix materially widens the design, changes a
   public contract, or creates another independently reviewable responsibility.
   Stop and propose either accepting/deferring the risk or splitting at that
   contract boundary. Do not split tests/docs from the behavior they verify, and
   do not split solely to satisfy a reviewer.

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
- **Adjudicated** — accepted risks, rejected false positives, and deferred
  hardening, with concise evidence so future review passes do not reopen them.
- **Verification** — what you ran (build/lint/test) and that it's green. If
  something is still failing, say so plainly with the output.
- **Left open** — judgment calls, false positives (with reasoning), and any
  Nits, so the user can decide.
- **Push prompt** — state that commits are local and **not pushed**, and ask
  for the go-ahead. The go-ahead authorizes only the current batch.
