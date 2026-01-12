@isTest
private class BulkOpportunityCreatorControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;

        // Create test Facilities linked to the Account
        List<Facility__c> facilities = new List<Facility__c>{
            new Facility__c(
                Name = 'Facility 1',
                Parent_Company__c = testAccount.Id
            ),
            new Facility__c(
                Name = 'Facility 2',
                Parent_Company__c = testAccount.Id
            )
        };
        insert facilities;
    }

    @isTest
    static void testGetInitialData_Success() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.getInitialData(testAccount.Id);
        Test.stopTest();

        // Verify
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('facilities'), 'Result should contain facilities');
        System.assert(result.containsKey('typeOptions'), 'Result should contain typeOptions');
        System.assert(result.containsKey('fieldSetFields'), 'Result should contain fieldSetFields');

        List<Object> facilities = (List<Object>) result.get('facilities');
        System.assertEquals(2, facilities.size(), 'Should return 2 facilities');

        List<Object> typeOptions = (List<Object>) result.get('typeOptions');
        System.assert(typeOptions.size() > 0, 'Should return type options');
    }

    @isTest
    static void testGetInitialData_NoFacilities() {
        // Create account without facilities
        Account accountWithoutFacilities = new Account(Name = 'No Facilities Account');
        insert accountWithoutFacilities;

        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        try {
            BulkOpportunityCreatorController.getInitialData(accountWithoutFacilities.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        // Verify
        System.assert(exceptionThrown, 'Should throw exception when no facilities exist');
    }

    @isTest
    static void testGetInitialData_NullAccountId() {
        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        try {
            BulkOpportunityCreatorController.getInitialData(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        // Verify
        System.assert(exceptionThrown, 'Should throw exception when accountId is null');
    }

    @isTest
    static void testCreateOpportunities_Success() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 2];

        // Build opportunities JSON
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp 1',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31'
                }
            },
            new Map<String, Object>{
                'name' => 'Test Opp 2',
                'type' => 'Existing Customer',
                'facilityId' => facilities[1].Id,
                'facilityName' => facilities[1].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-11-30'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify
        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(2, result.get('count'), 'Should create 2 opportunities');

        List<Opportunity> createdOpps = [SELECT Id, Name, Type, StageName, CloseDate, Facility__c
                                         FROM Opportunity
                                         WHERE AccountId = :testAccount.Id];
        System.assertEquals(2, createdOpps.size(), 'Should have created 2 opportunities in database');
        System.assertEquals('Proposal', createdOpps[0].StageName, 'Stage should be Proposal');
        System.assertEquals(Date.valueOf('2025-12-31'), createdOpps[0].CloseDate, 'CloseDate should be converted to Date');
    }

    @isTest
    static void testCreateOpportunities_WithCurrencyConversion() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with Amount (Currency field)
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp with Amount',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31',
                    'Amount' => '50000.75'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify
        System.assertEquals(true, result.get('success'), 'Should return success');

        Opportunity createdOpp = [SELECT Id, Amount FROM Opportunity WHERE AccountId = :testAccount.Id LIMIT 1];
        System.assertEquals(50000.75, createdOpp.Amount, 'Amount should be converted to Decimal');
    }

    @isTest
    static void testCreateOpportunities_SkipTypeField() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with Type in fieldValues (should be skipped)
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31',
                    'Type' => 'Different Type'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify Type from checkbox is used, not from fieldValues
        Opportunity createdOpp = [SELECT Id, Type FROM Opportunity WHERE AccountId = :testAccount.Id LIMIT 1];
        System.assertEquals('New Customer', createdOpp.Type, 'Should use Type from checkbox, not fieldValues');
    }

    @isTest
    static void testCreateOpportunities_EmptyList() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Build empty opportunities JSON
        String opportunitiesJson = '[]';

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify
        System.assertEquals(true, result.get('success'), 'Should return success even with empty list');
        System.assertEquals(0, result.get('count'), 'Count should be 0');
    }

    @isTest
    static void testCreateOpportunities_PartialFailure() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Create an existing open opportunity to trigger duplicate validation
        Opportunity existingOpp = new Opportunity(
            Name = 'Existing Opp',
            AccountId = testAccount.Id,
            Facility__c = facilities[0].Id,
            Type = 'New Customer',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30)
        );
        insert existingOpp;

        // Build opportunities JSON with duplicate
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Duplicate Opp',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        try {
            BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        // Verify error is thrown
        System.assert(exceptionThrown, 'Should throw exception for duplicate');
    }

    @isTest
    static void testCreateOpportunities_MultipleErrors() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 2];

        // Create existing open opportunities to trigger duplicate validation
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

        // Build opportunities JSON with multiple duplicates
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Duplicate Opp 1',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31'
                }
            },
            new Map<String, Object>{
                'name' => 'Duplicate Opp 2',
                'type' => 'Existing Customer',
                'facilityId' => facilities[1].Id,
                'facilityName' => facilities[1].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-11-30'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        try {
            BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        // Verify both errors are included
        System.assert(exceptionThrown, 'Should throw exception for duplicates');
    }

    @isTest
    static void testCreateOpportunities_MinimalFields() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with minimal fields (just CloseDate in fieldValues)
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Minimal Fields',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify - should succeed with minimal fields
        System.assertEquals(true, result.get('success'), 'Should succeed with minimal fields');
        System.assertEquals(1, result.get('count'), 'Should create 1 opportunity');
    }

    @isTest
    static void testCreateOpportunities_EmptyStringConversion() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with empty string value
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Empty Values',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31',
                    'Amount' => ''
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify - empty strings should be converted to null
        System.assertEquals(true, result.get('success'), 'Should succeed with empty string values');
        Opportunity createdOpp = [SELECT Id, Amount FROM Opportunity WHERE AccountId = :testAccount.Id LIMIT 1];
        System.assertEquals(null, createdOpp.Amount, 'Empty string should be converted to null');
    }

    @isTest
    static void testCreateOpportunities_DateTimeConversion() {
        // Test datetime field conversion
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with datetime value
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp DateTime',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify datetime conversion
        System.assertEquals(true, result.get('success'), 'Should handle datetime conversion');
        System.assertEquals(1, result.get('count'), 'Should create 1 opportunity');
    }

    @isTest
    static void testCreateOpportunities_IntegerConversion() {
        // Test integer field conversion
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Integer',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify integer conversion handling
        System.assertEquals(true, result.get('success'), 'Should handle integer fields');
    }

    @isTest
    static void testCreateOpportunities_BooleanConversion() {
        // Test boolean field conversion
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Boolean',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify boolean conversion handling
        System.assertEquals(true, result.get('success'), 'Should handle boolean fields');
    }

    @isTest
    static void testCreateOpportunities_DoubleConversion() {
        // Test double/decimal field conversion
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with double value
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Double',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31',
                    'Amount' => '123.45'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify double conversion
        System.assertEquals(true, result.get('success'), 'Should handle double conversion');
        Opportunity createdOpp = [SELECT Id, Amount FROM Opportunity WHERE AccountId = :testAccount.Id LIMIT 1];
        System.assertEquals(123.45, createdOpp.Amount, 'Double should be converted properly');
    }

    @isTest
    static void testCreateOpportunities_PercentConversion() {
        // Test percent field conversion
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with percent value
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Percent',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31',
                    'Probability' => '50'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify percent conversion
        System.assertEquals(true, result.get('success'), 'Should handle percent conversion');
        Opportunity createdOpp = [SELECT Id, Probability FROM Opportunity WHERE AccountId = :testAccount.Id LIMIT 1];
        System.assertEquals(50, createdOpp.Probability, 'Percent should be converted properly');
    }

    @isTest
    static void testCreateOpportunities_NullFieldValue() {
        // Test null field value handling
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with null value
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Null',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31',
                    'Amount' => null
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        Test.stopTest();

        // Verify null handling
        System.assertEquals(true, result.get('success'), 'Should handle null values');
        Opportunity createdOpp = [SELECT Id, Amount FROM Opportunity WHERE AccountId = :testAccount.Id LIMIT 1];
        System.assertEquals(null, createdOpp.Amount, 'Null should remain null');
    }

    @isTest
    static void testCreateOpportunities_InvalidDateFormat() {
        // Test invalid date format handling
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with invalid date
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Invalid Date',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => 'invalid-date'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        // Verify exception is thrown for invalid date
        System.assert(exceptionThrown, 'Should throw exception for invalid date format');
    }

    @isTest
    static void testCreateOpportunities_InvalidJson() {
        // Test invalid JSON handling
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        String invalidJson = 'this is not valid json';

        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            BulkOpportunityCreatorController.createOpportunities(testAccount.Id, invalidJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        // Verify exception is thrown
        System.assert(exceptionThrown, 'Should throw exception for invalid JSON');
    }

    @isTest
    static void testCreateOpportunities_FieldNotInSchema() {
        // Test field not in schema handling - expect exception
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<Facility__c> facilities = [SELECT Id, Name FROM Facility__c LIMIT 1];

        // Build opportunities JSON with non-existent field
        List<Map<String, Object>> oppsList = new List<Map<String, Object>>{
            new Map<String, Object>{
                'name' => 'Test Opp Invalid Field',
                'type' => 'New Customer',
                'facilityId' => facilities[0].Id,
                'facilityName' => facilities[0].Name,
                'fieldValues' => new Map<String, Object>{
                    'CloseDate' => '2025-12-31',
                    'NonExistentField__c' => 'somevalue'
                }
            }
        };
        String opportunitiesJson = JSON.serialize(oppsList);

        // Test
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            BulkOpportunityCreatorController.createOpportunities(testAccount.Id, opportunitiesJson);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        // Should throw exception for non-existent field
        System.assert(exceptionThrown, 'Should throw exception for non-existent field');
    }

    @isTest
    static void testGetInitialData_FieldSetMetadata() {
        // Test that field set metadata is retrieved correctly
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.getInitialData(testAccount.Id);
        Test.stopTest();

        // Verify field set metadata
        List<Object> fields = (List<Object>) result.get('fieldSetFields');
        System.assertNotEquals(null, fields, 'Field set fields should not be null');

        // Verify each field has required properties
        if (fields.size() > 0) {
            Map<String, Object> firstField = (Map<String, Object>) fields[0];
            System.assert(firstField.containsKey('apiName'), 'Field should have apiName');
            System.assert(firstField.containsKey('label'), 'Field should have label');
            System.assert(firstField.containsKey('type'), 'Field should have type');
        }
    }

    @isTest
    static void testGetInitialData_TypeOptionsNotEmpty() {
        // Verify type options are populated
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        // Test
        Test.startTest();
        Map<String, Object> result = BulkOpportunityCreatorController.getInitialData(testAccount.Id);
        Test.stopTest();

        // Verify type options
        List<Object> typeOptions = (List<Object>) result.get('typeOptions');
        System.assertNotEquals(null, typeOptions, 'Type options should not be null');
        System.assert(typeOptions.size() > 0, 'Should have at least one type option');

        // Verify type option structure
        Map<String, Object> firstType = (Map<String, Object>) typeOptions[0];
        System.assert(firstType.containsKey('label'), 'Type option should have label');
        System.assert(firstType.containsKey('value'), 'Type option should have value');
    }
}