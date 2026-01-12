public with sharing class BulkOpportunityEditorController {

    @AuraEnabled
    public static Map<String, Object> getOpportunitiesAndFields(Id accountId) {
        try {
            Map<String, Object> result = new Map<String, Object>();

            System.debug('Getting opportunities for account: ' + accountId);

            // Validate that accountId is not null
            if (accountId == null) {
                throw new AuraHandledException('Account ID is null. Please ensure the component is placed on an Account record page.');
            }

            // Get field set fields
            List<Map<String, Object>> fieldSetFields = new List<Map<String, Object>>();
            Schema.FieldSet fieldSet = Schema.SObjectType.Opportunity.FieldSets.getMap().get('Bulk_Opportunity_Edit');

            if (fieldSet == null) {
                throw new AuraHandledException('Field set "Bulk_Opportunity_Edit" not found on Opportunity object.');
            }

            for (Schema.FieldSetMember field : fieldSet.getFields()) {
                Map<String, Object> fieldInfo = new Map<String, Object>();
                fieldInfo.put('fieldPath', field.getFieldPath());
                fieldInfo.put('label', field.getLabel());
                fieldInfo.put('required', field.getRequired() || field.getDbRequired());
                fieldInfo.put('type', String.valueOf(field.getType()));

                // Get additional field metadata
                Schema.DescribeFieldResult fieldDescribe = field.getSObjectField().getDescribe();
                fieldInfo.put('updateable', fieldDescribe.isUpdateable());

                // For picklist fields, get the picklist values
                if (field.getType() == Schema.DisplayType.PICKLIST || field.getType() == Schema.DisplayType.MULTIPICKLIST) {
                    List<Map<String, String>> picklistValues = new List<Map<String, String>>();
                    for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                        if (entry.isActive()) {
                            Map<String, String> picklistValue = new Map<String, String>();
                            picklistValue.put('label', entry.getLabel());
                            picklistValue.put('value', entry.getValue());
                            picklistValues.add(picklistValue);
                        }
                    }
                    fieldInfo.put('picklistValues', picklistValues);
                }

                fieldSetFields.add(fieldInfo);
            }

            // Build dynamic SOQL query for opportunities - directly filter by Parent Company
            Set<String> fieldPaths = new Set<String>{'Id', 'Name', 'Facility__c', 'Facility__r.Name', 'Facility__r.Parent_Company__c', 'StageName', 'Type'};

            // Add all field set fields to the query
            for (Map<String, Object> field : fieldSetFields) {
                String fieldPath = (String)field.get('fieldPath');
                fieldPaths.add(fieldPath);
            }

            String query = 'SELECT ' + String.join(new List<String>(fieldPaths), ', ') +
                          ' FROM Opportunity ' +
                          ' WHERE Facility__c != null ' +
                          ' AND Facility__r.Parent_Company__c = :accountId ' +
                          ' AND StageName NOT IN (\'Closed Won\', \'Closed Lost\') ' +
                          ' ORDER BY Facility__c, Name';

            System.debug('Query: ' + query);
            System.debug('Account ID: ' + accountId);
            List<Opportunity> opportunities = Database.query(query);
            System.debug('Found opportunities: ' + opportunities.size());

            // Debug: Log ALL opportunities to verify filtering
            System.debug('=== DETAILED OPPORTUNITY BREAKDOWN ===');
            List<Opportunity> filteredOpportunities = new List<Opportunity>();

            for (Opportunity opp : opportunities) {
                System.debug('Opp Name: ' + opp.Name);
                System.debug('  Facility ID: ' + opp.Facility__c);
                System.debug('  Facility Name: ' + opp.Facility__r.Name);
                System.debug('  Parent Company ID: ' + opp.Facility__r.Parent_Company__c);
                System.debug('  Expected Account ID: ' + accountId);

                // Double-check in Apex to ensure filtering
                if (opp.Facility__c != null && opp.Facility__r.Parent_Company__c == accountId) {
                    System.debug('  Match: TRUE - INCLUDING');
                    filteredOpportunities.add(opp);
                } else {
                    System.debug('  Match: FALSE - EXCLUDING');
                }
                System.debug('---');
            }

            System.debug('Total opportunities after filtering: ' + filteredOpportunities.size());
            opportunities = filteredOpportunities;

            if (opportunities.isEmpty()) {
                throw new AuraHandledException('This account doesn\'t have any opportunities to edit.');
            }

            // Group opportunities by facility and build facility data
            Map<Id, Map<String, Object>> facilitiesMap = new Map<Id, Map<String, Object>>();

            for (Opportunity opp : opportunities) {
                Id facilityId = opp.Facility__c;
                String facilityName = opp.Facility__r.Name;

                // Create facility entry if it doesn't exist
                if (!facilitiesMap.containsKey(facilityId)) {
                    Map<String, Object> facilityData = new Map<String, Object>();
                    facilityData.put('Id', facilityId);
                    facilityData.put('Name', facilityName);
                    facilityData.put('opportunities', new List<Opportunity>());
                    facilityData.put('opportunityCount', 0);
                    facilitiesMap.put(facilityId, facilityData);
                }

                // Add opportunity to facility
                List<Opportunity> facilityOpps = (List<Opportunity>) facilitiesMap.get(facilityId).get('opportunities');
                facilityOpps.add(opp);
                facilitiesMap.get(facilityId).put('opportunityCount', facilityOpps.size());
            }

            System.debug('Grouped opportunities by facility: ' + facilitiesMap.keySet());

            // Convert map to list
            List<Map<String, Object>> facilitiesWithOpps = facilitiesMap.values();

            result.put('facilities', facilitiesWithOpps);
            result.put('fields', fieldSetFields);
            result.put('totalOpportunityCount', opportunities.size());

            System.debug('Returning result with ' + facilitiesWithOpps.size() + ' facilities');
            System.debug('Result JSON: ' + JSON.serialize(result));

            return result;
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledExceptions as-is (these are our intentional user-facing errors)
            System.debug('AuraHandledException in getOpportunitiesAndFields: ' + e.getMessage());
            throw e;
        } catch (Exception e) {
            // Catch unexpected exceptions and wrap them
            System.debug('Unexpected Exception in getOpportunitiesAndFields: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred while loading opportunities. Please contact your administrator.');
        }
    }

    @AuraEnabled
    public static Map<String, List<Map<String, String>>> getPicklistValues(List<String> fieldNames) {
        try {
            Map<String, List<Map<String, String>>> result = new Map<String, List<Map<String, String>>>();

            // Get Opportunity field map using Schema
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Opportunity.fields.getMap();

            for (String fieldName : fieldNames) {
                // Get the field describe
                Schema.SObjectField fieldToken = fieldMap.get(fieldName);

                if (fieldToken != null) {
                    Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
                    Schema.DisplayType fieldType = fieldDescribe.getType();

                    // Check if it's a picklist field
                    if (fieldType == Schema.DisplayType.PICKLIST || fieldType == Schema.DisplayType.MULTIPICKLIST) {
                        List<Map<String, String>> picklistValues = new List<Map<String, String>>();

                        // Get picklist values
                        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                            if (entry.isActive()) {
                                Map<String, String> picklistValue = new Map<String, String>();
                                picklistValue.put('label', entry.getLabel());
                                picklistValue.put('value', entry.getValue());
                                picklistValues.add(picklistValue);
                            }
                        }

                        result.put(fieldName, picklistValues);
                    }
                }
            }

            return result;
        } catch (Exception e) {
            System.debug('Exception in getPicklistValues: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('An error occurred while retrieving picklist values: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> updateOpportunities(String opportunitiesJson) {
        try {
            List<Object> opportunitiesData = (List<Object>) JSON.deserializeUntyped(opportunitiesJson);
            List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();

            // Get field type information for proper conversion
            Map<String, Schema.SObjectField> opportunityFields = Schema.SObjectType.Opportunity.fields.getMap();

            for (Object oppData : opportunitiesData) {
                Map<String, Object> oppMap = (Map<String, Object>) oppData;

                Opportunity opp = new Opportunity();
                opp.Id = (String) oppMap.get('Id');

                // Get the fields map
                Map<String, Object> fieldsMap = (Map<String, Object>) oppMap.get('fields');

                // Dynamically set fields with proper type conversion
                for (String fieldName : fieldsMap.keySet()) {
                    Object fieldValue = fieldsMap.get(fieldName);
                    if (fieldValue != null) {
                        // Get field type to handle conversion
                        Schema.SObjectField fieldToken = opportunityFields.get(fieldName);
                        if (fieldToken != null) {
                            Schema.DisplayType fieldType = fieldToken.getDescribe().getType();

                            // Convert based on field type
                            if (fieldType == Schema.DisplayType.CURRENCY ||
                                fieldType == Schema.DisplayType.DOUBLE ||
                                fieldType == Schema.DisplayType.PERCENT) {
                                // Convert String to Decimal
                                if (fieldValue instanceof String) {
                                    String strValue = (String) fieldValue;
                                    if (String.isNotBlank(strValue)) {
                                        opp.put(fieldName, Decimal.valueOf(strValue));
                                    }
                                } else {
                                    opp.put(fieldName, fieldValue);
                                }
                            } else if (fieldType == Schema.DisplayType.INTEGER) {
                                // Convert String to Integer
                                if (fieldValue instanceof String) {
                                    String strValue = (String) fieldValue;
                                    if (String.isNotBlank(strValue)) {
                                        opp.put(fieldName, Integer.valueOf(strValue));
                                    }
                                } else {
                                    opp.put(fieldName, fieldValue);
                                }
                            } else if (fieldType == Schema.DisplayType.DATE) {
                                // Convert String to Date
                                if (fieldValue instanceof String) {
                                    String strValue = (String) fieldValue;
                                    if (String.isNotBlank(strValue)) {
                                        opp.put(fieldName, Date.valueOf(strValue));
                                    }
                                } else {
                                    opp.put(fieldName, fieldValue);
                                }
                            } else if (fieldType == Schema.DisplayType.DATETIME) {
                                // Convert String to DateTime
                                if (fieldValue instanceof String) {
                                    String strValue = (String) fieldValue;
                                    if (String.isNotBlank(strValue)) {
                                        opp.put(fieldName, DateTime.valueOf(strValue));
                                    }
                                } else {
                                    opp.put(fieldName, fieldValue);
                                }
                            } else if (fieldType == Schema.DisplayType.BOOLEAN) {
                                // Handle Boolean
                                if (fieldValue instanceof String) {
                                    opp.put(fieldName, Boolean.valueOf((String) fieldValue));
                                } else {
                                    opp.put(fieldName, fieldValue);
                                }
                            } else {
                                // For other types (String, Picklist, etc.), use as-is
                                opp.put(fieldName, fieldValue);
                            }
                        } else {
                            // Field not found in schema, use as-is
                            opp.put(fieldName, fieldValue);
                        }
                    }
                }

                opportunitiesToUpdate.add(opp);
            }

            if (!opportunitiesToUpdate.isEmpty()) {
                update opportunitiesToUpdate;
            }

            Map<String, Object> result = new Map<String, Object>();
            result.put('success', true);
            result.put('count', opportunitiesToUpdate.size());

            return result;
        } catch (AuraHandledException e) {
            // Re-throw AuraHandledExceptions as-is (these are our intentional user-facing errors)
            System.debug('AuraHandledException in updateOpportunities: ' + e.getMessage());
            throw e;
        } catch (Exception e) {
            // Catch unexpected exceptions and wrap them
            System.debug('Unexpected Exception in updateOpportunities: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred while updating opportunities. Please contact your administrator.');
        }
    }
}