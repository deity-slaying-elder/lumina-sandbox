/**
 * End-to-end through DML.
 *
 * AdmissionDischargeTrigger invokes this action on after insert and the flow it
 * replaces is deactivated in the sandbox, so inserting a discharge exercises the real
 * path. Calling the action directly as well would create every episode twice.
 *
 * TcmSettings.reclaimOwnerOverride is set in each method so these tests do not depend
 * on the production administrator account existing in this org.
 */
@isTest
private class AdmissionDischargeCreateEpisodeTest {

    @TestSetup
    static void setupTestData() {
        insert new List<Patient__c>{
            // No call outcome at all - qualifies as new.
            new Patient__c(First_Name__c = 'Never', Last_Name__c = 'Called', Status__c = 'Active'),
            // Contacted long ago - qualifies as re-engaging.
            new Patient__c(First_Name__c = 'Long', Last_Name__c = 'Ago', Status__c = 'Active',
                           Latest_Call_Outcome__c = Date.today().addDays(-31)),
            // Contacted recently - must be left alone.
            new Patient__c(First_Name__c = 'Just', Last_Name__c = 'Spoke', Status__c = 'Active',
                           Latest_Call_Outcome__c = Date.today().addDays(-5))
        };
    }

    private static Patient__c patientNamed(String lastName) {
        return [SELECT Id, OwnerId, Community_Status__c, Call_Outcome__c, Latest_Call_Outcome__c
                FROM Patient__c WHERE Last_Name__c = :lastName LIMIT 1];
    }

    private static Integer episodeCountFor(Id patientId) {
        return [SELECT COUNT() FROM Community_Episode__c WHERE Patient__c = :patientId];
    }

    @isTest
    static void neverCalledPatientGetsEpisode() {
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Called');

        Test.startTest();
        insert new Admission_Discharge__c(Patient__c = patient.Id, Type__c = 'Discharge');
        Test.stopTest();

        List<Community_Episode__c> episodes = [
            SELECT Id, Community_Status__c, Admission_Discharge__c
            FROM Community_Episode__c WHERE Patient__c = :patient.Id
        ];
        Assert.areEqual(1, episodes.size(), 'One episode should be created');
        Assert.areEqual('New', episodes[0].Community_Status__c, 'Episode status should be New');
        Assert.areNotEqual(null, episodes[0].Admission_Discharge__c,
            'Episode should link back to the discharge');

        Patient__c reset = patientNamed('Called');
        Assert.areEqual('New', reset.Community_Status__c, 'Patient should be re-queued as New');
        Assert.areEqual(UserInfo.getUserId(), reset.OwnerId,
            'Patient should be reassigned to the reclaim owner');
    }

    @isTest
    static void staleContactPatientGetsEpisode() {
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Ago');

        Test.startTest();
        insert new Admission_Discharge__c(Patient__c = patient.Id, Type__c = 'Discharge');
        Test.stopTest();

        Assert.areEqual(1, episodeCountFor(patient.Id),
            'A contact 31 days old is past the 30 day threshold, so an episode is due');
    }

    @isTest
    static void recentContactPatientIsSkipped() {
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Spoke');
        Id originalOwner = patient.OwnerId;

        Test.startTest();
        insert new Admission_Discharge__c(Patient__c = patient.Id, Type__c = 'Discharge');
        Test.stopTest();

        Assert.areEqual(0, episodeCountFor(patient.Id),
            'A patient contacted 5 days ago should not get a new episode');
        Assert.areEqual(originalOwner, patientNamed('Spoke').OwnerId,
            'A skipped patient must keep its owner');
    }

    @isTest
    static void admissionTypeIsIgnored() {
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Called');

        Test.startTest();
        insert new Admission_Discharge__c(Patient__c = patient.Id, Type__c = 'Admission');
        Test.stopTest();

        Assert.areEqual(0, episodeCountFor(patient.Id),
            'Only Type__c = Discharge should open an episode');
    }

    @isTest
    static void missingReclaimOwnerLeavesOwnerAlone() {
        // In this sandbox the configured reclaim user exists AND runs the tests, so
        // "owner unchanged" would pass vacuously without the explicit force flag.
        TcmSettings.forceNoReclaimOwner = true;
        Patient__c patient = patientNamed('Called');
        Id originalOwner = patient.OwnerId;

        Test.startTest();
        insert new Admission_Discharge__c(Patient__c = patient.Id, Type__c = 'Discharge');
        Test.stopTest();

        Assert.areEqual(1, episodeCountFor(patient.Id),
            'The episode is still created even when the reclaim owner is absent');
        Assert.areEqual(originalOwner, patientNamed('Called').OwnerId,
            'A missing reclaim owner must not roll back the save');
    }

    @isTest
    static void skipsWhenActionIsBypassed() {
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        // Per-action runtime bypass, the flag the trigger checks before invoking this
        // action, and the same flag the framework's dispatch honours after takeover.
        MetadataTriggerHandler.bypass('AdmissionDischargeCreateEpisode');
        Patient__c patient = patientNamed('Called');

        Test.startTest();
        insert new Admission_Discharge__c(Patient__c = patient.Id, Type__c = 'Discharge');
        Test.stopTest();

        Assert.areEqual(0, episodeCountFor(patient.Id),
            'The per-action bypass should suppress the episode entirely');
    }

    @isTest
    static void sixtyDischargesForOnePatientDoNotHitTheDuplicateLimit() {
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Called');

        // THIS IS THE TEST LMNA-580 EXISTS FOR.
        //
        // The flow updated the patient once per discharge record. Salesforce caps a
        // single API call at twelve updates of the same Id, so thirteen or more
        // discharges for one patient in one save threw DUPLICATE_VALUE, "Maximum number
        // of duplicate updates in one batch (12 allowed)", and rolled the entire insert
        // back. Sixty is five times that ceiling, and this insert has to succeed.
        List<Admission_Discharge__c> records = new List<Admission_Discharge__c>();
        for (Integer i = 0; i < 60; i++) {
            records.add(new Admission_Discharge__c(Patient__c = patient.Id, Type__c = 'Discharge'));
        }

        Test.startTest();
        insert records;
        Test.stopTest();

        Assert.areEqual(60, episodeCountFor(patient.Id),
            'Every discharge still gets its own episode, as the flow produced');
        Assert.areEqual('New', patientNamed('Called').Community_Status__c,
            'The single collapsed patient write still lands');
    }

    @isTest
    static void bulkAcrossManyPatientsStaysFlat() {
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();

        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < 50; i++) {
            patients.add(new Patient__c(
                First_Name__c = 'Bulk', Last_Name__c = 'Discharge' + i, Status__c = 'Active'
            ));
        }
        insert patients;

        List<Admission_Discharge__c> records = new List<Admission_Discharge__c>();
        for (Patient__c patient : patients) {
            for (Integer i = 0; i < 4; i++) {
                records.add(new Admission_Discharge__c(Patient__c = patient.Id, Type__c = 'Discharge'));
            }
        }

        Test.startTest();
        insert records;
        Test.stopTest();

        Assert.areEqual(200,
            [SELECT COUNT() FROM Community_Episode__c WHERE Patient__c IN :patients],
            'Two hundred discharges across fifty patients, two hundred episodes');
    }
}
