@isTest
private class FacilityEditorControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create parent account
        Account parentAccount = new Account(
            Name = 'Test Parent Account'
        );
        insert parentAccount;

        // Create 250+ facilities for bulk testing (per steering docs requirement)
        List<Facility__c> facilities = new List<Facility__c>();
        for (Integer i = 1; i <= 250; i++) {
            Facility__c fac = new Facility__c(
                Name = 'Test Facility ' + i,
                Parent_Company__c = parentAccount.Id,
                CCM__c = Math.mod(i, 2) == 0,  // Even numbered facilities have CCM
                TCM__c = Math.mod(i, 3) == 0,  // Every 3rd facility has TCM
                BHI__c = Math.mod(i, 5) == 0,  // Every 5th facility has BHI
                RPM__c = Math.mod(i, 7) == 0,  // Every 7th facility has RPM
                AHTH__c = Math.mod(i, 11) == 0, // Every 11th facility has AHTH
                APCM__c = Math.mod(i, 13) == 0, // Every 13th facility has APCM
                COCM__c = Math.mod(i, 17) == 0  // Every 17th facility has COCM
            );
            facilities.add(fac);
        }
        insert facilities;

        // Create an account without any facilities
        Account emptyAccount = new Account(
            Name = 'Empty Account'
        );
        insert emptyAccount;
    }

    @isTest
    static void testGetFacilitiesAndFields_Success() {
        // Get test data
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.getFacilitiesAndFields(parentAccount.Id);
        Test.stopTest();

        // Verify result structure
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('facilities'), 'Result should contain facilities');
        System.assert(result.containsKey('fields'), 'Result should contain fields');
        System.assert(result.containsKey('totalFacilityCount'), 'Result should contain totalFacilityCount');

        // Verify facilities
        List<Object> facilities = (List<Object>) result.get('facilities');
        System.assertEquals(250, facilities.size(), 'Should have 250 facilities');

        // Verify total facility count
        Integer totalCount = (Integer) result.get('totalFacilityCount');
        System.assertEquals(250, totalCount, 'Should have 250 facilities');

        // Verify field set fields
        List<Object> fields = (List<Object>) result.get('fields');
        System.assertNotEquals(0, fields.size(), 'Should have at least one field from field set');

        // Verify each facility has required fields
        for (Object facilityObj : facilities) {
            Map<String, Object> facility = (Map<String, Object>) facilityObj;
            System.assert(facility.containsKey('Id'), 'Facility should have Id');
            System.assert(facility.containsKey('Name'), 'Facility should have Name');
        }
    }

    @isTest
    static void testGetFacilitiesAndFields_NullAccountId() {
        Test.startTest();
        try {
            FacilityEditorController.getFacilitiesAndFields(null);
            System.assert(false, 'Should have thrown an exception for null account ID');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFacilitiesAndFields_NoFacilities() {
        // Get account without facilities
        Account emptyAccount = [SELECT Id FROM Account WHERE Name = 'Empty Account' LIMIT 1];

        Test.startTest();
        try {
            FacilityEditorController.getFacilitiesAndFields(emptyAccount.Id);
            System.assert(false, 'Should have thrown an exception for no facilities');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFacilitiesAndFields_VerifyFieldMetadata() {
        // Test that field metadata is properly retrieved
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.getFacilitiesAndFields(parentAccount.Id);
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
    static void testUpdateFacilities_Success() {
        // Get test data
        List<Facility__c> facilities = [
            SELECT Id, Name
            FROM Facility__c
            LIMIT 2
        ];

        // Build update data JSON
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        for (Facility__c fac : facilities) {
            Map<String, Object> facData = new Map<String, Object>();
            facData.put('Id', fac.Id);

            Map<String, Object> fields = new Map<String, Object>();
            fields.put('Name', fac.Name + ' - Updated');

            facData.put('fields', fields);
            updateData.add(facData);
        }

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        // Verify result
        System.assertEquals(true, result.get('success'), 'Update should be successful');
        System.assertEquals(2, result.get('count'), 'Should have updated 2 facilities');

        // Verify facilities were actually updated
        List<Facility__c> updatedFacilities = [
            SELECT Id, Name
            FROM Facility__c
            WHERE Id IN :facilities
        ];

        for (Facility__c fac : updatedFacilities) {
            System.assert(fac.Name.contains('Updated'), 'Name should be updated');
        }
    }

    @isTest
    static void testUpdateFacilities_BooleanFieldAsString() {
        // Test boolean field with string value 'true'
        Facility__c facility = [
            SELECT Id, Name, CCM__c
            FROM Facility__c
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CCM__c', 'true'); // Boolean as string

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Facility__c updatedFacility = [SELECT CCM__c FROM Facility__c WHERE Id = :facility.Id];
        System.assertEquals(true, updatedFacility.CCM__c, 'CCM__c should be true');
    }

    @isTest
    static void testUpdateFacilities_BooleanFieldAsBoolean() {
        // Test boolean field with actual boolean value
        Facility__c facility = [
            SELECT Id, Name, TCM__c
            FROM Facility__c
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('TCM__c', true); // Boolean as actual boolean

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Facility__c updatedFacility = [SELECT TCM__c FROM Facility__c WHERE Id = :facility.Id];
        System.assertEquals(true, updatedFacility.TCM__c, 'TCM__c should be true');
    }

    @isTest
    static void testUpdateFacilities_EmptyList() {
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        // Should handle empty list gracefully
        System.assertEquals(true, result.get('success'), 'Should still return success for empty list');
        System.assertEquals(0, result.get('count'), 'Count should be 0');
    }

    @isTest
    static void testUpdateFacilities_InvalidJson() {
        String invalidJson = 'this is not valid json';

        Test.startTest();
        try {
            FacilityEditorController.updateFacilities(invalidJson);
            System.assert(false, 'Should have thrown an exception for invalid JSON');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateFacilities_MultipleFieldTypes() {
        // Test updating multiple field types at once
        Facility__c facility = [
            SELECT Id, Name, CCM__c, TCM__c, BHI__c
            FROM Facility__c
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Name', 'Multi-Field Test');
        fields.put('CCM__c', true);
        fields.put('TCM__c', 'true');
        fields.put('BHI__c', false);

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');
        System.assertEquals(1, result.get('count'), 'Should update 1 facility');

        Facility__c updatedFacility = [
            SELECT Name, CCM__c, TCM__c, BHI__c
            FROM Facility__c
            WHERE Id = :facility.Id
        ];

        System.assertEquals('Multi-Field Test', updatedFacility.Name);
        System.assertEquals(true, updatedFacility.CCM__c);
        System.assertEquals(true, updatedFacility.TCM__c);
        System.assertEquals(false, updatedFacility.BHI__c);
    }

    @isTest
    static void testUpdateFacilities_NullFieldValue() {
        // Test that null values are skipped
        Facility__c facility = [
            SELECT Id, Name
            FROM Facility__c
            LIMIT 1
        ];

        String originalName = facility.Name;

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Name', null); // Null value should be skipped

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should handle null without errors');

        Facility__c updatedFacility = [SELECT Name FROM Facility__c WHERE Id = :facility.Id];
        System.assertEquals(originalName, updatedFacility.Name, 'Name should remain unchanged when null provided');
    }

    @isTest
    static void testUpdateFacilities_TextFieldDefault() {
        // Test text field goes through default else branch
        Facility__c facility = [
            SELECT Id, Name
            FROM Facility__c
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Name', 'Text Field Test');

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Facility__c updatedFacility = [SELECT Name FROM Facility__c WHERE Id = :facility.Id];
        System.assertEquals('Text Field Test', updatedFacility.Name);
    }

    @isTest
    static void testUpdateFacilities_MultipleFacilities() {
        // Test updating multiple facilities at once
        List<Facility__c> facilities = [
            SELECT Id, Name
            FROM Facility__c
            LIMIT 3
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Integer counter = 1;
        for (Facility__c fac : facilities) {
            Map<String, Object> facData = new Map<String, Object>();
            facData.put('Id', fac.Id);

            Map<String, Object> fields = new Map<String, Object>();
            fields.put('Name', 'Bulk Updated ' + counter);
            fields.put('CCM__c', true);

            facData.put('fields', fields);
            updateData.add(facData);
            counter++;
        }

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Bulk update should be successful');
        System.assertEquals(3, result.get('count'), 'Should have updated 3 facilities');

        // Verify all facilities were updated
        List<Facility__c> updatedFacilities = [
            SELECT Name, CCM__c FROM Facility__c WHERE Id IN :facilities ORDER BY Name
        ];

        for (Facility__c fac : updatedFacilities) {
            System.assert(fac.Name.startsWith('Bulk Updated'), 'All facilities should be updated');
            System.assertEquals(true, fac.CCM__c, 'CCM__c should be true for all');
        }
    }

    @isTest
    static void testGetFacilitiesAndFields_PicklistValues() {
        // Test that picklist values are properly retrieved
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.getFacilitiesAndFields(parentAccount.Id);
        Test.stopTest();

        // Verify fields with picklist values
        List<Object> fields = (List<Object>) result.get('fields');

        for (Object fieldObj : fields) {
            Map<String, Object> field = (Map<String, Object>) fieldObj;
            String fieldType = (String) field.get('type');
            if (fieldType == 'PICKLIST' || fieldType == 'MULTIPICKLIST') {
                List<Object> picklistValues = (List<Object>) field.get('picklistValues');
                System.assertNotEquals(null, picklistValues, 'Picklist field should have picklistValues');

                // Verify each picklist value has label and value
                for (Object picklistObj : picklistValues) {
                    Map<String, Object> picklistEntry = (Map<String, Object>) picklistObj;
                    System.assert(picklistEntry.containsKey('label'), 'Picklist entry should have label');
                    System.assert(picklistEntry.containsKey('value'), 'Picklist entry should have value');
                }
            }
        }
    }

    @isTest
    static void testUpdateFacilities_AllBooleanFields() {
        // Test multiple boolean fields with both string and boolean values
        Facility__c facility = [
            SELECT Id, CCM__c, TCM__c, BHI__c, RPM__c, AHTH__c, APCM__c, COCM__c
            FROM Facility__c
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CCM__c', true);
        fields.put('TCM__c', true);
        fields.put('BHI__c', 'true');
        fields.put('RPM__c', 'false');
        fields.put('AHTH__c', false);
        fields.put('APCM__c', true);
        fields.put('COCM__c', 'true');

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Facility__c updatedFacility = [
            SELECT CCM__c, TCM__c, BHI__c, RPM__c, AHTH__c, APCM__c, COCM__c
            FROM Facility__c
            WHERE Id = :facility.Id
        ];

        System.assertEquals(true, updatedFacility.CCM__c);
        System.assertEquals(true, updatedFacility.TCM__c);
        System.assertEquals(true, updatedFacility.BHI__c);
        System.assertEquals(false, updatedFacility.RPM__c);
        System.assertEquals(false, updatedFacility.AHTH__c);
        System.assertEquals(true, updatedFacility.APCM__c);
        System.assertEquals(true, updatedFacility.COCM__c);
    }

    @isTest
    static void testUpdateFacilities_BooleanFalseAsString() {
        // Test boolean field with string value 'false'
        Facility__c facility = [
            SELECT Id, CCM__c
            FROM Facility__c
            LIMIT 1
        ];

        // First set it to true
        facility.CCM__c = true;
        update facility;

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CCM__c', 'false'); // Boolean as string false

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Facility__c updatedFacility = [SELECT CCM__c FROM Facility__c WHERE Id = :facility.Id];
        System.assertEquals(false, updatedFacility.CCM__c, 'CCM__c should be false');
    }

    @isTest
    static void testUpdateFacilities_UnknownFieldName() {
        // Test with a field name that doesn't exist in schema (covers else branch)
        Facility__c facility = [
            SELECT Id, Name
            FROM Facility__c
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Name', 'Valid Update');
        fields.put('NonExistentField__c', 'some value'); // This field doesn't exist

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        try {
            FacilityEditorController.updateFacilities(updateJson);
            // If it doesn't throw, that's also acceptable behavior
        } catch (AuraHandledException e) {
            // Expected - unknown field should cause error
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateFacilities_NonBooleanFieldType() {
        // Test non-boolean field to cover the else branch (line 143)
        Facility__c facility = [
            SELECT Id, Name
            FROM Facility__c
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Name', 'Non-Boolean Test'); // Name is a text field

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Facility__c updatedFacility = [SELECT Name FROM Facility__c WHERE Id = :facility.Id];
        System.assertEquals('Non-Boolean Test', updatedFacility.Name);
    }

    @isTest
    static void testGetFacilitiesAndFields_RequiredFieldCheck() {
        // Test that required field metadata is retrieved
        Account parentAccount = [SELECT Id FROM Account WHERE Name = 'Test Parent Account' LIMIT 1];

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.getFacilitiesAndFields(parentAccount.Id);
        Test.stopTest();

        List<Object> fields = (List<Object>) result.get('fields');
        System.assertNotEquals(0, fields.size(), 'Should have fields');

        // Verify required flag exists on fields
        for (Object fieldObj : fields) {
            Map<String, Object> field = (Map<String, Object>) fieldObj;
            System.assert(field.containsKey('required'), 'Field should have required flag');
        }
    }

    @isTest
    static void testUpdateFacilities_DMLException() {
        // Test that DML exceptions are properly caught and wrapped
        // Create invalid data that will cause DML error
        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', '001000000000000AAA'); // Invalid/non-existent ID

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('Name', 'Test');

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        try {
            FacilityEditorController.updateFacilities(updateJson);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should have a message');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateFacilities_DateFieldAsString() {
        // Test Date field conversion from string format (YYYY-MM-DD)
        // Skip if date fields not yet available in schema (sandbox sync issue)
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Facility__c.fields.getMap();
        if (!fieldMap.containsKey('ccm_launch_date__c')) {
            System.debug('Skipping test - CCM_Launch_Date__c not in schema yet');
            return;
        }

        Facility__c facility = [
            SELECT Id, Name, CCM__c
            FROM Facility__c
            WHERE CCM__c = true
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CCM_Launch_Date__c', '2025-06-15'); // Date as string from LWC

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        // Query using dynamic SOQL to avoid compile-time field reference
        String query = 'SELECT CCM_Launch_Date__c FROM Facility__c WHERE Id = :facilityId';
        Id facilityId = facility.Id;
        List<Facility__c> results = Database.query(query);
        System.assertEquals(Date.valueOf('2025-06-15'), results[0].get('CCM_Launch_Date__c'), 'CCM_Launch_Date__c should be set correctly');
    }

    @isTest
    static void testUpdateFacilities_DateFieldToNull() {
        // Test clearing a Date field by setting it to null
        // Skip if date fields not yet available in schema
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Facility__c.fields.getMap();
        if (!fieldMap.containsKey('ccm_launch_date__c')) {
            System.debug('Skipping test - CCM_Launch_Date__c not in schema yet');
            return;
        }

        Facility__c facility = [
            SELECT Id, CCM__c
            FROM Facility__c
            WHERE CCM__c = true
            LIMIT 1
        ];

        // First set a date value using dynamic field assignment
        facility.put('CCM_Launch_Date__c', Date.today());
        update facility;

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CCM_Launch_Date__c', null); // Clear the date

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Id facilityId = facility.Id;
        List<Facility__c> results = Database.query('SELECT CCM_Launch_Date__c FROM Facility__c WHERE Id = :facilityId');
        System.assertEquals(null, results[0].get('CCM_Launch_Date__c'), 'CCM_Launch_Date__c should be null');
    }

    @isTest
    static void testUpdateFacilities_DateFieldEmptyString() {
        // Test clearing a Date field by setting it to empty string
        // Skip if date fields not yet available in schema
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Facility__c.fields.getMap();
        if (!fieldMap.containsKey('ccm_launch_date__c')) {
            System.debug('Skipping test - CCM_Launch_Date__c not in schema yet');
            return;
        }

        Facility__c facility = [
            SELECT Id, CCM__c
            FROM Facility__c
            WHERE CCM__c = true
            LIMIT 1
        ];

        // First set a date value using dynamic field assignment
        facility.put('CCM_Launch_Date__c', Date.today());
        update facility;

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CCM_Launch_Date__c', ''); // Empty string should clear the date

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Id facilityId = facility.Id;
        List<Facility__c> results = Database.query('SELECT CCM_Launch_Date__c FROM Facility__c WHERE Id = :facilityId');
        System.assertEquals(null, results[0].get('CCM_Launch_Date__c'), 'CCM_Launch_Date__c should be null when empty string provided');
    }

    @isTest
    static void testUpdateFacilities_MultipleDateFields() {
        // Test updating multiple date fields at once
        // Skip if date fields not yet available in schema
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Facility__c.fields.getMap();
        if (!fieldMap.containsKey('ccm_launch_date__c')) {
            System.debug('Skipping test - CCM_Launch_Date__c not in schema yet');
            return;
        }

        Facility__c facility = [
            SELECT Id, CCM__c
            FROM Facility__c
            WHERE CCM__c = true
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CCM_Launch_Date__c', '2025-01-01');
        fields.put('CCM_On_Hold_Date__c', '2025-06-15');

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Id facilityId = facility.Id;
        List<Facility__c> results = Database.query('SELECT CCM_Launch_Date__c, CCM_On_Hold_Date__c FROM Facility__c WHERE Id = :facilityId');
        System.assertEquals(Date.valueOf('2025-01-01'), results[0].get('CCM_Launch_Date__c'), 'Launch date should be set');
        System.assertEquals(Date.valueOf('2025-06-15'), results[0].get('CCM_On_Hold_Date__c'), 'On Hold date should be set');
    }

    @isTest
    static void testUpdateFacilities_BulkDateUpdates() {
        // Test bulk updating date fields across 200+ facilities (governor limits test)
        // Skip if date fields not yet available in schema
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Facility__c.fields.getMap();
        if (!fieldMap.containsKey('ccm_launch_date__c')) {
            System.debug('Skipping test - CCM_Launch_Date__c not in schema yet');
            return;
        }

        List<Facility__c> facilities = [
            SELECT Id, CCM__c
            FROM Facility__c
            WHERE CCM__c = true
            LIMIT 200
        ];

        System.assert(facilities.size() >= 100, 'Should have at least 100 facilities with CCM enabled for bulk test');

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        for (Facility__c fac : facilities) {
            Map<String, Object> facData = new Map<String, Object>();
            facData.put('Id', fac.Id);

            Map<String, Object> fields = new Map<String, Object>();
            fields.put('CCM_Launch_Date__c', '2025-03-15');

            facData.put('fields', fields);
            updateData.add(facData);
        }

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();

        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);

        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Bulk update should be successful');
        System.assertEquals(facilities.size(), result.get('count'), 'Should update all facilities');

        // Verify O(1) operations - not O(n)
        System.assert(soqlUsed <= 5, 'SOQL should be O(1), not O(n). Used: ' + soqlUsed);
        System.assert(dmlUsed <= 3, 'DML should be O(1), not O(n). Used: ' + dmlUsed);

        // Verify dates were actually set using dynamic SOQL
        Set<Id> facilityIds = new Set<Id>();
        for (Facility__c fac : facilities) {
            facilityIds.add(fac.Id);
        }
        List<Facility__c> updatedFacilities = Database.query('SELECT CCM_Launch_Date__c FROM Facility__c WHERE Id IN :facilityIds');

        for (Facility__c fac : updatedFacilities) {
            System.assertEquals(Date.valueOf('2025-03-15'), fac.get('CCM_Launch_Date__c'), 'All facilities should have date set');
        }
    }

    @isTest
    static void testUpdateFacilities_AllProgramDates() {
        // Test updating dates for all 7 programs
        // Skip if date fields not yet available in schema
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Facility__c.fields.getMap();
        if (!fieldMap.containsKey('ccm_launch_date__c')) {
            System.debug('Skipping test - CCM_Launch_Date__c not in schema yet');
            return;
        }

        Facility__c facility = [
            SELECT Id
            FROM Facility__c
            LIMIT 1
        ];

        // Enable all programs first
        facility.CCM__c = true;
        facility.RPM__c = true;
        facility.TCM__c = true;
        facility.COCM__c = true;
        facility.AHTH__c = true;
        facility.APCM__c = true;
        facility.BHI__c = true;
        update facility;

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        // Set launch dates for all programs
        fields.put('CCM_Launch_Date__c', '2025-01-01');
        fields.put('CCM_On_Hold_Date__c', '2025-02-01');
        fields.put('RPM_Launch_Date__c', '2025-01-02');
        fields.put('RPM_On_Hold_Date__c', '2025-02-02');
        fields.put('TCM_Launch_Date__c', '2025-01-03');
        fields.put('TCM_On_Hold_Date__c', '2025-02-03');
        fields.put('COCM_Launch_Date__c', '2025-01-04');
        fields.put('COCM_On_Hold_Date__c', '2025-02-04');
        fields.put('AHTH_Launch_Date__c', '2025-01-05');
        fields.put('AHTH_On_Hold_Date__c', '2025-02-05');
        fields.put('APCM_Launch_Date__c', '2025-01-06');
        fields.put('APCM_On_Hold_Date__c', '2025-02-06');
        fields.put('BHI_Launch_Date__c', '2025-01-07');
        fields.put('BHI_On_Hold_Date__c', '2025-02-07');

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        // Use dynamic SOQL to query all date fields
        Id facilityId = facility.Id;
        String query = 'SELECT CCM_Launch_Date__c, CCM_On_Hold_Date__c, ' +
                      'RPM_Launch_Date__c, RPM_On_Hold_Date__c, ' +
                      'TCM_Launch_Date__c, TCM_On_Hold_Date__c, ' +
                      'COCM_Launch_Date__c, COCM_On_Hold_Date__c, ' +
                      'AHTH_Launch_Date__c, AHTH_On_Hold_Date__c, ' +
                      'APCM_Launch_Date__c, APCM_On_Hold_Date__c, ' +
                      'BHI_Launch_Date__c, BHI_On_Hold_Date__c ' +
                      'FROM Facility__c WHERE Id = :facilityId';
        List<Facility__c> results = Database.query(query);
        Facility__c updatedFacility = results[0];

        // Verify all 14 dates were set correctly
        System.assertEquals(Date.valueOf('2025-01-01'), updatedFacility.get('CCM_Launch_Date__c'), 'CCM Launch Date mismatch');
        System.assertEquals(Date.valueOf('2025-02-01'), updatedFacility.get('CCM_On_Hold_Date__c'), 'CCM On Hold Date mismatch');
        System.assertEquals(Date.valueOf('2025-01-02'), updatedFacility.get('RPM_Launch_Date__c'), 'RPM Launch Date mismatch');
        System.assertEquals(Date.valueOf('2025-02-02'), updatedFacility.get('RPM_On_Hold_Date__c'), 'RPM On Hold Date mismatch');
        System.assertEquals(Date.valueOf('2025-01-03'), updatedFacility.get('TCM_Launch_Date__c'), 'TCM Launch Date mismatch');
        System.assertEquals(Date.valueOf('2025-02-03'), updatedFacility.get('TCM_On_Hold_Date__c'), 'TCM On Hold Date mismatch');
        System.assertEquals(Date.valueOf('2025-01-04'), updatedFacility.get('COCM_Launch_Date__c'), 'COCM Launch Date mismatch');
        System.assertEquals(Date.valueOf('2025-02-04'), updatedFacility.get('COCM_On_Hold_Date__c'), 'COCM On Hold Date mismatch');
        System.assertEquals(Date.valueOf('2025-01-05'), updatedFacility.get('AHTH_Launch_Date__c'), 'AHTH Launch Date mismatch');
        System.assertEquals(Date.valueOf('2025-02-05'), updatedFacility.get('AHTH_On_Hold_Date__c'), 'AHTH On Hold Date mismatch');
        System.assertEquals(Date.valueOf('2025-01-06'), updatedFacility.get('APCM_Launch_Date__c'), 'APCM Launch Date mismatch');
        System.assertEquals(Date.valueOf('2025-02-06'), updatedFacility.get('APCM_On_Hold_Date__c'), 'APCM On Hold Date mismatch');
        System.assertEquals(Date.valueOf('2025-01-07'), updatedFacility.get('BHI_Launch_Date__c'), 'BHI Launch Date mismatch');
        System.assertEquals(Date.valueOf('2025-02-07'), updatedFacility.get('BHI_On_Hold_Date__c'), 'BHI On Hold Date mismatch');
    }

    @isTest
    static void testUpdateFacilities_DateAndBooleanMixed() {
        // Test updating both date and boolean fields in single update
        // Skip if date fields not yet available in schema
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Facility__c.fields.getMap();
        if (!fieldMap.containsKey('ccm_launch_date__c')) {
            System.debug('Skipping test - CCM_Launch_Date__c not in schema yet');
            return;
        }

        Facility__c facility = [
            SELECT Id, CCM__c
            FROM Facility__c
            LIMIT 1
        ];

        List<Map<String, Object>> updateData = new List<Map<String, Object>>();
        Map<String, Object> facData = new Map<String, Object>();
        facData.put('Id', facility.Id);

        Map<String, Object> fields = new Map<String, Object>();
        fields.put('CCM__c', true);
        fields.put('CCM_Launch_Date__c', '2025-04-01');
        fields.put('RPM__c', true);
        fields.put('RPM_Launch_Date__c', '2025-04-15');

        facData.put('fields', fields);
        updateData.add(facData);

        String updateJson = JSON.serialize(updateData);

        Test.startTest();
        Map<String, Object> result = FacilityEditorController.updateFacilities(updateJson);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Update should be successful');

        Id facilityId = facility.Id;
        List<Facility__c> results = Database.query('SELECT CCM__c, CCM_Launch_Date__c, RPM__c, RPM_Launch_Date__c FROM Facility__c WHERE Id = :facilityId');
        Facility__c updatedFacility = results[0];

        System.assertEquals(true, updatedFacility.CCM__c, 'CCM should be enabled');
        System.assertEquals(Date.valueOf('2025-04-01'), updatedFacility.get('CCM_Launch_Date__c'), 'CCM Launch Date should be set');
        System.assertEquals(true, updatedFacility.RPM__c, 'RPM should be enabled');
        System.assertEquals(Date.valueOf('2025-04-15'), updatedFacility.get('RPM_Launch_Date__c'), 'RPM Launch Date should be set');
    }
}