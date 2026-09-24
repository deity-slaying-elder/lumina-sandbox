/**
 * Trigger action: set Report User Facility Name as "ReportUser - Facility".
 *
 * Apex port of Report_User_Facility_TF_on_C_U_Update_Name:
 * LEFT(Report_User__r.Name, 47) & " - " & LEFT(Facility__r.Name, 30).
 * No entry criteria in the flow - it recomputed on every create AND every update -
 * and the truncation is per-part (47 + 3 + 30 = 80), not on the whole.
 *
 * Before-save; system mode - see PatientSetName for both rationales.
 *
 * Registered in Trigger_Action__mdt for Before Insert and Before Update on
 * Report_User_Facility__c.
 */
public without sharing class ReportUserFacilitySetName implements TriggerAction.BeforeInsert, TriggerAction.BeforeUpdate {

    public void beforeInsert(List<SObject> triggerNew) {
        setNames((List<Report_User_Facility__c>) triggerNew);
    }

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        setNames((List<Report_User_Facility__c>) triggerNew);
    }

    private void setNames(List<Report_User_Facility__c> records) {
        Set<Id> userIds = new Set<Id>();
        Set<Id> facilityIds = new Set<Id>();
        for (Report_User_Facility__c record : records) {
            if (record.Report_User__c != null) userIds.add(record.Report_User__c);
            if (record.Facility__c != null) facilityIds.add(record.Facility__c);
        }
        Map<Id, Report_User__c> users = new Map<Id, Report_User__c>(
            [SELECT Name FROM Report_User__c WHERE Id IN :userIds]);
        Map<Id, Facility__c> facilities = new Map<Id, Facility__c>(
            [SELECT Name FROM Facility__c WHERE Id IN :facilityIds]);

        for (Report_User_Facility__c record : records) {
            String userName = users.containsKey(record.Report_User__c)
                ? users.get(record.Report_User__c).Name : '';
            String facilityName = facilities.containsKey(record.Facility__c)
                ? facilities.get(record.Facility__c).Name : '';
            record.Name = userName.left(47) + ' - ' + facilityName.left(30);
        }
    }
}
