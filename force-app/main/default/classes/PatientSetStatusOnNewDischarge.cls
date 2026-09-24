/**
 * Trigger action: reclaim a patient who has gone quiet, on a new discharge.
 *
 * Apex port of the flow Patient_TF_On_Update_Set_Community_Status_For_Discharge,
 * production version 9. That version is `RecordBeforeSave`, so this is a before
 * update action: it mutates the records in place and issues no DML of its own.
 *
 * Flow behaviour, preserved exactly:
 *   entry - Patient updated, Latest_Discharge_Date__c populated and changed
 *   gate  - Latest_Call_Outcome__c is not blank
 *   gate  - Call30Days: TODAY() - Latest_Call_Outcome__c > 30
 *   action - on the patient itself:
 *              Call_Outcome__c                       = null
 *              Community_Status_Updated_Date_Time__c = now
 *              Community_Status__c                   = 'New'
 *              OwnerId                               = the reclaim owner
 *
 * WHAT THIS FLOW ACTUALLY IS
 * --------------------------
 * It is a reclaim mechanism, not a status setter. A patient with no logged call
 * outcome for 30 days is taken back from whoever owned it, reset to New and handed to
 * the reclaim account, so it re-enters the work queue. In production it has done this
 * to 47,610 patients, 1,767 of them in a single recent week, and it is a large part of
 * why roughly three quarters of all patients sit under one user.
 *
 * There is no task. The flow's `Call30Days` is a formula, not a record create.
 *
 * WHY THE CHANGE CHECK DOES NOT READ THE FORMULA FIELD
 * ---------------------------------------------------
 * The flow's entry criteria is IsChanged on Latest_Discharge_Date__c, which is the
 * formula DATEVALUE(Latest_Discharge__r.Census_Date__c). Formula fields are not
 * recalculated before a before-save trigger runs, so Trigger.new would carry the same
 * stale value as Trigger.old and the comparison would never fire.
 *
 * So the new value is derived the way the formula would: read Census_Date__c from the
 * Admission/Discharge that Latest_Discharge__c now points at - a writable lookup, so
 * it is current - and convert it the way DATEVALUE does. The old value comes from
 * Trigger.old, where the formula holds its committed and therefore correct value.
 *
 * DATEVALUE on a Datetime converts in GMT, not the running user's time zone, so
 * formatGmt is used rather than Datetime.date(). Using Datetime.date() would shift the
 * boundary by up to five hours for a US org and change which records qualify.
 *
 * Registered in Trigger_Action__mdt for the Before Update context on Patient__c.
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
public without sharing class PatientSetStatusOnNewDischarge implements TriggerAction.BeforeUpdate {

    /** Flow's Call30Days threshold, in days. */
    private static final Integer STALE_CONTACT_DAYS = 30;

    /** Community_Status__c value the flow writes. */
    private static final String STATUS_NEW = 'New';

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        setStatusOnNewDischarge((List<Patient__c>) triggerNew, (List<Patient__c>) triggerOld);
    }

    private void setStatusOnNewDischarge(List<Patient__c> newPatients, List<Patient__c> oldPatients) {

        Map<Id, Patient__c> oldByPatientId = new Map<Id, Patient__c>(oldPatients);

        Set<Id> dischargeIds = new Set<Id>();
        for (Patient__c patient : newPatients) {
            if (patient.Latest_Discharge__c != null) {
                dischargeIds.add(patient.Latest_Discharge__c);
            }
        }
        if (dischargeIds.isEmpty()) {
            return;
        }

        // Census_Date__c is what the Latest_Discharge_Date__c formula reads.
        Map<Id, Admission_Discharge__c> dischargesById = new Map<Id, Admission_Discharge__c>([
            SELECT Id, Census_Date__c
            FROM Admission_Discharge__c
            WHERE Id IN :dischargeIds
        ]);

        Id reclaimOwnerId = TcmSettings.reclaimOwnerId();
        Date today = Date.today();
        Datetime now = Datetime.now();

        for (Patient__c patient : newPatients) {
            Patient__c prior = oldByPatientId.get(patient.Id);
            if (prior == null || patient.Latest_Discharge__c == null) {
                continue;
            }

            Admission_Discharge__c discharge = dischargesById.get(patient.Latest_Discharge__c);
            Date newDischargeDate = discharge == null ? null : dateValueGmt(discharge.Census_Date__c);

            // Entry criteria: the formula value is populated, and it changed.
            if (newDischargeDate == null) {
                continue;
            }
            if (newDischargeDate == prior.Latest_Discharge_Date__c) {
                continue;
            }
            // Gate: If_There_Is_Latest_Call_Outcome, IsBlank = false.
            if (patient.Latest_Call_Outcome__c == null) {
                continue;
            }
            // Gate: Call30Days.
            if (patient.Latest_Call_Outcome__c.daysBetween(today) <= STALE_CONTACT_DAYS) {
                continue;
            }

            // Before-save context, so these are in-place edits and cost no DML. That is
            // also why there is no recursion guard: nothing here starts a second pass.
            patient.Call_Outcome__c = null;
            patient.Community_Status_Updated_Date_Time__c = now;
            patient.Community_Status__c = STATUS_NEW;
            // A null reclaim owner means the configured user is absent from this org.
            // Leaving OwnerId alone matches what the flow did in that situation, and
            // avoids INVALID_CROSS_REFERENCE_KEY rolling back the user's whole save.
            if (reclaimOwnerId != null) {
                patient.OwnerId = reclaimOwnerId;
            }
        }
    }

    /**
     * DATEVALUE() on a Datetime, which converts in GMT rather than the running user's
     * time zone. Datetime.date() would use the user's zone and pick a different day.
     */
    private static Date dateValueGmt(Datetime value) {
        return value == null ? null : Date.valueOf(value.formatGmt('yyyy-MM-dd'));
    }
}
