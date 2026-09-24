/**
 * Trigger action: fill a blank patient state from the facility on Closed Won.
 *
 * Apex port of Patient_TF_On_Update_Community_Status_Closed_Won_Check_State.
 *
 * Flow behaviour, preserved exactly:
 *   entry - Community_Status__c changed AND now 'Closed Won' AND the patient's
 *           Address state code is blank
 *   action - Address__StateCode__s = the facility's state code
 *
 * The flow read Patient__c.Facility_State__c, which is the formula
 * TEXT(Facility__r.Address__StateCode__s). Formula values are stale in a before-save
 * trigger, so this reads the facility's state code directly through the lookup - the
 * same value one hop shorter.
 *
 * Before-save; system mode - see PatientSetName for both rationales.
 *
 * Registered in Trigger_Action__mdt for Before Update on Patient__c.
 */
public without sharing class PatientSetStateOnClosedWon implements TriggerAction.BeforeUpdate {

    private static final String STATUS_CLOSED_WON = 'Closed Won';

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        List<Patient__c> newPatients = (List<Patient__c>) triggerNew;
        Map<Id, Patient__c> oldById = new Map<Id, Patient__c>((List<Patient__c>) triggerOld);

        Set<Id> facilityIds = new Set<Id>();
        List<Patient__c> qualifying = new List<Patient__c>();
        for (Patient__c patient : newPatients) {
            Patient__c prior = oldById.get(patient.Id);
            if (prior == null || prior.Community_Status__c == patient.Community_Status__c) {
                continue;
            }
            if (patient.Community_Status__c != STATUS_CLOSED_WON) {
                continue;
            }
            if (String.isNotBlank((String) patient.get('Address__StateCode__s'))) {
                continue;
            }
            if (patient.Facility__c != null) {
                facilityIds.add(patient.Facility__c);
                qualifying.add(patient);
            }
        }
        if (qualifying.isEmpty()) {
            return;
        }

        Map<Id, Facility__c> facilities = new Map<Id, Facility__c>([
            SELECT Id, Address__StateCode__s FROM Facility__c WHERE Id IN :facilityIds
        ]);

        for (Patient__c patient : qualifying) {
            Facility__c facility = facilities.get(patient.Facility__c);
            if (facility != null && String.isNotBlank((String) facility.get('Address__StateCode__s'))) {
                patient.put('Address__StateCode__s', facility.get('Address__StateCode__s'));
            }
        }
    }
}
