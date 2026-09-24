/**
 * Trigger action: open a Community Episode when a patient is discharged.
 *
 * Apex port of the flow Admission_Discharge_TF_On_Create_Create_Community_Episode.
 *
 * Flow behaviour, preserved exactly:
 *   entry  - Admission/Discharge created, Type__c = 'Discharge', Patient__c populated
 *   gate   - NewOrReengaging: the patient has no Latest_Call_Outcome__c at all, or
 *            the last one is more than 30 days old
 *   then   - create a Community Episode (status New, linked to the patient, the
 *            discharge record and the patient's facility, owned by the reclaim user)
 *   then   - reset the patient: clear Call_Outcome__c, set Community_Status__c = 'New',
 *            reassign OwnerId to the reclaim user
 *
 * The owner reassignment is the point of the flow, not incidental. A patient nobody
 * has contacted in 30 days is taken back from whoever held it and re-queued as new
 * work. See TcmSettings for why the Id is not inlined here.
 *
 * Bulk note. The flow ran one interview per discharge record, so two discharges for
 * the same patient in one insert produced two episodes and two patient resets. This
 * action still creates one episode per discharge, but collapses the patient resets
 * into a single DML row per patient. The written values are identical on every pass,
 * so the outcome is the same and it avoids the duplicate-update limit that made the
 * flow fail on bulk loads in the first place.
 *
 * Governor note. This is what LMNA-580 was raised for. Inserting more than twelve
 * discharge records for one patient in a single save made the flow throw
 * DUPLICATE_VALUE - "Maximum number of duplicate updates in one batch (12 allowed)"
 * - and roll back the entire insert. One DML row per patient removes that ceiling.
 *
 * Registered in Trigger_Action__mdt for the After Insert context on
 * Admission_Discharge__c. Deactivate by ticking Bypass Execution
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
public without sharing class AdmissionDischargeCreateEpisode implements TriggerAction.AfterInsert {

    /** Flow's Type__c entry filter. */
    private static final String TYPE_DISCHARGE = 'Discharge';

    /** Flow's NewOrReengaging threshold, in days. */
    private static final Integer STALE_CONTACT_DAYS = 30;

    /** Community_Status__c value the flow writes to both the episode and the patient. */
    private static final String STATUS_NEW = 'New';

    public void afterInsert(List<SObject> triggerNew) {
        createEpisodes((List<Admission_Discharge__c>) triggerNew);
    }

    private void createEpisodes(List<Admission_Discharge__c> newRecords) {

        List<Admission_Discharge__c> discharges = new List<Admission_Discharge__c>();
        Set<Id> patientIds = new Set<Id>();
        for (Admission_Discharge__c record : newRecords) {
            if (record.Patient__c != null && TYPE_DISCHARGE.equals(record.Type__c)) {
                discharges.add(record);
                patientIds.add(record.Patient__c);
            }
        }
        if (discharges.isEmpty()) {
            return;
        }

        // Latest_Call_Outcome__c gates the whole action and Facility__c is copied onto
        // the episode. Neither is on the trigger record.
        Map<Id, Patient__c> patientsById = new Map<Id, Patient__c>([
            SELECT Id, Latest_Call_Outcome__c, Facility__c
            FROM Patient__c
            WHERE Id IN :patientIds
        ]);

        Id reclaimOwnerId = TcmSettings.reclaimOwnerId();
        Date today = Date.today();

        List<Community_Episode__c> episodesToCreate = new List<Community_Episode__c>();
        Map<Id, Patient__c> pendingPatientResets = new Map<Id, Patient__c>();

        for (Admission_Discharge__c discharge : discharges) {
            Patient__c patient = patientsById.get(discharge.Patient__c);
            if (patient == null) {
                continue;
            }

            // NewOrReengaging. A blank outcome counts as new; the flow's OR is
            // short-circuited the same way here, so the date arithmetic never runs
            // against null.
            Boolean newOrReengaging = patient.Latest_Call_Outcome__c == null
                || patient.Latest_Call_Outcome__c.daysBetween(today) > STALE_CONTACT_DAYS;
            if (!newOrReengaging) {
                continue;
            }

            Community_Episode__c episode = new Community_Episode__c(
                Admission_Discharge__c = discharge.Id,
                Community_Status__c = STATUS_NEW,
                Facility__c = patient.Facility__c,
                Patient__c = discharge.Patient__c
            );
            // Leaving OwnerId unset keeps the running user as owner, which is what the
            // flow did whenever its hardcoded user was missing from the org.
            if (reclaimOwnerId != null) {
                episode.OwnerId = reclaimOwnerId;
            }
            episodesToCreate.add(episode);

            Patient__c reset = new Patient__c(
                Id = discharge.Patient__c,
                Call_Outcome__c = null,
                Community_Status__c = STATUS_NEW
            );
            if (reclaimOwnerId != null) {
                reset.OwnerId = reclaimOwnerId;
            }
            pendingPatientResets.put(discharge.Patient__c, reset);
        }

        if (episodesToCreate.isEmpty()) {
            return;
        }

        // Order matters and matches the flow: the episode is created first, then the
        // patient is reset. The insert fires CommunityEpisodeTrigger, which stamps
        // Patient.Latest_Community_Episode__c, exactly as the flow chain did.
        insert episodesToCreate;

        update pendingPatientResets.values();
    }
}
