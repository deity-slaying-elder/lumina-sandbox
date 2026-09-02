public with sharing class FacilityEditorController {

    @AuraEnabled
    public static Map<String, Object> getFacilitiesAndFields(Id accountId) {
        try {
            Map<String, Object> result = new Map<String, Object>();

            System.debug('Getting facilities for account: ' + accountId);

            // Validate that accountId is not null
            if (accountId == null) {
                throw new AuraHandledException('Account ID is null. Please ensure the component is placed on an Account record page.');
            }

            // Get field set fields from Facility_LWC field set on Facility__c
            List<Map<String, Object>> fieldSetFields = new List<Map<String, Object>>();
            Schema.FieldSet fieldSet = Schema.SObjectType.Facility__c.FieldSets.getMap().get('Facility_LWC');

            if (fieldSet == null) {
                throw new AuraHandledException('Field set "Facility_LWC" not found on Facility__c object.');
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

            // Build dynamic SOQL query for facilities
            Set<String> fieldPaths = new Set<String>{'Id', 'Name', 'Parent_Company__c'};

            // Add all field set fields to the query
            for (Map<String, Object> field : fieldSetFields) {
                String fieldPath = (String)field.get('fieldPath');
                fieldPaths.add(fieldPath);
            }

            String query = 'SELECT ' + String.join(new List<String>(fieldPaths), ', ') +
                          ' FROM Facility__c ' +
                          ' WHERE Parent_Company__c = :accountId ' +
                          ' ORDER BY Name';

            System.debug('Query: ' + query);
            System.debug('Account ID: ' + accountId);
            List<Facility__c> facilities = Database.query(query);
            System.debug('Found facilities: ' + facilities.size());

            if (facilities.isEmpty()) {
                throw new AuraHandledException('This account doesn\'t have any facilities to edit.');
            }

            // Build facility data with original values for change detection
            List<Map<String, Object>> facilitiesData = new List<Map<String, Object>>();

            for (Facility__c facility : facilities) {
                Map<String, Object> facilityData = new Map<String, Object>();
                facilityData.put('Id', facility.Id);
                facilityData.put('Name', facility.Name);

                // Add all field values
                for (Map<String, Object> field : fieldSetFields) {
                    String fieldPath = (String)field.get('fieldPath');
                    facilityData.put(fieldPath, facility.get(fieldPath));
                }

                facilitiesData.add(facilityData);
            }

            result.put('facilities', facilitiesData);
            result.put('fields', fieldSetFields);
            result.put('totalFacilityCount', facilities.size());

            System.debug('Returning result with ' + facilitiesData.size() + ' facilities');

            return result;
        } catch (AuraHandledException e) {
            System.debug('AuraHandledException in getFacilitiesAndFields: ' + e.getMessage());
            throw e;
        } catch (Exception e) {
            System.debug('Unexpected Exception in getFacilitiesAndFields: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred while loading facilities. Please contact your administrator.');
        }
    }

    @AuraEnabled
    public static Map<String, Object> updateFacilities(String facilitiesJson) {
        try {
            List<Object> facilitiesData = (List<Object>) JSON.deserializeUntyped(facilitiesJson);
            List<Facility__c> facilitiesToUpdate = new List<Facility__c>();

            // Get field type information for proper conversion
            Map<String, Schema.SObjectField> facilityFields = Schema.SObjectType.Facility__c.fields.getMap();

            for (Object facData : facilitiesData) {
                Map<String, Object> facMap = (Map<String, Object>) facData;

                Facility__c facility = new Facility__c();
                facility.Id = (String) facMap.get('Id');

                // Get the fields map
                Map<String, Object> fieldsMap = (Map<String, Object>) facMap.get('fields');

                // Dynamically set fields with proper type conversion
                for (String fieldName : fieldsMap.keySet()) {
                    Object fieldValue = fieldsMap.get(fieldName);
                    // Get field type to handle conversion (field map keys are lowercase)
                    Schema.SObjectField fieldToken = facilityFields.get(fieldName.toLowerCase());
                    if (fieldToken != null) {
                        Schema.DisplayType fieldType = fieldToken.getDescribe().getType();

                        // Convert based on field type
                        if (fieldType == Schema.DisplayType.BOOLEAN) {
                            if (fieldValue == null) {
                                facility.put(fieldName, false);
                            } else if (fieldValue instanceof String) {
                                facility.put(fieldName, Boolean.valueOf((String) fieldValue));
                            } else {
                                facility.put(fieldName, fieldValue);
                            }
                        } else if (fieldType == Schema.DisplayType.DATE) {
                            // Handle Date field conversion
                            if (fieldValue == null || (fieldValue instanceof String && String.isBlank((String) fieldValue))) {
                                facility.put(fieldName, null);
                            } else if (fieldValue instanceof String) {
                                facility.put(fieldName, Date.valueOf((String) fieldValue));
                            }
                        } else {
                            if (fieldValue != null) {
                                facility.put(fieldName, fieldValue);
                            }
                        }
                    } else {
                        if (fieldValue != null) {
                            facility.put(fieldName, fieldValue);
                        }
                    }
                }

                facilitiesToUpdate.add(facility);
            }

            if (!facilitiesToUpdate.isEmpty()) {
                // Use Security.stripInaccessible to enforce FLS before DML
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    facilitiesToUpdate
                );
                update decision.getRecords();
            }

            Map<String, Object> result = new Map<String, Object>();
            result.put('success', true);
            result.put('count', facilitiesToUpdate.size());

            return result;
        } catch (AuraHandledException e) {
            System.debug('AuraHandledException in updateFacilities: ' + e.getMessage());
            throw e;
        } catch (Exception e) {
            System.debug('Unexpected Exception in updateFacilities: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred while updating facilities. Please contact your administrator.');
        }
    }
}