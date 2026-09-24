/**
 * Backs the Visualforce page the batch renders to PDF for Link mode.
 *
 * Why a PDF at all: Salesforce's public file viewer previews PDF but shows "No preview
 * available" for CSV, so a facility administrator following the link could only download,
 * never read. The PDF is what they see in the browser; the CSV still serves Attachment mode.
 *
 * The page is rendered by getContentAsPDF() from the batch, which is a separate request, so
 * nothing can be handed over in memory. What arrives in the URL is deliberately minimal: the
 * facility and the report date. The window itself is derived here from the same rule the job
 * uses, and the timezone comes from config, because a caller that can name its own start and
 * end can widen a one-day clinical report into a facility's entire history. Cell formatting is
 * delegated to TCMReadmissionCsvBuilder so the PDF and the CSV can never disagree.
 *
 * Queries run in user mode, so field-level security and sharing apply to whoever renders the
 * page rather than being bypassed by Apex's default system mode.
 */
public with sharing class TCMReadmissionReportPdfController {

    public static final String PARAM_FACILITY = 'facilityId';
    /** Last covered day of the report, as yyyy-MM-dd. The window is derived from it. */
    public static final String PARAM_REPORT_DATE = 'reportDate';

    public String facilityName { get; private set; }
    public String windowDescription { get; private set; }
    public String generatedAt { get; private set; }
    public String problem { get; private set; }
    public List<String> headers { get; private set; }
    public List<List<String>> rows { get; private set; }

    public Integer rowCount { get { return rows == null ? 0 : rows.size(); } }

    public TCMReadmissionReportPdfController() {
        Map<String, String> params = ApexPages.currentPage().getParameters();
        Id facilityId = facilityParam(params.get(PARAM_FACILITY));
        Date reportDate = dateParam(params.get(PARAM_REPORT_DATE));

        TCMReportConfig config = new TCMReportConfig();
        TCMReadmissionWindow window =
            TCMReadmissionWindow.forLastCoveredDate(config.timeZoneName(), reportDate);

        headers = TCMReadmissionCsvBuilder.headers();
        rows = new List<List<String>>();
        windowDescription = window.describe();
        generatedAt = Datetime.now().format('EEEE, MMMM d, yyyy h:mm a z', window.timeZoneName);
        facilityName = '';

        if (facilityId == null) {
            problem = 'No facility was named, so there is nothing to report.';
            return;
        }

        List<Facility__c> facilities = Database.query(
            'SELECT Name FROM Facility__c WHERE Id = :facilityId LIMIT 1',
            AccessLevel.USER_MODE
        );
        if (facilities.isEmpty()) {
            // Either the facility does not exist or the running user cannot see it. The page
            // must not distinguish the two, and must not fall through to the rows query.
            problem = 'That facility is not available to you.';
            return;
        }
        facilityName = facilities[0].Name;

        Datetime startUtc = window.startUtc;
        Datetime endUtc = window.endUtc;
        TCMReadmissionCsvBuilder formatter = new TCMReadmissionCsvBuilder(window.timeZoneName);

        // The same clinical scope the batch and the resend use, still in user mode so field
        // level security and sharing apply to whoever renders the page.
        for (Hospital_Admission__c admission : (List<Hospital_Admission__c>) Database.queryWithBinds(
            TCMReadmissionAdmissionScope.soql(false, config),
            TCMReadmissionAdmissionScope.binds(facilityId, startUtc, endUtc, config),
            AccessLevel.USER_MODE
        )) {
            rows.add(formatter.values(admission));
        }
    }

    /**
     * A syntactically valid id of the wrong object would otherwise reach a bind and throw, so
     * the type is checked here rather than left to the query.
     */
    private static Id facilityParam(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            Id parsed = Id.valueOf(raw.trim());
            return parsed.getSObjectType() == Facility__c.SObjectType ? parsed : null;
        } catch (Exception e) {
            return null;
        }
    }

    /** Missing or unparseable falls back to the current window, never to an open range. */
    private static Date dateParam(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            List<String> parts = raw.trim().split('-');
            if (parts.size() != 3) {
                return null;
            }
            return Date.newInstance(
                Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), Integer.valueOf(parts[2])
            );
        } catch (Exception e) {
            return null;
        }
    }
}