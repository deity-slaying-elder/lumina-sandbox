---
name: lmna-580-conversion-state
description: "LMNA-580 flow-to-Apex conversion is code-complete in lumDev as of 2026-09-02; key blockers, decisions and traps that survive the session."
metadata: 
  node_type: memory
  type: project
  originSessionId: 00cf129d-364a-416c-8fff-fee94877d83c
  modified: 2026-09-02T19:22:55.634Z
---

As of 2026-09-03, 26 flows are Apex in lumDev (12 TCM + Chayim-approved expansion:
3 Patient name, 2 consent, programs-on-eligible, closed-won-state, and 7 name flows
on other objects), all replaced flows deactivated (versions retained), 110+ tests
green, live in-org QA passed. Deliberately NOT converted:
Patient_TF_On_Update_Community_Status_Update_Community_Status_Updated_Date_Time
(ThoroughCare second-pass dependency, phase 4) and the scheduled messaging flows. Committed to main
2026-09-24 as 9d28595 (31 Trigger_Action, 11 sObject_Trigger_Setting, 11 Trigger_Bypass
records, 11 triggers on the framework). lumProd untouched as of 2026-09-03; re-check before
assuming. Canonical detail:
`.docs/specs/lmna-580-flow-to-apex-spec-2026-09-01.md`.

**Why:** the next session must not re-audit or re-convert, and must not trust stale
assumptions that already caused wrong findings once.

**How to apply:**
- SOLVED 2026-09-02: the CMDT "insert blocker" was CustomMetadata fullName/MasterLabel
  capped at 40 chars, masked as UNKNOWN_EXCEPTION by the metadata-deploy path. The Apex
  Metadata API (Metadata.Operations.enqueueDeployment) surfaces real errors AND works -
  use it for CMDT record inserts (metadata deploy still throws UNKNOWN_EXCEPTION even
  for valid records in this org; destructive CMDT deploys work). All 16 Trigger_Action
  + 6 sObject_Trigger_Setting + 6 Trigger_Bypass records exist in lumDev and all six
  triggers run MetadataTriggerHandler.run(). Remember: run() with zero records executes
  NOTHING - never deploy that trigger body to an org before its records.
- Trigger actions run in system mode (`without sharing`, no stripInaccessible) on
  purpose - flows ran in system context, and `Latest_Community_Episode__c` has zero FLS
  for anyone. `TcmAutomationPermissionsTest` enforces this; don't "fix" it back.
- Repo flow bodies match prod active versions, but `flowDefinitions/` version stamps
  are stale - read bodies, never version numbers. Prod and dev flows can differ; the
  original defect audit was wrong three times from metadata-only reads. Query records
  before declaring anything dead.
- `Patient__c.Facility_State__c` only ever holds 2-letter codes, so spelled-out state
  names in any automation are dead branches.
- Pre-existing full-suite failures (not conversion-related): BulkFacilityCreator,
  BulkOpportunityCreator, PatientIntakeWorklist, ThoroughCareEmail, FacilityTriggerHandler
  test classes.
- Still open: Chana sign-offs (async SMS delivery, dev-only IPV work on the Visit flow,
  prod FLS for the zero-FLS fields), phase 4 ThoroughCare consolidation.
