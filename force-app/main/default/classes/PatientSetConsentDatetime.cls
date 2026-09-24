/**
 * Trigger action: stamp Consent_Datetime__c when consent status moves.
 *
 * Apex port of TWO flows whose undefined mutual order prompted this conversion:
 *   Patient_TF_On_Update_Of_Consent_Set_DateTime
 *     - fires when Consent_Status__c CHANGED and is now BLANK. Yes, it stamps the
 *       consent timestamp when consent is cleared. Odd, but that is what it does in
 *       production and it is preserved as branch A.
 *   Patient_TF_On_update_of_consent_status_update_consent_datetime
 *     - fires when a real status (non-blank, not 'Pending') is present, no datetime
 *       exists yet, and the record newly meets those criteria. Branch B.
 *
 * The ordering worry turned out to be moot: branch A requires a blank status and
 * branch B a populated one, so they cannot both fire on the same save. Converting
 * them into one action closes the question permanently regardless.
 *
 * Before-save; system mode - see PatientSetName for both rationales.
 *
 * Registered in Trigger_Action__mdt for Before Update on Patient__c.
 */
public without sharing class PatientSetConsentDatetime implements TriggerAction.BeforeUpdate {

    private static final String STATUS_PENDING = 'Pending';

    public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        Map<Id, Patient__c> oldById = new Map<Id, Patient__c>((List<Patient__c>) triggerOld);
        Datetime now = Datetime.now();

        for (Patient__c patient : (List<Patient__c>) triggerNew) {
            Patient__c prior = oldById.get(patient.Id);
            if (prior == null) {
                continue;
            }

            // Branch A: status changed to blank.
            Boolean statusChanged = prior.Consent_Status__c != patient.Consent_Status__c;
            if (statusChanged && String.isBlank(patient.Consent_Status__c)) {
                patient.Consent_Datetime__c = now;
                continue;
            }

            // Branch B: a real status, no datetime yet, and the criteria are NEWLY met
            // (the flow set doesRequireRecordChangedToMeetCriteria).
            Boolean matchesNow = String.isNotBlank(patient.Consent_Status__c)
                && patient.Consent_Status__c != STATUS_PENDING
                && patient.Consent_Datetime__c == null;
            Boolean matchedBefore = String.isNotBlank(prior.Consent_Status__c)
                && prior.Consent_Status__c != STATUS_PENDING
                && prior.Consent_Datetime__c == null;
            if (matchesNow && !matchedBefore) {
                patient.Consent_Datetime__c = now;
            }
        }
    }
}
