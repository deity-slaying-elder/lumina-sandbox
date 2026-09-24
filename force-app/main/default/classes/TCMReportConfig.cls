/**
 * Read-only accessor for the TCM_Report_Config__mdt "Default" record.
 *
 * Values that are still placeholders are left blank rather than filled with dummy
 * addresses, so nothing can be sent to a mailbox that does not exist. Callers use
 * unconfiguredPlaceholders() to report the gaps in the run digest, which keeps an unfilled
 * placeholder visible instead of silently doing nothing.
 */
public with sharing class TCMReportConfig {

    @TestVisible
    private static final String RECORD_NAME = 'Default';

    @TestVisible
    private static TCM_Report_Config__mdt overrideRecord;

    private final TCM_Report_Config__mdt record;

    public TCMReportConfig() {
        this.record = resolve();
    }

    private static TCM_Report_Config__mdt resolve() {
        if (overrideRecord != null) {
            return overrideRecord;
        }
        TCM_Report_Config__mdt cfg = TCM_Report_Config__mdt.getInstance(RECORD_NAME);
        if (cfg == null) {
            throw new ConfigException(
                'Missing TCM_Report_Config__mdt record "' + RECORD_NAME + '". Deploy ' +
                'customMetadata/TCM_Report_Config.Default.md-meta.xml before scheduling.'
            );
        }
        return cfg;
    }

    public Boolean isActive() {
        return record.Is_Active__c == true;
    }

    public Boolean requireFacilityTcm() {
        return record.Require_Facility_TCM__c == true;
    }

    /**
     * Only report admissions whose Patient Class contains this word, such as Inpatient. Blank
     * reports every class. Patient Class is a comma separated list, so callers match on
     * contains rather than equality.
     */
    public String requiredPatientClass() {
        return trimToNull(record.Required_Patient_Class__c);
    }

    public String timeZoneName() {
        return blankTo(record.Business_Timezone__c, 'America/New_York');
    }

    public String subjectTemplate() {
        return blankTo(record.Subject_Template__c, 'Readmissions Report - {0} - {1}');
    }

    public String njGhcParentCompanyName() {
        return blankTo(record.NJ_GHC_Parent_Company_Name__c, 'GHC');
    }

    /**
     * Lumina staff who get the same report as the facility.
     *
     * Not a Cc in the mail sense: in Link mode each of these addresses is issued its own link
     * and therefore its own one-time code, so they can open the report without the facility
     * ever seeing their code, and the facility's code never reaches them. That is the
     * behaviour Lumina chose over a true Cc.
     *
     * Semicolon or comma separated, so people can be added and removed in Setup without a
     * deploy. Callers split it themselves.
     */
    public String internalCc() {
        return trimToNull(record.Internal_CC_Emails__c);
    }

    public String njGhcCc() {
        return trimToNull(record.NJ_GHC_CC_Email__c);
    }

    /**
     * Where every sandbox email goes instead of the facility. The list field wins so more
     * than one tester can receive a run; the original single-address field is the fallback.
     * Callers split on ; or , themselves.
     */
    public String sandboxRedirect() {
        String addresses = trimToNull(record.Sandbox_Redirect_Emails__c);
        return addresses != null ? addresses : trimToNull(record.Sandbox_Redirect_Email__c);
    }

    /**
     * Cc'd on every facility email and on the daily digest.
     *
     * A true Cc, unlike internalCc() and njGhcCc(): in Link mode those two are issued their
     * own link so an open attributes to them, which means they also count as sends in the
     * digest. These addresses get a copy of somebody else's message and no link of their own,
     * so they cannot open the report -- the one-time code goes to the address the link was
     * issued to -- and the digest's send count is unchanged.
     *
     * Never used in a sandbox. A sandbox redirects the whole message, and a Cc would be the
     * one address that still reached a real mailbox.
     */
    public List<String> globalCc() {
        return separatedList(record.Global_CC_Emails__c);
    }

    /**
     * The daily summary can go to more than one person, so this field accepts a
     * separated list where the per-facility address fields hold only one.
     */
    public List<String> digestRecipients() {
        return separatedList(record.Digest_Recipients__c);
    }

    /** Lowercased, de-duplicated, order preserved. Same separators the resolver accepts. */
    private static List<String> separatedList(String raw) {
        List<String> addresses = new List<String>();
        if (String.isBlank(raw)) {
            return addresses;
        }
        Set<String> seen = new Set<String>();
        for (String part : raw.split('[;,]')) {
            String trimmed = part.trim().toLowerCase();
            if (String.isNotBlank(trimmed) && seen.add(trimmed)) {
                addresses.add(trimmed);
            }
        }
        return addresses;
    }

    public String orgWideAddress() {
        return trimToNull(record.From_Org_Wide_Address__c);
    }

    /**
     * Sender for sandbox runs. The production address usually cannot be verified in a
     * sandbox because its verification email goes to the client's mailbox, so a sandbox
     * gets its own. Falls back to the production address when blank.
     */
    public String orgWideAddressFor(Boolean isSandbox) {
        if (isSandbox == true) {
            String sandboxAddress = trimToNull(record.Sandbox_From_Org_Wide_Address__c);
            if (sandboxAddress != null) {
                return sandboxAddress;
            }
        }
        return orgWideAddress();
    }

    /**
     * Link is the intended mode: the facility email carries a count and a public link to the
     * CSV, never the CSV itself. Attachment is kept so the client can fall back without a
     * deploy if Content Deliveries turns out to be off in an org.
     */
    public Boolean deliverAsLink() {
        return !'Attachment'.equalsIgnoreCase(blankTo(record.Delivery_Mode__c, 'Link'));
    }

    /** Lifetime of the public link. Defaults to 72h so a Monday report survives a day off. */
    public Integer linkExpiryHours() {
        Decimal hours = record.Link_Expiry_Hours__c;
        if (hours == null || hours <= 0) {
            return 72;
        }
        return hours.intValue();
    }

    /**
     * Full URL of the report site page, when it cannot be derived from the org's own Site
     * record, such as behind a custom domain. Blank means derive it.
     */
    public String portalBaseUrl() {
        return trimToNull(record.Portal_Base_Url__c);
    }

    /** Whether the report page offers the PDF for download. Lumina said yes. */
    public Boolean allowDownload() {
        return record.Allow_Download__c == true;
    }

    /** Whether Salesforce emails the file owner each time the link is opened. */
    public Boolean notifyOnVisit() {
        return record.Notify_On_Visit__c == true;
    }

    /**
     * Opens allowed per recipient link before it is closed. Zero or blank disables the cap.
     * Enforced by the report site at the moment a code is accepted, so it is a hard cap.
     */
    public Integer maxOpens() {
        Decimal cap = record.Max_Opens__c;
        return cap == null || cap <= 0 ? 0 : cap.intValue();
    }

    /**
     * Config values still awaiting a real value. Reported in the digest each run so an
     * unfilled placeholder stays visible rather than quietly persisting.
     */
    public List<String> unconfiguredPlaceholders() {
        List<String> gaps = new List<String>();
        // Internal_CC_Emails__c is deliberately blank: the internal recipient asked for the
        // daily summary instead of a copy of every facility email. It stays supported for
        // anyone who wants a per-facility CC later, but blank is now the intended state
        // rather than an unfilled placeholder.
        if (orgWideAddress() == null) {
            gaps.add('From_Org_Wide_Address__c (sending from the running user instead)');
        }
        return gaps;
    }

    private static String trimToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String blankTo(String value, String fallback) {
        return String.isBlank(value) ? fallback : value.trim();
    }

    public class ConfigException extends Exception {}
}