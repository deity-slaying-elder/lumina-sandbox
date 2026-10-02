---
name: rehearse-scripts-in-sandbox-first
description: Never hand James a script to run against production without first running it end to end against a dev sandbox.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 3f272bcd-13de-4637-9d77-3d2cbf2a6eda
  modified: 2026-09-22T23:27:24.966Z
---

Every script written for James to run against production gets rehearsed against a true dev
sandbox (lumDev) first, start to finish, before it is handed over. Not read, not reasoned about.
Run.

**Why:** James cannot run production writes through me, so every prod script is him pasting my
work into his own terminal. On 2026-09-23 I handed him the four LMNA-581 digest scripts having
never executed them anywhere. Step 1 died on `MIXED_DML_OPERATION` because it updated a
`Hospital_Admission__c` and then enqueued a metadata deployment, and `DeployRequest` is a setup
object. One sandbox run would have caught it in thirty seconds. He asked afterwards, "is there no
way you can run first like validation without actually running the script first to test it in
your end?" The answer was yes the whole time. The gate in CLAUDE.md bans prod writes, it does not
ban dev-sandbox rehearsal, and reading the code is not a substitute because the failures that
matter here are runtime, not compile.

**How to apply:** Before handing over any `scripts/apex/*.apex` aimed at prod, run the whole
sequence against lumDev, creating whatever fixture the script expects by its exact name so it
runs verbatim rather than in a doctored form. Check each step's output, not just its exit code.
Restore any config the rehearsal changed and delete the fixture afterwards, and say in the
handover that it was rehearsed and what it printed. Failures that only show up at runtime and
are worth rehearsing for: MIXED_DML between records and setup objects, a fixture outside the
report window, a stale `getPopulatedFieldsAsMap()` clone reverting a field another write just
set, and async metadata deploys not having landed before the next step reads them.

Related: [[lmna-581-link-delivery-state]], [[lmna-580-conversion-state]],
[[feedback-brevity-and-autonomy]].
