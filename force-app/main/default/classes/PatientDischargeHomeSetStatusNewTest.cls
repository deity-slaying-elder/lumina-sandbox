/**
 * Invoked directly rather than through DML. See the note in
 * CommunityEpisodeSetLatestOnPatientTest for why.
 *
 * Discharged_Home__c is a formula on Admission_Discharge__c derived from
 * To_From_Type__c, so these tests set the source field and let the formula resolve
 * rather than asserting against a value they wrote themselves.
 */
@isTest
private class PatientDischargeHomeSetStatusNewTest {

    @TestSetup
    static void setupTestData() {
        insert new Patient__c(First_Name__c = 'Discharged', Last_Name__c = 'Home', Status__c = 'Active');
    }

    private static Patient__c thePatient() {
        return [SELECT Id, Community_Status__c, Latest_Discharge__c FROM Patient__c LIMIT 1];
    }

    /**
     * Inserts a real Discharge, then puts the patient's status back.
     *
     * Discharged_Home__c is a formula that requires Type__c = 'Discharge', so this
     * insert cannot dodge Admission_Discharge_TF_On_Create_Create_Community_Episode,
     * which is still active in the sandbox and stamps Community_Status__c = 'New' on
     * the patient as a side effect. Left alone, that side effect is what the assertions
     * below would be reading. Resetting the status here means each test controls the
     * state its own gate depends on.
     */
    private static Admission_Discharge__c dischargeTo(Id patientId, String toFromType, String statusAfter) {
        Admission_Discharge__c record = new Admission_Discharge__c(
            Patient__c = patientId, Type__c = 'Discharge', To_From_Type__c = toFromType
        );
        insert record;
        update new Patient__c(Id = patientId, Community_Status__c = statusAfter);
        return [SELECT Id, Discharged_Home__c FROM Admission_Discharge__c WHERE Id = :record.Id];
    }

    private static void run(Patient__c before, Patient__c after) {
        TriggerContext.reset();
        new PatientDischargeHomeSetStatusNew().afterUpdate(
            new List<Patient__c>{ after }, new List<Patient__c>{ before }
        );
    }

    @isTest
    static void dischargedHomeSetsStatusNew() {
        Patient__c before = thePatient();
        Admission_Discharge__c record = dischargeTo(before.Id, 'Home', null);
        // Guard the premise. If the formula does not read this as discharged home the
        // test below would pass for the wrong reason.
        Assert.isTrue(record.Discharged_Home__c, 'To_From_Type__c of Home should resolve as discharged home');

        Patient__c after = before.clone(true, true, true, true);
        after.Latest_Discharge__c = record.Id;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual('New', thePatient().Community_Status__c,
            'A patient discharged home with no status should be queued as New');
    }

    @isTest
    static void notDischargedHomeIsSkipped() {
        Patient__c before = thePatient();
        Admission_Discharge__c record = dischargeTo(before.Id, 'Skilled Nursing Facility', null);
        Assert.isFalse(record.Discharged_Home__c, 'A nursing facility is not a discharge home');

        Patient__c after = before.clone(true, true, true, true);
        after.Latest_Discharge__c = record.Id;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual(null, thePatient().Community_Status__c,
            'Only a discharge home should set the status');
    }

    @isTest
    static void existingStatusIsNotOverwritten() {
        Patient__c seed = thePatient();
        Admission_Discharge__c record = dischargeTo(seed.Id, 'Home', 'Closed Lost');

        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Latest_Discharge__c = record.Id;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual('Closed Lost', thePatient().Community_Status__c,
            'The flow only fired when Community_Status__c was blank');
    }

    @isTest
    static void unchangedLatestDischargeIsSkipped() {
        Patient__c seed = thePatient();
        Admission_Discharge__c record = dischargeTo(seed.Id, 'Home', null);

        Patient__c before = thePatient();
        before.Latest_Discharge__c = record.Id;
        Patient__c after = before.clone(true, true, true, true);

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual(null, thePatient().Community_Status__c,
            'Latest_Discharge__c must actually change for this to run');
    }

    @isTest
    static void bulkStaysAtOneQueryAndOneDml() {
        Patient__c seed = thePatient();
        Admission_Discharge__c record = dischargeTo(seed.Id, 'Home', null);

        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < 200; i++) {
            patients.add(new Patient__c(
                First_Name__c = 'Bulk', Last_Name__c = 'Home' + i, Status__c = 'Active'
            ));
        }
        insert patients;

        List<Patient__c> olds = new List<Patient__c>();
        List<Patient__c> news = new List<Patient__c>();
        for (Patient__c patient : patients) {
            Patient__c old = new Patient__c(Id = patient.Id, Community_Status__c = null, Latest_Discharge__c = null);
            Patient__c updated = old.clone(true, true, true, true);
            updated.Latest_Discharge__c = record.Id;
            olds.add(old);
            news.add(updated);
        }

        Test.startTest();
        TriggerContext.reset();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        new PatientDischargeHomeSetStatusNew().afterUpdate(news, olds);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(1, queriesUsed, 'The discharge lookup must be a single query for the whole batch');
        // This action issues one update. The second statement is the automation that
        // update sets off: PatientTrigger's after update context runs the other two
        // converted Patient actions, and the Patient flows still active in this org fire
        // as well. The property that matters is that the number is a constant and does
        // not grow with the two hundred patients, so it is asserted as a ceiling.
        Assert.isTrue(dmlUsed <= 2,
            '200 patients must not scale DML, got ' + dmlUsed);
    }
}
