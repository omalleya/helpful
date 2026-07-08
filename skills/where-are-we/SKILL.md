---
description: Provide a concise bulleted summary of the last few actions taken and topics discussed in the current session. Use when the user asks "where are we?", "what have we been doing?", or wants a quick session recap.
---

Summarize the recent session activity. Be brief — brevity is the top priority.

## Format

- Use bullet points, never paragraphs
- One short line per bullet (aim for <80 chars)
- Group into at most 2 sections if useful: **Done** and **Open**
- Skip section headers entirely if there are only a few items
- No preamble, no closing summary

## What to include

- Concrete actions taken (files edited, commands run, decisions made)
- Open questions or unresolved threads
- The current focus / what's next, if clear

## What to exclude

- Internal deliberation or tool-by-tool narration
- Restating the user's original request verbatim
- Anything older than the last few meaningful turns

## Example shape

```
- Edited foo.ts to add retry logic
- Ran tests — 2 failing in bar.test.ts
- Discussed whether to mock the DB; user said no
- Next: fix the failing assertions in bar.test.ts
```

Keep it tight. If unsure whether to include a bullet, leave it out.
