/**
 * Issues each facility's report as a link to the report site, one link per recipient.
 *
 * Why per recipient rather than per facility: a link is the only thing that identifies who
 * opened a report, so a distinct link per address is what makes an open attributable to a
 * person. The file is stored once per facility and every link points at that same
 * ContentVersion, so the extra cost is one small row per recipient, not a duplicated PDF.
 *
 * A link is a Readmission_Report_Link__c row holding the hash of a random token; the token
 * itself goes only into the URL in that recipient's email. No public file URL exists any more.
 * The site page is the only door, and it opens only for a one-time code emailed to the same
 * address at the moment of viewing.
 *
 * Reissuing a link to an address closes the previous live link to the same address for the
 * same facility, so only the newest link works.
 *
 * Bulk per chunk, partial-success DML throughout. A recipient whose link row cannot be
 * written is reported and not emailed; an email pointing at a link that does not exist must
 * never go out.
 */
public with sharing class TCMReadmissionLinkPublisher {

    private final TCMReportConfig config;

    public TCMReadmissionLinkPublisher(TCMReportConfig config) {
        this.config = config;
    }

    /**
     * One mailbox that gets its own link.
     *
     * email is the mailbox that can actually open it, which is what an open is attributed to
     * and where the one-time code is sent. intendedFor is the facility contact the report
     * represents. The two differ only on a redirected sandbox run, where delivery goes to
     * testers but the report still belongs to the facility's administrator.
     */
    public class Recipient {
        public String email;
        public String role;
        public String intendedFor;

        public Recipient(String email, String role) {
            this(email, role, email);
        }

        public Recipient(String email, String role, String intendedFor) {
            this.email = email == null ? null : email.trim().toLowerCase();
            this.role = role;
            this.intendedFor = intendedFor;
        }
    }

    /** One facility's file plus everyone who should get their own link to it. */
    public class Request {
        public Id facilityId;
        public String facilityName;
        public String fileName;
        public Blob report;
        /**
         * Set instead of report, after construction, to point new links at a file that is
         * already stored, which is what an on-demand resend does. Reusing the version keeps
         * one PDF per report per facility however many times it is reissued, and needs no PDF
         * render, so the resend can run synchronously and tell the user what happened.
         */
        public Id existingContentVersionId;
        public Date reportDate;
        public List<Recipient> recipients = new List<Recipient>();

        public Request(
            Id facilityId, String facilityName, String fileName, Blob report, Date reportDate
        ) {
            this.facilityId = facilityId;
            this.facilityName = facilityName;
            this.fileName = fileName;
            this.report = report;
            this.reportDate = reportDate;
        }
    }

    /** The link issued to one address. */
    public class Issued {
        public String email;
        public String role;
        public String intendedFor;
        public Id linkId;
        /** The site URL carrying the raw token. Exists here and in the email, nowhere else. */
        public String publicUrl;
        public Datetime expiresAt;
        public String failure;

        public Boolean isUsable() {
            return failure == null && String.isNotBlank(publicUrl);
        }
    }

    /** Everything published for one facility. */
    public class Published {
        public Id facilityId;
        public Id contentVersionId;
        /** Every problem seen for this facility, joined. Reported in the digest. */
        public String failure;
        public Map<String, Issued> byEmail = new Map<String, Issued>();

        /**
         * Appends rather than replaces. Two recipients can fail for different reasons, and a
         * file-storage failure must not be erased by a later attribution failure: whoever reads
         * the digest needs all of it.
         */
        public void note(String problem) {
            if (String.isBlank(problem)) {
                return;
            }
            failure = String.isBlank(failure) ? problem : failure + '; ' + problem;
        }

        /** True when at least one recipient has a working link. */
        public Boolean hasAnyUsable() {
            for (Issued i : byEmail.values()) {
                if (i.isUsable()) {
                    return true;
                }
            }
            return false;
        }
    }

    /**
     * Test seam. "Never send an email pointing at a link that does not exist" is the safety rule
     * both callers rest on, and a link row insert cannot be made to fail on demand, so the
     * failure has to be injectable or that rule stays unproven.
     */
    @TestVisible
    private static Map<Id, Published> publishOverride;

    public Map<Id, Published> publish(List<Request> requests) {
        if (publishOverride != null) {
            return publishOverride;
        }
        Map<Id, Published> byFacility = new Map<Id, Published>();
        if (requests == null || requests.isEmpty()) {
            return byFacility;
        }

        // 0. Nowhere to point a link at means no links. Checked before anything is stored.
        String baseUrl = TCMReadmissionPortal.baseUrl(config);
        if (String.isBlank(baseUrl)) {
            for (Request r : requests) {
                Published p = new Published();
                p.facilityId = r.facilityId;
                p.note(
                    'The report site ' + TCMReadmissionPortal.SITE_NAME + ' is not active in ' +
                    'this org and no Portal_Base_Url__c is configured, so no link can be issued.'
                );
                byFacility.put(r.facilityId, p);
            }
            return byFacility;
        }

        // 1. One file per facility. Every recipient's link points at this same version.
        List<ContentVersion> versions = new List<ContentVersion>();
        List<Request> ordered = new List<Request>();
        for (Request r : requests) {
            Published p = new Published();
            p.facilityId = r.facilityId;
            byFacility.put(r.facilityId, p);

            if (r.existingContentVersionId != null) {
                // A resend reuses the file already on the record, so there is nothing to store.
                p.contentVersionId = r.existingContentVersionId;
                continue;
            }
            // FirstPublishLocationId files the report on the Facility record, so Lumina staff
            // can find every report ever issued from the facility page.
            versions.add(new ContentVersion(
                Title = titleFor(r.fileName),
                PathOnClient = r.fileName,
                VersionData = r.report,
                FirstPublishLocationId = r.facilityId
            ));
            ordered.add(r);
        }

        if (!versions.isEmpty()) {
            List<Database.SaveResult> versionResults = Database.insert(versions, false);
            for (Integer i = 0; i < versionResults.size(); i++) {
                Published p = byFacility.get(ordered[i].facilityId);
                if (versionResults[i].isSuccess()) {
                    p.contentVersionId = versionResults[i].getId();
                } else {
                    p.note('File could not be stored: ' +
                        firstError(versionResults[i].getErrors()));
                }
            }
        }

        // 2. One token and one row per recipient.
        Datetime now = Datetime.now();
        Datetime expiresAt = now.addHours(config.linkExpiryHours());
        // Who was Cc'd on the message this link travels in. They can ask for the code to come
        // to their own mailbox rather than the facility's, which is the only way a Cc'd reader
        // can open the report without being sent a second email and a link of their own.
        String ccSnapshot = ccSnapshot(config);
        List<Readmission_Report_Link__c> rows = new List<Readmission_Report_Link__c>();
        List<Issued> issuedInOrder = new List<Issued>();
        List<Request> requestInOrder = new List<Request>();
        List<String> tokenInOrder = new List<String>();
        Set<Id> facilityIds = new Set<Id>();
        Set<String> emails = new Set<String>();

        for (Request r : requests) {
            Published p = byFacility.get(r.facilityId);
            if (p.contentVersionId == null) {
                continue;
            }
            for (Recipient rec : r.recipients) {
                if (String.isBlank(rec.email) || p.byEmail.containsKey(rec.email)) {
                    continue;
                }
                Issued issued = new Issued();
                issued.email = rec.email;
                issued.role = rec.role;
                issued.intendedFor = rec.intendedFor;
                p.byEmail.put(rec.email, issued);

                String token = TCMReadmissionAccessToken.mintToken();
                rows.add(new Readmission_Report_Link__c(
                    Facility__c = r.facilityId,
                    Recipient_Email__c = rec.email,
                    Recipient_Role__c = rec.role,
                    Intended_For__c = rec.intendedFor,
                    Content_Version_Id__c = p.contentVersionId,
                    Access_Token_Hash__c = TCMReadmissionAccessToken.hashToken(token),
                    Report_Date__c = r.reportDate,
                    // Snapshot, not a config read at request time: a link already in someone's
                    // inbox must not widen because the Cc list changed afterwards.
                    Cc_Emails__c = ccSnapshot,
                    Expires_At__c = expiresAt,
                    Opens__c = 0,
                    Downloads__c = 0,
                    Codes_Sent__c = 0,
                    Failed_Attempts__c = 0
                ));
                issuedInOrder.add(issued);
                requestInOrder.add(r);
                tokenInOrder.add(token);
                facilityIds.add(r.facilityId);
                emails.add(rec.email);
            }
        }
        if (rows.isEmpty()) {
            return byFacility;
        }

        // 3. Only the newest link to an address works. Done before the insert so a failed
        //    insert cannot leave an address with no working link and a closed old one; the
        //    closes are reported, not fatal.
        supersede(facilityIds, emails, now, byFacility, requestInOrder, issuedInOrder);

        // 4. The rows are the links. A row that could not be written is a link that does not
        //    exist, and that recipient is not emailed.
        List<Database.SaveResult> rowResults = Database.insert(rows, false);
        for (Integer i = 0; i < rowResults.size(); i++) {
            Issued issued = issuedInOrder[i];
            if (rowResults[i].isSuccess()) {
                issued.linkId = rowResults[i].getId();
                issued.expiresAt = expiresAt;
                issued.publicUrl = TCMReadmissionPortal.linkFor(baseUrl, tokenInOrder[i]);
            } else {
                issued.failure = 'Link could not be created: ' +
                    firstError(rowResults[i].getErrors());
                byFacility.get(requestInOrder[i].facilityId)
                    .note(issued.email + ': ' + issued.failure);
            }
        }
        return byFacility;
    }

    /**
     * Closes every live link to any of these addresses for any of these facilities. The pair
     * is checked per row, so a reissue for one facility cannot close the same person's link to
     * another facility's report.
     */
    private static void supersede(
        Set<Id> facilityIds, Set<String> emails, Datetime now,
        Map<Id, Published> byFacility, List<Request> requestInOrder, List<Issued> issuedInOrder
    ) {
        Set<String> pairs = new Set<String>();
        for (Integer i = 0; i < issuedInOrder.size(); i++) {
            pairs.add(requestInOrder[i].facilityId + '|' + issuedInOrder[i].email);
        }
        List<Readmission_Report_Link__c> toClose = new List<Readmission_Report_Link__c>();
        for (Readmission_Report_Link__c old : [
            SELECT Id, Facility__c, Recipient_Email__c
            FROM Readmission_Report_Link__c
            WHERE Facility__c IN :facilityIds
              AND Recipient_Email__c IN :emails
              AND Access_Token_Hash__c != null
              AND Closed_Reason__c = null
              AND Expires_At__c > :now
        ]) {
            if (!pairs.contains(old.Facility__c + '|' + old.Recipient_Email__c)) {
                continue;
            }
            old.Closed_Reason__c = 'Superseded';
            old.Closed_At__c = now;
            old.Code_Hash__c = null;
            old.Code_Expires_At__c = null;
            old.Unlocked_Until__c = null;
            toClose.add(old);
        }
        if (toClose.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.update(toClose, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                continue;
            }
            Published p = byFacility.get(toClose[i].Facility__c);
            if (p != null) {
                p.note(
                    'The previous link for ' + toClose[i].Recipient_Email__c +
                    ' could not be closed: ' + firstError(results[i].getErrors())
                );
            }
        }
    }

    private static String titleFor(String fileName) {
        String base = String.isBlank(fileName) ? 'Readmissions' : fileName;
        for (String ext : new List<String>{ '.csv', '.pdf' }) {
            if (base.endsWithIgnoreCase(ext)) {
                return base.left(base.length() - ext.length());
            }
        }
        return base;
    }

    private static String firstError(List<Database.Error> errors) {
        if (errors == null || errors.isEmpty()) {
            return 'unknown error';
        }
        Database.Error e = errors[0];
        return e.getStatusCode() + ' ' + e.getMessage();
    }

    /**
     * The Cc list as one stored string, or null when there is none. Never populated in a
     * sandbox: a sandbox redirects the whole message, so nobody was really Cc'd.
     */
    private static String ccSnapshot(TCMReportConfig config) {
        if (config == null || isSandboxOrg()) {
            return null;
        }
        List<String> cc = config.globalCc();
        return cc.isEmpty() ? null : String.join(cc, ';');
    }

    @TestVisible private static Boolean sandboxOverride;
    private static Boolean sandboxCache;

    private static Boolean isSandboxOrg() {
        if (sandboxOverride != null) {
            return sandboxOverride;
        }
        if (sandboxCache == null) {
            sandboxCache = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        }
        return sandboxCache;
    }

}