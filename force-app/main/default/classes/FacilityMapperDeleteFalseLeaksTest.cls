@isTest
private class FacilityMapperDeleteFalseLeaksTest {

    @TestSetup
    static void setupTestData() {
        List<Account> parents = new List<Account>{
            new Account(Name = 'Parent Company A'),
            new Account(Name = 'Parent Company B')
        };
        insert parents;

        List<Facility__c> facilities = new List<Facility__c>{
            new Facility__c(Name = 'Facility A1', Parent_Company__c = parents[0].Id),
            new Facility__c(Name = 'Facility B1', Parent_Company__c = parents[1].Id)
        };
        insert facilities;

        List<Patient__c> patients = new List<Patient__c>{
            new Patient__c(First_Name__c = 'Ada', Last_Name__c = 'Same', Status__c = 'Active', Facility__c = facilities[0].Id),
            new Patient__c(First_Name__c = 'Bo', Last_Name__c = 'Different', Status__c = 'Active', Facility__c = facilities[1].Id)
        };
        insert patients;

        // Mapper starts on the B facility so the test can move it to A.
        Facility_Mapper__c mapper = new Facility_Mapper__c(Facility__c = facilities[1].Id);
        insert mapper;

        insert new List<Leaked_Admission__c>{
            new Leaked_Admission__c(Facility_Mapper__c = mapper.Id, Patient__c = patients[0].Id),
            new Leaked_Admission__c(Facility_Mapper__c = mapper.Id, Patient__c = patients[1].Id)
        };
    }

    private static Facility__c facilityNamed(String name) {
        return [SELECT Id FROM Facility__c WHERE Name = :name LIMIT 1];
    }

    @isTest
    static void deletesOnlyLeakedAdmissionsSharingTheParentCompany() {
        Facility_Mapper__c mapper = [SELECT Id, Facility__c FROM Facility_Mapper__c LIMIT 1];
        Facility__c facilityA = facilityNamed('Facility A1');

        Test.startTest();
        mapper.Facility__c = facilityA.Id;
        update mapper;
        Test.stopTest();

        List<Leaked_Admission__c> remaining = [
            SELECT Id, Patient__r.Last_Name__c FROM Leaked_Admission__c
        ];
        Assert.areEqual(1, remaining.size(), 'Only the matching-parent leaked admission should be deleted');
        Assert.areEqual('Different', remaining[0].Patient__r.Last_Name__c,
            'The surviving record should be the one whose parent company differs');
    }

    @isTest
    static void doesNothingWhenFacilityDidNotChange() {
        Facility_Mapper__c mapper = [SELECT Id, Facility__c FROM Facility_Mapper__c LIMIT 1];

        Test.startTest();
        // Touch the record without changing Facility__c - the flow's entry criteria
        // required IsChanged, so this must be a no-op.
        update mapper;
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Leaked_Admission__c],
            'No leaked admissions should be deleted when Facility__c is unchanged');
    }

    @isTest
    static void skipsWhenTriggerIsBypassed() {
        // Per-action runtime bypass, the flag the trigger checks before invoking this
        // action, and the same flag the framework's dispatch honours after takeover.
        MetadataTriggerHandler.bypass('FacilityMapperDeleteFalseLeaks');

        Facility_Mapper__c mapper = [SELECT Id, Facility__c FROM Facility_Mapper__c LIMIT 1];
        Facility__c facilityA = facilityNamed('Facility A1');

        Test.startTest();
        mapper.Facility__c = facilityA.Id;
        update mapper;
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM Leaked_Admission__c],
            'The per-action bypass should suppress the delete entirely');
    }

    @isTest
    static void handlesBulkUpdateWithoutScalingQueries() {
        Account parent = [SELECT Id FROM Account WHERE Name = 'Parent Company A' LIMIT 1];
        Facility__c facilityA = facilityNamed('Facility A1');

        Patient__c patient = new Patient__c(
            First_Name__c = 'Bulk', Last_Name__c = 'Patient',
            Status__c = 'Active', Facility__c = facilityA.Id
        );
        insert patient;

        List<Facility_Mapper__c> mappers = new List<Facility_Mapper__c>();
        for (Integer i = 0; i < 200; i++) {
            mappers.add(new Facility_Mapper__c(Facility__c = null));
        }
        insert mappers;

        List<Leaked_Admission__c> leaked = new List<Leaked_Admission__c>();
        for (Facility_Mapper__c mapper : mappers) {
            leaked.add(new Leaked_Admission__c(Facility_Mapper__c = mapper.Id, Patient__c = patient.Id));
        }
        insert leaked;

        for (Facility_Mapper__c mapper : mappers) {
            mapper.Facility__c = facilityA.Id;
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        update mappers;
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Leaked_Admission__c WHERE Facility_Mapper__c IN :mappers],
            'All 200 matching leaked admissions should be deleted');
        // The whole point of the ticket: cost stays flat as volume rises.
        Assert.isTrue(queriesUsed <= 5, 'Expected a constant number of queries, used ' + queriesUsed);
        Assert.isTrue(dmlUsed <= 5, 'Expected a constant number of DML statements, used ' + dmlUsed);
    }
}
