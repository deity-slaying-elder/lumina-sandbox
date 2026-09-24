/**
 * The action is invoked directly rather than through DML.
 *
 * The trigger only reaches it via a Trigger_Action__mdt record, and new custom
 * metadata records cannot currently be inserted into this org by a metadata deploy,
 * so a DML-driven test would assert nothing until that record is created by hand in
 * Setup. Calling the action directly tests the logic today. Add an end-to-end test
 * once the metadata record exists.
 *
 * These assertions stay correct either way: the action writes the same value on
 * every pass, so a trigger that has already run it does not change the outcome.
 */
@isTest
private class CommunityEpisodeSetLatestOnPatientTest {

    @TestSetup
    static void setupTestData() {
        insert new List<Patient__c>{
            new Patient__c(First_Name__c = 'Episode', Last_Name__c = 'Owner', Status__c = 'Active'),
            new Patient__c(First_Name__c = 'Second', Last_Name__c = 'Holder', Status__c = 'Active')
        };
    }

    private static Patient__c patientNamed(String lastName) {
        return [SELECT Id, Latest_Community_Episode__c FROM Patient__c WHERE Last_Name__c = :lastName LIMIT 1];
    }

    @isTest
    static void pointsPatientAtNewEpisode() {
        Patient__c patient = patientNamed('Owner');
        Community_Episode__c episode = new Community_Episode__c(Patient__c = patient.Id);
        insert episode;

        Test.startTest();
        new CommunityEpisodeSetLatestOnPatient().afterInsert(new List<Community_Episode__c>{ episode });
        Test.stopTest();

        Assert.areEqual(episode.Id, patientNamed('Owner').Latest_Community_Episode__c,
            'Latest_Community_Episode__c should point at the new episode');
    }

    @isTest
    static void lastEpisodeInBatchWins() {
        Patient__c patient = patientNamed('Owner');
        List<Community_Episode__c> episodes = new List<Community_Episode__c>{
            new Community_Episode__c(Patient__c = patient.Id),
            new Community_Episode__c(Patient__c = patient.Id)
        };
        insert episodes;

        Test.startTest();
        new CommunityEpisodeSetLatestOnPatient().afterInsert(episodes);
        Test.stopTest();

        // The flow ran one interview per episode, so the last one overwrote the first.
        Assert.areEqual(episodes[1].Id, patientNamed('Owner').Latest_Community_Episode__c,
            'The last episode in the batch should win, matching the flow');
    }

    @isTest
    static void episodeWithoutPatientIsSkipped() {
        Community_Episode__c orphan = new Community_Episode__c();
        insert orphan;

        Test.startTest();
        new CommunityEpisodeSetLatestOnPatient().afterInsert(new List<Community_Episode__c>{ orphan });
        Test.stopTest();

        Assert.areEqual(null, patientNamed('Holder').Latest_Community_Episode__c,
            'An episode with no patient should touch nothing');
    }

    @isTest
    static void bulkCollapsesToOneDmlPerPatient() {
        List<Patient__c> patients = [SELECT Id FROM Patient__c];
        List<Community_Episode__c> episodes = new List<Community_Episode__c>();
        for (Integer i = 0; i < 200; i++) {
            episodes.add(new Community_Episode__c(Patient__c = patients[Math.mod(i, patients.size())].Id));
        }
        insert episodes;

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        new CommunityEpisodeSetLatestOnPatient().afterInsert(episodes);
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        // The point of the conversion: DML does not scale with record count.
        Assert.areEqual(1, dmlUsed, '200 episodes should collapse into a single DML statement');
    }
}
