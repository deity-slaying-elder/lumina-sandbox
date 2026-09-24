/**
 * Invoked directly rather than through DML. See the note in
 * CommunityEpisodeSetLatestOnPatientTest for why.
 *
 * TriggerContext.reset() runs before each exercise so one method's recursion claim
 * does not leak into the next.
 */
@isTest
private class PatientCountCallsWithin48HoursTest {

    @TestSetup
    static void setupTestData() {
        insert new Patient__c(
            First_Name__c = 'Call', Last_Name__c = 'Counter', Status__c = 'Active',
            Discharge_Date__c = Date.today().addDays(-1),
            Count_of_Calls__c = 1
        );
    }

    private static Patient__c thePatient() {
        return [SELECT Id, Count_of_Calls__c, Count_of_Calls_Within_48_Hours__c, Discharge_Date__c
                FROM Patient__c LIMIT 1];
    }

    /** Runs the action with a prior-value pair, mimicking one after-update pass. */
    private static void run(Patient__c before, Patient__c after) {
        TriggerContext.reset();
        new PatientCountCallsWithin48Hours().afterUpdate(
            new List<Patient__c>{ after }, new List<Patient__c>{ before }
        );
    }

    @isTest
    static void firstCallInWindowStartsCountAtOne() {
        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Count_of_Calls__c = 2;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual(1, thePatient().Count_of_Calls_Within_48_Hours__c,
            'A blank counter should start at 1, not 0');
    }

    @isTest
    static void subsequentCallIncrements() {
        Patient__c patient = thePatient();
        patient.Count_of_Calls_Within_48_Hours__c = 3;
        update patient;

        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Count_of_Calls__c = before.Count_of_Calls__c + 1;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual(4, thePatient().Count_of_Calls_Within_48_Hours__c, 'The counter should advance by one');
    }

    @isTest
    static void countOfZeroStopsAtGateOne() {
        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Count_of_Calls__c = 0;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual(null, thePatient().Count_of_Calls_Within_48_Hours__c,
            'A count of zero is terminal in the flow and must not increment');
    }

    @isTest
    static void decreaseStopsAtGateTwo() {
        Patient__c before = thePatient();
        before.Count_of_Calls__c = 5;
        Patient__c after = before.clone(true, true, true, true);
        after.Count_of_Calls__c = 3;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual(null, thePatient().Count_of_Calls_Within_48_Hours__c,
            'Only an increase should count');
    }

    @isTest
    static void outsideWindowStopsAtGateThree() {
        Patient__c patient = thePatient();
        patient.Discharge_Date__c = Date.today().addDays(-10);
        update patient;

        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Count_of_Calls__c = before.Count_of_Calls__c + 1;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual(null, thePatient().Count_of_Calls_Within_48_Hours__c,
            'A call ten days after discharge is outside the window');
    }

    @isTest
    static void nullDischargeDateStopsAtGateThree() {
        Patient__c patient = thePatient();
        patient.Discharge_Date__c = null;
        update patient;

        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Count_of_Calls__c = before.Count_of_Calls__c + 1;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        Assert.areEqual(null, thePatient().Count_of_Calls_Within_48_Hours__c,
            'A null discharge date made the flow formula null, which the decision read as false');
    }

    @isTest
    static void futureDischargeDateStillCountsAndThatIsTheFlowBug() {
        Patient__c patient = thePatient();
        patient.Discharge_Date__c = Date.today().addDays(30);
        update patient;

        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Count_of_Calls__c = before.Count_of_Calls__c + 1;

        Test.startTest();
        run(before, after);
        Test.stopTest();

        // Deliberate. TODAY() minus a future date is negative, and negative is <= 2, so
        // the flow counted these too. Reproduced so the port can be verified against the
        // flow; raised separately as a defect rather than fixed here.
        Assert.areEqual(1, thePatient().Count_of_Calls_Within_48_Hours__c,
            'The flow counted future discharge dates and this port must match it');
    }

    @isTest
    static void selfWriteDoesNotDoubleCount() {
        // The action's own update re-enters the trigger. Count_of_Calls__c is unchanged
        // on that pass, so the entry criteria stop it - the flow terminated identically.
        Patient__c before = thePatient();
        Patient__c after = before.clone(true, true, true, true);
        after.Count_of_Calls__c = 2;

        Test.startTest();
        update after;
        Test.stopTest();

        Assert.areEqual(1, thePatient().Count_of_Calls_Within_48_Hours__c,
            'One logged call is one increment, re-entry included');
    }

    @isTest
    static void twoUpdatesInOneTransactionBothCount() {
        // Two saves in one transaction each fired the flow, so each must increment.
        // A transaction-scoped recursion claim broke this and was removed.
        Patient__c patient = thePatient();

        Test.startTest();
        update new Patient__c(Id = patient.Id, Count_of_Calls__c = 2);
        update new Patient__c(Id = patient.Id, Count_of_Calls__c = 3);
        Test.stopTest();

        Assert.areEqual(2, thePatient().Count_of_Calls_Within_48_Hours__c,
            'Both calls in one transaction count, exactly as the flow behaved');
    }
}
