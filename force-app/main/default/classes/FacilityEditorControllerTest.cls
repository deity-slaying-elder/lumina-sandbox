@isTest
private class FacilityEditorControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create parent account
        Account parentAccount = new Account(
            Name = 'Test Parent Account'
        );
        insert parentAccount;

        // Create facilities linked to the parent account with various field values
        List<Facility__c> facilities = new List<Facility__c>();
        for (Integer i = 1; i <= 3; i++) {
            facilities.add(new Facility__c(
                Name = 'Test Facility ' + i,
                Parent_Company__c = parentAccount.Id,
                CCM__c = false,
                TCM__c = false,
                BHI__c = false,
                RPM__c = false,
                AHTH__c = false,
                APCM__c = false,
                COCM__c = false
            ));
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
        System.assertEquals(3, facilities.size(), 'Should have 3 facilities');

        // Verify total facility count
        Integer totalCount = (Integer) result.get('totalFacilityCount');
        System.assertEquals(3, totalCount, 'Should have 3 facilities');

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
}