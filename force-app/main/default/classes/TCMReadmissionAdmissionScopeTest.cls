/**
 * The shared clinical scope: which admissions count, and how the required patient class is
 * matched against a comma separated list.
 */
@IsTest
private class TCMReadmissionAdmissionScopeTest {

    private static final String TZ = 'America/New_York';

    private static TCMReportConfig config(String requiredClass) {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Business_Timezone__c = TZ,
            Required_Patient_Class__c = requiredClass
        );
        return new TCMReportConfig();
    }

    /** One facility, one patient, and an admission per patient class we have seen in the org. */
    private static Id stage(List<String> patientClasses) {
        Account parent = new Account(Name = 'Scope Parent', TCM__c = true);
        insert parent;
        Facility__c facility = new Facility__c(
            Name = 'Scope SNF', Parent_Company__c = parent.Id, TCM__c = true,
            Admin_Email__c = 'admin@scope.example', Exclude_from_TCM_Reporting__c = false
        );
        insert facility;
        Patient__c patient = new Patient__c(
            First_Name__c = 'Pat', Last_Name__c = 'Sample', Status__c = 'Inactive',
            Facility__c = facility.Id, Hospice__c = false
        );
        insert patient;

        Datetime inWindow = new TCMReadmissionWindow(TZ).startUtc.addHours(2);
        List<Hospital_Admission__c> admissions = new List<Hospital_Admission__c>();
        for (String patientClass : patientClasses) {
            admissions.add(new Hospital_Admission__c(
                Patient__c = patient.Id, Facility__c = 'Mercy General',
                Admit_DateTime__c = inWindow, Was_Discharged_Home_From_SNF__c = true,
                Patient_Class__c = patientClass
            ));
        }
        insert admissions;
        return facility.Id;
    }

    private static List<Hospital_Admission__c> find(Id facilityId, TCMReportConfig cfg) {
        TCMReadmissionWindow w = new TCMReadmissionWindow(TZ);
        return TCMReadmissionAdmissionScope.find(facilityId, w.startUtc, w.endUtc, cfg);
    }

    /** The real values this org holds, from production: a comma separated list, sometimes blank. */
    private static List<String> realClasses() {
        return new List<String>{
            'Emergency',
            'Emergency, Inpatient',
            'Inpatient',
            'Emergency, Observation, Inpatient',
            'Emergency, Observation',
            'Observation',
            'Observation, Inpatient',
            null
        };
    }

    @IsTest
    static void inpatientMatchesAnywhereInTheList() {
        Id facilityId = stage(realClasses());

        Test.startTest();
        List<Hospital_Admission__c> rows = find(facilityId, config('Inpatient'));
        Test.stopTest();

        Set<String> kept = new Set<String>();
        for (Hospital_Admission__c row : [
            SELECT Patient_Class__c FROM Hospital_Admission__c WHERE Id IN :rows
        ]) {
            kept.add(row.Patient_Class__c);
        }
        System.assertEquals(
            new Set<String>{
                'Emergency, Inpatient', 'Inpatient',
                'Emergency, Observation, Inpatient', 'Observation, Inpatient'
            },
            kept,
            'every list containing Inpatient is kept, whatever its position'
        );
        System.assertEquals(4, rows.size());
    }

    @IsTest
    static void aRowWithNoPatientClassIsLeftOut() {
        Id facilityId = stage(new List<String>{ null, 'Inpatient' });

        List<Hospital_Admission__c> rows = find(facilityId, config('Inpatient'));

        System.assertEquals(1, rows.size(), 'blank does not contain Inpatient');
    }

    @IsTest
    static void blankConfigKeepsEveryClassIncludingBlank() {
        Id facilityId = stage(realClasses());

        Test.startTest();
        System.assertEquals(8, find(facilityId, config(null)).size(), 'null config, no filter');
        System.assertEquals(8, find(facilityId, config('   ')).size(), 'blank config, no filter');
        Test.stopTest();
    }

    @IsTest
    static void observationCanBeRequiredInstead() {
        Id facilityId = stage(realClasses());

        System.assertEquals(
            4, find(facilityId, config('Observation')).size(),
            'the required class is configuration, not a constant in the code'
        );
    }

    @IsTest
    static void outpatientWouldNotBeMistakenForInpatient() {
        Id facilityId = stage(new List<String>{ 'Outpatient', 'Emergency, Outpatient', 'Inpatient' });

        List<Hospital_Admission__c> rows = find(facilityId, config('Inpatient'));

        System.assertEquals(
            1, rows.size(),
            'Outpatient does not contain the letters of Inpatient, so a contains match is safe here'
        );
    }

    @IsTest
    static void theOtherClinicalRulesStillApply() {
        Account parent = new Account(Name = 'Scope Parent', TCM__c = true);
        insert parent;
        Facility__c facility = new Facility__c(
            Name = 'Scope SNF', Parent_Company__c = parent.Id, TCM__c = true,
            Admin_Email__c = 'admin@scope.example', Exclude_from_TCM_Reporting__c = false
        );
        insert facility;
        Patient__c well = new Patient__c(
            First_Name__c = 'Pat', Last_Name__c = 'Sample', Status__c = 'Inactive',
            Facility__c = facility.Id, Hospice__c = false
        );
        Patient__c hospice = new Patient__c(
            First_Name__c = 'Hal', Last_Name__c = 'Grant', Status__c = 'Inactive',
            Facility__c = facility.Id, Hospice__c = true
        );
        insert new List<Patient__c>{ well, hospice };

        TCMReadmissionWindow w = new TCMReadmissionWindow(TZ);
        insert new List<Hospital_Admission__c>{
            // Kept.
            new Hospital_Admission__c(Patient__c = well.Id, Facility__c = 'Mercy',
                Admit_DateTime__c = w.startUtc.addHours(2),
                Was_Discharged_Home_From_SNF__c = true,
                Patient_Class__c = 'Inpatient'),
            // Not a discharge home from the facility.
            new Hospital_Admission__c(Patient__c = well.Id, Facility__c = 'Mercy',
                Admit_DateTime__c = w.startUtc.addHours(3),
                Was_Discharged_Home_From_SNF__c = false,
                Patient_Class__c = 'Inpatient'),
            // Hospice.
            new Hospital_Admission__c(Patient__c = hospice.Id, Facility__c = 'Mercy',
                Admit_DateTime__c = w.startUtc.addHours(2),
                Was_Discharged_Home_From_SNF__c = true,
                Patient_Class__c = 'Inpatient'),
            // Before the window.
            new Hospital_Admission__c(Patient__c = well.Id, Facility__c = 'Mercy',
                Admit_DateTime__c = w.startUtc.addDays(-5),
                Was_Discharged_Home_From_SNF__c = true,
                Patient_Class__c = 'Inpatient'),
            // The window end is exclusive.
            new Hospital_Admission__c(Patient__c = well.Id, Facility__c = 'Mercy',
                Admit_DateTime__c = w.endUtc,
                Was_Discharged_Home_From_SNF__c = true,
                Patient_Class__c = 'Inpatient')
        };

        System.assertEquals(
            1, find(facility.Id, config('Inpatient')).size(),
            'the patient class filter is added to the existing rules, not a replacement for them'
        );
    }

    @IsTest
    static void aSetOfFacilitiesUsesInAndAnIdUsesEquals() {
        TCMReportConfig cfg = config('Inpatient');

        String many = TCMReadmissionAdmissionScope.soql(true, cfg);
        String one = TCMReadmissionAdmissionScope.soql(false, cfg);

        System.assert(many.contains('Patient__r.Facility__c IN :facilityScope'), many);
        System.assert(one.contains('Patient__r.Facility__c = :facilityScope'), one);
        for (String query : new List<String>{ many, one }) {
            System.assert(query.contains('LIKE :patientClassPattern'), query);
            System.assert(query.contains('Was_Discharged_Home_From_SNF__c = true'), query);
            System.assert(query.contains('Patient__r.Hospice__c = false'), query);
            System.assert(query.endsWith('Admit_DateTime__c'), 'ordering is kept: ' + query);
        }
    }

    @IsTest
    static void theClassBindIsPresentOnlyWhenTheQueryAsksForIt() {
        Datetime now = Datetime.now();

        Map<String, Object> withClass =
            TCMReadmissionAdmissionScope.binds('a01', now, now, config('Inpatient'));
        Map<String, Object> withoutClass =
            TCMReadmissionAdmissionScope.binds('a01', now, now, config(null));

        System.assertEquals('%Inpatient%', withClass.get('patientClassPattern'));
        System.assertEquals(4, withClass.size());
        System.assert(
            !withoutClass.containsKey('patientClassPattern'),
            'queryWithBinds rejects a bind the query never mentions'
        );
        System.assertEquals(3, withoutClass.size());
        System.assert(
            !TCMReadmissionAdmissionScope.soql(false, config(null)).contains('Patient_Class__c'),
            'and the clause is absent from the query text too'
        );
    }

    @IsTest
    static void theScopeDescribesItselfForTheDigest() {
        System.assertEquals(
            'Discharged home from the facility, not on hospice, patient class contains "Inpatient".',
            TCMReadmissionAdmissionScope.describe(config('Inpatient'))
        );
        System.assertEquals(
            'Discharged home from the facility, not on hospice, any patient class.',
            TCMReadmissionAdmissionScope.describe(config(null))
        );
        System.assertEquals(
            'Discharged home from the facility, not on hospice, any patient class.',
            TCMReadmissionAdmissionScope.describe(null)
        );
    }
}