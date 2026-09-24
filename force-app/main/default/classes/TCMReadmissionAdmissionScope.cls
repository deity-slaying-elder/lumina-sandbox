/**
 * The one definition of which hospital admissions belong in a readmission report.
 *
 * Three callers need this exact set: the nightly batch, the on-demand resend, and the page the
 * PDF is rendered from. They used to carry three copies of the same WHERE clause, which is a
 * standing invitation for the resend or the PDF to report a different set of rows than the
 * email said. One definition here means a change to the clinical scope lands in all three.
 *
 * The rules:
 * - the patient was discharged home from the facility, and is not on hospice,
 * - the admission falls inside the report window,
 * - the admission belongs to the facility being reported,
 * - and, when configured, Patient Class contains the required word.
 *
 * Patient Class is free text holding a comma separated list, such as "Emergency, Inpatient" or
 * "Emergency, Observation, Inpatient", so the required class is a contains match rather than an
 * equality one. A row with no Patient Class at all does not contain it and is left out.
 *
 * Built as dynamic SOQL rather than three static queries because the class clause is present
 * only when it is configured. Every value travels as a bind, so nothing from configuration is
 * concatenated into the query text.
 */
public with sharing class TCMReadmissionAdmissionScope {

    /** Bind names, so callers cannot drift from the query text. */
    public static final String BIND_FACILITY = 'facilityScope';
    public static final String BIND_START = 'startUtc';
    public static final String BIND_END = 'endUtc';
    public static final String BIND_CLASS = 'patientClassPattern';

    private static final String COLUMNS =
        'SELECT Id, Facility__c, Admit_DateTime__c,' +
        '       Patient__c, Patient__r.Facility__c,' +
        '       Patient__r.First_Name__c, Patient__r.Last_Name__c,' +
        '       Patient__r.Discharge_Date__c, Patient__r.Had_TCM_Visit__c,' +
        '       Patient__r.Won_Date_Time__c' +
        ' FROM Hospital_Admission__c';

    private static final String ORDERING =
        ' ORDER BY Patient__r.Last_Name__c, Patient__r.First_Name__c, Admit_DateTime__c';

    /**
     * manyFacilities picks IN over =, so the batch can scan a chunk while the resend and the
     * PDF page ask about one facility. Both forms bind the same name.
     */
    public static String soql(Boolean manyFacilities, TCMReportConfig config) {
        String query =
            COLUMNS +
            ' WHERE Was_Discharged_Home_From_SNF__c = true' +
            '   AND Patient__r.Hospice__c = false' +
            '   AND Patient__r.Facility__c ' +
            (manyFacilities == true ? 'IN' : '=') + ' :' + BIND_FACILITY +
            '   AND Admit_DateTime__c >= :' + BIND_START +
            '   AND Admit_DateTime__c < :' + BIND_END;
        if (patternFor(config) != null) {
            query += '   AND Patient_Class__c LIKE :' + BIND_CLASS;
        }
        return query + ORDERING;
    }

    /**
     * facilityScope is a Set<Id> for the batch and an Id for the other two. The class bind is
     * present only when the query text asks for it, because queryWithBinds rejects a map
     * holding a name the query never mentions.
     */
    public static Map<String, Object> binds(
        Object facilityScope, Datetime startUtc, Datetime endUtc, TCMReportConfig config
    ) {
        Map<String, Object> binds = new Map<String, Object>{
            BIND_FACILITY => facilityScope,
            BIND_START => startUtc,
            BIND_END => endUtc
        };
        String pattern = patternFor(config);
        if (pattern != null) {
            binds.put(BIND_CLASS, pattern);
        }
        return binds;
    }

    /** Runs the query in system mode. The batch and the resend both want that. */
    public static List<Hospital_Admission__c> find(
        Object facilityScope, Datetime startUtc, Datetime endUtc, TCMReportConfig config
    ) {
        return (List<Hospital_Admission__c>) Database.queryWithBinds(
            soql(facilityScope instanceof Set<Id>, config),
            binds(facilityScope, startUtc, endUtc, config),
            AccessLevel.SYSTEM_MODE
        );
    }

    /** One line naming the clinical scope, for the run digest. */
    public static String describe(TCMReportConfig config) {
        String required = config == null ? null : config.requiredPatientClass();
        return String.isBlank(required)
            ? 'Discharged home from the facility, not on hospice, any patient class.'
            : 'Discharged home from the facility, not on hospice, patient class contains "' +
              required + '".';
    }

    private static String patternFor(TCMReportConfig config) {
        String required = config == null ? null : config.requiredPatientClass();
        return String.isBlank(required) ? null : '%' + required + '%';
    }
}