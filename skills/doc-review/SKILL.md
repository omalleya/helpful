---
name: doc-review
description: Iterate on an existing Notion doc — critically review it and leave comments as a persona, respond to the comment threads already on it, and apply clean updates that read as final state. The counterpart to writeup (which creates the doc). Use when the user says "doc-review", "/doc-review <notion-url>", "review this doc", "leave comments on this doc", "respond to the comments on the doc", "do another pass on the doc", or "is this doc ready for implementation".
---

# doc-review

Iterate on an **existing Notion doc**: review it, leave or answer comments, and
apply clean updates. It's the counterpart to `/writeup` — writeup *creates* a
doc, doc-review *iterates* on one. Lightweight by design: no worktree and no
codebase-research pipeline (that heavyweight ticket→plan flow is `ship-notion`).

Use the `mcp__*Notion*` tools (`ToolSearch("notion fetch comments update page")`).

`$ARGUMENTS` — the Notion page URL (or "the doc we just made"), plus an optional
mode (`review` | `respond` | `refine`) and an optional persona. If there's no URL
and no recent doc in context, ask.

## First: read the doc and its comments

- `notion-fetch <url>` for the full page — understand what the doc is *for*
  before touching it.
- `notion-get-comments` for the open threads. Note which are **unresolved** and
  which actually **ask for something** versus just remark.

## Persona — take one, don't be generic

The user reviews docs *as someone*. Take the persona from `$ARGUMENTS`; else
default to **a senior engineer who wants the simplest correct implementation of
the feature**. The common two:

- **Reviewer** (senior eng / tech lead) — critiquing someone else's doc.
- **Owner** — you wrote it; you're answering a reviewer's comments.

State which persona you used in your report.

## Modes

### review — leave critical comments

Read the whole doc, then leave comments (`notion-create-comment`, anchored to the
specific block) with concrete concerns. Bias hard toward **scope discipline**:

- Flag **overkill for a v0** — unnecessary API additions, premature streaming,
  complicated QOL that can wait.
- Name **simplifications** — a simpler shape that does the same job.
- Call out **gaps, risks, and anything under-specified**.
- Comment on real decisions, not nits.

End with a verdict: **is this ready for someone to pick up and implement?** — and
if not, the few things blocking that.

### respond — answer the threads already on it

Go through the open threads and **respond only to the ones that need it** (a
question, a challenge, a request) — skip pure acknowledgements. For each: reply
on the thread with the decision/rationale, or make the doc edit it calls for, or
both — acting the persona (e.g. owner answering a tech lead). Resolve a thread
only when the user asks.

### refine — apply agreed changes, clean

Apply the changes with `notion-update-page`. **The doc reads as final state, not
a log** — no "updated per comment", no decision history, no "changed X to Y."
Just the current, clean plan. (Same rule as `/writeup`.) Then report what
changed.

**Default when unspecified:** open comments on the doc → **respond**; none →
**review**.

## Report — in chat

Which persona, which mode, and what you left / answered / changed (naming the
thread or block), plus the ready-for-implementation verdict. Don't restate the
whole doc.

## Don't

- Don't @-mention or share anyone — comments on a private doc stay between you
  and the user.
- Don't wholesale-rewrite a section the user wrote in their own voice; weave the
  change in minimally, or raise it in chat (same spirit as the PR "never
  overwrite a human-edited body" rule).
- Don't pad the doc — cutting is as valid as adding.

## Note on local files

Modes assume Notion (comment threads are a Notion concept). For a **local
markdown** doc, only `review` (report concerns in chat) and `refine` (edit the
file) apply — there are no threads to respond to.
