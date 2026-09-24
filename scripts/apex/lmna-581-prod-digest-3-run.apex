/*
 * LMNA-581 digest test, step 3 of 4. RUN THE BATCH.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-digest-3-run.apex
 *
 * This checks the scope itself before it runs anything, and throws rather than starting the
 * batch if more than the one test facility is in scope.
 *
 * It did not always do that. On 2026-09-22 the arm step failed with MIXED_DML and rolled back,
 * so the marker never landed, and this script ran the batch against the real scope anyway
 * because it trusted the operator to have read step 2's verdict in the scroll-back. Three real
 * facility administrators were emailed. A safety check a human has to notice is not a safety
 * check, so the same test step 2 performs is repeated here, in the same transaction that starts
 * the batch, where nothing can drift between the two.
 *
 * Is_Active__c is not a backstop for any of this: only the scheduler reads it, and
 * Database.executeBatch ignores it.
 */
TCMReportConfig cfg = new TCMReportConfig();
TCMReadmissionWindow w = new TCMReadmissionWindow(cfg.timeZoneName());

Set<Id> facilityIds = new Set<Id>();
for (Facility__c f : [
    SELECT Id FROM Facility__c
    WHERE Exclude_from_TCM_Reporting__c = false AND Parent_Company__r.TCM__c = true
]) {
    facilityIds.add(f.Id);
}
Set<Id> wouldEmail = new Set<Id>();
for (Hospital_Admission__c a :
        TCMReadmissionAdmissionScope.find(facilityIds, w.startUtc, w.endUtc, cfg)) {
    wouldEmail.add(a.Patient__r.Facility__c);
}

List<String> names = new List<String>();
for (Facility__c f : [SELECT Name FROM Facility__c WHERE Id IN :wouldEmail]) {
    names.add(f.Name);
}
System.debug(LoggingLevel.ERROR, 'required patient class: ' + cfg.requiredPatientClass());
System.debug(LoggingLevel.ERROR, 'facilities in scope: ' + wouldEmail.size() + ' ' + names);

Boolean onlyTheTestFacility = wouldEmail.size() == 1
    && names.size() == 1
    && names[0].startsWith('ZZ TEST');
if (!onlyTheTestFacility) {
    throw new CalloutException(
        'REFUSING TO RUN. Expected only the ZZ TEST facility in scope, found ' +
        wouldEmail.size() + ': ' + names + '. The arm step has not taken effect. ' +
        'Running now would email real facilities. Re-run steps 1a and 1b, wait, then step 2.'
    );
}

Id jobId = Database.executeBatch(new TCMDailyReadmissionBatch(), 50);
System.debug(LoggingLevel.ERROR, 'scope confirmed. batch job ' + jobId
    + ' queued. The digest arrives when it finishes.');
System.debug(LoggingLevel.ERROR,
    'Check progress: SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = ' + jobId);
