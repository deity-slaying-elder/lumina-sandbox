/*
 * LMNA-581 digest test, step 1a of 4. ARM THE TEST DATA.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-digest-1a-arm-data.apex
 *
 * The digest is only produced by the daily batch, and the batch reports on every facility in
 * scope. Is_Active__c does not stop it, because only the scheduler reads that flag, so running
 * the batch as-is would email real facilities today.
 *
 * Narrowing the batch to the test facility takes two writes that cannot share a transaction:
 * this one touches records, step 1b writes configuration, and a metadata deployment counts as
 * a setup object. Doing both at once fails with MIXED_DML_OPERATION and rolls the whole thing
 * back, which is how this script was first written and what it did on 2026-09-23.
 *
 * This half tags the test admission with a marker no real record carries, and moves it into
 * the middle of whatever window the run will use. The window is yesterday, or Friday through
 * Sunday on a Monday, so an admission left on a fixed date drops out of scope overnight and
 * the run then reports nothing.
 */
String marker = 'ZZSMOKE';

Facility__c f = [
    SELECT Id, Name, Admin_Email__c FROM Facility__c
    WHERE Name = 'ZZ TEST - Readmission Smoke Test - DELETE ME' LIMIT 1
];
List<Hospital_Admission__c> rows = [
    SELECT Id, Patient_Class__c, Admit_DateTime__c
    FROM Hospital_Admission__c WHERE Patient__r.Facility__c = :f.Id
];
TCMReadmissionWindow window = new TCMReadmissionWindow(new TCMReportConfig().timeZoneName());
Datetime admitAt = window.startUtc.addHours(12);
for (Hospital_Admission__c a : rows) {
    a.Patient_Class__c = 'Emergency, Inpatient, ' + marker;
    a.Admit_DateTime__c = admitAt;
}
update rows;

System.debug('facility: ' + f.Name + ' -> ' + f.Admin_Email__c);
System.debug('tagged ' + rows.size() + ' test admission(s) with ' + marker
    + ', admitted ' + admitAt + ' UTC');
System.debug('window covers ' + window.describe());
System.debug('Now run step 1b.');
