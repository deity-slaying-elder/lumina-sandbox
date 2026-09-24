/**
 * Trigger action: copy the facility's program flags onto an eligible patient.
 *
 * Apex port of Patient_TF_On_Update_To_Program_Eligible_Update_Based_on_Facility.
 *
 * Flow behaviour, preserved exactly:
 *   entry - any of Payer_Eligibility_Status__c, Status__c, Initial_Visit_Date__c,
 *           Consent_Status__c changed
 *   gate  - Status = Active AND Payer_Eligibility_Status = Eligible AND
 *           Initial_Visit_Date populated AND Consent_Status in the four Approved values
 *   action - copy nine program checkboxes from the facility onto the patient:
 *           AHTH, APCM, BHI, CCM, COCM, PCM, RPM, TCM, Telepsych
 *
 * The program flags live on the facility and are cross-object reads, so they are
 * queried in bulk. A patient with no facility copies nothing, exactly as the flow's
 * null-reference reads resolved to blank and unchecked.
 *
 * Before-save; system mode - see PatientSetName for both rationales.
 *
 * Registered in Trigger_Action__mdt for Before Update on Patient__c.
 */
public without sharing class PatientSetProgramsOnEligible implements TriggerAction.BeforeUpdate {

    private static final Set<String> APPROVED_STATUSES = new Set<String>{
        'Approved', 'Approved - Verbal', 'Approved - NOK', 'Approved - NOK Verbal'
    };

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        List<Patient__c> newPatients = (List<Patient__c>) triggerNew;
        Map<Id, Patient__c> oldById = new Map<Id, Patient__c>((List<Patient__c>) triggerOld);

        Set<Id> facilityIds = new Set<Id>();
        List<Patient__c> qualifying = new List<Patient__c>();
        for (Patient__c patient : newPatients) {
            Patient__c prior = oldById.get(patient.Id);
            if (prior == null) {
                continue;
            }
            // Entry criteria: any of the four fields changed.
            Boolean entry = prior.Payer_Eligibility_Status__c != patient.Payer_Eligibility_Status__c
                || prior.Status__c != patient.Status__c
                || prior.Initial_Visit_Date__c != patient.Initial_Visit_Date__c
                || prior.Consent_Status__c != patient.Consent_Status__c;
            if (!entry) {
                continue;
            }
            // Gate.
            if (patient.Status__c != 'Active'
                || patient.Payer_Eligibility_Status__c != 'Eligible'
                || patient.Initial_Visit_Date__c == null
                || !APPROVED_STATUSES.contains(patient.Consent_Status__c)) {
                continue;
            }
            if (patient.Facility__c != null) {
                facilityIds.add(patient.Facility__c);
            }
            qualifying.add(patient);
        }
        if (qualifying.isEmpty()) {
            return;
        }

        Map<Id, Facility__c> facilities = new Map<Id, Facility__c>([
            SELECT AHTH__c, APCM__c, BHI__c, CCM__c, COCM__c, PCM__c, RPM__c, TCM__c, Telepsych__c
            FROM Facility__c WHERE Id IN :facilityIds
        ]);

        for (Patient__c patient : qualifying) {
            Facility__c facility = facilities.get(patient.Facility__c);
            if (facility == null) {
                continue;
            }
            patient.AHTH__c = facility.AHTH__c;
            patient.APCM__c = facility.APCM__c;
            patient.BHI__c = facility.BHI__c;
            patient.CCM__c = facility.CCM__c;
            patient.COCM__c = facility.COCM__c;
            patient.PCM__c = facility.PCM__c;
            patient.RPM__c = facility.RPM__c;
            patient.TCM__c = facility.TCM__c;
            patient.Telepsych__c = facility.Telepsych__c;
        }
    }
}
