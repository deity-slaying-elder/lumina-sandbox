/**
 * Trigger action: queue a patient discharged home as new community work.
 *
 * Apex port of the flow TF_Patient_Discharge_Home_Assign_To_IC.
 *
 * Flow behaviour, preserved exactly:
 *   entry  - Patient updated, Latest_Discharge__c changed, Community_Status__c blank
 *   gate   - Latest_Discharge__r.Discharged_Home__c = true
 *   action - Community_Status__c = 'New'
 *
 * THE FLOW NAME IS WRONG AND THE APEX NAME IS NOT
 * -----------------------------------------------
 * Despite the name, the flow no longer assigns an Intake Coordinator. Setting the
 * community status is its only action. It still carried an unused `patientIds` input
 * variable matching RoundRobinAssignmentWithPublicGroup.RoundRobinRequest.patientIds,
 * which is the fingerprint of an invocable call that was removed from it. That
 * variable is not carried over; nothing supplied it and nothing read it.
 *
 * Round robin assignment was not lost by accident, so it is deliberately not
 * restored here. In production: the public group the RoundRobin__c config names,
 * "TCM IC's", no longer exists; the rotation counter has been frozen at 5 since
 * 1 October 2024; no flow anywhere calls the invocable; and 74% of all patients are
 * owned by the administrator account. Assignment moved to being human-driven, in
 * Intake_Form_2_SF_Create_Form_2, which sets OwnerId to the running user. Restoring
 * round robin would re-enable automation somebody switched off eleven months ago,
 * and it would throw on the first run because the group is gone.
 *
 * Discharged_Home__c is a formula on Admission_Discharge__c, so it has to be
 * queried through the lookup - it cannot be read from the Patient trigger record.
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
public without sharing class PatientDischargeHomeSetStatusNew implements TriggerAction.AfterUpdate {

    /** Community_Status__c value the flow writes. */
    private static final String STATUS_NEW = 'New';

    public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        setStatusNew((List<Patient__c>) triggerNew, (List<Patient__c>) triggerOld);
    }

    private void setStatusNew(List<Patient__c> newPatients, List<Patient__c> oldPatients) {

        Map<Id, Patient__c> oldByPatientId = new Map<Id, Patient__c>(oldPatients);

        Map<Id, Id> dischargeIdByPatientId = new Map<Id, Id>();
        for (Patient__c patient : newPatients) {
            Patient__c prior = oldByPatientId.get(patient.Id);
            if (prior == null) {
                continue;
            }
            // Entry criteria: Latest_Discharge__c IsChanged and Community_Status__c blank.
            if (prior.Latest_Discharge__c == patient.Latest_Discharge__c) {
                continue;
            }
            if (String.isNotBlank(patient.Community_Status__c)) {
                continue;
            }
            if (patient.Latest_Discharge__c == null) {
                continue;
            }
            dischargeIdByPatientId.put(patient.Id, patient.Latest_Discharge__c);
        }
        if (dischargeIdByPatientId.isEmpty()) {
            return;
        }

        // Discharged_Home__c is a formula field on the discharge record.
        Map<Id, Admission_Discharge__c> dischargesById = new Map<Id, Admission_Discharge__c>([
            SELECT Id, Discharged_Home__c
            FROM Admission_Discharge__c
            WHERE Id IN :dischargeIdByPatientId.values()
        ]);

        Set<Id> candidateIds = new Set<Id>();
        for (Id patientId : dischargeIdByPatientId.keySet()) {
            Admission_Discharge__c discharge = dischargesById.get(dischargeIdByPatientId.get(patientId));
            if (discharge != null && discharge.Discharged_Home__c == true) {
                candidateIds.add(patientId);
            }
        }

        // No recursion guard, exactly like the flow. The write below sets
        // Community_Status__c, which takes the record out of this action's own entry
        // criteria (status must be blank), so the re-entrant pass stops naturally. A
        // transaction-scoped claim was tried and reverted: it also suppressed legitimate
        // repeat qualification within one transaction, which the flow honoured.
        if (candidateIds.isEmpty()) {
            return;
        }

        List<Patient__c> updates = new List<Patient__c>();
        for (Id patientId : candidateIds) {
            updates.add(new Patient__c(Id = patientId, Community_Status__c = STATUS_NEW));
        }

        update updates;
    }
}
