/**
 * CSV formatting rules. No DML: parent relationship fields and formula fields are both
 * read-only on in-memory sObjects, so the admission graph is assembled through JSON.
 */
@IsTest
private class TCMReadmissionCsvBuilderTest {

    private static final String ET = 'America/New_York';

    private static Hospital_Admission__c buildAdmission(
        String hospital,
        String firstName,
        String lastName,
        Datetime admitUtc,
        Date dischargeDate,
        Boolean hadTcmVisit,
        Datetime wonUtc
    ) {
        Patient__c patient = new Patient__c(
            First_Name__c = firstName,
            Last_Name__c = lastName,
            Discharge_Date__c = dischargeDate,
            Won_Date_Time__c = wonUtc
        );
        Map<String, Object> patientMap =
            (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(patient));
        // Had_TCM_Visit__c is a formula, so it cannot be assigned on the sObject.
        patientMap.put('Had_TCM_Visit__c', hadTcmVisit);

        Hospital_Admission__c admission = new Hospital_Admission__c(
            Facility__c = hospital,
            Admit_DateTime__c = admitUtc
        );
        Map<String, Object> admissionMap =
            (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(admission));
        admissionMap.put('Patient__r', patientMap);

        return (Hospital_Admission__c) JSON.deserialize(
            JSON.serialize(admissionMap), Hospital_Admission__c.class
        );
    }

    private static List<String> linesOf(Blob csv) {
        return csv.toString().split('\r\n');
    }

    @IsTest
    static void emptyListStillWritesTheHeader() {
        List<String> lines = linesOf(
            new TCMReadmissionCsvBuilder(ET).build(new List<Hospital_Admission__c>())
        );

        System.assertEquals(1, lines.size(), 'header only');
        System.assert(lines[0].contains('"Patient Name"'), 'header row: ' + lines[0]);
        System.assert(lines[0].endsWith('"TCM Program"'), 'header row: ' + lines[0]);
    }

    @IsTest
    static void nullListIsTreatedAsEmpty() {
        List<String> lines = linesOf(new TCMReadmissionCsvBuilder(ET).build(null));

        System.assertEquals(1, lines.size(), 'a null list should not throw');
    }

    @IsTest
    static void embeddedQuotesAreDoubledAndCommasSurvive() {
        Hospital_Admission__c admission = buildAdmission(
            'St. Mary, "The Heights"', 'Ann', 'Lee',
            Datetime.newInstanceGmt(2026, 8, 18, 20, 30, 0),
            Date.newInstance(2026, 8, 1), false, null
        );

        String csv = new TCMReadmissionCsvBuilder(ET)
            .build(new List<Hospital_Admission__c>{ admission }).toString();

        System.assert(
            csv.contains('"St. Mary, ""The Heights"""'),
            'comma preserved and quotes doubled: ' + csv
        );
    }

    @IsTest
    static void timestampsRenderInTheBusinessTimezoneNotUtc() {
        // 20:30Z on 2026-08-18 is 4:30 PM EDT the same day.
        Hospital_Admission__c admission = buildAdmission(
            'Mercy', 'Ann', 'Lee',
            Datetime.newInstanceGmt(2026, 8, 18, 20, 30, 0),
            Date.newInstance(2026, 8, 1), true, Datetime.newInstanceGmt(2026, 8, 20, 12, 0, 0)
        );

        String csv = new TCMReadmissionCsvBuilder(ET)
            .build(new List<Hospital_Admission__c>{ admission }).toString();

        System.assert(csv.contains('8/18/2026 4:30 PM'), 'admit time in Eastern: ' + csv);
        System.assert(csv.contains('"8/1/2026"'), 'discharge date as M/d/yyyy: ' + csv);
        System.assert(csv.contains('"Yes"'), 'a won patient is on the TCM programme: ' + csv);
    }

    @IsTest
    static void tcmProgrammeFollowsWonNotTheVisit() {
        // The two columns this replaced could disagree: a visit can be logged against a
        // patient who never joined the programme. Won is the answer the facility asked for.
        Hospital_Admission__c visitedButNotWon = buildAdmission(
            'Mercy', 'Ann', 'Lee', Datetime.newInstanceGmt(2026, 8, 18, 20, 30, 0),
            Date.newInstance(2026, 8, 1), true, null
        );
        Hospital_Admission__c wonWithoutAVisit = buildAdmission(
            'Mercy', 'Bob', 'Kay', Datetime.newInstanceGmt(2026, 8, 18, 20, 30, 0),
            Date.newInstance(2026, 8, 1), false, Datetime.newInstanceGmt(2026, 8, 20, 12, 0, 0)
        );

        List<String> visited = new TCMReadmissionCsvBuilder(ET).values(visitedButNotWon);
        List<String> won = new TCMReadmissionCsvBuilder(ET).values(wonWithoutAVisit);

        System.assertEquals(5, visited.size(), 'the last two columns are one column now');
        System.assertEquals('No', visited[4], 'a TCM visit alone is not the programme');
        System.assertEquals('Yes', won[4], 'a Won date is the programme, visit or not');
    }

    @IsTest
    static void utcEveningRollsBackADayInEastern() {
        // 02:00Z on the 19th is 10:00 PM EDT on the 18th. Rendering in UTC would put this
        // admission on the wrong calendar day in the facility's own report.
        Hospital_Admission__c admission = buildAdmission(
            'Mercy', 'Ann', 'Lee',
            Datetime.newInstanceGmt(2026, 8, 19, 2, 0, 0), null, false, null
        );

        String csv = new TCMReadmissionCsvBuilder(ET)
            .build(new List<Hospital_Admission__c>{ admission }).toString();

        System.assert(csv.contains('8/18/2026 10:00 PM'), 'should render as the 18th: ' + csv);
    }

    @IsTest
    static void blankValuesBecomeEmptyQuotedCells() {
        Hospital_Admission__c admission =
            buildAdmission('Mercy', 'Ann', null, null, null, false, null);

        List<String> lines = linesOf(
            new TCMReadmissionCsvBuilder(ET).build(new List<Hospital_Admission__c>{ admission })
        );

        System.assertEquals('"Ann","Mercy","","","No"', lines[1], 'row: ' + lines[1]);
    }

    @IsTest
    static void admissionWithNoPatientDoesNotThrow() {
        // Patient__c is an optional lookup, so an orphaned admission is possible in data.
        Hospital_Admission__c orphan = new Hospital_Admission__c(
            Facility__c = 'Mercy',
            Admit_DateTime__c = Datetime.newInstanceGmt(2026, 8, 18, 20, 30, 0)
        );

        List<String> lines = linesOf(
            new TCMReadmissionCsvBuilder(ET).build(new List<Hospital_Admission__c>{ orphan })
        );

        System.assertEquals(2, lines.size(), 'the row should still be written');
        System.assert(lines[1].startsWith('"",'), 'name cell should be empty: ' + lines[1]);
        System.assert(lines[1].contains('"No"'), 'missing patient means no TCM visit: ' + lines[1]);
    }

    @IsTest
    static void fileNameStripsPathCharacters() {
        TCMReadmissionWindow window = new TCMReadmissionWindow(
            ET, Datetime.newInstanceGmt(2026, 8, 19, 12, 0, 0)
        );

        System.assertEquals(
            'Readmissions-Bay-View-2026-08-18.csv',
            new TCMReadmissionCsvBuilder(ET).fileName('Bay/View', window)
        );
        System.assertEquals(
            'Readmissions-Facility-2026-08-18.csv',
            new TCMReadmissionCsvBuilder(ET).fileName('   ', window),
            'a blank facility name should not produce a dangling filename'
        );
    }
}