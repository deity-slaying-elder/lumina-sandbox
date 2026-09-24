/*
 * LMNA-581 production smoke test, step 3 of 3. Removes everything the setup script created.
 *
 * Run with:
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-smoke-cleanup.apex
 *
 * Deletes the link rows and their access log first, then the admission, the patient and the
 * facility. Touches nothing that is not part of the ZZ TEST facility.
 */
List<Facility__c> tests = [
    SELECT Id FROM Facility__c WHERE Name = 'ZZ TEST - Readmission Smoke Test - DELETE ME'
];
if (tests.isEmpty()) {
    System.debug('Nothing to clean up.');
    return;
}
Set<Id> facilityIds = new Map<Id, Facility__c>(tests).keySet();

List<Readmission_Report_Link__c> links = [
    SELECT Id FROM Readmission_Report_Link__c WHERE Facility__c IN :facilityIds
];
// The access log is a master-detail child, so deleting the links removes it too.
delete links;
System.debug('deleted link rows: ' + links.size());

List<Patient__c> patients = [SELECT Id FROM Patient__c WHERE Facility__c IN :facilityIds];
Set<Id> patientIds = new Map<Id, Patient__c>(patients).keySet();
List<Hospital_Admission__c> admissions = [
    SELECT Id FROM Hospital_Admission__c WHERE Patient__c IN :patientIds
];
delete admissions;
System.debug('deleted admissions: ' + admissions.size());
delete patients;
System.debug('deleted patients: ' + patients.size());
delete tests;
System.debug('deleted facilities: ' + tests.size());
