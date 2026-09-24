/**
 * Trigger action: set Report User Region Name as "ReportUser - Region".
 *
 * Apex port of Report_User_Region_TF_On_C_U_Update_Name:
 * LEFT(Report_User__r.Name, 47) & " - " & LEFT(Region__r.Name, 30).
 * Same shape as ReportUserFacilitySetName: no entry criteria, per-part truncation.
 *
 * Before-save; system mode - see PatientSetName for both rationales.
 *
 * Registered in Trigger_Action__mdt for Before Insert and Before Update on
 * Report_User_Region__c.
 */
public without sharing class ReportUserRegionSetName implements TriggerAction.BeforeInsert, TriggerAction.BeforeUpdate {

    public void beforeInsert(List<SObject> triggerNew) {
        setNames((List<Report_User_Region__c>) triggerNew);
    }

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        setNames((List<Report_User_Region__c>) triggerNew);
    }

    private void setNames(List<Report_User_Region__c> records) {
        Set<Id> userIds = new Set<Id>();
        Set<Id> regionIds = new Set<Id>();
        for (Report_User_Region__c record : records) {
            if (record.Report_User__c != null) userIds.add(record.Report_User__c);
            if (record.Region__c != null) regionIds.add(record.Region__c);
        }
        Map<Id, Report_User__c> users = new Map<Id, Report_User__c>(
            [SELECT Name FROM Report_User__c WHERE Id IN :userIds]);
        Map<Id, Region__c> regions = new Map<Id, Region__c>(
            [SELECT Name FROM Region__c WHERE Id IN :regionIds]);

        for (Report_User_Region__c record : records) {
            String userName = users.containsKey(record.Report_User__c)
                ? users.get(record.Report_User__c).Name : '';
            String regionName = regions.containsKey(record.Region__c)
                ? regions.get(record.Region__c).Name : '';
            record.Name = userName.left(47) + ' - ' + regionName.left(30);
        }
    }
}
