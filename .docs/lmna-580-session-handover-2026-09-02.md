# LMNA-580 — Session handover, 2026-09-02

Handover for a fresh agent session. Everything below was done in one session against the Lumina
repo at `/Users/hiccup/Documents/propela-tech/LUMINA/lumDev`, branch `main`, HEAD `d4666d9`.

**Nothing is committed. 81 uncommitted paths in the working tree.** Read "Repo state" before
touching git.

---

## 0. Read this first — the org gate

`lumDev` is **not a dev sandbox**. It resolves to:

```
username:    stevenlum@clarktn.com.partialsb
instanceUrl: https://data-efficiency-9627--partialsb.sandbox.my.salesforce.com
```

The `.partialsb` suffix means **partial sandbox**, which James's CLAUDE.md puts off-limits to
Claude via the `sf` CLI. He gave an **explicit one-time override on 2026-09-02** to deploy the
LMNA-580 conversion work there, after being shown the username and told the org type.

That override covers this conversion work in `lumDev`. It is not a standing permission and does
not extend to `lumProd`, `MDCAPStage`, `M&DCapitalFullSandbox` or any other org. `lumProd` was
touched **read-only only** (metadata retrieve + describes), which the CLAUDE.md read-only carve-out
allows.

If you are unsure whether a new action is covered, ask before running it.

---

## 1. Where the work stands

| Phase | State | Notes |
|---|---|---|
| Spec | done 2026-09-01 | `.docs/specs/lmna-580-flow-to-apex-spec-2026-09-01.md` |
| 1. Baseline | **done, uncommitted** | prod Flow metadata pulled into repo |
| 2. Reconcile dev to prod | not started | blocked on Chana, ~6 flows |
| 3. Re-audit | not started | blocked on phase 2 |
| 4. Trigger foundation | **step 13 only** | bypass shipped. Steps 12/14/15/16/17 are Patient/ThoroughCare, still blocked |
| 5. Convert 14 TCM flows | **3 of 14 done** | live in lumDev, flows deactivated, 29 tests green |
| 6. Deferred | not started | separate tickets |

**People:** Chayim = developer. Chana = PM and the LMNA-580 ticket reporter. The spec's Open
Questions are Chana's. Earlier drafts greeted Chayim by mistake — check the name before posting
anything.

---

## 2. Phase 1 findings (measured, not from the spec)

The spec's predictions were wrong in two places. These numbers are from live queries on 2026-09-02.

- lumProd **56** active triggered flows; lumDev **50**; repo 40 before retrieve, **64** after.
- **8 prod-only** active triggered flows, not the 4 the spec predicted — 5 `RecordAfterSave`
  (the 4 named plus `Patient_TF_Send_SMS_When_Appointment_Is_Scheduled`) and 3 `Scheduled`.
- **18 flows drift on version, in both directions.** Prod ahead on 16, dev ahead on 2.
- **26 flows active in prod were absent from the repo entirely.**
- The prod retrieve overwrote **no** dev-ahead work — verified explicitly.

### Schema gap that blocks the 4th conversion

`Patient__c.Latest_Visit_Provider__c` **exists in lumProd, not in lumDev.** That is why the flow
`Flow` (Visit — Fill Latest Visit Provider) is prod-only. Its conversion cannot deploy to lumDev
until the field ships. lumDev is also missing `Missing_TC_Provider_For_Enrollment__c`,
`Provider_Added_to_Tc_Date__c`, `No_TC_Provider_Datetime__c`, `No_Community_TC_Provider_Datetime__c`.

---

## 3. What is deployed in lumDev

### Converted, live, flows deactivated

| Flow (now inactive) | Object | Apex |
|---|---|---|
| `Facility_Mapper_TF_Delete_False_Leaked_Admissions` | `Facility_Mapper__c` | `FacilityMapperTrigger` + Handler + Test |
| `Hospital_Admissions_TF_On_C_U_Look_For_Prior_NH_Discharge_Home` | `Hospital_Admission__c` | `HospitalAdmissionTrigger` + Handler + Test |
| `Visit_TF_On_Create_Visit_Fill_Visit_Date_Fields_on_Patient` | `Visit__c` | `VisitTrigger` + Handler + Test |

Deactivated via `flowDefinition` `activeVersionNumber 0`. Versions retained, so rollback is
setting the number back.

**Verified org state:** lumDev went 50 → 47 active triggered flows. The delta is exactly those
three. Nothing else was deactivated and nothing was spuriously activated.

### Bypass switch — `Trigger_Bypass__mdt`

Custom **metadata**, one record per trigger. James chose this over a custom setting on 2026-09-02
after being shown the tradeoff.

```
Trigger_Bypass__mdt        Is_Bypassed__c
  All_Triggers                  false   <- org-wide lever, short-circuits
  FacilityMapperTrigger         false
  HospitalAdmissionTrigger      false
  VisitTrigger                  false
```

`TriggerContext.isBypassed('VisitTrigger')` checks, in order: runtime override, `All_Triggers`
record, that trigger's own record. The record DeveloperName **is** the trigger name, so an
unrecognised name finds no record and returns false — it fails closed.

Two things to know:

1. **CMDT cannot be inserted in an Apex test.** `TriggerContext.bypass()` / `.clearBypass()`
   provide a transaction-scoped override. That is how the tests simulate the Setup checkbox, and
   how a batch or data-load job would skip automation for its own run.
2. **These records deploy between orgs.** A record left `true` in a sandbox will ride a deploy
   into production and silently disable a trigger. All four ship `false`. Flip them in Setup,
   never in the repo. This risk was raised and accepted.

There was previously a `Trigger_Bypass__c` hierarchy custom setting. It is **fully removed** from
both org and repo — `Trigger_Bypass__c` and `Trigger_Bypass__mdt` cannot coexist, same developer
name.

### Tests

**29/29 passing.** Coverage: TriggerContext 96%, FacilityMapperTriggerHandler 96%,
HospitalAdmissionTriggerHandler 96%, VisitTriggerHandler 92%, all three triggers 100%.

Each handler test covers positive, negative, bypass, and a 200-record bulk case asserting
`Limits.getQueries()` and `Limits.getDmlStatements()` stay flat. That bulk assertion is the actual
ticket goal, so keep it.

---

## 4. Gotchas found the hard way — do not repeat these

**1. Never deploy `--source-dir force-app/main/default/flowDefinitions`.**
That directory holds 36 files carrying **prod's** active-version numbers (the phase-1 retrieve put
them there). Deploying the directory pushed all of them into lumDev and **activated three
SMS-sending flows** that had been inactive there, plus knocked
`Community_TF_On_Update_Status_Call_Outcome_Update_Patient` from Active to Obsolete.

Caught and fully reverted the same session. Always target flowDefinitions explicitly:
`--metadata FlowDefinition:<Name>`.

**2. `git checkout -- <dir>` reverts your own work too.** Restoring 5 wrongly-deleted files also
reverted 2 intentional conversion flowDefinitions. Check `git status` after any bulk checkout.

**3. The bypass tests failing did not mean the bypass was broken.** It meant the **flows were
still active** — flow and trigger both ran. Corollary: the other tests passing while both were
active was accidentally proving flow/Apex parity.

**4. A transaction-scoped recursion guard is wrong for cross-object handlers.** The first version
claimed record ids for the whole transaction, so an insert-then-update in one transaction silently
dropped the second pass. Guard removed from Visit and FacilityMapper (they write other objects and
cannot self-recurse); retained on HospitalAdmission, which does update its own record.

**5. `sf` CLI hygiene.** Set `export SF_AUTOUPDATE_DISABLE=true` and pipe through
`sed -n '/^[[{]/,$p'` before `jq`, or the update banner breaks the parse. Single-quote any org
alias containing `&`.

---

## 5. Repo state — 81 uncommitted paths

Branch `main`, HEAD `d4666d9`. **Do not commit without asking James.** CLAUDE.md forbids merging
to main automatically, and he has asked for commit approval on client repos.

**Modified (tracked), 18** — 15 flow files overwritten by the prod baseline, 2 conversion
flowDefinitions set to `activeVersionNumber 0`, plus `BulkOpportunityCreatorController.cls` which
was **already dirty before this session and is unrelated to LMNA-580**.

**Untracked, 63** — 24 new flows from the prod retrieve, 16 class files (8 classes + metas), 6
trigger files, 4 CMDT records, the `Trigger_Bypass__mdt` object dir, 1 flowDefinition, and
10 `Patient__c` field dirs that were **already untracked before this session**.

Suggested commit split, per the spec:

1. `chore(flows): sync flow metadata from production` — the phase-1 baseline, on its own
2. The trigger foundation + 3 conversions + their flowDefinition deactivations
3. Leave `BulkOpportunityCreatorController.cls` and the `Patient__c` field dirs alone — not ours

---

## 6. What is blocked, and on whom

| Item | Blocked on |
|---|---|
| `Flow` (Visit) conversion — 4th one, **already written** | `Latest_Visit_Provider__c` missing in lumDev. Field exists in prod; copy the definition and deploy it. No person needed. |
| `Community_Episode__c` — 2 flows | Chana, Open Q3: is the object live or abandoned? |
| `Admission_Discharge__c` — 3 flows | Chana, Open Q7. Spec says resolve the three `Discharge_TF_Send_SMS` defects **before** porting. |
| `Patient__c` — 5 flows | Chana Q4/Q10/Q11/Q12 **and** phase 4 steps 12/14/15/16/17. `Patient__c` already has 3 uncoordinated triggers and no characterization suite. Do not port into it yet. |

### Separate from LMNA-580

**Open Chayim questions on LMNA-581** (readmission daily report — different ticket):
transport decision email-vs-portal; the Monday-covers-Fri–Sun rule that is in code but not the
ticket; Kevin's email (`Internal_CC_Email__c` is blank); confirm the six report columns.
Plus two blockers he may not know: **294 TCM facilities, 1 has `Admin_Email__c`, 0 have
`DON_Email__c`**, and the current build emails patient names as an unencrypted CSV.

**Finding 11, raise separately and promptly:** `customMetadata/API_Configration.Sandbox_Config`
and `.Production_Config` both contain the **same plaintext ThoroughCare API key** and both point
at the production URL. Live credential committed to the repo; sandbox is not isolated from prod.
James's decision: describe it and name the files, never quote the key.

---

## 7. Immediate next steps

1. **Update the spec status block** — `.docs/specs/lmna-580-flow-to-apex-spec-2026-09-01.md` was
   updated mid-session and still describes the bypass as a *custom setting*. It is now custom
   metadata. Also line 336 lists `Trigger_Bypass__mdt` while line 265 says custom setting — that
   contradiction is now resolved in favour of `__mdt`, so fix line 265.
2. **Decide on committing** the phase-1 baseline.
3. **Optional, unblocked:** deploy `Latest_Visit_Provider__c` to lumDev and finish the 4th
   conversion. Takes it to 4 of 14 with no questions answered.
4. Everything else waits on Chana or on phase 4.

### Verification commands

```bash
export SF_AUTOUPDATE_DISABLE=true

# tests
sf apex run test --target-org 'lumDev' --wait 20 --result-format human \
  --class-names TriggerContextTest --class-names FacilityMapperTriggerHandlerTest \
  --class-names HospitalAdmissionTriggerHandlerTest --class-names VisitTriggerHandlerTest

# the 3 converted flows should be inactive, nothing else changed
sf data query --target-org 'lumDev' \
  --query "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE IsActive = true AND TriggerType != null"
# expect 47 active triggered flows

# bypass records, all false
sf data query --target-org 'lumDev' \
  --query "SELECT DeveloperName, Is_Bypassed__c FROM Trigger_Bypass__mdt"
```

---

## 8. Unrelated housekeeping from this session

James removed several Claude plugins. `settings.json` and `installed_plugins.json` are clean —
superpowers, feature-dev, skill-creator, ponytail and github are gone, and the `ensure-plugins.sh`
hook no longer reinstalls ponytail. Roughly 12 MB of dead plugin cache is still on disk under
`~/.claude/plugins/cache/`; an `rm` was declined. Harmless, purely cosmetic.

A harness review also ran. Output: `.docs/harness-review-plan-mode-2026-09-01.html`. Headline:
plan-mode adoption was zero across 2,111 sessions before 2026-09-01, and the real cost driver is
session length — the top 20 sessions hold 53% of all turns.
