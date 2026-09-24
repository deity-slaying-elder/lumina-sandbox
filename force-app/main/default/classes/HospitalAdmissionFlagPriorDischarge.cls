/**
 * Trigger action: flag a hospital admission that follows a discharge-home within 30 days.
 *
 * Apex port of the flow
 * Hospital_Admissions_TF_On_C_U_Look_For_Prior_NH_Discharge_Home.
 *
 * Flow behaviour, preserved exactly:
 *   Entry criteria  - none. Fires on every create and update.
 *   Then            - find Admission_Discharge__c for the same Patient where the
 *                     discharge was home and Census_Date__c falls in the 30 days
 *                     immediately before this admission. If any exist, stamp
 *                     Was_Discharged_Home_From_SNF__c = true on the admission.
 *
 * Window, copied from the flow's formula and filters:
 *   Census_Date__c > DATEVALUE(Admit_DateTime__c) - 30   AND
 *   Census_Date__c < Admit_DateTime__c
 * Note the flow compared a Date (the minus-30 formula) against a DateTime field,
 * which Salesforce coerces to midnight. That coercion is reproduced here rather
 * than corrected, so the boundary behaves identically.
 *
 * Kept as an after-trigger with its own DML, matching the flow, rather than moved
 * to before-save. Before-save would be cheaper but would change the point in the
 * save order at which the field becomes visible to other automation, and the port
 * has to be provable by parity testing.
 *
 * Registered in Trigger_Action__mdt for the After Insert and After Update contexts
 * on Hospital_Admission__c. Deactivate by ticking Bypass Execution
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
public without sharing class HospitalAdmissionFlagPriorDischarge implements TriggerAction.AfterInsert, TriggerAction.AfterUpdate {

    private static final String GUARD_KEY = 'HospitalAdmission.priorDischargeHome';
    private static final Integer LOOKBACK_DAYS = 30;

    public void afterInsert(List<SObject> triggerNew) {
        flagPriorDischargeHome((List<Hospital_Admission__c>) triggerNew);
    }

    public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        flagPriorDischargeHome((List<Hospital_Admission__c>) triggerNew);
    }

    private void flagPriorDischargeHome(List<Hospital_Admission__c> newAdmissions) {

        Set<Id> candidateIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        for (Hospital_Admission__c admission : newAdmissions) {
            if (admission.Patient__c != null && admission.Admit_DateTime__c != null) {
                candidateIds.add(admission.Id);
                patientIds.add(admission.Patient__c);
            }
        }

        // Without this guard the update below re-enters this same after-update action.
        // This is the one converted action that writes its own object, so it is the
        // only one that needs the guard.
        candidateIds = TriggerContext.claimUnprocessed(GUARD_KEY, candidateIds);
        if (candidateIds.isEmpty()) {
            return;
        }

        // Widest window across the batch, so this stays one query no matter how many
        // admissions are saved. Each admission is then matched against its own window.
        Datetime earliestAdmit = null;
        Datetime latestAdmit = null;
        for (Hospital_Admission__c admission : newAdmissions) {
            if (!candidateIds.contains(admission.Id)) {
                continue;
            }
            if (earliestAdmit == null || admission.Admit_DateTime__c < earliestAdmit) {
                earliestAdmit = admission.Admit_DateTime__c;
            }
            if (latestAdmit == null || admission.Admit_DateTime__c > latestAdmit) {
                latestAdmit = admission.Admit_DateTime__c;
            }
        }
        Datetime windowStart = Datetime.newInstance(earliestAdmit.date().addDays(-LOOKBACK_DAYS), Time.newInstance(0, 0, 0, 0));

        Map<Id, List<Admission_Discharge__c>> dischargesByPatient = new Map<Id, List<Admission_Discharge__c>>();
        for (Admission_Discharge__c discharge : [
            SELECT Id, Patient__c, Census_Date__c
            FROM Admission_Discharge__c
            WHERE Patient__c IN :patientIds
              AND Discharged_Home__c = TRUE
              AND Census_Date__c > :windowStart
              AND Census_Date__c < :latestAdmit
        ]) {
            if (!dischargesByPatient.containsKey(discharge.Patient__c)) {
                dischargesByPatient.put(discharge.Patient__c, new List<Admission_Discharge__c>());
            }
            dischargesByPatient.get(discharge.Patient__c).add(discharge);
        }

        List<Hospital_Admission__c> toUpdate = new List<Hospital_Admission__c>();
        for (Hospital_Admission__c admission : newAdmissions) {
            if (!candidateIds.contains(admission.Id)) {
                continue;
            }
            List<Admission_Discharge__c> discharges = dischargesByPatient.get(admission.Patient__c);
            if (discharges == null) {
                continue;
            }

            // Per-record window, matching the flow's own filters exactly.
            Datetime recordWindowStart = Datetime.newInstance(
                admission.Admit_DateTime__c.date().addDays(-LOOKBACK_DAYS),
                Time.newInstance(0, 0, 0, 0)
            );

            for (Admission_Discharge__c discharge : discharges) {
                if (discharge.Census_Date__c > recordWindowStart && discharge.Census_Date__c < admission.Admit_DateTime__c) {
                    // Only write when the value actually changes. The flow wrote
                    // unconditionally; skipping a no-op write is invisible to the
                    // record's final state and keeps the guard from burning a DML.
                    if (admission.Was_Discharged_Home_From_SNF__c != true) {
                        toUpdate.add(new Hospital_Admission__c(
                            Id = admission.Id,
                            Was_Discharged_Home_From_SNF__c = true
                        ));
                    }
                    break;
                }
            }
        }

        if (!toUpdate.isEmpty()) {
        update toUpdate;
        }
    }
}
