/**
 * Trigger action: point the Patient at its newest Community Episode.
 *
 * Apex port of the flow Community_Episode_TF_On_Create_Set_Latest_On_Patient.
 *
 * Flow behaviour, preserved exactly:
 *   entry  - Community Episode created, Patient__c populated
 *   action - Patient.Latest_Community_Episode__c = the new episode's Id
 *
 * There is no branching and no condition beyond the entry criteria.
 *
 * Bulk note. The flow ran one interview per episode, so when two episodes for the
 * SAME patient were inserted together the second interview overwrote the first and
 * the last episode in the batch won. Collapsing to one DML row per patient below
 * reproduces that, because the map keeps the last value written.
 *
 * Note on visibility. Patient__c.Latest_Community_Episode__c has no field-level
 * security granted to any profile in production, so the value this action writes is
 * invisible to every user, report and list view. That is a pre-existing org
 * condition, not something the port changes, but it means nobody can verify this
 * action's output through the UI.
 *
 * Registered in Trigger_Action__mdt for the After Insert context on
 * Community_Episode__c. Deactivate by ticking Bypass Execution
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
public without sharing class CommunityEpisodeSetLatestOnPatient implements TriggerAction.AfterInsert {

    public void afterInsert(List<SObject> triggerNew) {
        setLatestEpisodeOnPatient((List<Community_Episode__c>) triggerNew);
    }

    private void setLatestEpisodeOnPatient(List<Community_Episode__c> newEpisodes) {

        // One row per patient, last episode in the batch winning, which is what the
        // flow's sequential interviews produced.
        Map<Id, Patient__c> pendingUpdates = new Map<Id, Patient__c>();

        for (Community_Episode__c episode : newEpisodes) {
            if (episode.Patient__c == null) {
                continue;
            }
            pendingUpdates.put(
                episode.Patient__c,
                new Patient__c(
                    Id = episode.Patient__c,
                    Latest_Community_Episode__c = episode.Id
                )
            );
        }

        // No recursion guard. This action writes Patient__c and never
        // Community_Episode__c, and the Community Episode trigger runs on insert
        // only, so it cannot re-enter itself.
        if (pendingUpdates.isEmpty()) {
            return;
        }

        update pendingUpdates.values();
    }
}
