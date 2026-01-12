public class EnvironmentMetadataSelector {
    
    /**
     * Retrieves a Custom Metadata record based on the current environment
     * @param metadataTypeName The API name of your Custom Metadata Type (e.g., 'My_Config__mdt')
     * @param productionRecordName The DeveloperName of the record to use in production
     * @param sandboxRecordName The DeveloperName of the record to use in sandbox
     * @return SObject The Custom Metadata record, or null if not found
     */
    public static SObject getMetadataByEnvironment(String metadataTypeName, 
                                                  String productionRecordName, 
                                                  String sandboxRecordName) {
        
        String recordName = isSandbox() ? sandboxRecordName : productionRecordName;
        
        // Build dynamic SOQL query
        String query = 'SELECT Id, DeveloperName, MasterLabel FROM ' + metadataTypeName + 
                      ' WHERE DeveloperName = :recordName LIMIT 1';
        
        try {
            List<SObject> results = Database.query(query);
            return results.isEmpty() ? null : results[0];
        } catch (Exception e) {
            System.debug('Error querying Custom Metadata: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Alternative method that returns all fields from the metadata record
     * @param metadataTypeName The API name of your Custom Metadata Type
     * @param productionRecordName The DeveloperName for production
     * @param sandboxRecordName The DeveloperName for sandbox
     * @param fieldsToSelect Comma-separated list of field API names to retrieve
     * @return SObject The Custom Metadata record with specified fields
     */
    public static SObject getMetadataWithFields(String metadataTypeName,
                                               String productionRecordName,
                                               String sandboxRecordName,
                                               String fieldsToSelect) {
        
        String recordName = isSandbox() ? sandboxRecordName : productionRecordName;
        
        // Build dynamic SOQL query with custom fields
        String query = 'SELECT ' + fieldsToSelect + ' FROM ' + metadataTypeName + 
                      ' WHERE DeveloperName = :recordName LIMIT 1';
        
        try {
            List<SObject> results = Database.query(query);
            return results.isEmpty() ? null : results[0];
        } catch (Exception e) {
            System.debug('Error querying Custom Metadata: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Determines if the current org is a sandbox
     * @return Boolean true if sandbox, false if production
     */
    public static Boolean isSandbox() {
        Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
        return org.IsSandbox;
    }
    
    public static SObject getConfig() {
        // Get metadata record based on environment
        SObject config = getMetadataByEnvironment('API_Configration__mdt', 
                                                  'Production_Config', 
                                                  'Sandbox_Config');
        
        if (config != null) {
            System.debug('Selected config: ' + config.get('DeveloperName'));
            System.debug('Environment: ' + (isSandbox() ? 'Sandbox' : 'Production'));
        }
        
        // Get metadata with specific fields
        SObject detailedConfig = getMetadataWithFields('API_Configration__mdt',
                                                      'Production_Config',
                                                      'Sandbox_Config',
                                                      'Id, DeveloperName, MasterLabel, BASE_URL__c, TC_API_KEY__c');
        
        if (detailedConfig != null) {
            System.debug('Endpoint: ' + detailedConfig.get('BASE_URL__c'));
            System.debug('API Key: ' + detailedConfig.get('TC_API_KEY__c'));
        }

        return detailedConfig;
    }
}