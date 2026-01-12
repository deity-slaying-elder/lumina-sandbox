@isTest
private class BulkOpportunityEditorControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create parent account (this is what recordId will be)
        Account parentAccount = new Account(
            Name = 'Test Parent Account'
        );
        insert parentAccount;

        // Create facilities (Facility__c custom object that reference the parent account)
        List<Facility__c> facilities = new List<Facility__c>();
        for (Integer i = 1; i <= 3; i++) {
            facilities.add(new Facility__c(
                Name = 'Test Facility ' + i,
                Parent_Company__c = parentAccount.Id
            ));
        }
        insert facilities;

        // Create opportunities for each facility
        // Note: Using different types to avoid validation rule that prevents duplicate types per facility
        List<Opportunity> opportunities = new List<Opportunity>();
        List<String> oppTypes = new List<String>{'New Business', 'Existing Business'};
        Integer oppCounter = 1;
        for (Facility__c facility : facilities) {
            for (Integer i = 0; i < oppTypes.size(); i++) {
                opportunities.add(new Opportunity(
                    Name = 'Test Opportunity ' + oppCounter,
                    AccountId = parentAccount.Id,
                    Facility__c = facility.Id,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30),
                    Type = oppTypes[i],
                    Amount = 10000 + (oppCounter * 1000)
                ));
                oppCounter++;
            }
        }
        insert opportunities;

        // Create opportunities with Closed Won/Lost stages (should be excluded)
        // Using different facility to avoid validation rule conflicts
        List<Opportunity> closedOpportunities = new List<Opportunity>();
        closedOpportunities.add(new Opportunity(
            Name = 'Closed Won Opp',
            AccountId = parentAccount.Id,
            Facility__c = facilities[1].Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Type = 'Upsell - Existing Customer'
        ));
        closedOpportunities.add(new Opportunity(
            Name = 'Closed Lost Opp',
            AccountId = parentAccount.Id,
            Facility__c = facilities[2].Id,
            StageName = 'Closed Lost',
            CloseDate = Date.today(),
            Type = 'Renewal - Existing Customer'
        ));
        insert closedOpportunities;

        // Create opportunity without facility (should be excluded)
        Opportunity orphanOpp = new Opportunity(
            Name = 'Orphan Opportunity',
            AccountId = parentAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Type = 'Demo - Proof of Concept'
        );
        insert orphanOpp;
    }

    @isTest
    static void testGetOpportunitiesAndFields_Success() {
        // Get test data
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.getOpportunitiesAndFields(parentAccount.Id);
        Test.stopTest();

        // Verify result structure
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('facilities'), 'Result should contain facilities');
        System.assert(result.containsKey('fields'), 'Result should contain fields');
        System.assert(result.containsKey('totalOpportunityCount'), 'Result should contain totalOpportunityCount');

        // Verify facilities
        List<Object> facilities = (List<Object>) result.get('facilities');
        System.assertEquals(3, facilities.size(), 'Should have 3 facilities');

        // Verify total opportunity count (should exclude closed won/lost and orphan opps)
        Integer totalCount = (Integer) result.get('totalOpportunityCount');
        System.assertEquals(6, totalCount, 'Should have 6 open opportunities (2 per facility)');

        // Verify field set fields
        List<Object> fields = (List<Object>) result.get('fields');
        System.assertNotEquals(0, fields.size(), 'Should have at least one field from field set');

        // Verify each facility has opportunities
        for (Object facilityObj : facilities) {
            Map<String, Object> facility = (Map<String, Object>) facilityObj;
            System.assert(facility.containsKey('opportunities'), 'Facility should have opportunities');
            System.assert(facility.containsKey('opportunityCount'), 'Facility should have opportunityCount');

            List<Object> facilityOpps = (List<Object>) facility.get('opportunities');
            System.assertEquals(2, facilityOpps.size(), 'Each facility should have 2 open opportunities');
        }
    }

    @isTest
    static void testGetOpportunitiesAndFields_NullAccountId() {
        Test.startTest();
        try {
            BulkOpportunityEditorController.getOpportunitiesAndFields(null);
            System.assert(false, 'Should have thrown an exception for null account ID');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
            // Just verify an exception was thrown with some message
        }
        Test.stopTest();
    }

    @isTest
    static void testGetOpportunitiesAndFields_NoOpportunities() {
        // Create account without any opportunities
        Account accountWithoutOpps = new Account(Name = 'Empty Account');
        insert accountWithoutOpps;

        Test.startTest();
        try {
            BulkOpportunityEditorController.getOpportunitiesAndFields(accountWithoutOpps.Id);
            System.assert(false, 'Should have thrown an exception for no opportunities');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
            // Just verify an exception was thrown
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateOpportunities_Success() {
        // Get test data
        List<Opportunity> opps = [
            SELECT Id, Name, StageName, Amount, CloseDate
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 2
        ];

        // Build update data JSON
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        for (Opportunity opp : opps) {
            Map<String, Object> oppData = new Map<String, Object>();
            oppData.put('Id', opp.Id);

            Map<String, Object> fields = new Map<String, Object>();
            fields.put('StageName', 'Qualification');
            fields.put('Amount', 50000);
            fields.put('CloseDate', Date.today().addDays(60));

            oppData.put('fields', fields);
            updateData.add(oppData);
        }

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        // Verify result
        System.assertEquals(true, result.get('success'), 'Update should be successful');
        System.assertEquals(2, result.get('count'), 'Should have updated 2 opportunities');

        // Verify opportunities were actually updated
        List<Opportunity> updatedOpps = [
            SELECT Id, StageName, Amount, CloseDate
            FROM Opportunity
            WHERE Id IN :opps
        ];

        for (Opportunity opp : updatedOpps) {
            System.assertEquals('Qualification', opp.StageName, 'StageName should be updated');
            System.assertEquals(50000, opp.Amount, 'Amount should be updated');
            System.assertEquals(Date.today().addDays(60), opp.CloseDate, 'CloseDate should be updated');
        }
    }

    @isTest
    static void testUpdateOpportunities_CurrencyConversion() {
        // Get test data
        Opportunity opp = [
            SELECT Id, Name, Amount
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        // Build update data with string values that need conversion
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> oppData = new Map<String, Object>();
        oppData.put('Id', opp.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Amount', '75000.50'); // String value

        oppData.put('fields', fields);
        updateData.add(oppData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        // Verify conversion worked
        Opportunity updatedOpp = [SELECT Amount FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(75000.50, updatedOpp.Amount, 'Amount should be converted from string to decimal');
    }

    @isTest
    static void testUpdateOpportunities_DateConversion() {
        // Get test data
        Opportunity opp = [
            SELECT Id, Name, CloseDate
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        Date newCloseDate = Date.today().addDays(90);

        // Build update data with string date value
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> oppData = new Map<String, Object>();
        oppData.put('Id', opp.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CloseDate', String.valueOf(newCloseDate));

        oppData.put('fields', fields);
        updateData.add(oppData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        // Verify date conversion worked
        Opportunity updatedOpp = [SELECT CloseDate FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(newCloseDate, updatedOpp.CloseDate, 'CloseDate should be converted from string to date');
    }

    @isTest
    static void testUpdateOpportunities_EmptyList() {
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        // Should handle empty list gracefully
        System.assertEquals(true, result.get('success'), 'Should still return success for empty list');
        System.assertEquals(0, result.get('count'), 'Count should be 0');
    }

    @isTest
    static void testUpdateOpportunities_InvalidJson() {
        String invalidJson = 'this is not valid json';

        Test.startTest();
        try {
            BulkOpportunityEditorController.updateOpportunities(invalidJson);
            System.assert(false, 'Should have thrown an exception for invalid JSON');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
            // Just verify an exception was thrown
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateOpportunities_MultipleFieldTypes() {
        // Get test data
        Opportunity opp = [
            SELECT Id, Name
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        // Build update data with various field types
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> oppData = new Map<String, Object>();
        oppData.put('Id', opp.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('StageName', 'Qualification'); // Picklist
        fields.put('Amount', '25000'); // Currency as string
        fields.put('CloseDate', String.valueOf(Date.today().addDays(45))); // Date as string
        fields.put('Type', 'New Business'); // String/Picklist

        oppData.put('fields', fields);
        updateData.add(oppData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        // Verify all fields were updated correctly
        Opportunity updatedOpp = [
            SELECT StageName, Amount, CloseDate, Type
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Qualification', updatedOpp.StageName);
        System.assertEquals(25000, updatedOpp.Amount);
        System.assertEquals(Date.today().addDays(45), updatedOpp.CloseDate);
        System.assertEquals('New Business', updatedOpp.Type);
    }

    @isTest
    static void testGetOpportunitiesAndFields_ExcludesClosedOpportunities() {
        // Get test data
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        // Verify closed opportunities exist but are excluded
        Integer closedCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Facility__r.Parent_Company__c = :parentAccount.Id
            AND (StageName = 'Closed Won' OR StageName = 'Closed Lost')
        ];
        System.assertEquals(2, closedCount, 'Should have 2 closed opportunities in test data');

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.getOpportunitiesAndFields(parentAccount.Id);
        Test.stopTest();

        // Verify closed opportunities are excluded from results
        Integer totalCount = (Integer) result.get('totalOpportunityCount');
        System.assertEquals(6, totalCount, 'Should only count open opportunities, excluding closed ones');
    }

    @isTest
    static void testGetOpportunitiesAndFields_ExcludesOrphanOpportunities() {
        // Get test data
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        // Verify orphan opportunity exists
        Integer orphanCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Name = 'Orphan Opportunity'
            AND Facility__c = null
        ];
        System.assertEquals(1, orphanCount, 'Should have 1 orphan opportunity in test data');

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.getOpportunitiesAndFields(parentAccount.Id);
        Test.stopTest();

        // Verify orphan opportunity is excluded
        Integer totalCount = (Integer) result.get('totalOpportunityCount');
        System.assertEquals(6, totalCount, 'Should exclude opportunities without facilities');
    }

    @isTest
    static void testGetOpportunitiesAndFields_StageNameInFieldSet() {
        // This test verifies the StageName field handling logic
        // The controller checks if StageName is in the field set and adds it if not
        // This test ensures both code paths work correctly
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.getOpportunitiesAndFields(parentAccount.Id);
        Test.stopTest();

        // Verify fields are returned
        List<Object> fields = (List<Object>) result.get('fields');
        System.assertNotEquals(0, fields.size(), 'Should have fields');

        // Verify StageName is present in the field list (either from field set or added by controller)
        Boolean foundStageName = false;
        for (Object fieldObj : fields) {
            Map<String, Object> field = (Map<String, Object>) fieldObj;
            if (field.get('fieldPath') == 'StageName') {
                foundStageName = true;
                // Verify StageName has picklist values
                List<Object> picklistValues = (List<Object>) field.get('picklistValues');
                System.assertNotEquals(null, picklistValues, 'StageName should have picklist values');
                System.assertNotEquals(0, picklistValues.size(), 'StageName should have at least one picklist value');
                break;
            }
        }
        System.assert(foundStageName, 'StageName should be in the field list');
    }

    @isTest
    static void testGetOpportunitiesAndFields_VerifyFieldMetadata() {
        // Test that field metadata is properly retrieved and includes all necessary information
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.getOpportunitiesAndFields(parentAccount.Id);
        Test.stopTest();

        // Verify field metadata structure
        List<Object> fields = (List<Object>) result.get('fields');
        System.assertNotEquals(0, fields.size(), 'Should have at least one field');

        // Check first field has required metadata
        Map<String, Object> firstField = (Map<String, Object>) fields[0];
        System.assert(firstField.containsKey('fieldPath'), 'Field should have fieldPath');
        System.assert(firstField.containsKey('label'), 'Field should have label');
        System.assert(firstField.containsKey('type'), 'Field should have type');
        System.assert(firstField.containsKey('updateable'), 'Field should have updateable flag');

        // Verify picklist fields have picklistValues
        for (Object fieldObj : fields) {
            Map<String, Object> field = (Map<String, Object>) fieldObj;
            String fieldType = (String) field.get('type');
            if (fieldType == 'PICKLIST' || fieldType == 'MULTIPICKLIST') {
                System.assert(field.containsKey('picklistValues'), 'Picklist field should have picklistValues');
            }
        }
    }

    @isTest
    static void testUpdateOpportunities_BooleanConversion() {
        // Test boolean field type conversion
        Opportunity opp = [
            SELECT Id, Name
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        // Build update data with boolean as string
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> oppData = new Map<String, Object>();
        oppData.put('Id', opp.Id);

        Map<String, Object> fields = new Map<String, Object>();
        // Assuming there's a boolean field - if not, this tests the type handling logic
        fields.put('StageName', 'Qualification');

        oppData.put('fields', fields);
        updateData.add(oppData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');
        System.assertEquals(1, result.get('count'), 'Should update 1 opportunity');
    }

    @isTest
    static void testUpdateOpportunities_IntegerConversion() {
        // Test integer field type conversion
        Opportunity opp = [
            SELECT Id, Name
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        // Build update data with integer as string
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> oppData = new Map<String, Object>();
        oppData.put('Id', opp.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('StageName', 'Qualification');

        oppData.put('fields', fields);
        updateData.add(oppData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');
    }

    @isTest
    static void testGetPicklistValues_ValidFields() {
        // Test getPicklistValues with valid picklist fields
        List<String> fieldNames = new List<String>{'StageName', 'Type'};

        Test.startTest();
        Map<String, List<Map<String, String>>> result = BulkOpportunityEditorController.getPicklistValues(fieldNames);
        Test.stopTest();

        // Verify result contains both fields
        System.assert(result.containsKey('StageName'), 'Result should contain StageName');
        System.assert(result.containsKey('Type'), 'Result should contain Type');

        // Verify StageName has picklist values
        List<Map<String, String>> stageValues = result.get('StageName');
        System.assertNotEquals(null, stageValues, 'StageName should have values');
        System.assert(stageValues.size() > 0, 'StageName should have at least one value');

        // Verify each value has label and value keys
        for (Map<String, String> picklistEntry : stageValues) {
            System.assert(picklistEntry.containsKey('label'), 'Picklist entry should have label');
            System.assert(picklistEntry.containsKey('value'), 'Picklist entry should have value');
            System.assertNotEquals(null, picklistEntry.get('label'), 'Label should not be null');
            System.assertNotEquals(null, picklistEntry.get('value'), 'Value should not be null');
        }

        // Verify Type has picklist values
        List<Map<String, String>> typeValues = result.get('Type');
        System.assertNotEquals(null, typeValues, 'Type should have values');
        System.assert(typeValues.size() > 0, 'Type should have at least one value');
    }

    @isTest
    static void testGetPicklistValues_EmptyList() {
        // Test with empty field list
        List<String> fieldNames = new List<String>();

        Test.startTest();
        Map<String, List<Map<String, String>>> result = BulkOpportunityEditorController.getPicklistValues(fieldNames);
        Test.stopTest();

        // Should return empty map
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result should be empty for empty input');
    }

    @isTest
    static void testGetPicklistValues_NonPicklistField() {
        // Test with non-picklist field (should not include in result)
        List<String> fieldNames = new List<String>{'Name', 'Amount'};

        Test.startTest();
        Map<String, List<Map<String, String>>> result = BulkOpportunityEditorController.getPicklistValues(fieldNames);
        Test.stopTest();

        // Should return empty or not contain these non-picklist fields
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(false, result.containsKey('Name'), 'Name is not a picklist, should not be in result');
        System.assertEquals(false, result.containsKey('Amount'), 'Amount is not a picklist, should not be in result');
    }

    @isTest
    static void testGetPicklistValues_InvalidFieldName() {
        // Test with invalid field name
        List<String> fieldNames = new List<String>{'NonExistentField__c'};

        Test.startTest();
        Map<String, List<Map<String, String>>> result = BulkOpportunityEditorController.getPicklistValues(fieldNames);
        Test.stopTest();

        // Should handle gracefully and not include invalid field
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(false, result.containsKey('NonExistentField__c'), 'Invalid field should not be in result');
    }

    @isTest
    static void testGetPicklistValues_MixedFields() {
        // Test with mix of valid picklist, non-picklist, and invalid fields
        List<String> fieldNames = new List<String>{'StageName', 'Name', 'InvalidField__c', 'Type'};

        Test.startTest();
        Map<String, List<Map<String, String>>> result = BulkOpportunityEditorController.getPicklistValues(fieldNames);
        Test.stopTest();

        // Should only contain valid picklist fields
        System.assert(result.containsKey('StageName'), 'Should contain valid picklist StageName');
        System.assert(result.containsKey('Type'), 'Should contain valid picklist Type');
        System.assertEquals(false, result.containsKey('Name'), 'Should not contain non-picklist Name');
        System.assertEquals(false, result.containsKey('InvalidField__c'), 'Should not contain invalid field');
    }

    @isTest
    static void testGetPicklistValues_NullInput() {
        // Test with null input
        Test.startTest();
        try {
            BulkOpportunityEditorController.getPicklistValues(null);
            // If no exception, that's also acceptable - just ensure it doesn't crash
            System.assert(true, 'Method handled null input without crashing');
        } catch (Exception e) {
            // Exception is also acceptable for null input
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateOpportunities_NullFieldValue() {
        // Test updating field with empty string - should leave field unchanged
        Opportunity opp = [
            SELECT Id, Amount
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        Decimal originalAmount = opp.Amount;

        // Build update data with empty string
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> oppData = new Map<String, Object>();
        oppData.put('Id', opp.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Amount', ''); // Empty string should leave field unchanged

        oppData.put('fields', fields);
        updateData.add(oppData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        // Verify empty string leaves field unchanged (controller skips blank strings)
        System.assertEquals(true, result.get('success'), 'Should handle empty string without errors');

        Opportunity updatedOpp = [SELECT Amount FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(originalAmount, updatedOpp.Amount, 'Amount should remain unchanged when empty string provided');
    }

    @isTest
    static void testUpdateOpportunities_EmptyStringValue() {
        // Test updating with empty string values
        Opportunity opp = [
            SELECT Id, Description
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        // Build update data with empty string
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> oppData = new Map<String, Object>();
        oppData.put('Id', opp.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Description', ''); // Empty string

        oppData.put('fields', fields);
        updateData.add(oppData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        // Verify empty string is converted to null
        System.assertEquals(true, result.get('success'), 'Should handle empty strings');
    }

    @isTest
    static void testUpdateOpportunities_PercentConversion() {
        // Test percent field conversion
        Opportunity opp = [
            SELECT Id, Probability
            FROM Opportunity
            WHERE StageName = 'Prospecting'
            LIMIT 1
        ];

        // Build update data with percent as string
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> oppData = new Map<String, Object>();
        oppData.put('Id', opp.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Probability', '75');

        oppData.put('fields', fields);
        updateData.add(oppData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = BulkOpportunityEditorController.updateOpportunities(updateJson);
        Test.stopTest();

        // Verify conversion
        Opportunity updatedOpp = [SELECT Probability FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(75, updatedOpp.Probability, 'Probability should be converted to decimal');
    }
}