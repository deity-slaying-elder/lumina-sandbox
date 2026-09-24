/**
 * End-to-end through DML for the consent, program and state actions. The flows they
 * replace are deactivated in this sandbox.
 */
@isTest
private class PatientLifecycleFieldsTest {

    private static Patient__c freshPatient(String lastName) {
        Patient__c patient = new Patient__c(
            First_Name__c = 'Cycle', Last_Name__c = lastName, Status__c = 'Active');
        insert patient;
        return patient;
    }

    private static Patient__c reload(Id patientId) {
        return [SELECT Consent_Status__c, Consent_Datetime__c, Community_Status__c,
                       TCM__c, CCM__c, RPM__c, Facility__c
                FROM Patient__c WHERE Id = :patientId];
    }

    // ---------- Consent, branch B: first real status stamps ----------

    @isTest
    static void firstRealConsentStatusStampsDatetime() {
        Patient__c patient = freshPatient('ConsentB');
        update new Patient__c(Id = patient.Id, Consent_Status__c = 'Approved');
        Assert.areNotEqual(null, reload(patient.Id).Consent_Datetime__c,
            'A first real status stamps the datetime');
    }

    @isTest
    static void pendingConsentDoesNotStamp() {
        Patient__c patient = freshPatient('ConsentP');
        update new Patient__c(Id = patient.Id, Consent_Status__c = 'Pending');
        Assert.areEqual(null, reload(patient.Id).Consent_Datetime__c,
            'Pending is excluded by the flow');
    }

    @isTest
    static void existingDatetimeIsNotRestamped() {
        Patient__c patient = freshPatient('ConsentE');
        Datetime original = Datetime.newInstanceGmt(2026, 1, 1, 12, 0, 0);
        update new Patient__c(Id = patient.Id, Consent_Datetime__c = original);
        update new Patient__c(Id = patient.Id, Consent_Status__c = 'Approved');
        Assert.areEqual(original, reload(patient.Id).Consent_Datetime__c,
            'An existing datetime blocks branch B');
    }

    // ---------- Consent, branch A: clearing the status stamps ----------

    @isTest
    static void clearingConsentStatusStampsDatetime() {
        Patient__c patient = freshPatient('ConsentA');
        update new Patient__c(Id = patient.Id, Consent_Status__c = 'Denied');
        Datetime afterSet = reload(patient.Id).Consent_Datetime__c;

        update new Patient__c(Id = patient.Id, Consent_Status__c = null);
        Assert.areNotEqual(null, reload(patient.Id).Consent_Datetime__c,
            'Clearing the status stamps - odd, but it is what the flow did');
    }

    // ---------- Programs on eligible ----------

    private static Facility__c programFacility() {
        Facility__c facility = new Facility__c(Name = 'Program Facility',
            TCM__c = true, CCM__c = true, RPM__c = false);
        insert facility;
        return facility;
    }

    @isTest
    static void fullyEligiblePatientCopiesFacilityPrograms() {
        Facility__c facility = programFacility();
        Patient__c patient = new Patient__c(
            First_Name__c = 'Cycle', Last_Name__c = 'Programs', Status__c = 'Active',
            Facility__c = facility.Id,
            Initial_Visit_Date__c = Date.today(),
            Consent_Status__c = 'Approved');
        insert patient;

        update new Patient__c(Id = patient.Id, Payer_Eligibility_Status__c = 'Eligible');

        Patient__c after = reload(patient.Id);
        Assert.areEqual(true, after.TCM__c, 'TCM flag copied from the facility');
        Assert.areEqual(true, after.CCM__c, 'CCM flag copied from the facility');
        Assert.areEqual(false, after.RPM__c, 'An unchecked facility flag copies as unchecked');
    }

    @isTest
    static void ineligiblePatientCopiesNothing() {
        Facility__c facility = programFacility();
        Patient__c patient = new Patient__c(
            First_Name__c = 'Cycle', Last_Name__c = 'NotYet', Status__c = 'Active',
            Facility__c = facility.Id,
            Initial_Visit_Date__c = Date.today(),
            Consent_Status__c = 'Pending');
        insert patient;

        update new Patient__c(Id = patient.Id, Payer_Eligibility_Status__c = 'Eligible');

        Assert.areEqual(false, reload(patient.Id).TCM__c,
            'Pending consent fails the gate, nothing copies');
    }

    // ---------- State on Closed Won ----------

    @isTest
    static void closedWonFillsBlankStateFromFacility() {
        Facility__c facility = new Facility__c(Name = 'State Facility');
        facility.put('Address__StateCode__s', 'NJ');
        facility.put('Address__CountryCode__s', 'US');
        insert facility;
        Patient__c patient = new Patient__c(
            First_Name__c = 'Cycle', Last_Name__c = 'ClosedWon', Status__c = 'Active',
            Facility__c = facility.Id,
            Date_of_Birth__c = Date.newInstance(1950, 1, 1), Gender__c = 'Female');
        insert patient;

        update new Patient__c(Id = patient.Id, Community_Status__c = 'Closed Won');

        Patient__c filled = [SELECT Address__StateCode__s FROM Patient__c WHERE Id = :patient.Id];
        Assert.areEqual('NJ', (String) filled.get('Address__StateCode__s'),
            'A blank patient state is filled from the facility on Closed Won');
    }

    @isTest
    static void closedWonKeepsAnExistingState() {
        Facility__c facility = new Facility__c(Name = 'State Facility 2');
        facility.put('Address__StateCode__s', 'NJ');
        facility.put('Address__CountryCode__s', 'US');
        insert facility;
        Patient__c patient = new Patient__c(
            First_Name__c = 'Cycle', Last_Name__c = 'KeepState', Status__c = 'Active',
            Facility__c = facility.Id,
            Date_of_Birth__c = Date.newInstance(1950, 1, 1), Gender__c = 'Female');
        patient.put('Address__StateCode__s', 'PA');
        patient.put('Address__CountryCode__s', 'US');
        insert patient;

        update new Patient__c(Id = patient.Id, Community_Status__c = 'Closed Won');

        Patient__c kept = [SELECT Address__StateCode__s FROM Patient__c WHERE Id = :patient.Id];
        Assert.areEqual('PA', (String) kept.get('Address__StateCode__s'),
            'An existing state is never overwritten');
    }
}
