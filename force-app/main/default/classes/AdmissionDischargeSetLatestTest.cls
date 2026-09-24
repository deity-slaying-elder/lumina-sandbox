/**
 * Direct-invocation tests. The action is called explicitly rather than through a
 * DML save, because the Trigger_Action__mdt records that register it cannot be
 * deployed into this org yet. Once they land, add a parity pass that saves records
 * and asserts the same outcomes through the trigger.
 */
@isTest
private class AdmissionDischargeSetLatestTest {

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
    }

    private static Patient__c patient() {
        return [SELECT Id, Name, Latest_Admission__c, Latest_Discharge__c FROM Patient__c LIMIT 1];
    }

    private static Admission_Discharge__c makeAD(String type, Datetime census) {
        Admission_Discharge__c ad = new Admission_Discharge__c(
            Patient__c = patient().Id, Type__c = type, Census_Date__c = census
        );
        insert ad;
        return ad;
    }

    /** Invokes the action the way the framework would, then clears the guard. */
    private static void runAfterInsert(List<Admission_Discharge__c> records) {
        TriggerContext.reset();
        new AdmissionDischargeSetLatest().afterInsert(records);
    }

    @isTest
    static void admissionSetsLatestAdmissionWhenBlank() {
        Admission_Discharge__c ad = makeAD('Admission', Datetime.newInstanceGmt(2026, 3, 1, 12, 0, 0));

        Test.startTest();
        runAfterInsert(new List<Admission_Discharge__c>{ ad });
        Test.stopTest();

        Assert.areEqual(ad.Id, patient().Latest_Admission__c, 'Blank latest admission should be filled');
        Assert.isNull(patient().Latest_Discharge__c, 'The discharge lookup must not be touched');
    }

    @isTest
    static void laterAdmissionReplacesEarlierOne() {
        Admission_Discharge__c first = makeAD('Admission', Datetime.newInstanceGmt(2026, 3, 1, 12, 0, 0));
        runAfterInsert(new List<Admission_Discharge__c>{ first });
        Admission_Discharge__c second = makeAD('Admission', Datetime.newInstanceGmt(2026, 4, 1, 12, 0, 0));

        Test.startTest();
        runAfterInsert(new List<Admission_Discharge__c>{ second });
        Test.stopTest();

        Assert.areEqual(second.Id, patient().Latest_Admission__c, 'The later admission should win');
    }

    @isTest
    static void earlierAdmissionDoesNotReplace() {
        Admission_Discharge__c later = makeAD('Admission', Datetime.newInstanceGmt(2026, 4, 1, 12, 0, 0));
        runAfterInsert(new List<Admission_Discharge__c>{ later });
        Admission_Discharge__c earlier = makeAD('Admission', Datetime.newInstanceGmt(2026, 3, 1, 12, 0, 0));

        Test.startTest();
        runAfterInsert(new List<Admission_Discharge__c>{ earlier });
        Test.stopTest();

        Assert.areEqual(later.Id, patient().Latest_Admission__c,
            'An earlier admission must not overwrite a later one');
    }

    @isTest
    static void dischargeSetsLatestDischarge() {
        Admission_Discharge__c ad = makeAD('Discharge', Datetime.newInstanceGmt(2026, 3, 5, 9, 0, 0));

        Test.startTest();
        runAfterInsert(new List<Admission_Discharge__c>{ ad });
        Test.stopTest();

        Assert.areEqual(ad.Id, patient().Latest_Discharge__c, 'Discharge should fill the discharge lookup');
        Assert.isNull(patient().Latest_Admission__c, 'The admission lookup must not be touched');
    }

    @isTest
    static void nameIsBuiltFromPatientTypeAndGmtDate() {
        // GMT matters: DATEVALUE in the flow converted in GMT, so a late-evening
        // local time must still render as the GMT calendar date.
        String built = AdmissionDischargeSetLatest.buildName(
            'Ada Lovelace', 'Admission', Datetime.newInstanceGmt(2026, 3, 1, 23, 30, 0)
        );
        Assert.areEqual('Ada Lovelace - Admission - 2026-03-01', built,
            'Name should be "Patient - Type - yyyy-MM-dd" using the GMT date');
    }

    @isTest
    static void nameIsTruncatedAtEightyCharacters() {
        String built = AdmissionDischargeSetLatest.buildName(
            'X'.repeat(200), 'Discharge', Datetime.newInstanceGmt(2026, 3, 1, 0, 0, 0)
        );
        Assert.areEqual(80, built.length(), 'The flow wrapped the whole expression in LEFT(...,80)');
    }

    @isTest
    static void nullComponentsConcatenateAsEmpty() {
        Assert.areEqual(' -  - ', AdmissionDischargeSetLatest.buildName(null, null, null),
            'A flow formula treats blanks as empty text rather than throwing');
    }

    @isTest
    static void bulkInsertKeepsQueryAndDmlCountFlat() {
        Patient__c p = patient();
        List<Admission_Discharge__c> batch = new List<Admission_Discharge__c>();
        for (Integer i = 0; i < 200; i++) {
            batch.add(new Admission_Discharge__c(
                Patient__c = p.Id, Type__c = 'Admission',
                Census_Date__c = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0).addDays(i)
            ));
        }
        // Inserted in chunks of 10 on purpose. The flow this action replaces updates
        // the SAME Patient once per record, and Salesforce caps duplicate updates in
        // one batch at 12, so a single insert of 200 makes the flow throw
        // DUPLICATE_VALUE and roll everything back. That failure is the reason this
        // ticket exists. Once the flow is deactivated this can become one insert.
        List<Admission_Discharge__c> chunk = new List<Admission_Discharge__c>();
        for (Admission_Discharge__c rec : batch) {
            chunk.add(rec);
            if (chunk.size() == 10) {
                insert chunk;
                chunk = new List<Admission_Discharge__c>();
            }
        }
        if (!chunk.isEmpty()) {
            insert chunk;
        }

        Test.startTest();
        Integer q = Limits.getQueries();
        Integer d = Limits.getDmlStatements();
        runAfterInsert(batch);
        Integer queriesUsed = Limits.getQueries() - q;
        Integer dmlUsed = Limits.getDmlStatements() - d;
        Test.stopTest();

        // The whole point of the ticket: cost does not scale with volume.
        Assert.isTrue(queriesUsed <= 5, 'Expected a constant query count, used ' + queriesUsed);
        Assert.isTrue(dmlUsed <= 5, 'Expected a constant DML count, used ' + dmlUsed);
        // Latest across the batch is the last date, and the in-memory carry-forward
        // is what makes this work in one pass.
        Assert.areEqual(batch[199].Id, patient().Latest_Admission__c,
            'The chronologically latest admission in the batch should win');
    }

    @isTest
    static void recursionGuardStopsASecondPass() {
        Admission_Discharge__c ad = makeAD('Admission', Datetime.newInstanceGmt(2026, 3, 1, 12, 0, 0));

        Test.startTest();
        TriggerContext.reset();
        AdmissionDischargeSetLatest action = new AdmissionDischargeSetLatest();
        action.afterInsert(new List<Admission_Discharge__c>{ ad });
        Integer dmlAfterFirst = Limits.getDmlStatements();
        // Second pass in the same transaction, as a re-entrant save would do.
        action.afterInsert(new List<Admission_Discharge__c>{ ad });
        Integer dmlAfterSecond = Limits.getDmlStatements();
        Test.stopTest();

        Assert.areEqual(dmlAfterFirst, dmlAfterSecond,
            'The guard should make a re-entrant pass a complete no-op');
    }
}
