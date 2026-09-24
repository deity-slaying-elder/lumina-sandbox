/**
 * Builds the per-facility CSV attachment. Pure -- no SOQL, no DML, no email -- so the
 * formatting rules can be tested directly without staging records.
 */
public with sharing class TCMReadmissionCsvBuilder {

    /**
     * "Had TCM Visit" and "Won Date Time" used to be two columns. They are one now: the
     * facility asked whether the patient is on the TCM program, which is answered by the
     * opportunity being Won, not by the timestamp of when it happened.
     */
    private static final List<String> HEADERS = new List<String>{
        'Patient Name',
        'Hospital',
        'Admit DateTime',
        'Discharge Date',
        'TCM Program'
    };

    /** Excel will not read UTF-8 in a .csv without a byte-order mark. */
    private static final String UTF8_BOM = String.fromCharArray(new List<Integer>{ 65279 });

    private final String timeZoneName;

    public TCMReadmissionCsvBuilder(String timeZoneName) {
        this.timeZoneName = String.isBlank(timeZoneName) ? 'America/New_York' : timeZoneName.trim();
    }

    /** Column headings, in output order. Shared with the PDF so the two can never disagree. */
    public static List<String> headers() {
        return new List<String>(HEADERS);
    }

    /** One admission as formatted display strings, in headers() order. */
    public List<String> values(Hospital_Admission__c admission) {
        return cells(admission);
    }

    public Blob build(List<Hospital_Admission__c> admissions) {
        List<String> lines = new List<String>{ row(HEADERS) };
        if (admissions != null) {
            for (Hospital_Admission__c admission : admissions) {
                lines.add(row(cells(admission)));
            }
        }
        return Blob.valueOf(UTF8_BOM + String.join(lines, '\r\n') + '\r\n');
    }

    public String fileName(String facilityName, TCMReadmissionWindow window) {
        return fileName(facilityName, window.fileDateToken());
    }

    /**
     * Token overload. The batch holds the window as primitives rather than as an object,
     * so that Database.Stateful serialisation between chunks stays trivial.
     */
    public String fileName(String facilityName, String dateToken) {
        String safeName = String.isBlank(facilityName) ? 'Facility' : facilityName.trim();
        return ('Readmissions-' + safeName + '-' + dateToken + '.csv')
            .replaceAll('[\\\\/:*?"<>|]', '-');
    }

    private List<String> cells(Hospital_Admission__c admission) {
        Patient__c patient = admission.Patient__r;
        return new List<String>{
            patientName(patient),
            admission.Facility__c,
            dateTimeCell(admission.Admit_DateTime__c),
            dateCell(patient == null ? null : patient.Discharge_Date__c),
            // Won, not Had_TCM_Visit__c: being on the programme is what the facility asked
            // about, and a visit can be logged against a patient who never signed up.
            patient != null && patient.Won_Date_Time__c != null ? 'Yes' : 'No'
        };
    }

    @TestVisible
    private static String patientName(Patient__c patient) {
        if (patient == null) {
            return '';
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(patient.First_Name__c)) {
            parts.add(patient.First_Name__c.trim());
        }
        if (String.isNotBlank(patient.Last_Name__c)) {
            parts.add(patient.Last_Name__c.trim());
        }
        return String.join(parts, ' ');
    }

    private String dateTimeCell(Datetime value) {
        return value == null ? '' : value.format('M/d/yyyy h:mm a', timeZoneName);
    }

    private static String dateCell(Date value) {
        // Assembled by hand rather than via format(), which follows the running user
        // locale and could hand a facility a d/M/yyyy date.
        if (value == null) {
            return '';
        }
        return String.valueOf(value.month()) + '/' + String.valueOf(value.day()) +
            '/' + String.valueOf(value.year());
    }

    private static String row(List<String> values) {
        List<String> escaped = new List<String>();
        for (String value : values) {
            escaped.add(escape(value));
        }
        return String.join(escaped, ',');
    }

    /** Every cell is quoted, so embedded commas, quotes and newlines all survive. */
    private static String escape(String value) {
        String safe = value == null ? '' : value;
        return '"' + safe.replace('"', '""') + '"';
    }
}