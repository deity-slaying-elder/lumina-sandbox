/**
 * Trigger action: stamp the Patient's Latest Visit Provider from the visit.
 *
 * Apex port of the prod-only flow whose ApiName is literally `Flow`, labelled
 * "Visit - TF - On Create or Update Visit Fill Latest Visit Provider".
 *
 * Flow behaviour, preserved:
 *   Entry criteria - Not_Seen_Reason__c is blank, so only visits that happened
 *   Then           - Patient.Latest_Visit_Provider__c = $Record.Front_End_User__c
 *
 * DELIBERATE OMISSION. The flow also ran a Get Records on Visit__c for the same
 * patient, filtered to seen visits, sorted Visit_DateTime__c descending, first
 * record only. Its result is never referenced by anything downstream: the update
 * assigns from $Record, not from the query. It is one wasted SOQL per visit save,
 * so it is not reproduced here. Dropping it has no observable effect on data.
 *
 * DEFECT CARRIED FORWARD, raise separately. Because the write takes the provider
 * from the TRIGGERING visit rather than the most recent one, editing an old visit
 * overwrites Latest_Visit_Provider__c with that old visit's provider. The dead
 * query above is almost certainly a half-finished attempt to fix exactly this.
 * Reproduced faithfully so the conversion stays provable by parity testing.
 *
 * Bulk. The flow ran one interview per visit against the same patient, so the
 * last visit in the batch won. Accumulating into a map per patient reproduces
 * that, with Trigger.new order deciding the winner.
 *
 * Registered for After Insert and After Update on Visit__c. This is the SECOND
 * action on Visit__c, so its Order__c decides whether it runs before or after
 * VisitFillPatientVisitDates.
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
public without sharing class VisitSetLatestVisitProvider implements TriggerAction.AfterInsert, TriggerAction.AfterUpdate {

    public void afterInsert(List<SObject> triggerNew) {
        run((List<Visit__c>) triggerNew);
    }

    public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        run((List<Visit__c>) triggerNew);
    }

    private void run(List<Visit__c> visits) {

        // No recursion guard. This action writes Patient__c and never Visit__c, so
        // it cannot re-enter itself, and guarding would wrongly drop a legitimate
        // second pass over the same visit in one transaction.
        Map<Id, Patient__c> pendingUpdates = new Map<Id, Patient__c>();

        for (Visit__c visit : visits) {
            // Flow entry criteria: Not_Seen_Reason__c EqualTo blank.
            if (String.isNotBlank(visit.Not_Seen_Reason__c)) {
                continue;
            }
            if (visit.Patient__c == null) {
                continue;
            }

            Patient__c pending = pendingUpdates.get(visit.Patient__c);
            if (pending == null) {
                pending = new Patient__c(Id = visit.Patient__c);
                pendingUpdates.put(visit.Patient__c, pending);
            }
            // Last visit in Trigger.new order wins, matching the flow's sequential
            // interviews. Assigning null is intentional when the visit has no
            // provider - the flow wrote $Record.Front_End_User__r.Id unconditionally.
            pending.Latest_Visit_Provider__c = visit.Front_End_User__c;
        }

        if (!pendingUpdates.isEmpty()) {
            update pendingUpdates.values();
        }
    }
}
