/**
 * Trigger action: set Community Episode Name as "CE - Patient - yyyy-MM-dd".
 *
 * Apex port of Community_Episode_TF_On_C_U_Update_Name, which was already before-save:
 * LEFT("CE - " & Patient__r.Name & " - " & TEXT(DATEVALUE(Admission_Discharge__r.Census_Date__c)), 80)
 * on create and update, no entry criteria.
 *
 * DATEVALUE on a Datetime converts in GMT, so formatGmt is used rather than
 * Datetime.date() - the user-zone version would name evening episodes with the wrong
 * day. A null census date contributes an empty string, as TEXT(null) did.
 *
 * System mode - see PatientSetName for the rationale.
 *
 * Registered in Trigger_Action__mdt for Before Insert and Before Update on
 * Community_Episode__c.
 */
public without sharing class CommunityEpisodeSetName implements TriggerAction.BeforeInsert, TriggerAction.BeforeUpdate {

    public void beforeInsert(List<SObject> triggerNew) {
        setNames((List<Community_Episode__c>) triggerNew);
    }

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        setNames((List<Community_Episode__c>) triggerNew);
    }

    private void setNames(List<Community_Episode__c> episodes) {
        Set<Id> patientIds = new Set<Id>();
        Set<Id> dischargeIds = new Set<Id>();
        for (Community_Episode__c episode : episodes) {
            if (episode.Patient__c != null) patientIds.add(episode.Patient__c);
            if (episode.Admission_Discharge__c != null) dischargeIds.add(episode.Admission_Discharge__c);
        }
        Map<Id, Patient__c> patients = new Map<Id, Patient__c>(
            [SELECT Name FROM Patient__c WHERE Id IN :patientIds]);
        Map<Id, Admission_Discharge__c> discharges = new Map<Id, Admission_Discharge__c>(
            [SELECT Census_Date__c FROM Admission_Discharge__c WHERE Id IN :dischargeIds]);

        for (Community_Episode__c episode : episodes) {
            String patientName = patients.containsKey(episode.Patient__c)
                ? patients.get(episode.Patient__c).Name : '';
            String censusDay = '';
            Admission_Discharge__c discharge = discharges.get(episode.Admission_Discharge__c);
            if (discharge != null && discharge.Census_Date__c != null) {
                censusDay = discharge.Census_Date__c.formatGmt('yyyy-MM-dd');
            }
            episode.Name = ('CE - ' + patientName + ' - ' + censusDay).left(80);
        }
    }
}
