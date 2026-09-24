/**
 * The PDF controller re-queries with the job's filters. These tests pin that scoping: only the
 * named facility, only discharged-home, no hospice, only inside the window, and cells formatted
 * identically to the CSV.
 *
 * They also pin the hardening: the window is derived from a report date rather than taken from
 * the URL, so no caller can widen it, and an id of the wrong object is refused.
 *
 * Config is pinned rather than read from the org, so a change to the real TCM_Report_Config
 * record cannot silently change what these tests assert.
 */
@IsTest
private class TCMReadmissionReportPdfControllerTest {

    private static final String TZ = 'America/New_York';

    @TestSetup
    static void setup() {
        Account parent = new Account(Name = 'Parent', TCM__c = true);
        insert parent;
        Facility__c alpha = new Facility__c(Name = 'Alpha SNF', Parent_Company__c = parent.Id,
            Admin_Email__c = 'admin@alpha.com', TCM__c = true, Exclude_from_TCM_Reporting__c = false);
        Facility__c bravo = new Facility__c(Name = 'Bravo SNF', Parent_Company__c = parent.Id,
            Admin_Email__c = 'admin@bravo.com', TCM__c = true, Exclude_from_TCM_Reporting__c = false);
        insert new List<Facility__c>{ alpha, bravo };

        Patient__c ann = new Patient__c(First_Name__c = 'Ann', Last_Name__c = 'Adams', Status__c = 'Inactive', Facility__c = alpha.Id, Hospice__c = false);
        Patient__c hal = new Patient__c(First_Name__c = 'Hal', Last_Name__c = 'Grant', Status__c = 'Inactive', Facility__c = alpha.Id, Hospice__c = true);
        Patient__c cal = new Patient__c(First_Name__c = 'Cal', Last_Name__c = 'Brown', Status__c = 'Inactive', Facility__c = bravo.Id, Hospice__c = false);
        insert new List<Patient__c>{ ann, hal, cal };

        TCMReadmissionWindow w = new TCMReadmissionWindow(TZ);
        insert new List<Hospital_Admission__c>{
            // Patient Class values are the shapes production actually holds: a comma separated
            // list. Alpha's qualifying row contains Inpatient, Bravo's does not.
            new Hospital_Admission__c(Patient__c = ann.Id, Facility__c = 'Mercy General', Admit_DateTime__c = w.startUtc.addHours(2), Was_Discharged_Home_From_SNF__c = true, Patient_Class__c = 'Emergency, Inpatient'),
            new Hospital_Admission__c(Patient__c = ann.Id, Facility__c = 'Mercy General', Admit_DateTime__c = w.startUtc.addHours(3), Was_Discharged_Home_From_SNF__c = false, Patient_Class__c = 'Inpatient'),
            new Hospital_Admission__c(Patient__c = ann.Id, Facility__c = 'Mercy General', Admit_DateTime__c = w.startUtc.addDays(-3), Was_Discharged_Home_From_SNF__c = true, Patient_Class__c = 'Inpatient'),
            new Hospital_Admission__c(Patient__c = hal.Id, Facility__c = 'Mercy General', Admit_DateTime__c = w.startUtc.addHours(2), Was_Discharged_Home_From_SNF__c = true, Patient_Class__c = 'Inpatient'),
            new Hospital_Admission__c(Patient__c = cal.Id, Facility__c = 'County', Admit_DateTime__c = w.startUtc.addHours(2), Was_Discharged_Home_From_SNF__c = true, Patient_Class__c = 'Emergency, Observation')
        };
    }

    /**
     * Pins configuration for tests that do not care about it, so these assertions never depend
     * on the live TCM_Report_Config record. A test that does care sets its own override first.
     */
    private static void pinConfig() {
        if (TCMReportConfig.overrideRecord == null) {
            TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
                Is_Active__c = true, Business_Timezone__c = TZ
            );
        }
    }

    private static TCMReadmissionReportPdfController load(Id facilityId, TCMReadmissionWindow w) {
        return load(facilityId, w == null ? null : String.valueOf(w.lastCoveredDate()));
    }

    private static TCMReadmissionReportPdfController load(Id facilityId, String reportDate) {
        pinConfig();
        PageReference page = Page.TCMReadmissionReportPdf;
        Test.setCurrentPage(page);
        if (facilityId != null) {
            page.getParameters().put(TCMReadmissionReportPdfController.PARAM_FACILITY, facilityId);
        }
        if (reportDate != null) {
            page.getParameters().put(
                TCMReadmissionReportPdfController.PARAM_REPORT_DATE, reportDate
            );
        }
        return new TCMReadmissionReportPdfController();
    }

    @IsTest
    static void rendersOnlyThatFacilityQualifyingRowsInCsvFormat() {
        Facility__c alpha = [SELECT Id FROM Facility__c WHERE Name = 'Alpha SNF'];
        TCMReadmissionWindow w = new TCMReadmissionWindow(TZ);

        TCMReadmissionReportPdfController c = load(alpha.Id, w);

        System.assertEquals('Alpha SNF', c.facilityName);
        System.assertEquals(w.describe(), c.windowDescription);
        System.assertEquals(TCMReadmissionCsvBuilder.headers(), c.headers);
        System.assertEquals(1, c.rowCount, 'not-discharged-home, hospice, out-of-window and other-facility rows must all drop: ' + c.rows);
        List<String> row = c.rows[0];
        System.assertEquals('Ann Adams', row[0]);
        System.assertEquals('Mercy General', row[1]);
        System.assertEquals(
            new TCMReadmissionCsvBuilder(TZ).values([
                SELECT Id, Facility__c, Admit_DateTime__c, Patient__r.First_Name__c, Patient__r.Last_Name__c,
                       Patient__r.Discharge_Date__c, Patient__r.Had_TCM_Visit__c, Patient__r.Won_Date_Time__c
                FROM Hospital_Admission__c
                WHERE Patient__r.First_Name__c = 'Ann' AND Was_Discharged_Home_From_SNF__c = true
                  AND Admit_DateTime__c >= :w.startUtc LIMIT 1
            ]),
            row,
            'PDF cells must match the CSV builder exactly'
        );
        System.assert(String.isNotBlank(c.generatedAt));
    }

    @IsTest
    static void otherFacilitySeesOnlyItsOwnRow() {
        Facility__c bravo = [SELECT Id FROM Facility__c WHERE Name = 'Bravo SNF'];
        TCMReadmissionReportPdfController c = load(bravo.Id, new TCMReadmissionWindow(TZ));
        System.assertEquals('Bravo SNF', c.facilityName);
        System.assertEquals(1, c.rowCount);
        System.assertEquals('Cal Brown', c.rows[0][0]);
    }

    @IsTest
    static void missingOrBadParametersRenderEmptyNotError() {
        TCMReadmissionReportPdfController none = load(null, (String) null);
        System.assertEquals(0, none.rowCount);
        System.assertEquals('', none.facilityName);
        System.assert(
            none.problem != null && none.problem.contains('No facility'),
            'the page says why it is empty: ' + none.problem
        );

        TCMReadmissionReportPdfController bad = load(null, 'not-a-date');
        System.assertEquals(0, bad.rowCount, 'garbage parameters must not throw');
        System.assertEquals(TCMReadmissionCsvBuilder.headers(), bad.headers);
    }

    @IsTest
    static void anIdOfTheWrongObjectIsRefusedRatherThanQueried() {
        Account parent = [SELECT Id FROM Account WHERE Name = 'Parent' LIMIT 1];
        TCMReadmissionReportPdfController c = load(parent.Id, new TCMReadmissionWindow(TZ));
        System.assertEquals(0, c.rowCount, 'an Account id must not reach the admissions query');
        System.assertEquals('', c.facilityName);
        System.assertNotEquals(null, c.problem);
    }

    @IsTest
    static void theWindowComesFromTheReportDateNotFromTheCaller() {
        Facility__c alpha = [SELECT Id FROM Facility__c WHERE Name = 'Alpha SNF'];
        TCMReadmissionWindow current = new TCMReadmissionWindow(TZ);

        // The row seeded in setup sits inside the current window.
        TCMReadmissionReportPdfController inWindow = load(alpha.Id, current);
        System.assertEquals(1, inWindow.rowCount);

        // A caller asking for a much earlier report date gets that window, not a widened one,
        // and therefore none of today's rows. This is the tampering case: before hardening, a
        // start of zero returned every admission ever recorded.
        TCMReadmissionReportPdfController earlier =
            load(alpha.Id, String.valueOf(current.lastCoveredDate().addDays(-30)));
        System.assertEquals(
            0, earlier.rowCount, 'the window must follow the report date, not the caller'
        );
        System.assertNotEquals(
            inWindow.windowDescription,
            earlier.windowDescription,
            'and the heading must describe the window actually queried'
        );
    }

    @IsTest
    static void theWindowKeepsTheMondayRuleForAGivenReportDate() {
        // Monday 2026-09-07 covers Friday through Sunday, so its last covered day is Sunday.
        TCMReadmissionWindow monday =
            TCMReadmissionWindow.forLastCoveredDate(TZ, Date.newInstance(2026, 9, 6));
        System.assertEquals(Date.newInstance(2026, 9, 6), monday.lastCoveredDate());
        System.assertEquals(3, monday.dayCount(), 'a Monday run covers three days');
        System.assertEquals(Date.newInstance(2026, 9, 4), monday.localStartDate);

        TCMReadmissionWindow tuesday =
            TCMReadmissionWindow.forLastCoveredDate(TZ, Date.newInstance(2026, 9, 8));
        System.assertEquals(1, tuesday.dayCount());
        System.assertEquals(Date.newInstance(2026, 9, 8), tuesday.lastCoveredDate());
    }

    @IsTest
    static void thePageAppliesTheRequiredPatientClassTheSameWayTheJobDoes() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Business_Timezone__c = TZ,
            Required_Patient_Class__c = 'Inpatient'
        );
        Id alpha = [SELECT Id FROM Facility__c WHERE Name = 'Alpha SNF'].Id;
        Id bravo = [SELECT Id FROM Facility__c WHERE Name = 'Bravo SNF'].Id;

        Test.startTest();
        TCMReadmissionReportPdfController alphaPage =
            load(alpha, new TCMReadmissionWindow(TZ));
        TCMReadmissionReportPdfController bravoPage =
            load(bravo, new TCMReadmissionWindow(TZ));
        Test.stopTest();

        System.assertEquals(
            1, alphaPage.rowCount,
            'Alpha\'s qualifying row is "Emergency, Inpatient", so it stays'
        );
        System.assertEquals(
            0, bravoPage.rowCount,
            'Bravo\'s only row is "Emergency, Observation", so the page reports nothing'
        );
        System.assertEquals(null, bravoPage.problem, 'an empty report is not an error');
    }
}