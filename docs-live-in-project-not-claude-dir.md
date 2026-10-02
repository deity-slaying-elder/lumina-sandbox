---
name: docs-live-in-project-not-claude-dir
description: "Plans, specs and audits go in the project's .docs/ folder, named <jira-key>-<topic>-YYYY-MM-DD.ext — never ~/.claude/plans with a generated name"
metadata:
  type: feedback
---

Every plan, spec, audit or report lives in the **project repo** under `.docs/`, not in
`~/.claude/plans/` and not anywhere under `~/.claude/`.

Layout, matching M&D Capital Local:
- `.docs/specs/` — design and spec docs
- `.docs/plans/` — build plans
- `.docs/` root — audits, one-offs

Filename is **`<jira-key>-<topic>-YYYY-MM-DD.ext`**, lowercase key. Jira key first, always.
Example: `lmna-580-flow-to-apex-spec-2026-09-01.md`, matching the existing
`mdcap-250-deterministic-pre-parse-design-2026-06-25.md`.

Never accept the harness-generated plan filename (e.g. `let-s-plan-this-or-dapper-ripple.md`) —
it is random, has no ticket key, and sits outside the repo.

**Why:** James called this out on 2026-09-01. Docs must be versioned with the code and findable by
ticket number. A plan in `~/.claude/plans` with a generated slug is invisible to the team and
unversioned. Extends [[local-html-never-artifacts]], same instinct: deliverables live where he will
actually use them.

**How to apply:** when plan mode hands you a `~/.claude/plans/<slug>.md` path, still write the real
document to `.docs/specs/` or `.docs/plans/` with the ticket-prefixed name, and keep the plan-mode
file only as the approval copy.
