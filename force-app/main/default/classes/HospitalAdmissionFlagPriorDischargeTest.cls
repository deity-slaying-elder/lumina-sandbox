@isTest
private class HospitalAdmissionFlagPriorDischargeTest {

    private static final Datetime ADMIT_TIME = Datetime.newInstanceGmt(2026, 6, 15, 12, 0, 0);

    @TestSetup
    static void setupTestData() {
        insert new List<Patient__c>{
            new Patient__c(First_Name__c = 'Qual', Last_Name__c = 'Ifying', Status__c = 'Active'),
            new Patient__c(First_Name__c = 'Out', Last_Name__c = 'OfWindow', Status__c = 'Active'),
            new Patient__c(First_Name__c = 'Not', Last_Name__c = 'Home', Status__c = 'Active')
        };
    }

    private static Patient__c patientNamed(String lastName) {
        return [SELECT Id FROM Patient__c WHERE Last_Name__c = :lastName LIMIT 1];
    }

    /** Discharged_Home__c is a formula: Type = Discharge AND To_From_Type contains home/alf/assisted. */
    private static Admission_Discharge__c discharge(Id patientId, Datetime censusDate, String toFromType) {
        return new Admission_Discharge__c(
            Patient__c = patientId,
            Type__c = 'Discharge',
            To_From_Type__c = toFromType,
            Census_Date__c = censusDate
        );
    }

    @isTest
    static void flagsAdmissionWithPriorDischargeHomeInWindow() {
        Patient__c patient = patientNamed('Ifying');
        insert discharge(patient.Id, ADMIT_TIME.addDays(-10), 'Home');

        Test.startTest();
        Hospital_Admission__c admission = new Hospital_Admission__c(
            Patient__c = patient.Id, Admit_DateTime__c = ADMIT_TIME
        );
        insert admission;
        Test.stopTest();

        Assert.isTrue(
            [SELECT Was_Discharged_Home_From_SNF__c FROM Hospital_Admission__c WHERE Id = :admission.Id].Was_Discharged_Home_From_SNF__c,
            'A discharge home 10 days before admission is inside the 30-day window'
        );
    }

    @isTest
    static void ignoresDischargeOlderThanThirtyDays() {
        Patient__c patient = patientNamed('OfWindow');
        insert discharge(patient.Id, ADMIT_TIME.addDays(-40), 'Home');

        Test.startTest();
        Hospital_Admission__c admission = new Hospital_Admission__c(
            Patient__c = patient.Id, Admit_DateTime__c = ADMIT_TIME
        );
        insert admission;
        Test.stopTest();

        Assert.isFalse(
            [SELECT Was_Discharged_Home_From_SNF__c FROM Hospital_Admission__c WHERE Id = :admission.Id].Was_Discharged_Home_From_SNF__c,
            'A discharge 40 days before admission is outside the window'
        );
    }

    @isTest
    static void ignoresDischargeThatIsNotHome() {
        Patient__c patient = patientNamed('Home');
        // "nursing" is explicitly excluded by the Discharged_Home__c formula.
        insert discharge(patient.Id, ADMIT_TIME.addDays(-5), 'Skilled Nursing');

        Test.startTest();
        Hospital_Admission__c admission = new Hospital_Admission__c(
            Patient__c = patient.Id, Admit_DateTime__c = ADMIT_TIME
        );
        insert admission;
        Test.stopTest();

        Assert.isFalse(
            [SELECT Was_Discharged_Home_From_SNF__c FROM Hospital_Admission__c WHERE Id = :admission.Id].Was_Discharged_Home_From_SNF__c,
            'A discharge to skilled nursing is not a discharge home'
        );
    }

    @isTest
    static void ignoresDischargeAfterTheAdmission() {
        Patient__c patient = patientNamed('Ifying');
        insert discharge(patient.Id, ADMIT_TIME.addDays(2), 'Home');

        Test.startTest();
        Hospital_Admission__c admission = new Hospital_Admission__c(
            Patient__c = patient.Id, Admit_DateTime__c = ADMIT_TIME
        );
        insert admission;
        Test.stopTest();

        Assert.isFalse(
            [SELECT Was_Discharged_Home_From_SNF__c FROM Hospital_Admission__c WHERE Id = :admission.Id].Was_Discharged_Home_From_SNF__c,
            'A discharge after the admission must not count'
        );
    }

    @isTest
    static void skipsWhenTriggerIsBypassed() {
        MetadataTriggerHandler.bypass('HospitalAdmissionFlagPriorDischarge');

        Patient__c patient = patientNamed('Ifying');
        insert discharge(patient.Id, ADMIT_TIME.addDays(-10), 'Home');

        Test.startTest();
        Hospital_Admission__c admission = new Hospital_Admission__c(
            Patient__c = patient.Id, Admit_DateTime__c = ADMIT_TIME
        );
        insert admission;
        Test.stopTest();

        Assert.isFalse(
            [SELECT Was_Discharged_Home_From_SNF__c FROM Hospital_Admission__c WHERE Id = :admission.Id].Was_Discharged_Home_From_SNF__c,
            'The per-trigger bypass should suppress the stamp'
        );
    }

    @isTest
    static void handlesBulkInsertWithoutScalingQueries() {
        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < 200; i++) {
            patients.add(new Patient__c(First_Name__c = 'Bulk', Last_Name__c = 'Patient' + i, Status__c = 'Active'));
        }
        insert patients;

        List<Admission_Discharge__c> discharges = new List<Admission_Discharge__c>();
        for (Patient__c patient : patients) {
            discharges.add(discharge(patient.Id, ADMIT_TIME.addDays(-10), 'Home'));
        }
        insert discharges;

        List<Hospital_Admission__c> admissions = new List<Hospital_Admission__c>();
        for (Patient__c patient : patients) {
            admissions.add(new Hospital_Admission__c(Patient__c = patient.Id, Admit_DateTime__c = ADMIT_TIME));
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        insert admissions;
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Hospital_Admission__c WHERE Was_Discharged_Home_From_SNF__c = TRUE],
            'All 200 admissions should be flagged');
        Assert.isTrue(queriesUsed <= 5, 'Expected a constant number of queries, used ' + queriesUsed);
        Assert.isTrue(dmlUsed <= 5, 'Expected a constant number of DML statements, used ' + dmlUsed);
    }
}
