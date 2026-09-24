/**
 * Trigger action: count calls made inside the 48-hour post-discharge window.
 *
 * Apex port of the flow Patient_TF_On_Update_Update_Count_Within_48_Hours.
 *
 * This is TCM billing logic. CPT 99495 and 99496 both require interactive contact
 * within two business days of discharge, so the counter this action maintains is
 * evidence that the requirement was met.
 *
 * Flow behaviour, preserved exactly. Three gates in order, all must pass:
 *   entry - Patient updated, Count_of_Calls__c changed
 *   1. Count_of_Calls__c = 0            -> stop (the flow's rule has no connector)
 *   2. Count_of_Calls__c > prior value  -> continue, otherwise stop
 *   3. within48Hours: TODAY() - Discharge_Date__c <= 2 -> continue, otherwise stop
 *   action - Count_of_Calls_Within_48_Hours__c = blank ? 1 : current + 1
 *
 * Count_of_Calls__c is written by two other flows, Intake_Form_2_SF_Create_Form_2
 * (which increments it) and Community_TF_On_Update_Status_Call_Outcome_Update_Patient.
 * A disabled DLRS rollup of the same name also targets the field and is not the
 * writer. In production 39,117 patients carry a non-zero value, 24,223 of them
 * touched in the last week, so this path is live.
 *
 * TWO FLOW DEFECTS REPRODUCED DELIBERATELY, NOT FIXED
 * ---------------------------------------------------
 * A port that also changes output cannot be verified by comparing it against the
 * flow, so both of these are carried forward as-is and raised separately.
 *
 *  1. A future Discharge_Date__c always passes gate 3. TODAY() minus a future date
 *     is negative, and negative is <= 2, so a mis-keyed discharge date counts every
 *     call as being inside the window.
 *  2. The window is named 48 hours and the field says 48 hours, but the comparison
 *     is <= 2 whole days against a Date, not 48 hours against a Datetime. A call
 *     made late on day two lands up to 24 hours outside a true 48-hour window.
 *     TCM's actual rule is two business days, which this does not model either.
 *
 * A null Discharge_Date__c stops at gate 3 and increments nothing, matching the
 * flow, where the formula returned null and the decision treated that as false.
 *
 * Registered in Trigger_Action__mdt for the After Update context on Patient__c.
 * Deactivate by ticking Bypass Execution
 * on that record in Setup - the framework reads it live - or at runtime with
 * MetadataTriggerHandler.bypass in a test or batch job.
 *
 * SYSTEM MODE, DELIBERATELY. The flow this replaces ran in system context and wrote
 * what it needed regardless of who saved the record. Running-user enforcement here
 * (WITH USER_MODE, stripInaccessible) makes the same save silently drop writes for
 * lower-privilege profiles - in production, Lumina Manager No Edit Access can create
 * discharges without Patient edit, and Latest_Community_Episode__c carries no field
 * permissions for anyone - and a silently dropped TCM timestamp is a billing defect
 * nobody sees. Automation runs as the system, exactly as the flow did. User-facing
 * controllers are different and keep user-mode enforcement.
 */
public without sharing class PatientCountCallsWithin48Hours implements TriggerAction.AfterUpdate {

    /** Flow's within48Hours threshold, in whole days. See defect 2 above. */
    private static final Integer WINDOW_DAYS = 2;

    public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        countCalls((List<Patient__c>) triggerNew, (List<Patient__c>) triggerOld);
    }

    private void countCalls(List<Patient__c> newPatients, List<Patient__c> oldPatients) {

        Map<Id, Patient__c> oldByPatientId = new Map<Id, Patient__c>(oldPatients);
        Date today = Date.today();

        Set<Id> candidateIds = new Set<Id>();
        for (Patient__c patient : newPatients) {
            Patient__c prior = oldByPatientId.get(patient.Id);
            if (prior == null) {
                continue;
            }

            // Entry criteria: Count_of_Calls__c IsChanged.
            if (prior.Count_of_Calls__c == patient.Count_of_Calls__c) {
                continue;
            }
            // Gate 1. Terminal in the flow.
            if (patient.Count_of_Calls__c == 0) {
                continue;
            }
            // Gate 2. A decrease, or a change from null to null, stops here. Comparing
            // against null on either side yields false, which is what the flow's
            // GreaterThan operator did.
            if (patient.Count_of_Calls__c == null
                || prior.Count_of_Calls__c == null
                || patient.Count_of_Calls__c <= prior.Count_of_Calls__c) {
                continue;
            }
            // Gate 3. within48Hours. Null discharge date stops here.
            if (patient.Discharge_Date__c == null
                || patient.Discharge_Date__c.daysBetween(today) > WINDOW_DAYS) {
                continue;
            }
            candidateIds.add(patient.Id);
        }

        // No recursion guard, exactly like the flow. This action's own update writes only
        // Count_of_Calls_Within_48_Hours__c; the re-entrant pass sees Count_of_Calls__c
        // unchanged and stops at the entry criteria. The flow terminated the same way. A
        // transaction-scoped claim here was tried and reverted: it also suppressed a
        // LEGITIMATE second call logged in the same transaction, which the flow counted.
        if (candidateIds.isEmpty()) {
            return;
        }

        List<Patient__c> updates = new List<Patient__c>();
        for (Patient__c patient : newPatients) {
            if (!candidateIds.contains(patient.Id)) {
                continue;
            }
            Decimal current = patient.Count_of_Calls_Within_48_Hours__c;
            updates.add(new Patient__c(
                Id = patient.Id,
                Count_of_Calls_Within_48_Hours__c = current == null ? 1 : current + 1
            ));
        }

        if (updates.isEmpty()) {
            return;
        }

        update updates;
    }
}
