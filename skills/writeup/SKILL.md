---
name: writeup
description: Turn the current conversation — a code review, a plan, an investigation, or a design discussion — into a clean standalone doc (a private Notion page or a local markdown file) that reads as final state, not a transcript. Use when the user says "writeup", "/writeup", "put this in a doc", "write this up in Notion", "make a doc from this", or wants to capture what an agent just produced.
---

# writeup

Take what we produced in **this conversation** and turn it into a clean,
standalone document. The source is the conversation itself — **synthesize it,
never re-investigate or re-derive.** Two destinations: a **private Notion page**
(default) or a **local markdown file**.

`$ARGUMENTS` — optional destination (`notion` | `file [path]`) and/or type
(`review` | `plan` | `investigation` | `discussion`). Infer both from context
when omitted; ask only when genuinely ambiguous.

## The one rule that makes this worth using

The doc reads as **final state, not a transcript.** The reader wasn't in the
conversation and doesn't care how we got here.

- No "we first tried X", no decision log, no "as discussed above", no "I then
  realized", no dead ends, no meta narration of the back-and-forth.
- Present tense, declarative. **Lead with the conclusion**; hold supporting
  detail below it — the reader gets the answer first, the reasoning only if they
  keep going.
- If a rejected alternative matters, state it in one line *as the decision* —
  "Chose X over Y because Z" — not as the story of choosing.

This is the thing the user otherwise has to repeat every time ("just the final
decisions, not the log"). Bake it in so they don't.

## Pick the type → structure

- **review** — Findings (each: severity, `file:line`, the problem, the fix),
  then a short summary / priority order.
- **plan** — Problem or goal, Approach, Steps (ordered, each independently
  shippable), Risks & mitigations, Open questions.
- **investigation** — Summary + cause(s), Evidence (numbers / timestamps /
  queries), Verified vs suspected, Recommended actions (tiered).
- **discussion / design** — Decision, Context (only what's needed), Options
  considered (one line each + why not), Rationale, Consequences.

These are defaults, not a straitjacket — adapt to the material. The **title is
the subject** ("Realtime fan-out reliability"), never "Writeup of…".

## Destination

### Notion — default

- Load the tool: `ToolSearch("notion create page")`.
- Create a **private** page with `notion-create-pages` and **no `parent`** — it
  lands in the user's private workspace section. Do not file it under a shared
  page or database unless the user names one.
- Body is Notion-flavored markdown. Put the title in `properties.title`, **not**
  in the body. Give it a fitting emoji `icon`.
- Return the page URL when done.

### File

- Write markdown to the path in `$ARGUMENTS`, else `./<kebab-title>.md` in the
  current directory.
- If we're inside a worktree and this is a **plan meant for another agent to
  execute**, prefer the worktree root as `PLAN.md` — that's the create-ws
  handoff convention.

## Don't

- Don't share, post, or @-mention anyone. A private Notion page and a local file
  are both private — keep them that way.
- Don't create Linear tickets or comment on anything. If the user wants that,
  it's a separate ask.
- Don't pad. A short conversation makes a short doc.

## Pairs with

- After an investigation or debugging session → `/writeup investigation`.
- After a review or a planning discussion → `/writeup review` / `/writeup plan`.
