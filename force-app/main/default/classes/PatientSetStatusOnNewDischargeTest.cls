/**
 * End-to-end through DML.
 *
 * Inserting a Discharge is enough to exercise this action: AdmissionDischargeSetLatest
 * stamps Patient.Latest_Discharge__c on that insert, and THAT patient update runs this
 * before-update action. The tests therefore insert a discharge rather than setting the
 * lookup by hand, because setting it by hand is not how the value ever changes in
 * production.
 *
 * AdmissionDischargeCreateEpisode and DischargeSendSms also fire on a discharge insert
 * and both write the same patient fields this action writes, so they are bypassed in
 * every method here. This class tests the reclaim in isolation; the cross-action
 * cascade has its own test.
 */
@isTest
private class PatientSetStatusOnNewDischargeTest {

    @TestSetup
    static void setupTestData() {
        insert new List<Patient__c>{
            new Patient__c(First_Name__c = 'Stale', Last_Name__c = 'Contact', Status__c = 'Active',
                           Community_Status__c = 'Working', Call_Outcome__c = 'Left Voicemail',
                           Latest_Call_Outcome__c = Date.today().addDays(-31)),
            new Patient__c(First_Name__c = 'Fresh', Last_Name__c = 'Contact', Status__c = 'Active',
                           Community_Status__c = 'Working',
                           Latest_Call_Outcome__c = Date.today().addDays(-5)),
            new Patient__c(First_Name__c = 'Never', Last_Name__c = 'Contacted', Status__c = 'Active',
                           Community_Status__c = 'Working')
        };
    }

    private static void isolateThisAction() {
        MetadataTriggerHandler.bypass('AdmissionDischargeCreateEpisode');
        MetadataTriggerHandler.bypass('DischargeSendSms');
    }

    private static Patient__c patientNamed(String lastName, String firstName) {
        return [SELECT Id, OwnerId, Community_Status__c, Call_Outcome__c,
                       Community_Status_Updated_Date_Time__c, Latest_Discharge__c
                FROM Patient__c
                WHERE Last_Name__c = :lastName AND First_Name__c = :firstName LIMIT 1];
    }

    private static Admission_Discharge__c newDischarge(Id patientId) {
        return new Admission_Discharge__c(
            Patient__c = patientId, Type__c = 'Discharge', Census_Date__c = Datetime.now().addDays(-1)
        );
    }

    @isTest
    static void staleContactPatientIsReclaimed() {
        isolateThisAction();
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Contact', 'Stale');

        Test.startTest();
        insert newDischarge(patient.Id);
        Test.stopTest();

        Patient__c reclaimed = patientNamed('Contact', 'Stale');
        Assert.areEqual('New', reclaimed.Community_Status__c, 'The patient should be re-queued as New');
        Assert.areEqual(null, reclaimed.Call_Outcome__c, 'Call_Outcome__c should be cleared');
        Assert.areNotEqual(null, reclaimed.Community_Status_Updated_Date_Time__c,
            'The status timestamp should be stamped');
        Assert.areEqual(UserInfo.getUserId(), reclaimed.OwnerId,
            'The patient should be handed to the reclaim owner');
    }

    @isTest
    static void freshContactPatientIsLeftAlone() {
        isolateThisAction();
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Contact', 'Fresh');

        Test.startTest();
        insert newDischarge(patient.Id);
        Test.stopTest();

        Patient__c untouched = patientNamed('Contact', 'Fresh');
        Assert.areEqual('Working', untouched.Community_Status__c,
            'A contact 5 days old is inside the 30 day threshold');
        Assert.areEqual(null, untouched.Community_Status_Updated_Date_Time__c,
            'No reclaim means no timestamp');
    }

    @isTest
    static void neverContactedPatientIsLeftAlone() {
        // The flow's first gate requires Latest_Call_Outcome__c to be POPULATED. A
        // never-contacted patient stops there, unlike the create-episode action where a
        // blank outcome qualifies. The two flows genuinely disagree on this and each
        // port preserves its own flow's rule.
        isolateThisAction();
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Contacted', 'Never');

        Test.startTest();
        insert newDischarge(patient.Id);
        Test.stopTest();

        Assert.areEqual('Working', patientNamed('Contacted', 'Never').Community_Status__c,
            'A blank Latest_Call_Outcome__c stops at the first gate');
    }

    @isTest
    static void updateWithoutDischargeChangeDoesNotReFire() {
        isolateThisAction();
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        Patient__c patient = patientNamed('Contact', 'Stale');
        insert newDischarge(patient.Id);

        // The insert above legitimately reclaimed the patient. Put the moved fields
        // back, which itself must not re-fire because the discharge date is unchanged.
        update new Patient__c(
            Id = patient.Id, Community_Status__c = 'Working',
            Latest_Call_Outcome__c = Date.today().addDays(-31)
        );

        Test.startTest();
        update new Patient__c(Id = patient.Id, Call_Outcome__c = 'Left Voicemail');
        Test.stopTest();

        Patient__c untouched = patientNamed('Contact', 'Stale');
        Assert.areEqual('Working', untouched.Community_Status__c,
            'An update that does not move the discharge date must not re-fire the reclaim');
        Assert.areEqual('Left Voicemail', untouched.Call_Outcome__c,
            'The user\'s own Call_Outcome__c write must survive');
    }

    @isTest
    static void missingReclaimOwnerStillSetsStatusAndKeepsOwner() {
        isolateThisAction();
        // In this sandbox the configured reclaim user exists AND is the user running the
        // tests, so this needs the explicit force flag - a plain "owner unchanged" check
        // would pass no matter what the code did.
        TcmSettings.forceNoReclaimOwner = true;
        Patient__c patient = patientNamed('Contact', 'Stale');
        Id originalOwner = patient.OwnerId;

        Test.startTest();
        insert newDischarge(patient.Id);
        Test.stopTest();

        Patient__c reclaimed = patientNamed('Contact', 'Stale');
        Assert.areEqual('New', reclaimed.Community_Status__c,
            'The status change is not hostage to the owner lookup');
        Assert.areEqual(originalOwner, reclaimed.OwnerId,
            'A missing reclaim owner leaves the current owner in place');
    }

    @isTest
    static void bulkReclaimStaysFlat() {
        isolateThisAction();
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();

        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < 100; i++) {
            patients.add(new Patient__c(
                First_Name__c = 'Bulk', Last_Name__c = 'Reclaim' + i, Status__c = 'Active',
                Community_Status__c = 'Working',
                Latest_Call_Outcome__c = Date.today().addDays(-40)
            ));
        }
        insert patients;

        List<Admission_Discharge__c> discharges = new List<Admission_Discharge__c>();
        for (Patient__c patient : patients) {
            discharges.add(newDischarge(patient.Id));
        }

        Test.startTest();
        insert discharges;
        Test.stopTest();

        Assert.areEqual(100,
            [SELECT COUNT() FROM Patient__c WHERE Community_Status__c = 'New'
             AND Last_Name__c LIKE 'Reclaim%'],
            'All hundred stale patients should be reclaimed in one save');
    }
}
