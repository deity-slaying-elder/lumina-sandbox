trigger ThoroughcareTriggerController on Patient__c (after update) {
    
    for (Patient__c patient : Trigger.new) {
        // Check if Community_Status__c has changed and Community_Thoroughcare_ID__c is null
        if (patient.Community_Thoroughcare_ID__c == null && 
            patient.Community_Status__c != Trigger.oldMap.get(patient.Id).Community_Status__c && patient.Community_Status__c == 'Closed Won') {
            System.debug('Thoroughcare Trigger Triggered');
            // Call the future method asynchronously
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            // Check if the URL contains the word 'sandbox'
            Boolean isSandbox = baseUrl.contains('sandbox');
            
            // Output result (for example purposes)
            System.debug('Is this a sandbox environment? ' + isSandbox);
            ThoroughcareCreateController.sendPatientId(patient.Id, isSandbox);
        }
        else{
            System.debug('Thoroughcare Trigger Not Triggered');
        }
    }

}