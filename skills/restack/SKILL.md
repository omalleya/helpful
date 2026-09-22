---
name: restack
description: Bring the current stacked branch up to date with the parent branch it's stacked on. Detects the parent, judges whether it changed materially since this branch forked, then rebases (no PR or draft PR) or merges (open non-draft PR) the parent's changes in — resolving what it safely can, including regenerating lockfiles/codegen — and hands back WITHOUT pushing, printing the exact push command. Single hop (current branch vs its parent). Use when the user says "restack", "/restack", "the branch below changed, update this one", "rebase this onto its parent", "the bottom of my stack changed, pull it up", or hands over a stacked branch whose parent moved.
---

# restack

The branch below you in a stack (`A`) changed; the current branch (`B`) is now
built on a stale copy of it. `restack` brings `B` up to date with `A` — the right
way for `B`'s PR state — **locally, without pushing**. Run it **from `B`**.

`$ARGUMENTS` may contain an explicit parent ref (a branch or SHA). Omit it to
auto-detect. This skill is **single-hop**: it updates `B` against its immediate
parent only. For a deeper stack, run it from each branch in turn, bottom-up.

## Locked behavior
- **Never pushes.** Everything is local. The final report prints the exact push
  command for the user to run.
- **Operation follows `B`'s PR state** (to avoid rewriting history reviewers are
  reading): **no PR or DRAFT → rebase**; **open non-draft → merge**.
- **Conflicts:** auto-handle everything confidently resolvable — mechanical
  "preserve both" merges **and regeneration** of generated files. **Stop only**
  when a conflict genuinely needs a human decision.

## Step 1 — Analyze (read-only)

Run the analyzer. It fetches, detects the parent, judges materiality, reads
`B`'s PR state, and prints a recommended operation + the exact command:

```bash
bash ~/.claude/skills/restack/scripts/restack-analyze.sh [parent-ref]
```

(The script lives next to this SKILL.md in `scripts/`; the path above is where
it's symlinked. Pass `parent-ref` only when you already know the parent.)

Read its output. The keys you act on: `parent`, `parent-ref`, `merge-base`,
`pr`, `recommend` (`rebase`|`merge`|`none`), `command`, `old-base`, and `flags`.
The `OVERLAP` section — files **both** branches changed — is the manual-review
surface for Step 5.

## Step 2 — Gate on flags before touching anything

- **`up-to-date`** — the parent gained nothing since `B` forked. Report it and
  stop. Nothing to do.
- **`STOP-DIVERGED`** — the parent's local and origin refs have *both* advanced
  (it was rebased/force-pushed, or two worktrees moved it). Do **not** guess
  which is authoritative. Stop and ask the user which side wins, then re-run with
  that as an explicit `parent-ref`.
- **`ASK-PARENT`** — detection isn't certain (it fell back to a heuristic or to
  trunk while a nearer feature branch exists). Show the detected parent and the
  candidate, and confirm with the user before rebasing.
- **`LOCAL-A-AHEAD`** on a **merge** recommendation — the parent has unpushed
  local commits; merging them into `B` embeds commits reviewers can't see on
  `A`'s PR. Note this and confirm before merging, or use `origin/<parent>`.

## Step 3 — Preconditions

```bash
ORIG=$(git rev-parse HEAD)                                  # recovery anchor
git rev-parse --verify --quiet origin/$(git branch --show-current) >/dev/null \
  && EXPECT=$(git rev-parse origin/$(git branch --show-current))  # for the printed push
```

- **Clean tree:** if `git status --porcelain` is non-empty, `git stash push -u -m
  restack` and remember to `git stash pop` at the end (on success *and* abort).
- **No op in progress:** refuse if a rebase or merge is already underway
  (`.git/rebase-merge`, `.git/rebase-apply`, or `MERGE_HEAD`).
- **Never `git checkout` the parent** — in a stack it's often checked out in
  another worktree. Operate on `B`; reference the parent by the analyzer's
  `parent-ref`. `git worktree list` shows where it lives.

## Step 4 — Execute the recommended operation

Run the analyzer's `command` verbatim:

- **rebase:** `git rebase --onto <parent-ref> <old-base> HEAD` — the `--onto`
  form (with `old-base` from the analyzer) is correct whether the parent merely
  gained commits *or* was rewritten; it replays only `B`'s own commits.
- **merge:** `git merge --no-ff <parent-ref> -m "merge <parent> into <B>"` —
  lowercase, imperative, no conventional-commit prefix (house convention). The
  `--no-ff` commit makes the incorporation explicit and revertable.

## Step 5 — Resolve conflicts (handle all you confidently can)

For each conflicted file, first see what the parent did to it:

```bash
git log -p -n 3 <parent-ref> -- <file>
```

Then:

- **Mechanical / additive** (both sides added in different places, clear intent)
  → **preserve both sides**, `git add <file>`, then `git rebase --continue` (or
  `git commit` for a merge).
- **Generated files** (lockfiles, codegen output) → **regenerate, don't
  hand-merge**. Take the parent's version, then rebuild:
  - Lockfile — detect the manager from the lockfile name and re-run install:
    `pnpm-lock.yaml`→`pnpm install`, `package-lock.json`→`npm install`,
    `yarn.lock`→`yarn install`, `Cargo.lock`→`cargo build`, `poetry.lock`→
    `poetry lock`, etc.
  - Codegen output (GraphQL types, Prisma client, protobuf, snapshots) → run the
    repo's codegen script (find it in `package.json` scripts or the tool's
    config), then stage the result.
  Stage the regenerated file and continue.
- **Stop only** when it genuinely needs a decision — the same symbol redefined
  incompatibly, or an `OVERLAP` file whose correct resolution is unclear. Leave
  the rebase/merge **paused**, explain exactly which file and why, and hand back.
  Do not guess.

If it goes wrong, recover cleanly: `git rebase --abort` / `git merge --abort`
(else `git reset --hard $ORIG`), then `git stash pop` if you stashed.

## Step 6 — Verify

Run the fast checks the repo supports — typecheck and build, plus tests if
they're quick. If a check is slow, say it was skipped rather than block. Report
failures honestly with the output.

Then compute the **semantic-review list**: the `OVERLAP` files that did **not**
raise a conflict. These are the dangerous ones — the parent changed something
`B` builds on, git merged it cleanly, and nothing flagged it. Name them.

## Step 7 — Report and hand back (no push)

Respond in chat:

```
## ♻️ restacked `<B>` onto `<parent>`  (<rebase|merge>)
**Parent gained:** <N commits / short summary of what A added since the fork>
**Operation:** <rebase --onto … | merge --no-ff …> — because PR is <state>.

### Conflicts
- Auto-resolved: <files + how> · Regenerated: <lockfile/codegen> · (or "none")
- ⛔ Needs your call: <file + why>   ← only if you stopped in Step 5

### 🔬 Review by hand (parent + B both touched, no conflict raised)
- `file` — <what A changed here that B may depend on>   (or "none")

### ✅ Verification
- typecheck/build/tests: <result, or skipped + why>

### ⬆️ Push it yourself
<one command:>
- rebase:  git push --force-with-lease=refs/heads/<B>:<EXPECT> origin <B>
- merge:   git push origin <B>
```

Use the pinned `--force-with-lease=refs/heads/<B>:<EXPECT>` (with the `EXPECT`
OID captured in Step 3) so the user's push refuses to clobber an `origin/<B>`
that moved. If `origin/<B>` didn't exist, the push is a plain
`git push -u origin <B>`.

## Guardrails

- **Never pushes.** The skill ends locally; the push is the user's to run.
- **Never `git checkout` the parent** — reference it by ref; it may be checked
  out elsewhere.
- **Clean-tree precondition** — stash and restore; never discard uncommitted work.
- **Stop, don't guess:** on `STOP-DIVERGED`, an ambiguous parent (`ASK-PARENT`),
  a conflict that needs a decision, or an in-progress rebase/merge.
- The printed rebase push is **only ever `--force-with-lease`**, pinned to the
  observed `origin/<B>` OID — never plain `--force`.
- Analyze (read-only) before mutating; `ORIG` is the one-command recovery anchor.
- Single hop only — don't walk the stack; the user re-runs per level.
