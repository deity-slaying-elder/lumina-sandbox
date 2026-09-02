/**
 * Apex port of the flow Visit_TF_On_Create_Visit_Fill_Visit_Date_Fields_on_Patient.
 *
 * Flow behaviour, preserved exactly. The flow is a three-way branch, evaluated in
 * this order, and only ONE branch runs per visit:
 *
 *   1. Not_Seen_Reason__c is populated
 *        -> Patient.Latest_Not_Seen_DateTime__c = Visit.CreatedDate
 *           (and nothing else - the flow terminates on this branch)
 *   2. otherwise, Patient.Initial_Visit_Date__c is blank
 *        -> Patient.Initial_Visit_Date__c     = DATEVALUE(Visit.Visit_DateTime__c)
 *           Patient.Initial_Visit_Provider__c = Visit.Front_End_User__c
 *           Patient.Latest_Visit_DateTime__c  = Visit.Visit_DateTime__c
 *   3. otherwise
 *        -> Patient.Latest_Visit_DateTime__c  = Visit.Visit_DateTime__c
 *
 * Bulk note. The flow ran once per visit, so when two visits for the SAME patient
 * saved together, the second interview saw the first interview's write and took
 * branch 3 rather than branch 2. This handler reproduces that by carrying the
 * pending Patient state forward in memory as it walks the batch, instead of
 * deciding every branch from the single initial query. Dropping that would let a
 * two-visit insert set Initial_Visit_Date__c twice.
 *
 * Ordering within the batch follows Trigger.new, which is the same order the flow
 * would have been invoked in.
 */
public with sharing class VisitTriggerHandler {

    public static void afterInsert(List<Visit__c> newVisits) {
        fillVisitDateFieldsOnPatient(newVisits);
    }

    public static void afterUpdate(List<Visit__c> newVisits, Map<Id, Visit__c> oldVisitMap) {
        fillVisitDateFieldsOnPatient(newVisits);
    }

    private static void fillVisitDateFieldsOnPatient(List<Visit__c> newVisits) {

        Set<Id> visitIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        for (Visit__c visit : newVisits) {
            if (visit.Patient__c != null) {
                visitIds.add(visit.Id);
                patientIds.add(visit.Patient__c);
            }
        }

        // No recursion guard here on purpose. This handler writes Patient__c and never
        // Visit__c, so it cannot re-enter itself. A transaction-scoped guard would be
        // actively wrong: it would claim a visit on insert and then silently drop a
        // legitimate later update of the same visit in that same transaction, which
        // the flow would have processed.
        if (visitIds.isEmpty()) {
            return;
        }

        // Initial_Visit_Date__c drives branch 2 and is not on the trigger record.
        Map<Id, Patient__c> patientsById = new Map<Id, Patient__c>([
            SELECT Id, Initial_Visit_Date__c
            FROM Patient__c
            WHERE Id IN :patientIds
            WITH USER_MODE
        ]);

        // Accumulates the writes, one entry per patient, so repeated visits for the
        // same patient collapse into a single DML row with last-write-wins - which is
        // what the flow's sequential interviews produced.
        Map<Id, Patient__c> pendingUpdates = new Map<Id, Patient__c>();

        for (Visit__c visit : newVisits) {
            if (!visitIds.contains(visit.Id)) {
                continue;
            }
            Patient__c patient = patientsById.get(visit.Patient__c);
            if (patient == null) {
                continue;
            }

            Patient__c pending = pendingUpdates.get(visit.Patient__c);
            if (pending == null) {
                pending = new Patient__c(Id = visit.Patient__c);
                pendingUpdates.put(visit.Patient__c, pending);
            }

            // Branch 1 - not seen. Terminal in the flow, so no other field is touched.
            if (String.isNotBlank(visit.Not_Seen_Reason__c)) {
                pending.Latest_Not_Seen_DateTime__c = visit.CreatedDate;
                continue;
            }

            // Branch 2 - first visit for this patient. `patient` is mutated below so a
            // later visit in the same batch correctly falls through to branch 3.
            if (patient.Initial_Visit_Date__c == null) {
                Date visitDate = visit.Visit_DateTime__c == null ? null : visit.Visit_DateTime__c.date();
                pending.Initial_Visit_Date__c = visitDate;
                pending.Initial_Visit_Provider__c = visit.Front_End_User__c;
                pending.Latest_Visit_DateTime__c = visit.Visit_DateTime__c;
                patient.Initial_Visit_Date__c = visitDate;
                continue;
            }

            // Branch 3 - subsequent visit.
            pending.Latest_Visit_DateTime__c = visit.Visit_DateTime__c;
        }

        if (!pendingUpdates.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, pendingUpdates.values());
            update decision.getRecords();
        }
    }
}
