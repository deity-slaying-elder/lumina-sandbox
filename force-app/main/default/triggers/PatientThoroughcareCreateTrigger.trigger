trigger PatientThoroughcareCreateTrigger on Patient__c (after insert, after update) {
    Set<Id> facilityIds = new Set<Id>();
    for (Patient__c p : Trigger.new) {
        if (p.Facility__c != null) facilityIds.add(p.Facility__c);
    }

    Map<Id, Facility__c> facById = new Map<Id, Facility__c>();
    if (!facilityIds.isEmpty()) {
        facById = new Map<Id, Facility__c>([
            SELECT Id, ThoroughCare_Facility_Name__c
            FROM Facility__c
            WHERE Id IN :facilityIds
        ]);
    }

    List<Id> idsToSend = new List<Id>();
    for (Patient__c p : Trigger.new) {
        System.debug('Patient Id' + p.Id + ' triggered');

        if (p.Community_Status__c == 'Closed Won') {
            if (Trigger.isUpdate && (p.Date_Added_To_Community_Thoroughcare__c != NULL || p.Community_Thoroughcare_ID__c != NULL)) {
                System.debug(p.Id + ' patient is already in community thoroughcare');
                continue;
            }
            System.debug('Patient Id' + p.Id + ' is closed won');
            Boolean isWonDateAfter = p.Won_Date_Time__c >= DateTime.newInstanceGmt(2024, 10, 23, 0, 0, 0);
            if (isWonDateAfter) {
                System.debug('Patient Id' + p.Id + ' send');
                PatientThoroughcareCreateCallout.send(p.Id, true);
            }
        } else {
            if (Trigger.isUpdate && (p.Date_Added_To_Thoroughcare__c != NULL || p.Thoroughcare_ID__c != NULL)) {
                System.debug(p.Id + ' patient is already in thoroughcare');
                continue;
            }

            Boolean hasProgram = (p.BHI__c == true) || (p.RPM__c == true) || (p.CCM__c == true);
            Boolean payerEligible = p.Payer_Eligibility_Status__c == 'Eligible';
            Boolean consentOk = p.Consent_Status__c == 'Approved'
                            || p.Consent_Status__c == 'Approved - NOK'
                            || p.Consent_Status__c == 'Approved - Verbal';
            Boolean hasAnyExternalId = p.PCC_ID__c != null || p.PCC_Resident_Id__c != null || p.Matrix_Id__c != null;
            Boolean facilityHasName = p.Facility__c != null
                                && facById.containsKey(p.Facility__c)
                                && facById.get(p.Facility__c).ThoroughCare_Facility_Name__c != null;
            Boolean isnpIsNull = p.ISNP__c == null;

            System.debug(p.Id + ' hasProgram:' + String.valueOf(hasProgram) + ' payerEligible:' + String.valueOf(payerEligible) + ' consentOk:' + String.valueOf(consentOk) + ' hasAnyExternalId:' + String.valueOf(hasAnyExternalId) + ' facilityHasName:' + String.valueOf(facilityHasName) + 'isnpIsNull' + String.valueOf(isnpIsNull));
            if (hasProgram && payerEligible && consentOk && hasAnyExternalId && facilityHasName && isnpIsNull) {
                PatientThoroughcareCreateCallout.send(p.Id, false);
            }
        }
    }
}