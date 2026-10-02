---
name: local-html-never-artifacts
description: "Deliver reports/audits/mockups as a local .html file in .docs/, never as a claude.ai Artifact"
metadata:
  type: feedback
---

Write every HTML deliverable — report, audit, plan, mockup, walkthrough — as a **standalone local
`.html`** under `.docs/`, then `open` it. **Never call the Artifact tool.** This includes the
`artifact-design` skill's publish step; its design guidance still applies to the local file.

Filename is **title-first**: `<topic>-YYYY-MM-DD.html`, e.g.
`lumina-flow-debt-audit-2026-09-01.html`. Not the date-first default.

Standalone means a real `<!doctype html><html><head>…viewport…</head><body>` wrapper, since there
is no Artifact harness to supply one.

**Why:** James has given this feedback in at least four separate projects (portfolio 2026-07-07,
M&D Local 2026-08-19, ParsingRules, ~/.claude) and hit it again in lumDev on 2026-09-01. The work
is client-adjacent Salesforce material that must live with the repo and be versioned and shared on
his terms; a hosted claude.ai URL is a surface he did not ask for. Memory is **per-project**, so
those four copies never load elsewhere — that is why it keeps recurring.

**How to apply:** Write + `open`, report the file path, stop. Only publish an Artifact if he asks
for a shareable link in that message.
