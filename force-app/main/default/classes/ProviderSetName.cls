/**
 * Trigger action: set Provider Name as "Last, First", truncated to 80.
 *
 * Apex port of Provider_TF_On_Create_Create_Provider_Name:
 * left(Last_Name__c & ", " & First_Name__c, 80), on create only.
 *
 * Before-save; system mode - see PatientSetName for both rationales.
 *
 * Registered in Trigger_Action__mdt for Before Insert on Provider__c.
 */
public without sharing class ProviderSetName implements TriggerAction.BeforeInsert {

    public void beforeInsert(List<SObject> triggerNew) {
        for (Provider__c provider : (List<Provider__c>) triggerNew) {
            String name = (provider.Last_Name__c == null ? '' : provider.Last_Name__c)
                + ', '
                + (provider.First_Name__c == null ? '' : provider.First_Name__c);
            provider.Name = name.left(80);
        }
    }
}
