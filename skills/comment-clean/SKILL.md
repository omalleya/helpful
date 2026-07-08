---
name: comment-clean
description: Strip verbose, redundant, or stale comments that this branch added, preferring self-documenting code. Keeps only comments that are genuinely necessary, capped at 2 lines. Use when the user says "comment-clean", "/comment-clean", "clean up the comments I added", or wants to de-clutter comments before pushing.
allowed-tools:
  - Bash(git diff *)
  - Bash(git log *)
  - Bash(git status *)
  - Bash(git merge-base *)
  - Bash(git symbolic-ref *)
---

# Comment Clean

Remove the noise comments **this branch introduced** and leave behind only
the few that genuinely earn their place. The bar is high: prefer
self-documenting code over a comment, and when a comment really is needed,
keep it to **2 lines max**.

This skill only touches comments **added or modified on the current branch**.
Pre-existing comments are out of scope — don't reformat the whole file.

## Scope: only the branch's own additions

Compute the diff against the merge-base and act only on added (`+`) lines that
introduce or change a comment:

```bash
# Resolve the repo's default branch, then the merge-base with it.
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
BASE=$(git merge-base "$DEFAULT" HEAD)
git diff "$BASE"...HEAD
```

If the working tree has uncommitted changes the user wants cleaned, include
them too (`git diff "$BASE"` with no `...HEAD`). Read each affected file in
full for context — you cannot judge whether a comment is redundant without
seeing the code it sits on.

## The decision, per added comment

For every comment this branch added, pick exactly one:

1. **Delete it** — the default. Delete if it restates what the code already
   says, narrates the obvious, captions a block, references the
   ticket/PR/task, or is commented-out code. Most added comments land here.
2. **Replace it with self-documenting code** — if the comment exists because a
   name is unclear or a block is doing too much, fix *that* instead: rename the
   variable/function, extract a well-named helper, or introduce a named
   constant. The comment then has nothing left to explain — delete it. Always
   prefer this over keeping a comment.
3. **Keep it, tightened** — only if removing it would genuinely leave a future
   reader confused, and code alone can't carry the meaning. Then:
   - **2 lines maximum.** Cut it down to the invariant or the non-obvious
     *why*; delete the prose around it.
   - State what is true today and will stay true — never *why it changed* or
     what it used to be.
   - Keep it on its own line(s) above the code, not inline (repo style).

When in doubt between delete and keep, **delete**. A wrong "keep" leaves
clutter; a wrong "delete" is trivially recovered from git.

## Hard exception: doc comments on exported symbols stay

Doc comments (`/** … */` TSDoc, docstrings, etc.) on exported/public API
symbols — functions, classes, types, constants — are API documentation, not
clutter. Do **not** delete those to satisfy the 2-line rule, and do not
convert them to inline `//`. Trim them for verbosity — cut redundant prose,
drop a restated parameter list — but the doc block itself remains. The 2-line
cap is for explanatory comments inside bodies, not API docs. If the project's
own conventions (a `CLAUDE.md`/`AGENTS.md`, `.claude/rules/`, or lint config)
require these docs, that requirement wins over the 2-line cap — check first.

Likewise keep any comment that is load-bearing for tooling or correctness: a
documented `eslint-disable` justification, a `@ts-expect-error` reason, or a
comment a downstream generator/parser reads.

## Apply, then verify

1. Make the edits directly in the working tree.
2. Removing a comment must never change behavior — but a stray edit can. Run
   the project's build/type-check and lint on the affected code (use whatever
   the repo uses — `turbo`/`pnpm`/`npm` scripts, `tsc`, the linter). Lint
   matters here: many repos enforce comment-line-length and no-inline-comment
   rules, so a kept comment that's too long or misplaced can fail lint.
3. **Leave the changes uncommitted** for the user to review. Comment cleanup is
   judgment-heavy; the user should eyeball it before it's committed.

## Report

Summarize concisely:

- **Deleted** — count, with a few representative `file:line` examples.
- **Replaced with code** — each spot where you renamed/extracted instead of
  commenting, with the `file:line`.
- **Kept (tightened)** — each comment you kept, the `file:line`, and one line
  on why it survived the bar.
- **Verification** — build/lint result.

Then note the changes are uncommitted and ask whether to commit.
