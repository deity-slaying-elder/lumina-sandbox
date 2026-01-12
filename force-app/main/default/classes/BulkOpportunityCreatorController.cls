public with sharing class BulkOpportunityCreatorController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getInitialData(Id accountId) {
        System.debug('*** getInitialData START - accountId: ' + accountId);

        // Validate accountId is provided
        if (accountId == null) {
            System.debug('*** ERROR: Account ID is null');
            throw new AuraHandledException('Account ID is required.');
        }

        try {
            Map<String, Object> result = new Map<String, Object>();

            // Get facilities related to the account (only facilities explicitly linked to this account)
            System.debug('*** Querying facilities for accountId: ' + accountId);
            List<Facility__c> facilities = [
                SELECT Id, Name, Parent_Company__c
                FROM Facility__c
                WHERE Parent_Company__c = :accountId
                ORDER BY Name
            ];
            System.debug('*** Found ' + facilities.size() + ' facilities');

            // Validate that facilities exist
            if (facilities.isEmpty()) {
                System.debug('*** ERROR: No facilities found');
                throw new AuraHandledException('No facilities found for this account.');
            }

            // Get Opportunity Type picklist values
            System.debug('*** Getting Opportunity Type picklist values');
            List<Map<String, String>> typeOptions = new List<Map<String, String>>();
            Schema.DescribeFieldResult fieldResult = Opportunity.Type.getDescribe();
            List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();

            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive()) {
                    Map<String, String> option = new Map<String, String>();
                    option.put('label', entry.getLabel());
                    option.put('value', entry.getValue());
                    typeOptions.add(option);
                }
            }
            System.debug('*** Found ' + typeOptions.size() + ' type options');

            // Get FieldSet metadata for dynamic field rendering
            System.debug('*** Getting FieldSet metadata');
            List<Map<String, Object>> fieldSetFields = getFieldSetMetadata();
            System.debug('*** Found ' + fieldSetFields.size() + ' fields in fieldset');

            result.put('facilities', facilities);
            result.put('typeOptions', typeOptions);
            result.put('fieldSetFields', fieldSetFields);

            System.debug('*** getInitialData SUCCESS - returning result');
            return result;
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledExceptions as-is (these are our intentional user-facing errors)
            System.debug('*** AuraHandledException in getInitialData: ' + e.getMessage());
            throw e;
        } catch (Exception e) {
            // Catch unexpected exceptions and wrap them
            System.debug('*** Unexpected EXCEPTION in getInitialData: ' + e.getMessage());
            System.debug('*** Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred while loading data. Please contact your administrator.');
        }
    }

    private static List<Map<String, Object>> getFieldSetMetadata() {
        List<Map<String, Object>> fieldMetadata = new List<Map<String, Object>>();
        System.debug('*** getFieldSetMetadata START');

        try {
            System.debug('*** Accessing Opportunity.fieldSets.Bulk_Opportunity_Create');
            Schema.FieldSet fieldSet = Schema.SObjectType.Opportunity.fieldSets.Bulk_Opportunity_Create;
            System.debug('*** FieldSet retrieved: ' + (fieldSet != null));

            if (fieldSet != null) {
                List<Schema.FieldSetMember> fields = fieldSet.getFields();
                System.debug('*** FieldSet has ' + fields.size() + ' fields');

                for (Schema.FieldSetMember field : fields) {
                    try {
                        System.debug('*** Processing field: ' + field.getFieldPath());

                        // Get additional field describe information
                        Schema.DescribeFieldResult fieldDescribe = field.getSObjectField().getDescribe();
                        String apiName = fieldDescribe.getName();
                        System.debug('*** Field API Name: ' + apiName + ', Type: ' + field.getType());

                        // Skip the Type field since it's handled via checkboxes
                        if (apiName == 'Type') {
                            System.debug('*** Skipping Type field');
                            continue;
                        }

                        Map<String, Object> fieldInfo = new Map<String, Object>();
                        fieldInfo.put('fieldPath', field.getFieldPath());
                        fieldInfo.put('label', field.getLabel());
                        fieldInfo.put('required', field.getRequired() || field.getDbRequired());
                        fieldInfo.put('type', String.valueOf(field.getType()));
                        fieldInfo.put('apiName', apiName);

                        // For picklist fields, get the values
                        if (field.getType() == Schema.DisplayType.PICKLIST ||
                            field.getType() == Schema.DisplayType.MULTIPICKLIST) {
                            System.debug('*** Getting picklist values for: ' + apiName);
                            List<Map<String, String>> picklistOptions = new List<Map<String, String>>();
                            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                                if (entry.isActive()) {
                                    Map<String, String> option = new Map<String, String>();
                                    option.put('label', entry.getLabel());
                                    option.put('value', entry.getValue());
                                    picklistOptions.add(option);
                                }
                            }
                            fieldInfo.put('picklistValues', picklistOptions);
                            System.debug('*** Found ' + picklistOptions.size() + ' picklist values');
                        }

                        fieldMetadata.add(fieldInfo);
                        System.debug('*** Successfully added field: ' + apiName);
                    } catch (Exception fieldEx) {
                        System.debug('*** ERROR processing field: ' + fieldEx.getMessage());
                        System.debug('*** Field error stack trace: ' + fieldEx.getStackTraceString());
                        // Continue processing other fields
                    }
                }
            } else {
                System.debug('*** WARNING: FieldSet is null');
            }
        } catch (Exception e) {
            System.debug('*** EXCEPTION in getFieldSetMetadata: ' + e.getMessage());
            System.debug('*** FieldSet error stack trace: ' + e.getStackTraceString());
            // Return empty list if fieldset doesn't exist or can't be accessed
        }

        System.debug('*** getFieldSetMetadata COMPLETE - returning ' + fieldMetadata.size() + ' fields');
        return fieldMetadata;
    }

    private static Boolean isDateString(String value) {
        // Check if string matches date format YYYY-MM-DD
        Pattern datePattern = Pattern.compile('^\\d{4}-\\d{2}-\\d{2}$');
        Matcher dateMatcher = datePattern.matcher(value);
        return dateMatcher.matches();
    }

    @AuraEnabled
    public static Map<String, Object> createOpportunities(Id accountId, String opportunitiesJson) {
        try {
            List<Object> opportunitiesData = (List<Object>) JSON.deserializeUntyped(opportunitiesJson);
            List<Opportunity> opportunitiesToCreate = new List<Opportunity>();

            // Get field describe information for proper type conversion
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Opportunity.fields.getMap();

            for (Object oppData : opportunitiesData) {
                Map<String, Object> oppMap = (Map<String, Object>) oppData;

                Opportunity opp = new Opportunity();
                opp.AccountId = accountId;
                opp.Name = (String) oppMap.get('name');
                opp.StageName = 'Proposal';
                opp.Type = (String) oppMap.get('type');

                // Set the Facility lookup field
                opp.Facility__c = (String) oppMap.get('facilityId');

                // Dynamically set fields from the fieldSet
                Map<String, Object> fieldValues = (Map<String, Object>) oppMap.get('fieldValues');
                if (fieldValues != null) {
                    for (String fieldName : fieldValues.keySet()) {
                        // Skip Type field - it's already set from the checkbox selection
                        if (fieldName == 'Type') {
                            continue;
                        }

                        Object fieldValue = fieldValues.get(fieldName);

                        // Handle different field types with proper conversion
                        if (fieldValue != null && fieldValue != '') {
                            Object convertedValue = convertFieldValue(fieldName, fieldValue, fieldMap);
                            if (convertedValue != null) {
                                opp.put(fieldName, convertedValue);
                            }
                        }
                    }
                }

                opportunitiesToCreate.add(opp);
            }

            if (!opportunitiesToCreate.isEmpty()) {
                // Use Database.insert with allOrNone=false to get all errors
                Database.SaveResult[] saveResults = Database.insert(opportunitiesToCreate, false);

                // Collect all errors
                List<String> errorMessages = new List<String>();
                Integer successCount = 0;

                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    if (!sr.isSuccess()) {
                        // Get the opportunity that failed
                        Opportunity failedOpp = opportunitiesToCreate[i];
                        Map<String, Object> oppMap = (Map<String, Object>) opportunitiesData[i];

                        // Get the error message
                        for (Database.Error err : sr.getErrors()) {
                            String facilityName = (String) oppMap.get('facilityName');
                            errorMessages.add('• ' + facilityName + ' - ' + failedOpp.Type + ': ' + err.getMessage());
                        }
                    } else {
                        successCount++;
                    }
                }

                // If there were any errors, throw them
                if (!errorMessages.isEmpty()) {
                    String errorMessage = 'The following opportunities could not be created:\n\n' + String.join(errorMessages, '\n');
                    throw new AuraHandledException(errorMessage);
                }
            }

            Map<String, Object> result = new Map<String, Object>();
            result.put('success', true);
            result.put('count', opportunitiesToCreate.size());
            result.put('opportunities', opportunitiesToCreate);

            return result;
        } catch (AuraHandledException e) {
            // Re-throw our formatted errors
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Object convertFieldValue(String fieldName, Object fieldValue, Map<String, Schema.SObjectField> fieldMap) {
        if (!fieldMap.containsKey(fieldName)) {
            return fieldValue;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
        Schema.DisplayType fieldType = fieldDescribe.getType();

        try {
            // Handle string values that need conversion
            if (fieldValue instanceof String) {
                String strValue = (String) fieldValue;

                // Skip empty strings
                if (String.isBlank(strValue)) {
                    return null;
                }

                switch on fieldType {
                    when DATE {
                        return Date.valueOf(strValue);
                    }
                    when DATETIME {
                        return DateTime.valueOf(strValue);
                    }
                    when DOUBLE, CURRENCY, PERCENT {
                        return Decimal.valueOf(strValue);
                    }
                    when INTEGER {
                        return Integer.valueOf(strValue);
                    }
                    when BOOLEAN {
                        return Boolean.valueOf(strValue);
                    }
                    when else {
                        return strValue;
                    }
                }
            }

            // Value is already the correct type
            return fieldValue;
        } catch (Exception e) {
            System.debug('Error converting field ' + fieldName + ': ' + e.getMessage());
            return null;
        }
    }
}