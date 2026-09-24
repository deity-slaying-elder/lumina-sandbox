/**
 * End-to-end through DML for the seven naming actions. The flows they replace are
 * deactivated in this sandbox, so every Name below is written by Apex or not at all.
 */
@isTest
private class RecordNamingTest {

    @isTest
    static void patientNameOnInsertAndUpdate() {
        Patient__c patient = new Patient__c(First_Name__c = 'Ada', Last_Name__c = 'Lovelace', Status__c = 'Active');
        insert patient;
        Assert.areEqual('Ada Lovelace', [SELECT Name FROM Patient__c WHERE Id = :patient.Id].Name,
            'Insert should compose First Last');

        patient.Last_Name__c = 'Byron';
        update patient;
        Assert.areEqual('Ada Byron', [SELECT Name FROM Patient__c WHERE Id = :patient.Id].Name,
            'A name change should recompose');
    }

    @isTest
    static void patientNameTruncatesAtEightyAndNeverThrows() {
        // The old duplicate pair disagreed here: one flow truncated, one threw
        // STRING_TOO_LONG. The surviving behaviour is the truncation.
        String longFirst = 'F'.repeat(60);
        String longLast = 'L'.repeat(60);
        Patient__c patient = new Patient__c(First_Name__c = longFirst, Last_Name__c = longLast, Status__c = 'Active');
        insert patient;
        String name = [SELECT Name FROM Patient__c WHERE Id = :patient.Id].Name;
        Assert.areEqual(80, name.length(), 'Name must be truncated to 80');
        Assert.areEqual((longFirst + ' ' + longLast).left(80), name, 'LEFT(...,80) semantics');
    }

    @isTest
    static void patientUnrelatedUpdateLeavesNameAlone() {
        Patient__c patient = new Patient__c(First_Name__c = 'Keep', Last_Name__c = 'Name', Status__c = 'Active');
        insert patient;
        // A manual rename survives updates that do not touch first or last name,
        // because the flow's entry criteria required a name-field change.
        patient.Name = 'Hand Edited';
        patient.First_Name__c = 'Keep';
        update patient;
        Assert.areEqual('Hand Edited', [SELECT Name FROM Patient__c WHERE Id = :patient.Id].Name,
            'No name-field change means no recompute');
    }

    @isTest
    static void communityProviderAndProviderNames() {
        Community_Provider__c cp = new Community_Provider__c(First_Name__c = 'Grace', Last_Name__c = 'Hopper');
        insert cp;
        Assert.areEqual('Grace Hopper', [SELECT Name FROM Community_Provider__c WHERE Id = :cp.Id].Name);
        cp.First_Name__c = 'G';
        update cp;
        Assert.areEqual('G Hopper', [SELECT Name FROM Community_Provider__c WHERE Id = :cp.Id].Name);

        Provider__c provider = new Provider__c(First_Name__c = 'Grace', Last_Name__c = 'Hopper');
        insert provider;
        Assert.areEqual('Hopper, Grace', [SELECT Name FROM Provider__c WHERE Id = :provider.Id].Name,
            'Provider uses Last, First');
    }

    @isTest
    static void patientInsuranceName() {
        Patient__c patient = new Patient__c(First_Name__c = 'Pat', Last_Name__c = 'Ins', Status__c = 'Active');
        insert patient;
        Insurance__c insurance = new Insurance__c(Name = 'Acme Health');
        insert insurance;
        Patient_Insurance__c record = new Patient_Insurance__c(Patient__c = patient.Id, Insurance__c = insurance.Id);
        insert record;
        Assert.areEqual('Pat Ins - Acme Health',
            [SELECT Name FROM Patient_Insurance__c WHERE Id = :record.Id].Name);
    }

    @isTest
    static void reportUserFacilityAndRegionNames() {
        Account account = new Account(Name = 'Rita Employer');
        insert account;
        Report_User__c reportUser = new Report_User__c(Name = 'Reporting Rita');
        insert reportUser;
        Facility__c facility = new Facility__c(Name = 'Sunny Acres');
        insert facility;
        // Region__c requires an Account.
        Region__c region = new Region__c(Name = 'North East', Account__c = account.Id);
        insert region;

        Report_User_Facility__c ruf = new Report_User_Facility__c(
            Report_User__c = reportUser.Id, Facility__c = facility.Id);
        insert ruf;
        Assert.areEqual('Reporting Rita - Sunny Acres',
            [SELECT Name FROM Report_User_Facility__c WHERE Id = :ruf.Id].Name);

        Report_User_Region__c rur = new Report_User_Region__c(
            Report_User__c = reportUser.Id, Region__c = region.Id);
        insert rur;
        Assert.areEqual('Reporting Rita - North East',
            [SELECT Name FROM Report_User_Region__c WHERE Id = :rur.Id].Name);

        // The flow recomputed on EVERY update, entry criteria none. A hand-edit is
        // overwritten on the next save - preserved behaviour.
        rur.Name = 'Hand Edit';
        update rur;
        Assert.areEqual('Reporting Rita - North East',
            [SELECT Name FROM Report_User_Region__c WHERE Id = :rur.Id].Name,
            'Recompute on every update, as the flow did');
    }

    @isTest
    static void communityEpisodeNameUsesGmtDay() {
        Patient__c patient = new Patient__c(First_Name__c = 'Epi', Last_Name__c = 'Sode', Status__c = 'Active');
        insert patient;
        // 23:30 New York on 20 Aug is 03:30 GMT on 21 Aug. DATEVALUE works in GMT, so
        // the flow named this episode with the 21st. The port must match.
        Datetime census = Datetime.newInstanceGmt(2026, 8, 21, 3, 30, 0);
        Admission_Discharge__c discharge = new Admission_Discharge__c(
            Patient__c = patient.Id, Type__c = 'Admission', Census_Date__c = census);
        insert discharge;
        Community_Episode__c episode = new Community_Episode__c(
            Patient__c = patient.Id, Admission_Discharge__c = discharge.Id);
        insert episode;
        Assert.areEqual('CE - Epi Sode - 2026-08-21',
            [SELECT Name FROM Community_Episode__c WHERE Id = :episode.Id].Name,
            'The GMT day, exactly as DATEVALUE computed it');
    }

    @isTest
    static void communityEpisodeNameWithNoDischarge() {
        Patient__c patient = new Patient__c(First_Name__c = 'No', Last_Name__c = 'Census', Status__c = 'Active');
        insert patient;
        Community_Episode__c episode = new Community_Episode__c(Patient__c = patient.Id);
        insert episode;
        // Salesforce trims the trailing space on save, for the flow exactly as for Apex.
        Assert.areEqual('CE - No Census -',
            [SELECT Name FROM Community_Episode__c WHERE Id = :episode.Id].Name,
            'TEXT(DATEVALUE(null)) contributed an empty string in the flow');
    }

    @isTest
    static void bulkNamingStaysFlat() {
        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < 200; i++) {
            patients.add(new Patient__c(First_Name__c = 'Bulk', Last_Name__c = 'Name' + i, Status__c = 'Active'));
        }
        Test.startTest();
        insert patients;
        Test.stopTest();
        Assert.areEqual(200, [SELECT COUNT() FROM Patient__c WHERE Name LIKE 'Bulk Name%'],
            'All 200 names composed in one save');
    }
}
