/**
 * Direct-invocation tests, for the same reason as AdmissionDischargeSetLatestTest:
 * the Trigger_Action__mdt records that register this action cannot be deployed
 * into this org yet, so the action is called explicitly. Add a parity pass through
 * real DML once the wiring lands.
 */
@isTest
private class VisitSetLatestVisitProviderTest {

    @TestSetup
    static void setupTestData() {
        Account parent = new Account(Name = 'Parent Co');
        insert parent;
        Facility__c fac = new Facility__c(Name = 'Fac 1', Parent_Company__c = parent.Id);
        insert fac;
        insert new Patient__c(
            First_Name__c = 'Ada', Last_Name__c = 'Lovelace',
            Status__c = 'Active', Facility__c = fac.Id
        );
        insert new List<Front_End_User__c>{
            new Front_End_User__c(Name = 'Provider A'),
            new Front_End_User__c(Name = 'Provider B')
        };
    }

    private static Patient__c patient() {
        return [SELECT Id, Latest_Visit_Provider__c FROM Patient__c LIMIT 1];
    }

    private static Front_End_User__c provider(String name) {
        return [SELECT Id FROM Front_End_User__c WHERE Name = :name LIMIT 1];
    }

    private static void run(List<Visit__c> visits) {
        new VisitSetLatestVisitProvider().afterInsert(visits);
    }

    @isTest
    static void seenVisitStampsTheProvider() {
        Visit__c v = new Visit__c(
            Patient__c = patient().Id,
            Front_End_User__c = provider('Provider A').Id,
            Visit_DateTime__c = Datetime.newInstanceGmt(2026, 3, 1, 10, 0, 0)
        );
        insert v;

        Test.startTest();
        run(new List<Visit__c>{ v });
        Test.stopTest();

        Assert.areEqual(provider('Provider A').Id, patient().Latest_Visit_Provider__c,
            'A seen visit should stamp its provider onto the patient');
    }

    @isTest
    static void notSeenVisitIsSkipped() {
        Visit__c v = new Visit__c(
            Patient__c = patient().Id,
            Front_End_User__c = provider('Provider A').Id,
            Visit_DateTime__c = Datetime.newInstanceGmt(2026, 3, 1, 10, 0, 0),
            Not_Seen_Reason__c = 'Unavailable'
        );
        insert v;

        Test.startTest();
        run(new List<Visit__c>{ v });
        Test.stopTest();

        Assert.isNull(patient().Latest_Visit_Provider__c,
            'The flow entry criteria required Not_Seen_Reason__c to be blank');
    }

    @isTest
    static void lastVisitInTheBatchWins() {
        Id patientId = patient().Id;
        Visit__c first = new Visit__c(
            Patient__c = patientId, Front_End_User__c = provider('Provider A').Id,
            Visit_DateTime__c = Datetime.newInstanceGmt(2026, 3, 1, 10, 0, 0)
        );
        Visit__c second = new Visit__c(
            Patient__c = patientId, Front_End_User__c = provider('Provider B').Id,
            Visit_DateTime__c = Datetime.newInstanceGmt(2026, 3, 2, 10, 0, 0)
        );
        insert new List<Visit__c>{ first, second };

        Test.startTest();
        run(new List<Visit__c>{ first, second });
        Test.stopTest();

        Assert.areEqual(provider('Provider B').Id, patient().Latest_Visit_Provider__c,
            'Trigger.new order decides the winner, matching the flow sequential interviews');
    }

    @isTest
    static void olderVisitOverwritesNewerProvider_knownDefect() {
        Id patientId = patient().Id;
        Visit__c newer = new Visit__c(
            Patient__c = patientId, Front_End_User__c = provider('Provider B').Id,
            Visit_DateTime__c = Datetime.newInstanceGmt(2026, 5, 1, 10, 0, 0)
        );
        insert newer;
        run(new List<Visit__c>{ newer });

        Visit__c older = new Visit__c(
            Patient__c = patientId, Front_End_User__c = provider('Provider A').Id,
            Visit_DateTime__c = Datetime.newInstanceGmt(2026, 1, 1, 10, 0, 0)
        );
        insert older;

        Test.startTest();
        run(new List<Visit__c>{ older });
        Test.stopTest();

        // Characterises the flow defect deliberately. Editing an OLD visit clobbers
        // the latest provider. If this assertion ever starts failing, someone fixed
        // the behaviour, which is a real change and needs sign-off, not a test edit.
        Assert.areEqual(provider('Provider A').Id, patient().Latest_Visit_Provider__c,
            'Known defect carried forward: the triggering visit wins, not the latest');
    }

    @isTest
    static void nullProviderIsWrittenAsNull() {
        Visit__c v = new Visit__c(
            Patient__c = patient().Id,
            Visit_DateTime__c = Datetime.newInstanceGmt(2026, 3, 1, 10, 0, 0)
        );
        insert v;

        Test.startTest();
        run(new List<Visit__c>{ v });
        Test.stopTest();

        Assert.isNull(patient().Latest_Visit_Provider__c,
            'The flow assigned $Record.Front_End_User__r.Id unconditionally, so a blank clears it');
    }

    @isTest
    static void bulkInsertKeepsQueryAndDmlCountFlat() {
        Id patientId = patient().Id;
        Id providerId = provider('Provider A').Id;
        List<Visit__c> batch = new List<Visit__c>();
        for (Integer i = 0; i < 200; i++) {
            batch.add(new Visit__c(
                Patient__c = patientId, Front_End_User__c = providerId,
                Visit_DateTime__c = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0).addDays(i)
            ));
        }
        insert batch;

        Test.startTest();
        Integer q = Limits.getQueries();
        Integer d = Limits.getDmlStatements();
        run(batch);
        Integer queriesUsed = Limits.getQueries() - q;
        Integer dmlUsed = Limits.getDmlStatements() - d;
        Test.stopTest();

        // 200 visits for one patient must collapse to a single DML row. That is the
        // assertion that matters and it is exact.
        Assert.areEqual(1, dmlUsed, 'Expected exactly one DML, used ' + dmlUsed);
        // The action itself issues no SOQL. Any queries counted here come from the
        // Patient triggers that the one Patient update fires downstream, which is
        // why this is a ceiling rather than zero.
        Assert.isTrue(queriesUsed <= 3, 'Expected a constant query count, used ' + queriesUsed);
    }
}
