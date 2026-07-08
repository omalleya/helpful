---
description: Review the open review comments on the current branch's PR and report back how to handle each one — without commenting on the PR or changing code. Use when the user says "comment report", "/comment-report", "go through the PR comments", "triage the PR comments", or asks what to do about review feedback.
---

Go through the human review comments on the current branch's pull request
and produce a triage report. **Do not post anything to the PR and do not
change any code** unless the user explicitly asks afterward — this skill
only investigates and reports.

## Gather the comments

1. Resolve the PR for the current branch:
   `gh pr view --json number,title,url,body`
2. Pull every comment thread and review:
   - Inline review comments:
     `gh api repos/<owner>/<repo>/pulls/<n>/comments`
     (fields: `id, user.login, path, line, body, in_reply_to_id, created_at`)
   - Top-level issue comments:
     `gh api repos/<owner>/<repo>/issues/<n>/comments`
   - Reviews:
     `gh api repos/<owner>/<repo>/pulls/<n>/reviews`
3. **Filter out bot/automation noise** — skip comments from bots and service
   accounts (`unblocked[bot]`, `linear-code[bot]`, coverage/review-app/
   linkback comments, "✅ No issues found", etc.).
   Focus on real human reviewers or legitimate automated comments from Unblocked or Claude. Mention in one line that bot comments
   were skipped, but don't itemize them.
4. Skip comments the author has already resolved or replied to, unless
   the reply leaves an open question.

## Investigate before reporting

For each human comment, actually read the referenced code in the current
session — open the file at the cited `path:line`, read enough
surrounding context to understand what the reviewer is pointing at, and
check tests or callers when the comment is about behavior. Follow the
evidence contract in `.claude/rules/answering-questions.md`: cite
`file:line` for factual claims, label inference as inference, and flag
anything you can't verify. If a comment questions an intentional design
decision (e.g. one with a test asserting the current behavior), say so
and surface it as the user's call rather than silently picking a side.

## Report format

For each comment, output these three numbered parts:

1. **The comment** — quote the reviewer's comment (trim to the essential
   sentence(s)) and note who left it and the `file:line` it's on.
2. **The code being referenced** — clarify, with `file:line` evidence,
   what the comment is actually about: what the code currently does and
   any context the reviewer's one-liner omits.
3. **How I'd handle it** — state whether it's:
   - **Just respond** — no code change needed. Draft the reply you'd
     send (don't post it).
   - **Code change** — describe the change (and show the proposed
     snippet/diff when it clarifies). Note any ripple effects (tests,
     callers) you'd also need to touch.
   - **Needs the user's decision** — when it conflicts with an
     intentional choice or is genuinely ambiguous. Give a recommendation,
     but make clear it's their call.

Use a clear heading per comment. Keep each part tight — evidence over
prose. End with a one-line offer to act on whichever items the user
picks (post replies, make the changes), since this skill stops at the
report.

## Hard rules

- Never post comments, replies, or reviews to the PR.
- Never edit code, run formatters, or commit during this skill.
- If `gh` isn't authenticated or there's no PR for the branch, say so and
  stop — don't guess at the comments.
