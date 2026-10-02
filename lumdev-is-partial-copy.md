---
name: lumdev-is-partial-copy
description: "The lumDev alias is a Partial Copy sandbox, not a true dev sandbox, so the CLAUDE.md deploy gate applies to it."
metadata:
  node_type: memory
  type: project
  originSessionId: d7dec3a0-7083-4f0d-b247-d2cec9ad1ace
  modified: 2026-09-30T15:23:49.984Z
---

`lumDev` (data-efficiency-9627--partialsb) is a **Partial Copy** sandbox. Verified 2026-09-30 by a
read-only tooling query of `SandboxInfo` in lumProd: `PartialSb | PARTIAL`. The alias name hides
this.

The CLAUDE.md hard gate bans Claude deploys and writes to partial sandboxes. Earlier LMNA-580 and
LMNA-581 sessions deployed to lumDev anyway ([[lmna-580-conversion-state]], [[lmna-581-link-delivery-state]]).
A partial copy also holds sampled prod data, so browser QA there can pull real patient records
(PHI) into the transcript.

**Why:** a follow-up session was about to be handed a deploy-and-e2e prompt aimed at lumDev.

**How to apply:** before any deploy, DML, user or permission-set change in lumDev, confirm James
has explicitly carved it out of the gate. Otherwise target a true Developer sandbox, checked through
`SandboxInfo`, and use synthetic data only.
