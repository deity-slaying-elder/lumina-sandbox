/**
 * Resolves the To and CC lists for a single facility email.
 *
 * Pure given a Facility and the config -- no SOQL, no DML -- so every branch of the
 * fallback and the NJ rule is directly testable.
 */
public with sharing class TCMReadmissionRecipientResolver {

    private final TCMReportConfig config;
    private final Boolean isSandbox;

    public TCMReadmissionRecipientResolver(TCMReportConfig config, Boolean isSandbox) {
        this.config = config;
        this.isSandbox = isSandbox;
    }

    public class Resolution {
        public List<String> toAddresses = new List<String>();
        public List<String> ccAddresses = new List<String>();
        /**
         * Who the report was actually for, before any sandbox redirect replaced the delivery
         * addresses. Per-recipient link attribution has to record the intended mailbox, or a
         * sandbox run would file every open against a tester instead of the facility contact.
         */
        public List<String> intendedTo = new List<String>();
        public List<String> intendedCc = new List<String>();
        public String primarySource;
        public String skipReason;
        public Boolean redirected = false;

        public Boolean isSendable() {
            return skipReason == null && !toAddresses.isEmpty();
        }

        /** Role label for an intended address, for the attribution row. */
        public String roleFor(String email) {
            if (email == null) {
                return null;
            }
            String lower = email.trim().toLowerCase();
            for (String t : intendedTo) {
                if (t == lower) {
                    return 'DON_Email__c'.equals(primarySource)
                        ? 'Director of Nursing'
                        : 'Administrator';
                }
            }
            return 'Internal';
        }
    }

    public Resolution resolve(Facility__c facility) {
        Resolution result = new Resolution();

        // Admin then DON, exclusively. The fallback replaces the primary rather than
        // adding to it.
        List<String> primary = split(facility.Admin_Email__c);
        result.primarySource = 'Admin_Email__c';
        if (primary.isEmpty()) {
            primary = split(facility.DON_Email__c);
            result.primarySource = 'DON_Email__c';
        }
        if (primary.isEmpty()) {
            result.primarySource = null;
            result.skipReason = 'No Admin_Email__c or DON_Email__c on file';
            return result;
        }
        result.toAddresses = primary;

        Set<String> cc = new Set<String>();
        cc.addAll(split(config.internalCc()));
        if (isNjGhc(facility)) {
            cc.addAll(split(config.njGhcCc()));
        }
        cc.removeAll(result.toAddresses);
        result.ccAddresses = new List<String>(cc);

        // Snapshot before any redirect, so attribution survives a sandbox run.
        result.intendedTo = new List<String>(result.toAddresses);
        result.intendedCc = new List<String>(result.ccAddresses);

        if (isSandbox) {
            List<String> redirect = split(config.sandboxRedirect());
            if (redirect.isEmpty()) {
                // Refuse to fall through to a real facility address from a sandbox.
                result.toAddresses = new List<String>();
                result.ccAddresses = new List<String>();
                result.skipReason = 'Sandbox run with no Sandbox_Redirect_Email__c configured';
                return result;
            }
            result.toAddresses = redirect;
            result.ccAddresses = new List<String>();
            result.redirected = true;
        }

        return result;
    }

    /**
     * Exact, case-insensitive match on the parent company name, deliberately not a
     * "contains" check. An Account named AUGHC exists in this org and would satisfy
     * contains('GHC').
     */
    @TestVisible
    private Boolean isNjGhc(Facility__c facility) {
        if (facility.Parent_Company__r == null || facility.Parent_Company__r.Name == null) {
            return false;
        }
        Boolean isGhc = facility.Parent_Company__r.Name.trim()
            .equalsIgnoreCase(config.njGhcParentCompanyName());
        if (!isGhc) {
            return false;
        }
        String state = facility.Address__StateCode__s;
        return state != null && 'NJ'.equalsIgnoreCase(state.trim());
    }

    /**
     * These fields are expected to hold one address each, but a stray "a@x.com; b@y.com"
     * would fail the entire send, so both separators are handled. Lowercased so the CC
     * dedupe against the To list is case-insensitive.
     */
    private static List<String> split(String raw) {
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
}