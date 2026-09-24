/*
 * LMNA-581 production smoke test, step 1 of 3. Creates the test data ONLY.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-smoke-setup.apex
 *
 * Sending is deliberately a separate run. The report PDF is produced by rendering a Visualforce
 * page, and that render happens in its own request which cannot see records this transaction
 * has inserted but not yet committed. Creating the facility and sending in one go produces a
 * PDF that says "That facility is not available to you" with zero rows. So: create here, let
 * the transaction commit, then send in step 2.
 */
String testerEmail = 'shuaib.abdurahman22@gmail.com';

Account parent = [SELECT Id FROM Account WHERE TCM__c = true LIMIT 1];
Facility__c f = new Facility__c(
    Name = 'ZZ TEST - Readmission Smoke Test - DELETE ME',
    Parent_Company__c = parent.Id,
    Admin_Email__c = testerEmail,
    TCM__c = true,
    Exclude_from_TCM_Reporting__c = false
);
insert f;

Patient__c p = new Patient__c(
    First_Name__c = 'Smoke', Last_Name__c = 'TestPatient', Status__c = 'Inactive',
    Facility__c = f.Id, Hospice__c = false
);
insert p;

TCMReadmissionWindow w = new TCMReadmissionWindow(new TCMReportConfig().timeZoneName());
insert new Hospital_Admission__c(
    Patient__c = p.Id,
    Facility__c = 'ZZ TEST Hospital',
    Admit_DateTime__c = w.startUtc.addHours(9),
    Was_Discharged_Home_From_SNF__c = true,
    Patient_Class__c = 'Emergency, Inpatient'
);

System.debug('Created facility ' + f.Id + ' for window ' + w.describe());
System.debug('Now run lmna-581-prod-smoke-send.apex');
