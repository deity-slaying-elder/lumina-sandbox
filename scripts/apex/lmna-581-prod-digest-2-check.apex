/*
 * LMNA-581 digest test, step 2 of 4. CONFIRM IT IS SAFE TO RUN THE BATCH.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-digest-2-check.apex
 *
 * Do not run step 3 until this prints "SAFE". It counts how many facilities the batch would
 * email right now. Anything other than the one test facility means the marker has not taken
 * effect and real facilities would be contacted.
 */
TCMReportConfig cfg = new TCMReportConfig();
TCMReadmissionWindow w = new TCMReadmissionWindow(cfg.timeZoneName());
System.debug('required patient class is now: ' + cfg.requiredPatientClass());

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
System.debug('facilities the batch would email: ' + wouldEmail.size());
for (Facility__c f : [SELECT Name FROM Facility__c WHERE Id IN :wouldEmail]) {
    System.debug('   ' + f.Name);
}
Boolean safe = wouldEmail.size() == 1;
System.debug(safe
    ? 'SAFE. Only the test facility is in scope, so step 3 will not reach a real facility.'
    : 'NOT SAFE. Stop. Do not run step 3.');
