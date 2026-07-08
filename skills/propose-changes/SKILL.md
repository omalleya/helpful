---
name: propose-changes
description: Investigate an issue or ticket, identify the relevant code/infra, and produce a high-confidence execution plan with code snippets. Use when the user says "propose changes", "plan this ticket", "how would you implement <ISSUE-…>", or invokes `/propose-changes [issue]`.
---

# propose-changes

Produce a concise, high-confidence plan for executing an issue or ticket. **Do not edit code.** The deliverable is a plan the user can read, push back on, and then hand to an implementation pass.

Arguments: $ARGUMENTS

## 1. Get the issue

Resolve the issue ID in this priority order:

1. **Explicit argument** — if `$ARGUMENTS` contains an issue identifier (for example `PROJ-1234`) or issue URL, use it.
2. **Current branch** — otherwise read the current branch with `git branch --show-current` and extract the first issue-key match (for example `aidan/proj-22865-agent-temporal-wiring` → `PROJ-22865`).
3. **Ask the user** — if neither yields an ID, stop and ask which issue to plan.

Once resolved, fetch the issue:

- Use the available issue tracker tool, such as Linear's `get_issue`, with the identifier.
- Fetch comments/discussion for the same issue when available; comments often contain the real spec, edge cases, and decisions.

If the issue references attachments, designs, or linked issues/projects that look load-bearing, fetch them too (`get_attachment`, `get_project`, `get_issue` on related IDs). Stop pulling once you have enough to write the plan — don't drown in adjacent tickets.

## 2. Extract the goal and constraints

From the issue body + comments, write down (internally, not in the final report yet):

- **Goal** — one sentence: what does "done" look like from a user/system perspective?
- **Scope boundaries** — what's explicitly in vs. out? Watch comments for "let's not do X here" or "follow-up ticket for Y".
- **Constraints** — feature flags, rollout staging, deadlines, dependencies on other tickets, compatibility requirements.
- **Acceptance signal** — how will the user/QA verify this? (test cases listed, screenshots, dashboards, etc.)

If the issue is genuinely ambiguous after reading everything, flag the ambiguity in the final report rather than guessing.

## 3. Investigate the codebase

Find the code that will change. Default to spawning an `Explore` subagent for breadth — the main context should stay clean for the plan itself.

Things to locate:

- **Entry points** — the route, component, resolver, workflow, activity, job, CLI handler, etc. where the change starts.
- **Data layer** — Prisma models, GraphQL schema files, data-access functions touched by the change.
- **Tests** — existing test files that cover the area (unit, integration, e2e). These are the natural homes for new test cases.
- **Feature flags** — flag definitions, rollout config, or kill switches if the issue mentions a gated rollout.
- **Adjacent prior art** — recent PRs that touched the same area. Use `git log -p --since=...` or `gh pr list` scoped to relevant paths to see how similar work was structured.

Cite `file:line` for every claim you make about what currently exists. If you haven't read it this session, don't claim it.

## 4. Draft the plan

Build the plan around **discrete, sequenceable steps**. Each step should:

- Name the file(s) touched.
- State the change in one or two sentences.
- Include a code snippet **only when** the snippet clarifies something a sentence cannot — a non-obvious API shape, the exact JSX/SQL/GraphQL fragment to add, a tricky branch. Skip snippets for boilerplate or anything self-evident from the prose.

Order steps so each one leaves the repo compiling and the tests at least no worse than before. Call out steps that *do* require coordinated changes (schema + codegen + caller, migration + backfill, etc.) and group them.

For each non-trivial step, note the **risk** in a short phrase: "breaks existing callers", "needs migration ordering", "depends on flag X being enabled", "no test coverage today".

## 5. Confidence audit

Before writing the report, sweep the plan and ask:

- Is every file path I reference one I actually read this session?
- Is there a step that depends on behavior I'm *assuming* rather than *verified*? Mark it explicitly.
- Are there branches in the work I haven't decided between? List them as open questions, not silent picks.

Anything below high confidence gets flagged in the **Open questions** section — never hide uncertainty behind confident prose. If the investigation leads to a solution that differs from what was detailed in the issue (or you think of a better solution) flag that.

## 6. Output format

Render the report as markdown in the chat. Keep it tight — a senior engineer should be able to skim it in under two minutes.

```markdown
## <ISSUE-1234> — <issue title>

**Goal:** <one sentence>

**Scope:** <in vs. out; one or two bullets>

**Constraints:** <flags, deadlines, dependencies; omit section if none>

### Where the change lives

- `path/to/file.ts:123` — <what's there now, why it's relevant>
- `path/to/other.ts:45` — <…>

### Plan

1. **<short step title>** — `path/to/file.ts`
   <one or two sentences>
   ```ts
   // snippet only if it clarifies something prose can't
   ```
   _Risk:_ <short phrase, or omit if none>

2. **<next step>** — `path/to/other.ts`
   …

### Tests

- <which existing tests to extend, or new test files to add, and what they should assert>

### Open questions

- <anything genuinely undecided — keep this honest; "none" is a valid answer>
```

Rules for the output:

- **No preamble.** Start at the `## <ISSUE-1234>` heading.
- **No closing summary** ("this plan accomplishes…") — the plan speaks for itself.
- **Cite files with `path:line`** so the user can click through.
- **Snippets are surgical** — show the diff-relevant lines, not whole functions. Prefer `// …` ellipses over copying unchanged context.
- **Don't promise to implement** in the report. Hand it back; the user decides whether to proceed.

## 7. After delivering

Stop. Do not start editing code. If the user replies "go ahead" / "implement this" / similar, then proceed — but the propose step ends with the report.
