# LMNA-580 — Flow to Apex, TCM first

> Canonical copy: `.docs/specs/lmna-580-flow-to-apex-spec-2026-09-01.md` in the lumDev repo.
> The `~/.claude/plans/` file is only the plan-mode approval copy.

## Status

Update this block at every phase transition. It is the single answer to "where are we".

| Phase | State | Notes |
|---|---|---|
| Spec written | **done** 2026-09-01 | audit run against lumDev + lumProd, read-only |
| Jira comment posted | not started | needs James's approval of exact text |
| 1. Establish the baseline | **done (uncommitted)** 2026-09-02 | prod Flow metadata retrieved into repo; 3-way diff below. Baseline commit still needs approval |
| 2. Reconcile dev to prod | not started | blocked on Chana on ~6 flows |
| 3. Re-audit | not started | blocked on phase 2 |
| 4. Trigger foundation | **partly done** 2026-09-02 | step 13 (bypass infra) shipped to lumDev. Steps 12/14/15/16/17 are Patient/ThoroughCare and stay blocked |
| 5. Convert the 12 TCM flows | **12 of 12 done** 2026-09-02 | All twelve are Apex in lumDev, all twelve flows deactivated with versions retained, 93 tests green plus live in-org QA. Count corrected from 14: the two `_TC_` flows are ThoroughCare integration, not TCM |
| 6. Deferred items | not started | separate tickets |

### Phase 1 findings (2026-09-02, measured)

- lumProd 56 active triggered flows, lumDev 50, repo 40 before retrieve / 64 after.
- **8 prod-only** active triggered flows, not the 4 the spec predicted: 5 RecordAfterSave
  (the 4 named, plus `Patient_TF_Send_SMS_When_Appointment_Is_Scheduled`) and 3 Scheduled.
- **18 flows drift on version**, in both directions. Prod ahead on 16, dev ahead on 2.
- 26 flows active in prod were absent from the repo entirely.
- No dev-ahead work was overwritten by the prod retrieve.

### Corrections to this spec, measured against both orgs 2026-09-02

Four findings below were wrong. All four came from reading metadata only - flow bodies,
field definitions, the DLRS rollup config - without querying a single record. Queries
against lumProd overturned them.

**Finding 4 was wrong. `Community_Episode__c` is live, not dormant.** 34,779 records in
production, every one created in the last 90 days, newest created and modified the same
afternoon this was checked. The original reasoning - no tab, no trigger, no Apex
reference, no start or end date, no CPT field - was all true and all irrelevant. The
object is flow-maintained, and the flows about to be converted are what maintain it. "Not
referenced by code" was mistaken for "not used". Both Community Episode flows are
converted rather than deactivated.

**Finding 8 was wrong. The 48-hour counter is not dead.** `Count_of_Calls__c` is non-zero
on 39,117 patients, 24,223 of them modified in the last seven days. The DLRS rollup named
`Count_of_Calls` is genuinely inactive in production as well as dev, but it was never the
writer. Two flows write the field: `Community_TF_On_Update_Status_Call_Outcome_Update_Patient`
sets it and `Intake_Form_2_SF_Create_Form_2` increments it. The mistake was checking the
rollup, finding it disabled, and stopping instead of grepping for the field.

**There is no Patient / Community Episode write cycle.** Only one flow writes the episode
copy of `Last_SMS_Sent_Date__c`, in one direction. Patient is the source of truth: 8,411
patients carry the field against 393 episodes, five flows read or write the Patient field
against one that touches the episode, and the formula driving the four-day SMS cadence,
`Patient__c.X4_Days_After_Last_SMS__c`, reads the Patient field. Nothing reads the episode
copy at all. The conversion is a one-way mirror and needs no ownership decision.

**`Patient_TF_On_Update_Set_Community_Status_For_Discharge` does not create a task.** Its
production body has two decisions and one `recordUpdates`, no `recordCreates` anywhere.
`Call30Days` is a formula, `today() - Latest_Call_Outcome__c > 30`, not a record. The
hardcoded `OwnerId` is set on the **patient**, not on a task, which makes this a patient
reclaim mechanism: 30 days with no call outcome and the patient is taken from whoever held
it, reset to `New` and handed to the administrator account. It fires constantly - 47,610
patients all time, 1,767 in the last seven days. It is also `RecordBeforeSave` in
production, so it starts no second save pass and is not a phase 4 dependency.

### Version drift matters, and the repo is trustworthy while the version stamps are not

All seven then-unconverted flow bodies in the repo are byte-identical to production's
active version, verified by a fresh retrieve and diff. A `Flow` retrieve returns the
active version body, so the repo can be read with confidence.

The `activeVersionNumber` values in the repo's `flowDefinitions/` files are stale and
disagree with production by up to three versions. They are separate metadata that the
retrieve did not refresh. Read the flow body, never the version stamp.

Three of the seven differ between production and dev, so conversions target production:

| Flow | lumProd | lumDev |
|---|---|---|
| `Discharge_TF_Send_SMS` | has the `Type__c = "Discharge"` gate and correct parentheses | has neither |
| `Patient_TF_On_Update_Update_Count_Within_48_Hours` | `RecordBeforeSave` | `RecordAfterSave` |
| `Patient_TF_On_Update_Set_Community_Status_For_Discharge` | Active, before-save, stamps the timestamp | Obsolete, after-save, no timestamp |

**One of the three `Discharge_TF_Send_SMS` defects does not exist in production.** The
`dischargedHome` formula is correct there: `NOT(OR(funeral, nursing, hospice))` is a
proper third argument to the outer `AND`. The broken version, with the `NOT` nested inside
the `OR`, is dev only. That defect is withdrawn. The other two stand and are live in
production: `textLast2Days` is inverted, and `Deleware` is misspelled.

### Round robin assignment is deliberately dead, not broken

Five independent measurements, so `TF_Patient_Discharge_Home_Assign_To_IC` is converted as
what it does - setting the community status - and the assignment is not restored:

- the public group its `RoundRobin__c` config names, `TCM IC's`, does not exist in production
- `IndexOfLastUsed__c` has been frozen at 5 since 1 October 2024, and the class writes it
  on every assignment under a `FOR UPDATE` lock
- no flow anywhere calls the invocable, across all 64 flows including the prod retrieve
- 248,333 of 335,205 patients are owned by the administrator account, and 30,020 of the
  last 30 days' patients against roughly 1,258 spread over ten named staff
- the flow retains only a vestigial `patientIds` variable matching
  `RoundRobinAssignmentWithPublicGroup.RoundRobinRequest.patientIds`

Assignment moved to being human-driven in `Intake_Form_2_SF_Create_Form_2`, which sets
`OwnerId` to the running user and offers a screen picklist of active users on the Intake
Coordinator and Intake Coordinator Manager profiles.

### Two findings for Chana that are not LMNA-580 work

- `Patient__c.Latest_Community_Episode__c` has **zero `FieldPermissions` records** in
  production. No profile, no permission set, not System Administrator. Flows write it in
  system mode so the value lands on all 34,779 episodes, but it is invisible to every
  user, report, list view and SOQL query. Same trap as `Latest_Visit_Provider__c`.
- `Patient__c.X4_Days_After_Last_SMS__c` uses `DATEVALUE()` on a Datetime, which converts
  in GMT. For a US org that moves the day boundary by up to five hours, so the four-day
  SMS gate fires a day early or late for evening timestamps.

### Phase 5 blocker found during conversion

`Patient__c.Latest_Visit_Provider__c` **exists in lumProd but not in lumDev**. The flow `Flow`
(Visit - Fill Latest Visit Provider) writes it, which is why that flow is prod-only. Its
conversion is written but cannot deploy to lumDev until the field ships in phase 2. lumDev is
also missing `Missing_TC_Provider_For_Enrollment__c`, `Provider_Added_to_Tc_Date__c`,
`No_TC_Provider_Datetime__c` and `No_Community_TC_Provider_Datetime__c`.

**As of 2026-09-02, lumDev (partial sandbox) has been changed under an explicit one-time override
from James.** Deployed there: `Trigger_Bypass__c` + 4 fields, `TriggerContext`, and the trigger,
handler and test for Facility_Mapper, Hospital_Admission and Visit. Three flows deactivated
(activeVersionNumber 0), versions retained so rollback is a checkbox. Nothing committed to the
repo yet, and lumProd is untouched.

## Where the conversion actually stands, 2026-09-02

All twelve TCM flows are Apex in lumDev. Every replaced flow is deactivated with its
version retained, so rollback per flow is re-activating it and ticking the action's
bypass. 93 tests green across the conversion and permission suites; full local run 609
pass / 34 fail with every failure in five classes that were already failing before this
work (`BulkFacilityCreatorControllerTest`, `BulkOpportunityCreatorControllerTest`,
`PatientIntakeWorklistControllerTest`, `ThoroughCareEmailQueueableTest`,
`FacilityTriggerHandlerTest` - the Patient one proved pre-existing by reverting
`PatientTrigger` and re-running).

lumDev was synced to production first: prod's `Discharge_TF_Send_SMS` v10 and
`Patient_TF_On_Update_Set_Community_Status_For_Discharge` v9 were deployed into dev, so
the conversions target what production actually runs.

| Object | Action class | Flow replaced |
|---|---|---|
| `Facility_Mapper__c` | `FacilityMapperDeleteFalseLeaks` | `Facility_Mapper_TF_Delete_False_Leaked_Admissions` |
| `Hospital_Admission__c` | `HospitalAdmissionFlagPriorDischarge` | `Hospital_Admissions_TF_On_C_U_Look_For_Prior_NH_Discharge_Home` |
| `Visit__c` | `VisitFillPatientVisitDates` | `Visit_TF_On_Create_Visit_Fill_Visit_Date_Fields_on_Patient` |
| `Visit__c` | `VisitSetLatestVisitProvider` | `Flow` (Visit - Fill Latest Visit Provider) |
| `Admission_Discharge__c` | `AdmissionDischargeSetLatest` | `Admission_Discharge_TF_On_Create_Set_Latest_A_D_on_Patient` |
| `Admission_Discharge__c` | `AdmissionDischargeCreateEpisode` | `Admission_Discharge_TF_On_Create_Create_Community_Episode` |
| `Community_Episode__c` | `CommunityEpisodeSetLatestOnPatient` | `Community_Episode_TF_On_Create_Set_Latest_On_Patient` |
| `Patient__c` | `PatientSyncLastSmsToEpisode` | `Patient_TF_On_Update_Last_SMS_Update_Latest_Episode` |
| `Patient__c` | `PatientCountCallsWithin48Hours` | `Patient_TF_On_Update_Update_Count_Within_48_Hours` |
| `Patient__c` | `PatientDischargeHomeSetStatusNew` | `TF_Patient_Discharge_Home_Assign_To_IC` |
| `Patient__c` | `PatientSetStatusOnNewDischarge` | `Patient_TF_On_Update_Set_Community_Status_For_Discharge` (before update) |
| `Admission_Discharge__c` | `DischargeSendSms` + `DischargeSendSmsQueueable` | `Discharge_TF_Send_SMS` |

### The ticket's own failure is now a passing test

`AdmissionDischargeCreateEpisodeTest.sixtyDischargesForOnePatientDoNotHitTheDuplicateLimit`
inserts sixty discharges for one patient in a single save. Under the flow that threw
`DUPLICATE_VALUE`, "Maximum number of duplicate updates in one batch (12 allowed)", and
rolled the whole insert back, because the flow updated the patient once per record.
Sixty is five times that ceiling. The Apex collapses the patient writes to one row and
the insert succeeds.

### System mode is a deliberate decision, tested, not an omission

Record-triggered flows run in system context. The first cut of these actions used
`with sharing`, `WITH USER_MODE` and `Security.stripInaccessible`, which silently drops
automated writes for lower-privilege profiles - measured concretely: production profile
"Lumina Manager No Edit Access" can create discharges but has no edit on Patient__c, and
`Patient__c.Latest_Community_Episode__c` carries zero FieldPermissions for anyone, so
stripInaccessible would discard that write for every user in the org, System
Administrator included. A silently dropped TCM timestamp is a billing defect nobody
sees. All twelve actions now run `without sharing` with plain SOQL and DML, each with
the rationale in its header. `TcmAutomationPermissionsTest` runs the whole discharge
cascade as a Minimum Access user and asserts every write lands, including the zero-FLS
lookup - reintroduce user-mode enforcement anywhere and that class fails.

User-facing controllers (`FacilityEditorController`, the worklist) keep user-mode
enforcement; the system-mode call is for trigger automation only.

### The SMS port

`DischargeSendSms` decides synchronously in the trigger, exactly where the flow decided;
`DischargeSendSmsQueueable` delivers, because Apex cannot call out from a trigger's
transaction. The Twilio entry point is the same invocable the flow called,
`TwilioSF.TwilioSendSMS.sendSMSToNumber(List<SmsDetail>)`, one detail per message. The
stamp on `Last_SMS_Sent_Date__c` lands only after a send that did not throw, matching
the flow's connector order, and a send failure is rethrown after stamping the successes
so the job shows failed in Apex Jobs instead of vanishing into a debug log.

**One intended behaviour change, needs sign-off: delivery is asynchronous.** The
message goes out seconds after the save instead of during it. Everything else is
byte-faithful, including two reproduced defects: the inverted recency gate (patients
texted in the last three days get texted again; patients quiet for longer are skipped)
and the `Deleware` misspelling.

**The state-list defects are milder than first reported.** `Patient__c.Facility_State__c`
is `TEXT(Facility__r.Address__StateCode__s)`, which only ever yields two-letter codes.
Every spelled-out name in the flow's state lists - 'New Jersey', 'Maryland',
'Pennsylvania', 'Illinois' and the misspelled 'Deleware' - is a branch that can never
match. So the misspelling costs nothing today; the whole spelled-out tier is dead
weight, preserved in the port for fidelity and worth deleting in both places once
parity is confirmed.

### The reclaim port

`PatientSetStatusOnNewDischarge` is a before-update action, matching prod's
`RecordBeforeSave`: in-place field writes, no DML, no recursion. The flow's entry
criteria is IsChanged on a formula field, which Apex before-triggers cannot read
freshly, so the new value is derived the way the formula derives it - `Census_Date__c`
through the `Latest_Discharge__c` lookup, converted with `formatGmt` because DATEVALUE
works in GMT - and compared against Trigger.old's committed formula value.

### Live QA, run in the org on 2026-09-02, records created and deleted

- Single discharge for a stale-contact patient: full cascade correct in one save -
  status New, outcome cleared, owner reclaimed to the real production owner, timestamp,
  `Latest_Discharge__c`, episode created and linked on the patient. SMS correctly not
  sent for a non-home discharge. ThoroughCare triggers evaluated and correctly idle.
- **Twenty discharges for one patient in a single insert succeeded.** That exact
  operation is what threw `DUPLICATE_VALUE (12 allowed)` under the flows and rolled the
  whole batch back - the failure LMNA-580 was raised for.
- 48-hour counter increments live; the SMS mirror lands on the latest episode live.
- Found while testing: `Latest_Community_Episode__c` was invisible to anonymous Apex in
  lumDev too - the zero-FLS condition exists in both orgs. Admin-profile FLS was granted
  in lumDev so the value can be verified; production needs the same grant, plus a
  decision on which other profiles should see it.

### Dead code removed and dead code flagged

Deleted from repo and lumDev (orphaned by the conversion, recoverable from git):
`FacilityMapperTriggerHandler`, `HospitalAdmissionTriggerHandler`, `VisitTriggerHandler`
and their three test classes.

Flagged, not removed, because they are phase 4 / phase 6 scope: `SendPatientIdToThoroughCare`
(only caller is an Obsolete flow), `roundRobinAssigner` + `roundRobinTests` (only caller
is the Obsolete Testing_Round_Robin flow), `RoundRobinAssignmentWithPublicGroup` +
its test (no caller anywhere; the public group it needs no longer exists).

### The CMDT insert blocker is solved - it was a 40-character limit all along

Metadata deploys of new `Trigger_Action__mdt` / `sObject_Trigger_Setting__mdt` records
failed for two days with `UNKNOWN_EXCEPTION` and a support ErrorId. The Apex Metadata
API (`Metadata.Operations.enqueueDeployment`) surfaced the real error the deploy path
was swallowing: **CustomMetadata record fullName and MasterLabel are capped at 40
characters**, and several record names and labels exceeded it. Shortened the offenders
(`Facility_Mapper_Delete_False_Leaks`, `Hospital_Admission_Flag_Prior_Insert/_Update`,
plus several labels), inserted everything through the Apex Metadata API, and the org now
holds all 16 `Trigger_Action__mdt`, 6 `sObject_Trigger_Setting__mdt` and 6
`Trigger_Bypass__mdt` records.

Two facts worth keeping: record inserts through the *metadata deploy* path still return
the useless UNKNOWN_EXCEPTION in this org even for valid records, while the Apex path
both works and reports real errors - use the Apex path (`scratchpad md_settings/`
`md_actions` pattern) for prod too. And destructive deploys of CMDT records work fine.

**All six triggers now run `new MetadataTriggerHandler().run();`** behind the
`TriggerContext` incident lever. Per-action activate/deactivate from Setup - the
flow-like switching the ticket asked for - is live and verified: 93 conversion and
permission tests green through the framework, plus a live in-org cascade smoke test
(created and deleted). Ticking Bypass Execution on an action record now genuinely
switches that behaviour off, no deploy.

### The reclaim owner is no longer hardcoded in two places

`TcmSettings.reclaimOwnerId()` holds the single Id both flows hardcoded, resolves it
against `User` and returns null when the user is absent or inactive. Callers treat null as
"leave the owner alone", because the alternative is `INVALID_CROSS_REFERENCE_KEY` rolling
back a save that includes the episode the patient needs. This should become a Custom
Metadata setting; it is a constant only because of the insert blocker above.

## Expansion, 2026-09-03: Chayim's "convert them all"

Chayim approved converting the remaining Patient flows and the name-formatting flows.
Fourteen flows collapse into ten actions, same pattern as the twelve TCM conversions.

| Action | Contexts | Replaces |
|---|---|---|
| `PatientSetName` | BI, BU | `Patient_TF_On_Create_Update_Name`, `Patient_TF_On_Update_Update_Name`, `Patient_TF_On_Update_of_First_or_Last_Name_Update_Name` |
| `CommunityProviderSetName` | BI, BU | `Community_Provider_TF_On_Create_Update_Name`, `Community_Provider_TF_On_Update_Update_Name` |
| `ProviderSetName` | BI | `Provider_TF_On_Create_Create_Provider_Name` |
| `PatientInsuranceSetName` | BI | `Patient_Insurance_TF_On_Create_Update_Name` |
| `ReportUserFacilitySetName` | BI, BU | `Report_User_Facility_TF_on_C_U_Update_Name` |
| `ReportUserRegionSetName` | BI, BU | `Report_User_Region_TF_On_C_U_Update_Name` |
| `CommunityEpisodeSetName` | BI, BU | `Community_Episode_TF_On_C_U_Update_Name` |
| `PatientSetConsentDatetime` | BU | `Patient_TF_On_Update_Of_Consent_Set_DateTime`, `Patient_TF_On_update_of_consent_status_update_consent_datetime` |
| `PatientSetProgramsOnEligible` | BU | `Patient_TF_On_Update_To_Program_Eligible_Update_Based_on_Facility` |
| `PatientSetStateOnClosedWon` | BU | `Patient_TF_On_Update_Community_Status_Closed_Won_Check_State` |

New triggers: CommunityProvider, Provider, PatientInsurance, ReportUserFacility,
ReportUserRegion. CommunityEpisodeTrigger gains before insert / before update.
PatientTrigger already declares every needed context.

### Expansion status: shipped to lumDev 2026-09-03

Ten actions deployed, five new triggers (CommunityProvider, Provider, PatientInsurance,
ReportUserFacility, ReportUserRegion), CommunityEpisodeTrigger extended with before
contexts. Fifteen new Trigger_Action__mdt records, five settings and five bypass records
inserted through the Apex Metadata API. All fourteen replaced flows deactivated,
versions retained.

Verified: 17 new tests green (RecordNamingTest, PatientLifecycleFieldsTest), full local
run 627 pass / 34 fail with the failure set byte-identical to the pre-conversion
baseline (the same five pre-existing classes), and a live in-org smoke of the naming,
consent and provider paths, cleaned up after.

Running totals: 26 flows converted into 22 Apex actions across 11 objects, all
switchable per action from Setup. Still flows on purpose:
`Patient_TF_On_Update_Community_Status_Update_Community_Status_Updated_Date_Time`
(phase 4, ThoroughCare-load-bearing) and the scheduled messaging flows (not
record-triggered; separate conversion shape).

### Five judgement calls in this expansion

1. **The duplicate Patient name pair becomes one truncating action.** The two update
   flows had identical entry criteria; one truncated to 80 and one did not, so a long
   name made one of them throw STRING_TOO_LONG with undefined ordering. The surviving
   behaviour is LEFT 80, the version that cannot fail and the one the create flow
   always used.
2. **After-save self-writes become before-save.** The name and consent flows spent an
   extra save pass each to write fields on their own record. Before-save removes that
   pass, which also stops it re-firing the rest of the Patient automation - a real but
   benign change, and the direction production already took with its own Patient
   self-write flows.
3. **The consent pair cannot actually collide.** One fires when Consent_Status__c is
   cleared to blank (and stamps the datetime then - odd, but preserved); the other
   fires when a first real non-Pending status arrives and no datetime exists. Mutually
   exclusive entry criteria. Converted as one action with both branches, so the
   ordering question is closed permanently either way.
4. **`Patient_TF_On_Update_Community_Status_Update_Community_Status_Updated_Date_Time`
   is NOT converted.** Its unconditional after-save self-update is the second save pass
   the ThoroughCare community callout depends on (finding 6). It converts in phase 4,
   after the characterization tests, or community patients silently stop reaching the
   vendor.
5. **The five messaging flows are not in this batch.** They are scheduled flows or
   inactive in this sandbox - not record-triggered, so they cannot be trigger actions.
   Scheduled Apex is a separate conversion shape and a separate piece of work.

## Context

Chana raised LMNA-580 on 2026-08-17: *"There are many flows that get triggered on discharge,
hospital admissions, and other TCM work. Use claude to identify active flows, and move them into
apex. Limits in flows have caused them to fail, so we need to flexibility of apex."*

TCM is Transitional Care Management, a Medicare-reimbursable service (CPT 99495/99496) covering the
30 days after an inpatient discharge. It requires interactive contact within 2 business days,
non-face-to-face services across the period, and a face-to-face visit within 7 or 14 days. Miss a
window and the claim is not billable, so the timestamps these flows maintain are revenue logic.

An audit on 2026-09-01 against `lumDev`, `lumProd` and the repo found the ticket cannot be executed
as written. Three separate problems sit in front of the conversion, and the conversion itself is
smaller than the ticket implies.

Intended outcome: TCM discharge/admission automation running in Apex, on a codebase where dev, prod
and the repo agree, without regressing a live billing path or the ThoroughCare integration.

## Findings that shape the plan

### 1. The obvious fix is already live in prod

Nine `Patient__c` flows that update the triggering record are `RecordBeforeSave` in prod and
`RecordAfterSave` in dev, each exactly one version ahead in prod. Someone already did the
after-save-to-before-save optimisation in production and it never came back to the sandbox.

### 2. Drift runs both directions; nothing is authoritative

| | Definitions | Active | Active triggered |
|---|---|---|---|
| Repo | 40 files | — | — |
| `lumDev` | 127 | 110 | 50 |
| `lumProd` | 138 | 118 | 56 |

- Prod ahead: the 9 Patient flows, `Discharge_TF_Send_SMS` (v10/v9), `Visit_TF_On_Create` (v4/v3), `Twilio_Message` (v8/v4), `Intake_Form_2` (v51/v49)
- Dev ahead: `Facility_TF_On_Update_Set_Rollout_Status` (**v4/v1**), `Facility_SF_Send_Document` (v9/v3), `Opportunity_TF_On_Closed_Won` (v2/v1), `Lead_TF_On_Create` (v2/v1)
- Dev only: `Community_Episode_BS_On_Update_Clear_Won_Date`, `Facility_TF_On_Create_Set_CX_Lead`
- Prod only, 8 triggered, incl. `Patient_TF_Patient_TC_Update`, `Patient_TC_Update_Missing_Provider_for_Enrollment`, `Update_Fe_Role`, and a Visit flow whose **ApiName is literally `Flow`**

The repo is not a third opinion, it is a snapshot: all 40 flow files landed in the initial commit
(`373e28a`, 2026-01-12) and no commit has touched `flows/` since. Two concrete proofs the repo is
stale rather than merely behind: `Patient__c.Latest_Community_Episode__c` is referenced by a live
org flow but **does not exist in the repo at all**, and
`Community_TF_On_Update_Status_Call_Outcome_Update_Patient` is `Draft` in the repo but **Active in
both orgs**.

### 3. Only 14 of prod's 56 triggered flows are TCM

The rest: messaging 10, name concatenation 10, enrollment/eligibility 8, Facility onboarding 8,
sales 3, misc 3. "Turn every flow into apex" is three unrelated efforts under one ticket number.

### 4. `Community_Episode__c` is dormant, not the TCM episode record

It has 28 fields that near-exactly mirror a subset of `Patient__c`, but **no tab, no trigger, no
Apex reference anywhere, no start/end date, no CPT or billing field**. It reads as an abandoned or
not-yet-cut-over refactor. Real TCM state is denormalised onto `Patient__c`. Do not build on this
object without confirming its intent.

### 5. `Patient__c` already has three uncoordinated Apex triggers

Which the repo's own `.claude/steering/structure.md:26` forbids ("Single trigger per object"):

- `PatientTrigger` (before insert/update) → `PatientTriggerHandler.setLocalAppointmentTimes`
- `PatientThoroughcareCreateTrigger` (after insert/update) → ThoroughCare callout, bulkified
- `ThoroughcareTriggerController` (after update) → older, **overlapping** ThoroughCare callout

Both ThoroughCare triggers call `@future` **inside a for loop**. Two live bombs, not one style
violation: the limit is 50 async calls per transaction, so a 200-row load with 60 qualifying
patients throws `LimitException` and **the whole batch fails**; and `@future` cannot be called from
Batch Apex at all, so any batch touching Patient throws `AsyncException`. Violates
`.claude/steering/tech.md:32`.

Two live generations, not three. `SendPatientIdToThoroughCare` is dead — its only caller is
`Patient_TF_On_Update_Community_Status_Send_Patient_To_Thorough_Care`, which is `Obsolete`.

### 6. Recursion is load-bearing for the ThoroughCare integration

**This is the finding that most changes the plan.** A naive recursion guard silently disables
community patient creation in ThoroughCare, with no error and no log.

`Won_Date_Time__c` is not set by the user. It is stamped by
`Patient_TF_On_Update_Community_Status_Update_Community_Status_Updated_Date_Time` (Active,
after-save, unconditional `$Record` update). So one user edit produces **two save passes and two
callouts to two different systems**:

| | Pass 1, user DML | flow re-save | Pass 2, flow DML |
|---|---|---|---|
| `Won_Date_Time__c` | null | → `NOW()` | populated |
| Trigger 2, community | `null >= 2024-10-23` is false → no send | | floor passes → **POST `/tc/create-comm-patient`** |
| Trigger 3, legacy | status changed → **POST Heroku** | | status unchanged → no send |

A `static Boolean hasRun` or a single `Set<Id> processed` suppresses pass 2. Community patients
then stop appearing in ThoroughCare and nobody finds out, because
`PatientThoroughcareCreateCallout` swallows every exception into `System.debug`.

**Triggers 2 and 3 are also not redundant.** Trigger 3 is the legacy/backfill path and fires in
three states trigger 2 does not: when `Date_Added_to_Community_Thoroughcare__c` is populated but
the ID is null, when `Won_Date_Time__c` pre-dates the 2024-10-23 floor, and on pass 1 of every
normal transition. Deleting it drops every pre-cutoff patient.

### 7. No trigger framework, no recursion guard, no bypass switch

Nowhere in the 34 classes. Given finding 6, the guard must be keyed on **what was sent**, per send
type, not on "have I seen this record".

### 8. Some of this automation may already be dead

`Patient_TF_On_Update_Update_Count_Within_48_Hours` fires on `Count_of_Calls__c IsChanged`. The only
automated writer of that field is the DLRS rollup `Count_of_Calls`, which has
**`dlrs__Active__c = false`**. Either something else writes it in the org, or the 48-hour TCM
counter has been silently dead. This must be checked before it is converted.

Similarly `TF_Patient_Discharge_Home_Assign_To_IC` no longer assigns an Intake Coordinator. Its only
action is setting `Community_Status__c = 'New'`. It still carries a vestigial `patientIds` input
variable matching `RoundRobinRequest.patientIds`, the fingerprint of an invocable that was removed.
The flow name is a lie about its behaviour.

### 9. Three defects to decide on, not inherit silently

In `Discharge_TF_Send_SMS`:
- the `dischargedHome` formula puts `NOT(OR(funeral, nursing, hospice))` **inside** the outer `OR`, so a blank or unrecognised `To_From_Type__c` evaluates TRUE
- `textLast2Days` is inverted relative to its use: patients texted in the last 3 days get texted again, those texted longer ago get skipped
- `Deleware` is misspelled, so Delaware-spelled-out records never match the state matrix

A port is the moment these either get fixed deliberately or carried forward deliberately. Silently
reproducing them in Apex is the one unacceptable option.

### 10. Loops are clean, with one caveat

No flow performs DML or SOQL inside a loop.
`Facility_Mapper_TF_Delete_False_Leaked_Admissions` collects and deletes once. However it evaluates
**cross-object formulas per iteration** (`Facility__r.Parent_Company__r.Name`), which is the most
plausible remaining governor-limit candidate and the strongest single conversion case.

### 11. Unrelated, but found and must be raised

`customMetadata/API_Configration.Sandbox_Config.md-meta.xml` and `.Production_Config.md-meta.xml`
contain **the same plaintext ThoroughCare API key**, and both point at the production URL
`https://app.lumina-be.com`. A live credential is committed to the repo and sandbox is not isolated
from production. This is outside LMNA-580 and should be raised separately and promptly.

## Decisions taken

- One ticket, phased. LMNA-580 keeps its number; reconciliation becomes phase 1.
- Per-flow review on drift. Prod wins by default; the ~6 dev-ahead flows get reviewed individually,
  since the Facility rollout work looks like real unshipped effort rather than drift.
- The 10 name-concatenation flows are out of scope. Note as debt, separate ticket.
- Pulling prod metadata down is approved. Deploying into the partial sandbox needs one explicit
  confirmation at the time — see Open Questions.
- **The three `Discharge_TF_Send_SMS` defects are reproduced faithfully on port**, and raised as
  their own bugs. This keeps the conversion provably behaviour-preserving; a port that also changes
  output cannot be verified by parity testing.
- **The credential exposure is mentioned in LMNA-580.** The comment will describe the problem and
  name the files, but will not quote the key itself — a ticket comment is a wider surface than the
  credential should get, and the fix does not need the value restated.
- **The spec goes in the Jira comment in full**, as Jira markdown. No separate doc.

## Deliverable and Jira rules

A single comment on LMNA-580 containing the whole spec: findings, phased plan, and the open
questions for Chana. Jira markdown, no em-dashes.

Standing rules for anything that reaches Jira, on this project and every other:

1. **Draft in chat, wait for James's approval of that exact text, then post.** Never post first.
2. **Placement is a comment, or an append to the ticket description.** New discoveries found
   mid-work go up as a comment.
3. **Never reference local artifacts.** No repo paths, no `.docs/...`, no filenames, no branch
   names. Jira is read by PMs and client-side stakeholders with no access to the repo, so a path is
   noise at best. If a finding matters, write the finding out in full in the comment.

The audit HTML in `.docs/` is superseded by the prod findings. Regenerate or delete it rather than
leave it to mislead — and it is a working artifact, so it is never mentioned in the ticket.

## Plan

### Phase 1 — Establish the baseline (blocks everything)

1. Retrieve all Flow metadata from `lumProd` into a scratch project. Read-only on prod.
2. Retrieve all Flow metadata from `lumDev` into a second scratch project.
3. Three-way diff: prod vs dev vs repo, per flow, per version.
4. Read and classify the 4 prod-only flow bodies: `Patient_TF_Patient_TC_Update`,
   `Patient_TC_Update_Missing_Provider_for_Enrollment`, `Flow` (Visit — Fill Latest Visit Provider),
   `Update_Fe_Role`.
5. Commit prod's flow metadata as the new baseline, one commit,
   `chore(flows): sync flow metadata from production`.

**Exit:** repo matches prod for Flow metadata; diff list of dev-ahead flows ready for review.

### Phase 2 — Reconcile dev to prod

6. Walk the dev-ahead flows with Chana. Each: promote to prod, or discard.
7. Deploy the agreed baseline into `lumDev`.
8. Rename the `Flow` ApiName flow to something addressable. Production change, own approval, do not
   bundle.

**Exit:** dev, prod and repo agree. Flow retrieve yields an empty diff against both orgs.

### Phase 3 — Re-audit against the true baseline

9. Re-run the cascade analysis. Every number in `.docs/lumina-flow-debt-audit-2026-09-01.html` was
   measured against stale dev and is superseded.
10. Verify the dead-automation suspicions from finding 7: is `Count_of_Calls__c` written by anything
    in the org? Is IC assignment supposed to still happen?
11. Get a concrete failure case from Chana — a record Id, a date, or a flow error email. The ticket
    asserts limit failures; phase 6 should prove they are fixed, not assume it.

**Exit:** a defensible, evidenced list of what is actually still broken in prod.

### Phase 4 — Trigger foundation

Six commits, deliberately small, because finding 6 means a mistake here fails silently in
production. **The first commit contains zero production code.**

12. **Characterization tests only.** A recording `HttpCalloutMock` plus a table of
    (record state, DML) → (multiset of endpoints hit), written against the *unmodified* triggers.
    Cannot break anything by construction. Twelve cases, including the two-pass case, the
    trigger-3-only case that proves it is not redundant, and a bulk-200 case that should
    currently throw `LimitException`. Assert on the **sorted multiset** of endpoints, never the
    sequence — async execution order is not guaranteed and a sequence assert will flake.
    If any case disagrees with the prediction, stop. The model is wrong and the refactor is unsafe.
13. **Bypass infrastructure.** `Trigger_Bypass__c` hierarchy custom setting plus `TriggerBypass.cls`,
    checked at the top of all three existing triggers. Org default off, so behaviour-neutral. Ship
    and let it bake. Hierarchy custom setting rather than custom metadata for two reasons: it can be
    ticked in Setup in seconds during an incident where CMDT needs a deploy, and it supports a
    per-user override so a bulk data load can skip automation while real users do not.
    Get the incident lever in before the thing that might need it.
14. **Consolidate the three Patient triggers.** One `PatientTrigger` routing to
    `PatientTriggerHandler`, with ThoroughCare decision logic moved to a new
    `PatientThoroughcareService`. Old triggers set to `Inactive`, **not deleted**, so revert is a
    status flip. Still calls the existing `@future` — no async change in this commit.
    Characterization suite must pass identically.
15. **Queueable migration.** Separate commit, because it changes async semantics. Extract
    `buildRequest` and `fire` from the existing callout so the old `@future` and the new Queueable
    provably build byte-identical requests. Chunk at 10 per job — the binding limit is the 120s
    total callout time per transaction, not the 100-callout cap.
16. **Recursion guard.** Last of the behavioural changes. Three separate `Set<Id>` keyed per send
    type (community, standard, legacy), claimed via `Set.add()` as an atomic test-and-set. A single
    `processed` set or a boolean silently kills the pass-2 community send.
17. **Cleanup, two weeks later.** Delete the inactive triggers, the dead
    `SendPatientIdToThoroughCare`, and `TestPatientTriggerAndService` (it asserts nothing about the
    code under test). Unify the three different sandbox detections. Record the
    `[Object][Feature]Service` naming in `.claude/steering/structure.md`.

**Exit:** one trigger per object on Patient; ThoroughCare behaviour provably unchanged, evidenced by
the characterization suite plus 7 days of matching vendor-side request counts.

**Known intended delta:** where a user sets `Community_Status__c` and `Won_Date_Time__c` in the same
edit, today produces three callouts and the guard produces two. This is the only behaviour change.
Name it in the PR and get it signed off; do not let it ride silently.

**Rollback:** validate the revert package against production *before* the forward deploy and keep
the Quick Deploy Id — that turns a revert from a 30-minute test run into about two minutes. Note you
cannot deactivate a trigger from the Setup UI in production; it needs a metadata deploy. Do not put
"just untick Active" in the runbook.

**Prove one assumption first, it takes thirty seconds.** Run in the sandbox:
`DateTime d = null; System.debug(d >= DateTime.newInstanceGmt(2024,10,23,0,0,0));`
The entire two-pass analysis depends on this returning `false`. If it does not, re-plan.

### Phase 5 — Convert the TCM flows

15. Convert the 14 TCM flows, one object at a time, each with tests, each **deactivating not
    deleting** its flow. Ordered by blast radius, smallest first:
    - `Facility_Mapper__c` — 1 flow, self-contained, no Patient writes. Best first conversion.
    - `Hospital_Admission__c` — 1 flow, 30-day readmission detector
    - `Visit__c` — 2 flows. Note `dlrs_VisitTrigger` also fires here
    - `Community_Episode__c` — 2 flows, **pending the finding-4 decision**
    - `Admission_Discharge__c` — 3 flows, incl. the 4-update Patient setter and the SMS send
    - `Patient__c` — remaining TCM flows, folded into the consolidated handler
16. Resolve the three `Discharge_TF_Send_SMS` defects explicitly with Chana before porting it.
17. Break the `Patient__c` ↔ `Community_Episode__c` write cycle. Needs the ownership decision on
    `Last_SMS_Sent_Date__c` first.

**Exit:** TCM path is Apex end to end. Flows deactivated, so rollback is a checkbox.

### Phase 6 — Deferred, separate tickets

- 10 name-concatenation flows. Name is a plain Text field on all 7 objects, so a formula is not
  possible — these need Apex or consolidation, but not under a TCM ticket. Note the three Patient
  ones disagree: two use `LEFT(...,80)`, one does not and can exceed the 80-char limit.
- Messaging/outreach flows (10); Facility onboarding and sales (11).
- The two Payer Verification flows, both firing with no entry criteria.
- The duplicate pair `Patient_TF_On_Update_Update_Name` and
  `Patient_TF_On_Update_of_First_or_Last_Name_Update_Name` — identical entry criteria and body.
  Deactivating one is free and can be done at any time.
- The committed API key (finding 10). Raise now, do not wait for this ticket.

## Files

Created:
- `classes/TriggerContext.cls` — recursion guard + bypass check
- `objects/Trigger_Bypass__mdt/` — bypass custom metadata
- `triggers/{AdmissionDischarge,HospitalAdmission,CommunityEpisode,Visit,FacilityMapper}Trigger.trigger`
  each with a matching `[Object]TriggerHandler.cls` and `[Object]TriggerHandlerTest.cls`

Modified:
- `triggers/PatientTrigger.trigger` — absorbs the other two Patient triggers
- `classes/PatientTriggerHandler.cls` — gains TCM methods alongside `setLocalAppointmentTimes`
- `classes/PatientThoroughcareCreateCallout.cls` — `@future` to Queueable

Deleted:
- `triggers/PatientThoroughcareCreateTrigger.trigger`
- `triggers/ThoroughcareTriggerController.trigger`

Do not touch: `dlrs_*` triggers and tests. Managed-package generated, regenerated by the DLRS app,
and `.claude/steering/structure.md:106` forbids hand-editing them.

## Schema facts the implementation must respect

Getting these wrong is the most likely source of a failed deploy or a silent bug:

- `Patient__c.Latest_Discharge_Date__c` is a **formula** — not writable. Write `Latest_Discharge__c`
  (Lookup to `Admission_Discharge__c`) instead. Same for `Latest_Admission__c`.
- `TCM_Eligible__c`, `Had_TCM_Visit__c`, `Time_Passed_In_48_Hour_Window__c`,
  `Community_Status_Updated_Date__c`, `Discharged_Home__c` are all formulas. Read-only.
- The field is `Appointment_Time_In_Text__c` — capital `In`.
- The child relationship on `Payer_Verification__c` is misspelled `Payer_Verfications__r`.
- `Patient__c` validation rule `Community_Won_DOB_Gender`: setting
  `Community_Status__c = 'Closed Won'` requires `Date_of_Birth__c` and `Gender__c` populated.
- `Status__c`, `Consent_Status__c`, `Community_Status__c`, `Payer_Eligibility_Status__c` are
  **restricted** picklists. `First_Name__c`, `Last_Name__c`, `Status__c` are required.
- `Visit__c.Patient__c` is `deleteConstraint=Restrict`.
- No Master-Detail and no native rollups exist in the TCM object set. All rollups are DLRS.
- The 30-day, 48-hour, 2-day and 4-day TCM constants are hardcoded across field and flow formulas,
  with **known inconsistency**: `TCM_Eligible__c` uses `Discharge_Date__c` while
  `Time_Passed_In_48_Hour_Window__c` uses `Latest_Discharge__r.Census_Date__c`. They can disagree.

## Conventions to follow

From `.claude/steering/structure.md` and `tech.md`, plus observed practice:

- `public with sharing class [Object]TriggerHandler`, static methods,
  `(List<T> newRecords, Map<Id,T> oldMap)`, `null` for oldMap on insert
- Test class `[Class]Test`, `@isTest private class`, `@TestSetup static void setupTestData()`
- Mirror `OpportunityTriggerHandlerTest.cls` — positive, negative, skip, bulk, multiple-match
- Bulk tests at 200+ records with `Limits` assertions
- `Security.stripInaccessible()` before DML; bind variables in SOQL
- Queueable for callouts, never `@future` in a trigger
- Run `npm run prettier` before commit or `lint-staged` will reformat and dirty the diff
- No `TestDataFactory` exists. Do not build one unless it falls out naturally

## Verification

Per converted object:

1. `sf project deploy start --target-org <org> --dry-run` before any real deploy
2. `sf apex run test --target-org <org> --class-names <Handler>Test --result-format human`
3. **Bulk proof:** insert 200 records and assert `Limits.getDmlStatements()` and
   `Limits.getQueries()` stay flat as volume rises. This is the actual ticket goal, so assert it
4. **Parity proof:** with the flow still active, capture field values for a known record set;
   deactivate the flow, run the same operation through Apex, diff. Same in, same out
5. **Cycle proof:** update `Patient__c.Last_SMS_Sent_Date__c` and assert the save order does not
   re-enter, via `Limits.getDmlStatements()` before and after

Before any phase is called done:

6. `sf project retrieve start --target-org <org> --metadata Flow` returns an empty diff
7. Full org test run green, coverage at or above 75%

## Open questions

1. **Deploying into `lumDev`** — it is a partial sandbox (`stevenlum@clarktn.com.partialsb`), which
   your standing rule puts off-limits. Pulling prod down is approved; deploying into the sandbox
   needs one explicit yes. Alternatively, point me at a true Lumina dev sandbox.
2. **Renaming the `Flow` ApiName flow** is a production change. Separate approval.
3. **Is `Community_Episode__c` live or abandoned?** Blocks two conversions in phase 5.
4. **`Last_SMS_Sent_Date__c` ownership** — Patient or Community Episode?
5. **Is `Count_of_Calls__c` written by anything?** Its only known writer is a disabled DLRS rollup.
   If nothing writes it, the 48-hour TCM counter is dead and that is a live billing problem, not a
   refactor problem.
6. **Should IC assignment still be happening?** If yes, it is currently broken.
7. **The three `Discharge_TF_Send_SMS` defects** — fix on port, or reproduce faithfully?
8. **Consent datetime rule** — two flows write `Consent_Datetime__c` under different conditions.
9. **A real failure case** for the limit errors Chana reported.
10. **Are both ThoroughCare endpoints actually required?** The legacy Heroku
    `/create-thoroughcare-patient` and the newer `/tc/create-comm-patient` both fire on a Closed Won
    transition. Whether one has been a no-op the vendor silently discards is a vendor answer, not a
    code answer. If only one is real, phase 4 gets dramatically simpler.
11. **Is `Patient_TF_On_Update_Community_Status_Send_Patient_To_Thorough_Care` obsolete in the
    production org**, or only in the repo? If it is active in prod there is a third live send and
    the two-pass analysis in finding 6 needs redoing.
12. **Is anyone loading Patient data via Batch Apex today?** If so the `@future` calls are already
    throwing `AsyncException` on those runs, and the Queueable migration jumps the queue.
