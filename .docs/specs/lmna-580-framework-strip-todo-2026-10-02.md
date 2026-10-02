# LMNA-580 follow-up: strip flow and entry-criteria support from the trigger framework

To-do for the next ticket. Not started. Open a new Jira ticket, link it to LMNA-580, then work
down this list.

## References

| What | Where |
|---|---|
| Parent ticket | https://propela-tech.atlassian.net/browse/LMNA-580 |
| Conversion commit (on main) | https://github.com/deity-slaying-elder/lumina-sandbox/commit/9d28595d7c7607736e1091fd8cac37d855469a90 |
| Adjacent LMNA-581 commit (on main) | https://github.com/deity-slaying-elder/lumina-sandbox/commit/c318fed1a4930a82c279fb059f71f2670ecce4c0 |
| Repo | https://github.com/deity-slaying-elder/lumina-sandbox |
| Behaviour spec, read first | `.docs/specs/lmna-580-flow-to-apex-spec-2026-09-01.md` (sections "Live QA", "System mode", "SMS port") |
| Architecture / CAB deck | `.docs/lmna-580-architecture-overview-2026-09-03.html` |
| Vendored framework licence | `LICENSE-trigger-actions-framework.txt` (keep it, Apache 2.0 section 4(b)) |
| Memory note | `lmna-580-conversion-state` (Claude project memory) |

The original granular branch `lmna-580-flow-to-apex` (7 commits) was squashed into 9d28595.

## Background

9d28595 vendored the mitchspano Trigger Actions Framework and moved 26 record-triggered flows onto
22 Apex trigger actions. We use none of the framework's flow support and none of its entry
criteria. Strip both before this goes to prod, then retest everything live, end to end, in Chrome.

Verified 2026-09-30, read-only:

- lumProd has none of the framework: no MetadataTriggerHandler, FormulaFilter, TriggerActionFlow
  or TriggerRecord classes, and no Trigger_Action, sObject_Trigger_Setting, Trigger_Bypass or
  DML_Finalizer CMDT types. Prod needs no destructive change.
- None of the 31 Trigger_Action records in the repo set Entry_Criteria__c, Flow_Name__c,
  Allow_Flow_Recursion__c, Required_Permission__c or Bypass_Permission__c.
- lumDev is a PARTIAL COPY sandbox (SandboxInfo in lumProd: PartialSb | PARTIAL). Claude must not
  deploy, run DML, or change users or permission sets there. Read-only only.

## 0. Target org gate

- [ ] Pick the dev sandbox alias (currently a placeholder: `<DEV_SANDBOX_ALIAS>`).
- [ ] Prove it is Developer or Developer Pro before any write:
      `sf data query --use-tooling-api -o lumProd --query "SELECT SandboxName, LicenseType FROM SandboxInfo"`.
      If it isn't, stop.
- [ ] If it was freshly created from prod (has none of LMNA-580/581), run it as the prod rehearsal:
      (1) deploy main as it is, (2) apply the removal as a delta deploy, (3) run e2e. Log every step
      and failure in order.
- [ ] Work on a new branch off main. No commits until asked. No push, no merge to main.

## 1. Remove flow support

- [ ] Classes plus their tests: TriggerActionFlow, TriggerActionFlowAddError,
      TriggerActionFlowBypass, TriggerActionFlowBypassProcessor, TriggerActionFlowChangeEvent,
      TriggerActionFlowClearAllBypasses, TriggerActionFlowClearBypass, TriggerActionFlowIsBypassed,
      FlowChangeEventHeader.
- [ ] Fields `Trigger_Action__mdt.Flow_Name__c` and `Allow_Flow_Recursion__c`.
- [ ] Validation rules `Trigger_Action__mdt.Flow_Name` and `Recursion_Only_For_Flows`.

## 2. Remove entry criteria

- [ ] Classes FormulaFilter and TriggerRecord plus their tests.
- [ ] Fields `Trigger_Action__mdt.Entry_Criteria__c` and
      `sObject_Trigger_Setting__mdt.TriggerRecord_Class_Name__c`.

## 3. Clean the references

- [ ] Every reference to the above in MetadataTriggerHandler, MetadataTriggerHandlerTest and the
      two CMDT layouts, including SOQL field lists.
- [ ] Grep force-app again afterwards to prove nothing else references them.

## 4. Guard rail

- [ ] Validation rule: a Trigger_Action record can't be saved with a blank `Apex_Class_Name__c`
      (today a blank one fails at runtime).

## Out of scope (report usage only, decide separately)

DML finalizers (DML_Finalizer__mdt, FinalizerHandler), Required_Permission__c and
Bypass_Permission__c, TriggerContext and Trigger_Bypass__mdt, and the unrelated @InvocableMethod
classes the same grep matches (RoundRobinAssignmentWithPublicGroup, roundRobinAssigner,
SendPatientIdToThoroughCare, Upload*FileController).

- [ ] Report whether the finalizers and permission fields are used anywhere.

## Rules

- [ ] Before deleting: tooling query on `MetadataComponentDependency` where
      `RefMetadataComponentName` is in the class list, and grep `force-app/main/default/flows` for
      the TriggerActionFlow* invocable actions. Any hit: stop and report.
- [ ] Keep `LICENSE-trigger-actions-framework.txt` and the existing header in every vendored file.
      Add one line to each vendored file you modify:
      "Modified by Propela Tech 2026: flow and entry-criteria support removed."
- [ ] Order: deploy the code that no longer references the fields first, then delete fields and
      validation rules via `destructiveChangesPost.xml`. Destructive CMDT deploys work.
- [ ] CMDT record inserts do NOT work through a metadata deploy (UNKNOWN_EXCEPTION); use
      `Metadata.Operations.enqueueDeployment`. Label and DeveloperName are capped at 40 characters.
      Insert CMDT records before the trigger bodies, because `run()` with no records runs nothing.
- [ ] Keep the actions `without sharing` (TcmAutomationPermissionsTest enforces it).
- [ ] No ticket keys in code, comments or test names. No AI attribution in commits.

## Verify: Apex

- [ ] Run all local tests in the target org. Known failures that aren't ours: BulkFacilityCreator,
      BulkOpportunityCreator, PatientIntakeWorklist, ThoroughCareEmail, FacilityTriggerHandler test
      classes. Report any other failure with its output.
- [ ] Report coverage for MetadataTriggerHandler and every trigger action class.

## Verify: live e2e in Chrome (chrome-devtools MCP)

- [ ] Build the user matrix from metadata: which profiles and permission sets grant create/edit on
      the 11 framework objects.
- [ ] Test as: System Administrator; Standard User with no permission sets; that user with each
      relevant permission set (at least Lumina_Sales_Rep, Lumina_Sales_Manager, Sales_User,
      TCM_Readmission_Report_Operator); a Minimum Access - Salesforce user with and without the
      granting permission set. Reuse users where possible; create test users only in the dev
      sandbox. Use Login As.
- [ ] Each of the 22 actions: as every user who can make the triggering save, make it and check
      the field outcome against the spec. Plus one save that should NOT trigger (watched fields
      unchanged). Same outcome expected for every user (system mode). Can't save at all = n/a.
- [ ] Bulk: repeat the spec's 60-record same-patient insert as admin; confirm it still collapses
      to one row per patient.
- [ ] Switches, one at a time (flip, save, confirm stopped, flip back, confirm runs):
      Trigger_Action `Bypass_Execution__c` on one action; sObject_Trigger_Setting
      `Bypass_Execution__c` on one object; one Trigger_Bypass record; the All_Triggers record.
      Leave all four false.
- [ ] In Setup: Trigger Action and sObject Trigger Setting layouts no longer show the removed
      fields; a Trigger_Action without an Apex class is rejected.

## Safety

- [ ] Synthetic data only, obviously fake names (e.g. "Zztest Alpha"). Never open, snapshot or
      screenshot a list view or record you didn't create.
- [ ] Discharge saves queue a Twilio SMS (DischargeSendSmsQueueable). Patient saves also fire
      PatientThoroughcareCreateTrigger (outside the framework, calls ThoroughCare via
      API_Configration__mdt / EnvironmentMetadataSelector). Prove sandbox/test endpoints and
      fake-or-ours phone numbers first, or skip those paths and report them untested.
- [ ] Close every browser page opened.

## Deliverables (in chat)

- [ ] Answer first, five lines max: what was removed, deploy result, test result, e2e pass/fail.
- [ ] Matrix of action x user (pass / fail / n/a).
- [ ] Untested paths and why.
- [ ] lumDev handover (James runs it, partial sandbox): destructive package + exact sf command,
      rehearsed verbatim in the dev sandbox first, plus Deleted and Modified tables
      (Type | Members, one row per type, members comma-joined).
- [ ] Prod New set after removal, same table format.
- [ ] Dated section on the removal added to the LMNA-580 spec. Nothing posted to Jira.
