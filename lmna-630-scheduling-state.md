---
name: lmna-630-scheduling-state
description: "LMNA-630 facility scheduling shipped to main 2026-10-02 as 6cf762a; what is done, what is not, and the two prod data gaps that make it inert."
metadata:
  node_type: memory
  type: project
  originSessionId: d4042fdb-61a6-4491-ab0c-3030f035df26
  modified: 2026-10-02T12:10:33.465Z
---

LMNA-630 facility scheduling is on `main` in lumina-sandbox as **6cf762a** (2026-10-02),
with the sandbox scripts in **35bd3c1**. Branch `LMNA-630-scheduling-ui` points at the
same commit.

Built for Chayim's five questions: several programmes per visit, change notifications,
programmes pre-filled from the facility, providers filtered to a current State License for
the facility's state covering **every** programme on the visit (two of three is not
enough, decided 2026-09-24), and patient counts.

Patient counts moved from live aggregate queries to **three DLRS rollups** at Chayim's
request, Patient to Facility into `Census__c`, `Seen__c`, `Consented__c`. DLRS was already
in production use here, so this extends it. `Patient__c.Facility__c` is a **lookup, not
master-detail**, in both dev and prod, so native roll-up summaries were never possible.

**Not done, in rough priority order:**
- The DLRS back-fill was queued in lumDev but its numbers were never compared against the
  live aggregates the screen used to compute. Do that before this goes near prod.
- No notification email has ever been watched arriving. Only unit tested.
- The demo film is unfinished; see [[lmna-630-demo-video-state]].
- The spec at `.docs/specs/LMNA-630-...-2026-09-30.md` still describes the v1 design.

**Two production data gaps make two of the five answers inert:** there are **no State
License records at all** in prod, and the programme checkboxes are **false on all 194
onboarding facilities**. Until both are loaded the provider filter returns nobody and the
programme pre-fill ticks nothing. Raised, not yet actioned.

Still open with Dorothy or Chayim: which programmes genuinely conflict (only BHI/CoCM is
wired, and that was a guess), and that Community Full-Time, IPV Onboarding, RPM, PCM and
APCM can be put on a visit but have no field on the facility record, so they can never
pre-fill.

Related: [[lumdev-is-partial-copy]], [[propela-jira-project-keys]].
