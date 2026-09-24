/**
 * Trigger action: keep Community Provider Name as "First Last", truncated to 80.
 *
 * Apex port of Community_Provider_TF_On_Create_Update_Name and
 * Community_Provider_TF_On_Update_Update_Name. Same formula in both:
 * left(First_Name__c & " " & Last_Name__c, 80); update fires when either name changed.
 *
 * Before-save; system mode - see PatientSetName for both rationales.
 *
 * Registered in Trigger_Action__mdt for Before Insert and Before Update on
 * Community_Provider__c.
 */
public without sharing class CommunityProviderSetName implements TriggerAction.BeforeInsert, TriggerAction.BeforeUpdate {

    public void beforeInsert(List<SObject> triggerNew) {
        for (Community_Provider__c provider : (List<Community_Provider__c>) triggerNew) {
            provider.Name = buildName(provider);
        }
    }

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        Map<Id, Community_Provider__c> oldById =
            new Map<Id, Community_Provider__c>((List<Community_Provider__c>) triggerOld);
        for (Community_Provider__c provider : (List<Community_Provider__c>) triggerNew) {
            Community_Provider__c prior = oldById.get(provider.Id);
            if (prior != null
                && prior.First_Name__c == provider.First_Name__c
                && prior.Last_Name__c == provider.Last_Name__c) {
                continue;
            }
            provider.Name = buildName(provider);
        }
    }

    private static String buildName(Community_Provider__c provider) {
        String name = (provider.First_Name__c == null ? '' : provider.First_Name__c)
            + ' '
            + (provider.Last_Name__c == null ? '' : provider.Last_Name__c);
        return name.left(80);
    }
}
