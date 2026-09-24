/**
 * Trigger action: mirror the Patient's last SMS timestamp onto its latest episode.
 *
 * Apex port of the flow Patient_TF_On_Update_Last_SMS_Update_Latest_Episode.
 *
 * Flow behaviour, preserved exactly:
 *   entry  - Patient updated, Last_SMS_Sent_Date__c changed,
 *            Latest_Community_Episode__c populated
 *   action - Community_Episode__c.Last_SMS_Sent_Date__c = the Patient's value
 *
 * Direction matters. Patient__c is the source of truth for this field: it is
 * populated on 8,411 patients in production against 393 episodes, five flows read
 * or write the Patient field, and the formula that drives the four-day SMS cadence
 * (Patient__c.X4_Days_After_Last_SMS__c) reads the Patient field. Nothing reads the
 * episode copy. So this is a one-way mirror, not a sync, and there is no write cycle
 * to break.
 *
 * Bulk note. Two patients can point at the same episode. The flow's last interview
 * won; the map below reproduces that.
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
public without sharing class PatientSyncLastSmsToEpisode implements TriggerAction.AfterUpdate {

    public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        syncLastSms((List<Patient__c>) triggerNew, (List<Patient__c>) triggerOld);
    }

    private void syncLastSms(List<Patient__c> newPatients, List<Patient__c> oldPatients) {

        Map<Id, Patient__c> oldByPatientId = new Map<Id, Patient__c>(oldPatients);

        Map<Id, Community_Episode__c> pendingUpdates = new Map<Id, Community_Episode__c>();

        for (Patient__c patient : newPatients) {
            if (patient.Latest_Community_Episode__c == null) {
                continue;
            }
            Patient__c prior = oldByPatientId.get(patient.Id);
            // IsChanged in the flow's entry criteria.
            if (prior != null && prior.Last_SMS_Sent_Date__c == patient.Last_SMS_Sent_Date__c) {
                continue;
            }
            pendingUpdates.put(
                patient.Latest_Community_Episode__c,
                new Community_Episode__c(
                    Id = patient.Latest_Community_Episode__c,
                    Last_SMS_Sent_Date__c = patient.Last_SMS_Sent_Date__c
                )
            );
        }

        // No recursion guard. This action writes Community_Episode__c and never
        // Patient__c, and the Community Episode trigger is insert-only, so an update
        // here starts no second pass.
        if (pendingUpdates.isEmpty()) {
            return;
        }

        update pendingUpdates.values();
    }
}
