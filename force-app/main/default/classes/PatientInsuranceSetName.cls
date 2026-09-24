/**
 * Trigger action: set Patient Insurance Name as "Patient - Insurance", truncated to 80.
 *
 * Apex port of Patient_Insurance_TF_On_Create_Update_Name:
 * LEFT(Patient__r.Name & " - " & Insurance__r.Name, 80), on create only.
 *
 * The two parent names are cross-object reads, not on the trigger record, so they are
 * queried in bulk. A missing parent contributes an empty string, exactly as the
 * formula's null handling did.
 *
 * Before-save; system mode - see PatientSetName for both rationales.
 *
 * Registered in Trigger_Action__mdt for Before Insert on Patient_Insurance__c.
 */
public without sharing class PatientInsuranceSetName implements TriggerAction.BeforeInsert {

    public void beforeInsert(List<SObject> triggerNew) {
        List<Patient_Insurance__c> records = (List<Patient_Insurance__c>) triggerNew;

        Set<Id> patientIds = new Set<Id>();
        Set<Id> insuranceIds = new Set<Id>();
        for (Patient_Insurance__c record : records) {
            if (record.Patient__c != null) patientIds.add(record.Patient__c);
            if (record.Insurance__c != null) insuranceIds.add(record.Insurance__c);
        }
        Map<Id, Patient__c> patients = new Map<Id, Patient__c>(
            [SELECT Name FROM Patient__c WHERE Id IN :patientIds]);
        Map<Id, Insurance__c> insurances = new Map<Id, Insurance__c>(
            [SELECT Name FROM Insurance__c WHERE Id IN :insuranceIds]);

        for (Patient_Insurance__c record : records) {
            String patientName = patients.containsKey(record.Patient__c)
                ? patients.get(record.Patient__c).Name : '';
            String insuranceName = insurances.containsKey(record.Insurance__c)
                ? insurances.get(record.Insurance__c).Name : '';
            record.Name = (patientName + ' - ' + insuranceName).left(80);
        }
    }
}
