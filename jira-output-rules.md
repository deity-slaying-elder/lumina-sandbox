---
name: jira-output-rules
description: "Jira deliverables: draft in chat for approval first, post only as comment or description append, and NEVER reference local file paths"
metadata:
  type: feedback
---

Applies to **every project**, not just Lumina.

**1. Draft first, always.** Any spec, plan, finding or status that is going to Jira gets shown in
chat first and waits for James's explicit approval of that exact text. He reviews before anything
is posted. No exceptions, no "I'll just add a quick comment".

**2. Where it goes.** Either a **comment** on the ticket, or **appended to the ticket
description**. New discoveries mid-work go up as a comment.

**3. Never mention local artifacts in Jira.** No repo paths, no `.docs/specs/...`, no filenames, no
branch names, no "see the audit HTML". People reading the ticket have no idea what those are and it
reads as noise. The Jira text must stand completely on its own — if a finding matters, write the
finding out in the comment, do not point at a file.

Local docs under `.docs/` are for the working repo only. See
[[docs-live-in-project-not-claude-dir]].

**Why:** James raised this on 2026-09-01 while specing LMNA-580, after a draft comment ended with a
pointer to `.docs/specs/lmna-580-...md`. Jira is read by PMs and client-side stakeholders who do not
have the repo.

**How to apply:** write the Jira text as a standalone document. Then show it and stop. The global
CLAUDE.md already forbids posting without approval; this memory adds the "no local paths" rule and
the comment-or-description placement.
