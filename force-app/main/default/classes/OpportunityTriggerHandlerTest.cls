@isTest
private class OpportunityTriggerHandlerTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        // Create test Facilities
        List<Facility__c> facilities = new List<Facility__c>{
            new Facility__c(
                Name = 'Facility 1',
                Parent_Company__c = testAccount.Id
            ),
            new Facility__c(
                Name = 'Facility 2',
                Parent_Company__c = testAccount.Id
            ),
            new Facility__c(
                Name = 'Facility 3',
                Parent_Company__c = testAccount.Id
            )
        };
        insert facilities;
    }

    @isTest
    static void testPreventDuplicate_Insert_BlocksDuplicate() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 1];

        // Create an existing open opportunity
        Opportunity existingOpp = new Opportunity(
            Name = 'Existing Open Opp',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
        insert existingOpp;

        // Try to create duplicate
        Opportunity duplicateOpp = new Opportunity(
            Name = 'Duplicate Opp',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(60)
        );

        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        try {
            insert duplicateOpp;
        } catch (DmlException e) {
            exceptionThrown = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        // Verify
        System.assert(exceptionThrown, 'Should throw exception for duplicate');
        System.assert(exceptionMessage.contains('open opportunity'), 'Error should mention open opportunity');
        System.assert(exceptionMessage.contains('New Customer'), 'Error should include Type');
    }

    @isTest
    static void testPreventDuplicate_Insert_AllowsIfExistingClosed() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 1];

        // Get a closed stage name
        String closedStage = getClosedStageName();

        // Create an existing closed opportunity
        Opportunity existingClosedOpp = new Opportunity(
            Name = 'Existing Closed Opp',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = closedStage,
            CloseDate = Date.today().addDays(-30)
        );
        insert existingClosedOpp;

        // Try to create same type (should succeed since existing is closed)
        Opportunity newOpp = new Opportunity(
            Name = 'New Opp Same Type',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );

        // Test
        Test.startTest();
        insert newOpp;
        Test.stopTest();

        // Verify - should succeed
        Opportunity insertedOpp = [SELECT Id, Name FROM Opportunity WHERE Id = :newOpp.Id];
        System.assertNotEquals(null, insertedOpp, 'Should successfully insert when existing is closed');
    }

    @isTest
    static void testPreventDuplicate_Insert_AllowsDifferentFacility() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 2];

        // Create opportunity at first facility
        Opportunity oppFacility1 = new Opportunity(
            Name = 'Opp Facility 1',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
        insert oppFacility1;

        // Create same type at different facility (should succeed)
        Opportunity oppFacility2 = new Opportunity(
            Name = 'Opp Facility 2',
            AccountId = testAccount.Id,
            Facility__c = facilities[1].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );

        // Test
        Test.startTest();
        insert oppFacility2;
        Test.stopTest();

        // Verify - should succeed
        Opportunity insertedOpp = [SELECT Id FROM Opportunity WHERE Id = :oppFacility2.Id];
        System.assertNotEquals(null, insertedOpp, 'Should allow same type at different facility');
    }

    @isTest
    static void testPreventDuplicate_Insert_AllowsDifferentType() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 1];

        // Create opportunity with Type A
        Opportunity oppTypeA = new Opportunity(
            Name = 'Opp Type A',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
        insert oppTypeA;

        // Create opportunity with Type B at same facility (should succeed)
        Opportunity oppTypeB = new Opportunity(
            Name = 'Opp Type B',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'Existing Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );

        // Test
        Test.startTest();
        insert oppTypeB;
        Test.stopTest();

        // Verify - should succeed
        Opportunity insertedOpp = [SELECT Id FROM Opportunity WHERE Id = :oppTypeB.Id];
        System.assertNotEquals(null, insertedOpp, 'Should allow different type at same facility');
    }

    @isTest
    static void testPreventDuplicate_Insert_SkipsIfNoType() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 1];

        // Create opportunity without Type (should succeed)
        Opportunity oppNoType = new Opportunity(
            Name = 'Opp No Type',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );

        // Test
        Test.startTest();
        insert oppNoType;
        Test.stopTest();

        // Verify - should succeed
        Opportunity insertedOpp = [SELECT Id FROM Opportunity WHERE Id = :oppNoType.Id];
        System.assertNotEquals(null, insertedOpp, 'Should allow opportunity without Type');
    }

    @isTest
    static void testPreventDuplicate_Insert_SkipsIfNoFacility() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Create opportunity without Facility (should succeed)
        Opportunity oppNoFacility = new Opportunity(
            Name = 'Opp No Facility',
            AccountId = testAccount.Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );

        // Test
        Test.startTest();
        insert oppNoFacility;
        Test.stopTest();

        // Verify - should succeed
        Opportunity insertedOpp = [SELECT Id FROM Opportunity WHERE Id = :oppNoFacility.Id];
        System.assertNotEquals(null, insertedOpp, 'Should allow opportunity without Facility');
    }

    @isTest
    static void testPreventDuplicate_Update_BlocksDuplicate() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 2];

        // Create two opportunities at different facilities with different types
        Opportunity opp1 = new Opportunity(
            Name = 'Opp 1',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );

        Opportunity opp2 = new Opportunity(
            Name = 'Opp 2',
            AccountId = testAccount.Id,
            Facility__c = facilities[1].Id,
            Type = 'Existing Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
        insert new List<Opportunity>{opp1, opp2};

        // Try to update opp2 to have same Facility+Type as opp1
        opp2.Facility__c = facilities[0].Id;
        opp2.Type = 'New Customer';

        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        try {
            update opp2;
        } catch (DmlException e) {
            exceptionThrown = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        // Verify
        System.assert(exceptionThrown, 'Should throw exception when updating to duplicate');
        System.assert(exceptionMessage.contains('open opportunity'), 'Error should mention open opportunity');
    }

    @isTest
    static void testPreventDuplicate_Update_AllowsIfNoRelevantChange() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 1];

        // Create opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Update non-relevant fields (should succeed)
        opp.Name = 'Updated Name';
        opp.CloseDate = Date.today().addDays(60);

        // Test
        Test.startTest();
        update opp;
        Test.stopTest();

        // Verify - should succeed
        Opportunity updatedOpp = [SELECT Id, Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Updated Name', updatedOpp.Name, 'Should allow updates to non-relevant fields');
    }

    @isTest
    static void testPreventDuplicate_Update_AllowsIfExistingClosed() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 2];

        // Get a closed stage name
        String closedStage = getClosedStageName();

        // Create two opportunities
        Opportunity opp1 = new Opportunity(
            Name = 'Opp 1 Closed',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = closedStage,
            CloseDate = Date.today().addDays(-30)
        );

        Opportunity opp2 = new Opportunity(
            Name = 'Opp 2',
            AccountId = testAccount.Id,
            Facility__c = facilities[1].Id,
            Type = 'Existing Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
        insert new List<Opportunity>{opp1, opp2};

        // Update opp2 to match closed opp1 (should succeed)
        opp2.Facility__c = facilities[0].Id;
        opp2.Type = 'New Customer';

        // Test
        Test.startTest();
        update opp2;
        Test.stopTest();

        // Verify - should succeed
        Opportunity updatedOpp = [SELECT Id, Type FROM Opportunity WHERE Id = :opp2.Id];
        System.assertEquals('New Customer', updatedOpp.Type, 'Should allow update when existing is closed');
    }

    @isTest
    static void testPreventDuplicate_BulkInsert_MixedResults() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 3];

        // Create an existing open opportunity at facility 1
        Opportunity existingOpp = new Opportunity(
            Name = 'Existing Opp',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
        insert existingOpp;

        // Try to insert multiple opportunities (one duplicate, one valid)
        List<Opportunity> oppsToInsert = new List<Opportunity>{
            new Opportunity(
                Name = 'Duplicate Opp',
                AccountId = testAccount.Id,
                Facility__c = facilities[0].Id,
                Type = 'New Customer',
                StageName = 'Proposal',
                CloseDate = Date.today().addDays(60)
            ),
            new Opportunity(
                Name = 'Valid Opp',
                AccountId = testAccount.Id,
                Facility__c = facilities[1].Id,
                Type = 'New Customer',
                StageName = 'Proposal',
                CloseDate = Date.today().addDays(60)
            )
        };

        // Test with Database.insert to allow partial success
        Test.startTest();
        Database.SaveResult[] results = Database.insert(oppsToInsert, false);
        Test.stopTest();

        // Verify mixed results
        System.assertEquals(false, results[0].isSuccess(), 'First insert should fail (duplicate)');
        System.assertEquals(true, results[1].isSuccess(), 'Second insert should succeed (different facility)');

        // Verify only 1 new opportunity was created (plus the existing one)
        Integer oppCount = [SELECT COUNT() FROM Opportunity WHERE AccountId = :testAccount.Id];
        System.assertEquals(2, oppCount, 'Should have 2 opportunities (1 existing + 1 new valid)');
    }

    @isTest
    static void testPreventDuplicate_MultipleDuplicatesAtOnce() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 2];

        // Create existing open opportunities at both facilities
        List<Opportunity> existingOpps = new List<Opportunity>{
            new Opportunity(
                Name = 'Existing Opp 1',
                AccountId = testAccount.Id,
                Facility__c = facilities[0].Id,
                Type = 'New Customer',
                StageName = 'Proposal',
                CloseDate = Date.today().addDays(30)
            ),
            new Opportunity(
                Name = 'Existing Opp 2',
                AccountId = testAccount.Id,
                Facility__c = facilities[1].Id,
                Type = 'Existing Customer',
                StageName = 'Proposal',
                CloseDate = Date.today().addDays(30)
            )
        };
        insert existingOpps;

        // Try to insert duplicates of both
        List<Opportunity> duplicateOpps = new List<Opportunity>{
            new Opportunity(
                Name = 'Duplicate Opp 1',
                AccountId = testAccount.Id,
                Facility__c = facilities[0].Id,
                Type = 'New Customer',
                StageName = 'Proposal',
                CloseDate = Date.today().addDays(60)
            ),
            new Opportunity(
                Name = 'Duplicate Opp 2',
                AccountId = testAccount.Id,
                Facility__c = facilities[1].Id,
                Type = 'Existing Customer',
                StageName = 'Proposal',
                CloseDate = Date.today().addDays(60)
            )
        };

        // Test with Database.insert to see all errors
        Test.startTest();
        Database.SaveResult[] results = Database.insert(duplicateOpps, false);
        Test.stopTest();

        // Verify both failed
        System.assertEquals(false, results[0].isSuccess(), 'First duplicate should fail');
        System.assertEquals(false, results[1].isSuccess(), 'Second duplicate should fail');

        // Verify error messages contain relevant info
        String error1 = results[0].getErrors()[0].getMessage();
        String error2 = results[1].getErrors()[0].getMessage();
        System.assert(error1.contains('New Customer'), 'Error should mention Type');
        System.assert(error2.contains('Existing Customer'), 'Error should mention Type');
    }

    @isTest
    static void testGetClosedStages_ReturnsClosedStages() {
        // This test verifies that the getClosedStages method works
        // We can't directly test a private method, but we can verify behavior
        // through the trigger logic

        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id FROM Facility__c LIMIT 1];

        // Get a closed stage name
        String closedStage = getClosedStageName();

        // Create closed opportunity
        Opportunity closedOpp = new Opportunity(
            Name = 'Closed Opp',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = closedStage,
            CloseDate = Date.today().addDays(-30)
        );
        insert closedOpp;

        // Try to create same type (should succeed)
        Opportunity newOpp = new Opportunity(
            Name = 'New Opp',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );

        // Test
        Test.startTest();
        insert newOpp;
        Test.stopTest();

        // Verify - if closed stages are working correctly, this should succeed
        Opportunity insertedOpp = [SELECT Id FROM Opportunity WHERE Id = :newOpp.Id];
        System.assertNotEquals(null, insertedOpp, 'Should succeed, proving closed stages are recognized');
    }

    // Helper method to get a closed stage name
    private static String getClosedStageName() {
        List<OpportunityStage> closedStages = [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsClosed = true
            LIMIT 1
        ];

        if (!closedStages.isEmpty()) {
            return closedStages[0].MasterLabel;
        }

        // Fallback to common closed stage names if none found
        return 'Closed Won';
    }
}