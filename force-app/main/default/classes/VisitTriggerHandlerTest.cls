@isTest
private class VisitTriggerHandlerTest {

    private static final Datetime VISIT_TIME = Datetime.newInstanceGmt(2026, 6, 15, 9, 0, 0);

    @TestSetup
    static void setupTestData() {
        insert new List<Patient__c>{
            new Patient__c(First_Name__c = 'First', Last_Name__c = 'Visit', Status__c = 'Active'),
            new Patient__c(First_Name__c = 'Repeat', Last_Name__c = 'Visitor', Status__c = 'Active',
                           Initial_Visit_Date__c = Date.newInstance(2026, 1, 1)),
            new Patient__c(First_Name__c = 'Missed', Last_Name__c = 'Appointment', Status__c = 'Active')
        };
    }

    private static Patient__c patientNamed(String lastName) {
        return [SELECT Id, Initial_Visit_Date__c, Initial_Visit_Provider__c,
                       Latest_Visit_DateTime__c, Latest_Not_Seen_DateTime__c
                FROM Patient__c WHERE Last_Name__c = :lastName LIMIT 1];
    }

    @isTest
    static void firstVisitStampsInitialFields() {
        Patient__c patient = patientNamed('Visit');

        Test.startTest();
        insert new Visit__c(Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME);
        Test.stopTest();

        Patient__c updated = patientNamed('Visit');
        Assert.areEqual(VISIT_TIME.date(), updated.Initial_Visit_Date__c,
            'Initial_Visit_Date__c should be the visit date');
        Assert.areEqual(VISIT_TIME, updated.Latest_Visit_DateTime__c,
            'Latest_Visit_DateTime__c should also be set on the first visit');
    }

    @isTest
    static void subsequentVisitUpdatesOnlyLatest() {
        Patient__c patient = patientNamed('Visitor');
        Date originalInitial = patient.Initial_Visit_Date__c;

        Test.startTest();
        insert new Visit__c(Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME);
        Test.stopTest();

        Patient__c updated = patientNamed('Visitor');
        Assert.areEqual(originalInitial, updated.Initial_Visit_Date__c,
            'Initial_Visit_Date__c must not be overwritten once populated');
        Assert.areEqual(VISIT_TIME, updated.Latest_Visit_DateTime__c,
            'Latest_Visit_DateTime__c should advance');
    }

    @isTest
    static void notSeenVisitStampsOnlyNotSeenDate() {
        Patient__c patient = patientNamed('Appointment');

        Test.startTest();
        insert new Visit__c(
            Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME, Not_Seen_Reason__c = 'Unavailable'
        );
        Test.stopTest();

        Patient__c updated = patientNamed('Appointment');
        Assert.isNotNull(updated.Latest_Not_Seen_DateTime__c,
            'Latest_Not_Seen_DateTime__c should be stamped');
        Assert.isNull(updated.Initial_Visit_Date__c,
            'The not-seen branch is terminal, so Initial_Visit_Date__c must stay blank');
        Assert.isNull(updated.Latest_Visit_DateTime__c,
            'The not-seen branch must not advance Latest_Visit_DateTime__c');
    }

    @isTest
    static void twoVisitsForOnePatientInOneSaveOnlySetInitialOnce() {
        Patient__c patient = patientNamed('Visit');

        Test.startTest();
        insert new List<Visit__c>{
            new Visit__c(Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME),
            new Visit__c(Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME.addDays(3))
        };
        Test.stopTest();

        Patient__c updated = patientNamed('Visit');
        // The flow ran per record, so the second interview saw the first one's write
        // and took the "not initial" branch. The batch must behave the same way.
        Assert.areEqual(VISIT_TIME.date(), updated.Initial_Visit_Date__c,
            'Initial_Visit_Date__c should come from the FIRST visit in the batch');
        Assert.areEqual(VISIT_TIME.addDays(3), updated.Latest_Visit_DateTime__c,
            'Latest_Visit_DateTime__c should come from the last visit in the batch');
    }

    @isTest
    static void updatingAVisitAdvancesLatestVisitDateTime() {
        Patient__c patient = patientNamed('Visitor');
        Visit__c visit = new Visit__c(Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME);
        insert visit;

        Test.startTest();
        visit.Visit_DateTime__c = VISIT_TIME.addDays(7);
        update visit;
        Test.stopTest();

        Assert.areEqual(VISIT_TIME.addDays(7), patientNamed('Visitor').Latest_Visit_DateTime__c,
            'The after-update path should advance Latest_Visit_DateTime__c');
    }

    @isTest
    static void updatingAVisitToNotSeenStampsNotSeenDate() {
        Patient__c patient = patientNamed('Appointment');
        Visit__c visit = new Visit__c(Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME);
        insert visit;

        Test.startTest();
        visit.Not_Seen_Reason__c = 'Hospital';
        update visit;
        Test.stopTest();

        Assert.isNotNull(patientNamed('Appointment').Latest_Not_Seen_DateTime__c,
            'Switching a visit to not-seen on update should stamp the not-seen date');
    }

    @isTest
    static void skipsWhenTriggerIsBypassed() {
        TriggerContext.bypass('VisitTrigger');

        Patient__c patient = patientNamed('Visit');

        Test.startTest();
        insert new Visit__c(Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME);
        Test.stopTest();

        Assert.isNull(patientNamed('Visit').Initial_Visit_Date__c,
            'The per-trigger bypass should suppress the Patient write');
    }

    @isTest
    static void handlesBulkInsertWithoutScalingQueries() {
        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < 200; i++) {
            patients.add(new Patient__c(First_Name__c = 'Bulk', Last_Name__c = 'V' + i, Status__c = 'Active'));
        }
        insert patients;

        List<Visit__c> visits = new List<Visit__c>();
        for (Patient__c patient : patients) {
            visits.add(new Visit__c(Patient__c = patient.Id, Visit_DateTime__c = VISIT_TIME));
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        insert visits;
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Patient__c WHERE Initial_Visit_Date__c = :VISIT_TIME.date()],
            'All 200 patients should have their initial visit stamped');
        Assert.isTrue(queriesUsed <= 5, 'Expected a constant number of queries, used ' + queriesUsed);
        Assert.isTrue(dmlUsed <= 5, 'Expected a constant number of DML statements, used ' + dmlUsed);
    }
}
