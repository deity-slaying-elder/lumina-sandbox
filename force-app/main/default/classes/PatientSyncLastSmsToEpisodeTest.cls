/**
 * Invoked directly rather than through DML. See the note in
 * CommunityEpisodeSetLatestOnPatientTest for why.
 */
@isTest
private class PatientSyncLastSmsToEpisodeTest {

    private static final Datetime SMS_TIME = Datetime.newInstanceGmt(2026, 6, 15, 14, 30, 0);

    @TestSetup
    static void setupTestData() {
        Patient__c patient = new Patient__c(First_Name__c = 'Sms', Last_Name__c = 'Mirror', Status__c = 'Active');
        insert patient;
        Community_Episode__c episode = new Community_Episode__c(Patient__c = patient.Id);
        insert episode;
        patient.Latest_Community_Episode__c = episode.Id;
        update patient;
    }

    private static Patient__c thePatient() {
        return [SELECT Id, Last_SMS_Sent_Date__c, Latest_Community_Episode__c FROM Patient__c LIMIT 1];
    }

    private static Community_Episode__c theEpisode() {
        return [SELECT Id, Last_SMS_Sent_Date__c FROM Community_Episode__c LIMIT 1];
    }

    @isTest
    static void changedSmsDateMirrorsToEpisode() {
        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Last_SMS_Sent_Date__c = SMS_TIME;

        Test.startTest();
        new PatientSyncLastSmsToEpisode().afterUpdate(
            new List<Patient__c>{ after }, new List<Patient__c>{ before }
        );
        Test.stopTest();

        Assert.areEqual(SMS_TIME, theEpisode().Last_SMS_Sent_Date__c,
            'The episode should carry the patient timestamp');
    }

    @isTest
    static void unchangedSmsDateWritesNothing() {
        Patient__c before = thePatient();
        before.Last_SMS_Sent_Date__c = SMS_TIME;
        Patient__c after = before.clone(true, true, true, true);

        Test.startTest();
        new PatientSyncLastSmsToEpisode().afterUpdate(
            new List<Patient__c>{ after }, new List<Patient__c>{ before }
        );
        Test.stopTest();

        Assert.areEqual(null, theEpisode().Last_SMS_Sent_Date__c,
            'An unchanged timestamp should not reach the episode');
    }

    @isTest
    static void patientWithoutEpisodeIsSkipped() {
        Patient__c before = new Patient__c(
            First_Name__c = 'No', Last_Name__c = 'Episode', Status__c = 'Active'
        );
        insert before;
        Patient__c after = before.clone(true, true, true, true);
        after.Last_SMS_Sent_Date__c = SMS_TIME;

        Test.startTest();
        new PatientSyncLastSmsToEpisode().afterUpdate(
            new List<Patient__c>{ after }, new List<Patient__c>{ before }
        );
        Test.stopTest();

        Assert.areEqual(null, theEpisode().Last_SMS_Sent_Date__c,
            'A patient with no latest episode should touch nothing');
    }

    @isTest
    static void bulkStaysAtOneDmlStatement() {
        Community_Episode__c episode = theEpisode();
        List<Patient__c> olds = new List<Patient__c>();
        List<Patient__c> news = new List<Patient__c>();
        for (Integer i = 0; i < 200; i++) {
            Patient__c old = new Patient__c(
                Id = fakeId(Patient__c.SObjectType, i),
                Latest_Community_Episode__c = episode.Id
            );
            Patient__c updated = old.clone(true, true, true, true);
            updated.Last_SMS_Sent_Date__c = SMS_TIME;
            olds.add(old);
            news.add(updated);
        }

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        new PatientSyncLastSmsToEpisode().afterUpdate(news, olds);
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(1, dmlUsed, '200 patients pointing at one episode should be a single DML statement');
    }

    /** Ids must be exactly 15 or 18 characters, so the counter is padded. */
    private static Id fakeId(Schema.SObjectType sobjectType, Integer index) {
        String prefix = sobjectType.getDescribe().getKeyPrefix();
        return Id.valueOf(prefix + String.valueOf(index + 1).leftPad(12, '0'));
    }
}
