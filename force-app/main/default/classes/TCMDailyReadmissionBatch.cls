/**
 * Emails each enrolled facility about its own patients who were admitted to a hospital during
 * the reporting window after being discharged home from that facility.
 *
 * In Link mode (the default) the email carries a count and an expiring link to the report
 * site, where a one-time code emailed to the same address opens the PDF, and no patient
 * information at all. In Attachment mode the CSV rides along as before.
 * The mode is a config switch so the client can fall back without a deploy.
 *
 * Batches over Facility rather than over Hospital Admission, so each chunk owns a complete
 * set of facilities and can send their mail immediately. That keeps heap bounded regardless
 * of total volume and keeps every chunk inside the 10-sendEmail-calls-per-transaction limit
 * with a single call.
 *
 * Facilities with no rows in the window are not emailed at all.
 *
 * The window is held as primitives rather than as a TCMReadmissionWindow so that
 * Database.Stateful serialisation between chunks stays trivial.
 */
// AllowsCallouts: rendering the PDF with getContentAsPDF() counts as a callout.
public with sharing class TCMDailyReadmissionBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {

    private final Datetime windowStartUtc;
    private final Datetime windowEndUtc;
    private final String timeZoneName;
    private final String fileDateToken;
    private final String windowDescription;
    private final Date windowLastCoveredDate;
    private final Boolean requireFacilityTcm;
    private final Boolean isSandbox;
    /**
     * Cc'd on every facility message and on the digest. Empty in a sandbox: the redirect
     * replaces To, and a Cc would be the one address still reaching a real mailbox.
     */
    private final List<String> globalCc;

    // Stateful accumulators for the finish() digest.
    private Integer facilitiesScanned = 0;
    private Integer emailsSent = 0;
    private Integer rowsReported = 0;
    private Boolean anyRedirected = false;
    private List<String> skipped = new List<String>();
    private List<String> failures = new List<String>();
    private List<String> sent = new List<String>();
    private TCMReadmissionLinkAudit.Result auditResult;

    public TCMDailyReadmissionBatch() {
        this(new TCMReportConfig(), [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox);
    }

    @TestVisible
    private TCMDailyReadmissionBatch(TCMReportConfig config, Boolean isSandbox) {
        TCMReadmissionWindow window = new TCMReadmissionWindow(config.timeZoneName());
        this.windowStartUtc = window.startUtc;
        this.windowEndUtc = window.endUtc;
        this.timeZoneName = window.timeZoneName;
        this.fileDateToken = window.fileDateToken();
        this.windowDescription = window.describe();
        this.windowLastCoveredDate = window.lastCoveredDate();
        this.requireFacilityTcm = config.requireFacilityTcm();
        this.isSandbox = isSandbox;
        this.globalCc = isSandbox == true ? new List<String>() : config.globalCc();
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        String soql =
            'SELECT Id, Name, Admin_Email__c, DON_Email__c, Address__StateCode__s, ' +
            '       Parent_Company__c, Parent_Company__r.Name ' +
            'FROM Facility__c ' +
            'WHERE Exclude_from_TCM_Reporting__c = false ' +
            '  AND Parent_Company__r.TCM__c = true';
        if (requireFacilityTcm) {
            soql += ' AND TCM__c = true';
        }
        soql += ' ORDER BY Name';
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext context, List<Facility__c> facilities) {
        ChunkResult result = buildForFacilities(facilities);

        facilitiesScanned += facilities.size();
        rowsReported += result.rowsReported;
        skipped.addAll(result.skipped);
        failures.addAll(result.failures);
        anyRedirected = anyRedirected || result.redirected;

        if (result.messages.isEmpty()) {
            return;
        }
        // result.sent is parallel to result.messages; a line only reaches the digest's
        // "Facility emails" list once its message actually went out.
        send(result.messages, result.sent);
    }

    public void finish(Database.BatchableContext context) {
        TCMReportConfig config = new TCMReportConfig();

        // Refresh yesterday's attribution before the digest is written, so the summary reports
        // real open and download counts, and any link past its cap is closed.
        try {
            auditResult = TCMReadmissionLinkAudit.sync();
            // A link that reached its cap but could not be closed is still open. That belongs
            // in front of a person, not in a debug log.
            failures.addAll(auditResult.closeFailures);
        } catch (Exception e) {
            failures.add('Link audit sync failed: ' + e.getMessage());
        }

        List<String> recipients = digestRecipientsFor(config);
        if (recipients.isEmpty()) {
            return;
        }

        Messaging.SingleEmailMessage digest = new Messaging.SingleEmailMessage();
        digest.setToAddresses(recipients);
        digest.setSubject(
            (isSandbox ? '[SANDBOX] ' : '') +
            'Readmissions Report run - ' + fileDateToken +
            ' - ' + emailsSent + ' sent, ' + skipped.size() + ' skipped'
        );
        // Same sender as the facility mail, so the digest is not the odd one out arriving
        // from a personal address. Resolved before the body is built so any sender problem
        // it records is included in this digest rather than the next one.
        Id orgWideId = resolveOrgWideAddressId(config);
        if (orgWideId != null) {
            digest.setOrgWideEmailAddressId(orgWideId);
        }
        // No global Cc here on purpose. That Cc is for the facility correspondence -- the
        // messages a facility actually receives -- and the digest is an internal run summary
        // naming every facility and address. Digest_Recipients__c decides who reads it.
        digest.setHtmlBody(digestBody(config));
        digest.setSaveAsActivity(false);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ digest }, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'TCM digest send failed: ' + e.getMessage());
        }
    }

    /**
     * The digest list holds client addresses. A sandbox run must never reach them, so in a
     * sandbox the digest follows the same redirect as the facility mail, and is dropped
     * entirely if no redirect is configured. Same rule the recipient resolver applies.
     */
    @TestVisible
    private List<String> digestRecipientsFor(TCMReportConfig config) {
        if (!isSandbox) {
            return config.digestRecipients();
        }
        // Same separators the recipient resolver accepts, so one redirect setting can name
        // more than one tester.
        List<String> redirects = new List<String>();
        String redirect = config.sandboxRedirect();
        if (String.isBlank(redirect)) {
            return redirects;
        }
        Set<String> seen = new Set<String>();
        for (String part : redirect.split('[;,]')) {
            String trimmed = part.trim().toLowerCase();
            if (String.isNotBlank(trimmed) && seen.add(trimmed)) {
                redirects.add(trimmed);
            }
        }
        return redirects;
    }

    public class ChunkResult {
        public List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        public List<String> skipped = new List<String>();
        public List<String> failures = new List<String>();
        /** One line per message built: facility, rows, recipients, link expiry. Feeds the digest. */
        public List<String> sent = new List<String>();
        public Integer rowsReported = 0;
        public Boolean redirected = false;
    }

    /**
     * Everything interesting about a chunk, with no sending. Kept separate so the query,
     * grouping and skip rules can be asserted directly without the batch machinery.
     */
    @TestVisible
    private ChunkResult buildForFacilities(List<Facility__c> facilities) {
        ChunkResult result = new ChunkResult();
        if (facilities == null || facilities.isEmpty()) {
            return result;
        }

        Map<Id, Facility__c> facilityById = new Map<Id, Facility__c>(facilities);
        Map<Id, List<Hospital_Admission__c>> admissionsByFacility = groupByFacility(facilityById.keySet());
        if (admissionsByFacility.isEmpty()) {
            return result;
        }

        TCMReportConfig config = new TCMReportConfig();
        TCMReadmissionCsvBuilder csv = new TCMReadmissionCsvBuilder(timeZoneName);
        TCMReadmissionRecipientResolver resolver = new TCMReadmissionRecipientResolver(config, isSandbox);
        Id orgWideId = resolveOrgWideAddressId(config);
        Boolean asLink = config.deliverAsLink();

        // First pass: decide who is sendable and build every CSV. Iterating the facility list
        // rather than the map keeps output order stable.
        List<Facility__c> sendable = new List<Facility__c>();
        Map<Id, TCMReadmissionRecipientResolver.Resolution> recipientsByFacility =
            new Map<Id, TCMReadmissionRecipientResolver.Resolution>();
        Map<Id, Blob> csvByFacility = new Map<Id, Blob>();
        Map<Id, String> fileNameByFacility = new Map<Id, String>();
        List<TCMReadmissionLinkPublisher.Request> linkRequests =
            new List<TCMReadmissionLinkPublisher.Request>();

        for (Facility__c facility : facilities) {
            List<Hospital_Admission__c> rows = admissionsByFacility.get(facility.Id);
            if (rows == null || rows.isEmpty()) {
                continue;
            }

            TCMReadmissionRecipientResolver.Resolution recipients = resolver.resolve(facility);
            if (!recipients.isSendable()) {
                result.skipped.add(
                    facility.Name + ' (' + rows.size() + ' row(s) unsent): ' + recipients.skipReason
                );
                continue;
            }

            String fileName = csv.fileName(facility.Name, fileDateToken);
            Blob body = csv.build(rows);
            sendable.add(facility);
            recipientsByFacility.put(facility.Id, recipients);
            csvByFacility.put(facility.Id, body);
            fileNameByFacility.put(facility.Id, fileName);
            if (asLink) {
                // The report site serves a PDF, rendered here before any DML in this
                // transaction, which getContentAsPDF() requires.
                TCMReadmissionLinkPublisher.Request request =
                    new TCMReadmissionLinkPublisher.Request(
                        facility.Id, facility.Name, pdfFileName(fileName),
                        renderPdf(facility.Id), windowLastCoveredDate
                    );
                // One link per mailbox that can actually open it, so an open attributes to a
                // person rather than only to a facility.
                //
                // On a redirected sandbox run the deliverable mailboxes are the testers, so
                // they get the links and the real facility contact is carried alongside as
                // Intended For. Issuing links to contacts nobody can open would make the
                // sandbox prove nothing about attribution.
                if (recipients.redirected) {
                    String representing = String.join(orderedRecipients(recipients), ', ');
                    for (String tester : recipients.toAddresses) {
                        request.recipients.add(new TCMReadmissionLinkPublisher.Recipient(
                            tester, 'Sandbox Tester', representing
                        ));
                    }
                } else {
                    for (String address : orderedRecipients(recipients)) {
                        request.recipients.add(new TCMReadmissionLinkPublisher.Recipient(
                            address, recipients.roleFor(address)
                        ));
                    }
                }
                linkRequests.add(request);
            }
        }

        // Second pass: one bulk publish for the whole chunk, then one message per facility.
        Map<Id, TCMReadmissionLinkPublisher.Published> links = asLink
            ? new TCMReadmissionLinkPublisher(config).publish(linkRequests)
            : new Map<Id, TCMReadmissionLinkPublisher.Published>();

        for (Facility__c facility : sendable) {
            List<Hospital_Admission__c> rows = admissionsByFacility.get(facility.Id);
            TCMReadmissionRecipientResolver.Resolution recipients = recipientsByFacility.get(facility.Id);

            if (!asLink) {
                // Attachment mode is unchanged: one message carrying the CSV, To plus CC.
                result.messages.add(buildMessage(
                    facility, rows, recipients, orgWideId,
                    csvByFacility.get(facility.Id), fileNameByFacility.get(facility.Id), null, null
                ));
                result.sent.add(describeSent(facility, rows.size(), recipients, null, null));
                result.rowsReported += rows.size();
                result.redirected = result.redirected || recipients.redirected;
                continue;
            }

            TCMReadmissionLinkPublisher.Published published = links.get(facility.Id);
            if (published == null || !published.hasAnyUsable()) {
                // Never send an email pointing at a link that does not exist.
                String why = published == null
                    ? 'no publish result'
                    : (published.failure != null ? published.failure : 'no usable link');
                result.failures.add(
                    facility.Name + ' (' + rows.size() + ' row(s) unsent): ' + why
                );
                continue;
            }
            if (published.failure != null) {
                // Partial problem, such as a missing attribution row. Report it but still send.
                result.failures.add(facility.Name + ': ' + published.failure);
            }

            // One message per recipient, each carrying only its own link. This also removes the
            // multi-tenant Cc that Exchange Online rejects with 4.5.3. On a redirected run the
            // deliverable addresses are the testers, which is who holds the links.
            Boolean countedRows = false;
            List<String> deliverTo = recipients.redirected
                ? recipients.toAddresses
                : orderedRecipients(recipients);
            for (String address : deliverTo) {
                TCMReadmissionLinkPublisher.Issued issued = published.byEmail.get(address);
                if (issued == null || !issued.isUsable()) {
                    result.failures.add(
                        facility.Name + ': no link for ' + address +
                        (issued != null && issued.failure != null ? ' (' + issued.failure + ')' : '')
                    );
                    continue;
                }
                result.messages.add(buildMessage(
                    facility, rows, recipients, orgWideId, null,
                    fileNameByFacility.get(facility.Id), issued, address
                ));
                result.sent.add(describeSent(facility, rows.size(), recipients, issued, address));
                if (!countedRows) {
                    result.rowsReported += rows.size();
                    countedRows = true;
                }
                result.redirected = result.redirected || recipients.redirected;
            }
        }
        return result;
    }

    /**
     * Cc list with anything already in To removed, so nobody is both. Exchange Online treats a
     * duplicated address as a delivery fault, which is the same 4.5.3 family of problem the
     * one-message-per-recipient change was made to avoid.
     */
    private static List<String> dedupe(List<String> cc, List<String> toAddresses) {
        Set<String> already = new Set<String>();
        if (toAddresses != null) {
            for (String address : toAddresses) {
                if (String.isNotBlank(address)) {
                    already.add(address.trim().toLowerCase());
                }
            }
        }
        List<String> result = new List<String>();
        for (String address : cc) {
            String trimmed = String.isBlank(address) ? null : address.trim().toLowerCase();
            if (trimmed != null && already.add(trimmed)) {
                result.add(trimmed);
            }
        }
        return result;
    }

    /** Intended addresses, primary first, de-duplicated. */
    private static List<String> orderedRecipients(
        TCMReadmissionRecipientResolver.Resolution recipients
    ) {
        List<String> ordered = new List<String>();
        Set<String> seen = new Set<String>();
        for (String address : recipients.intendedTo) {
            if (String.isNotBlank(address) && seen.add(address)) {
                ordered.add(address);
            }
        }
        for (String address : recipients.intendedCc) {
            if (String.isNotBlank(address) && seen.add(address)) {
                ordered.add(address);
            }
        }
        return ordered;
    }

    private String describeSent(
        Facility__c facility,
        Integer rowCount,
        TCMReadmissionRecipientResolver.Resolution recipients,
        TCMReadmissionLinkPublisher.Issued issued,
        String intendedAddress
    ) {
        if (issued == null) {
            // Attachment mode: one line for the whole facility.
            String entry = facility.Name + ' (' + rowCount + ' row(s)) to ' +
                String.join(recipients.toAddresses, ', ');
            if (!recipients.ccAddresses.isEmpty()) {
                entry += ', cc ' + String.join(recipients.ccAddresses, ', ');
            }
            if (recipients.redirected) {
                entry += ' [redirected]';
            }
            return entry;
        }
        // Link mode: one line per recipient, naming the address the link was issued to.
        String entry = facility.Name + ' (' + rowCount + ' row(s)) to ' + intendedAddress;
        if (String.isNotBlank(issued.role)) {
            entry += ' [' + issued.role + ']';
        }
        if (recipients.redirected && String.isNotBlank(issued.intendedFor)) {
            entry += ' [sandbox, representing ' + issued.intendedFor + ']';
        }
        if (issued.expiresAt != null) {
            entry += ', own link expires ' + formatLocal(issued.expiresAt);
        }
        return entry;
    }

    private String formatLocal(Datetime value) {
        return value == null ? '' : value.format('EEEE, MMMM d, yyyy h:mm a z', timeZoneName);
    }

    /**
     * Renders the facility's report page to PDF. The page runs as a separate request, so the
     * window travels as URL parameters and the controller re-queries with the batch's filters.
     * getContentAsPDF() is unavailable in test context, so tests get a placeholder blob.
     */
    private Blob renderPdf(Id facilityId) {
        PageReference page = Page.TCMReadmissionReportPdf;
        Map<String, String> params = page.getParameters();
        params.put(TCMReadmissionReportPdfController.PARAM_FACILITY, facilityId);
        // Only the report date travels. The page derives the window from it with the same rule
        // this job used, so the URL cannot widen the range it covers.
        params.put(
            TCMReadmissionReportPdfController.PARAM_REPORT_DATE,
            String.valueOf(windowLastCoveredDate)
        );
        if (Test.isRunningTest()) {
            return Blob.valueOf('%PDF-1.4 test placeholder');
        }
        return page.getContentAsPDF();
    }

    private static String pdfFileName(String csvFileName) {
        String base = csvFileName == null ? 'Readmissions' : csvFileName;
        if (base.endsWithIgnoreCase('.csv')) {
            base = base.left(base.length() - 4);
        }
        return base + '.pdf';
    }

    private Map<Id, List<Hospital_Admission__c>> groupByFacility(Set<Id> facilityIds) {
        Map<Id, List<Hospital_Admission__c>> grouped = new Map<Id, List<Hospital_Admission__c>>();

        // One definition of the clinical scope, shared with the resend and the PDF page, so the
        // three can never report different rows for the same facility and day.
        for (Hospital_Admission__c admission : TCMReadmissionAdmissionScope.find(
            facilityIds, windowStartUtc, windowEndUtc, new TCMReportConfig()
        )) {
            Id facilityId = admission.Patient__r.Facility__c;
            if (!grouped.containsKey(facilityId)) {
                grouped.put(facilityId, new List<Hospital_Admission__c>());
            }
            grouped.get(facilityId).add(admission);
        }
        return grouped;
    }

    /**
     * attachmentBody is null in Link mode; link is null in Attachment mode. Exactly one of the
     * two is populated for any message that gets built.
     */
    private Messaging.SingleEmailMessage buildMessage(
        Facility__c facility,
        List<Hospital_Admission__c> rows,
        TCMReadmissionRecipientResolver.Resolution recipients,
        Id orgWideId,
        Blob attachmentBody,
        String fileName,
        TCMReadmissionLinkPublisher.Issued issued,
        String intendedAddress
    ) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        List<String> cc = new List<String>();
        if (issued == null) {
            // Attachment mode keeps the original To plus Cc shape.
            message.setToAddresses(recipients.toAddresses);
            cc.addAll(recipients.ccAddresses);
        } else {
            // Link mode: this recipient only, so the link stays attributable to one mailbox.
            message.setToAddresses(new List<String>{ intendedAddress });
        }
        // The global Cc rides on the message rather than becoming a recipient of its own, so
        // it is not issued a link and does not appear in the digest as another send.
        cc.addAll(globalCc);
        if (!cc.isEmpty()) {
            message.setCcAddresses(dedupe(cc, message.getToAddresses()));
        }
        TCMReadmissionEmailBuilder builder = emailBuilder();
        message.setSubject(builder.subjectFor(facility));
        message.setHtmlBody(builder.bodyFor(
            facility, rows.size(), recipients.redirected, issued, intendedAddress, false
        ));
        message.setSaveAsActivity(false);
        if (orgWideId != null) {
            message.setOrgWideEmailAddressId(orgWideId);
        }
        if (attachmentBody != null) {
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(fileName);
            attachment.setBody(attachmentBody);
            attachment.setContentType('text/csv');
            message.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
        }
        return message;
    }

    private TCMReadmissionEmailBuilder emailBuilder() {
        return new TCMReadmissionEmailBuilder(
            new TCMReportConfig(), timeZoneName, windowDescription, fileDateToken
        );
    }

    private String digestBody(TCMReportConfig config) {
        String html =
            '<div style="font-family: Arial, sans-serif; color: #333;">' +
                '<p><strong>Readmissions Report run</strong></p>' +
                '<ul>' +
                    '<li>Window: ' + escape(windowDescription) + ' (' + escape(timeZoneName) + ')</li>' +
                    '<li>Facilities scanned: ' + facilitiesScanned + '</li>' +
                    '<li>Emails sent: ' + emailsSent + '</li>' +
                    '<li>Admissions reported: ' + rowsReported + '</li>' +
                    '<li>Facilities skipped: ' + skipped.size() + '</li>' +
                    '<li>Rows counted: ' +
                        escape(TCMReadmissionAdmissionScope.describe(config)) + '</li>' +
                    '<li>Facilities in scope: enrolled parent company' +
                        (requireFacilityTcm ? ', facility TCM ticked' : '') +
                        ', not excluded from TCM reporting.</li>' +
                '</ul>';

        if (anyRedirected) {
            html +=
                '<p style="color:#a00;"><strong>Sandbox run</strong> - all facility mail was ' +
                'redirected and no facility received anything.</p>';
        }

        // Itemised so the digest recipient sees every facility that was written to, how many
        // rows it had and where it went, rather than a bare total.
        if (!sent.isEmpty()) {
            html += '<p><strong>Facility emails (' + sent.size() + '):</strong></p>' + htmlList(sent);
        }

        if (auditResult != null) {
            html +=
                '<p><strong>Link activity since the last run</strong></p><ul>' +
                    '<li>Links tracked: ' + auditResult.linksExamined + '</li>' +
                    '<li>Opens recorded: ' + auditResult.opens + '</li>' +
                    '<li>Downloads recorded: ' + auditResult.downloads + '</li>' +
                    '<li>Links closed on the view cap: ' + auditResult.cappedEarly + '</li>' +
                    '<li>Links locked after wrong codes: ' + auditResult.locked + '</li>' +
                '</ul>' +
                '<p style="font-size:12px;color:#666;">Per recipient detail is on the ' +
                'Readmission Report Links related list of each Facility.</p>';
        }

        List<String> gaps = config.unconfiguredPlaceholders();
        if (!gaps.isEmpty()) {
            html += '<p><strong>Config still on placeholder values:</strong></p>' + htmlList(gaps);
        }
        if (!failures.isEmpty()) {
            html += '<p><strong>Send failures:</strong></p>' + htmlList(failures);
        }
        if (!skipped.isEmpty()) {
            html +=
                '<p><strong>Facilities with admissions but no deliverable address:</strong></p>' +
                htmlList(skipped);
        }
        return html + '</div>';
    }

    private void send(List<Messaging.SingleEmailMessage> messages, List<String> sentLines) {
        try {
            // Partial success, so one bad address cannot take down a whole chunk.
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(messages, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    emailsSent++;
                    if (sentLines != null && i < sentLines.size()) {
                        sent.add(sentLines[i]);
                    }
                } else {
                    failures.add(describeFailure(messages[i], results[i]));
                }
            }
        } catch (Exception e) {
            failures.add('sendEmail threw: ' + e.getMessage());
        }
    }

    private static String describeFailure(
        Messaging.SingleEmailMessage message,
        Messaging.SendEmailResult result
    ) {
        List<String> reasons = new List<String>();
        for (Messaging.SendEmailError error : result.getErrors()) {
            reasons.add(error.getMessage());
        }
        String target = message.getToAddresses() == null
            ? '(no recipient)'
            : String.join(message.getToAddresses(), ', ');
        return target + ': ' + String.join(reasons, '; ');
    }

    /**
     * Resolved once per chunk rather than per message. A configured address that is missing
     * or not yet verified is reported in the digest and the mail goes out as the running
     * user instead. Setting an unverified address on the message makes Salesforce reject the
     * whole send, which would silence the report over a setup gap. Reported once per chunk.
     */
    private Id resolveOrgWideAddressId(TCMReportConfig config) {
        String address = config.orgWideAddressFor(isSandbox);
        if (address == null) {
            return null;
        }
        List<OrgWideEmailAddress> found = [
            SELECT Id, IsVerified FROM OrgWideEmailAddress WHERE Address = :address LIMIT 1
        ];
        if (found.isEmpty()) {
            noteOnce(
                'From_Org_Wide_Address__c is set to ' + address +
                ' but no matching Org-Wide Email Address exists; sending as the running user.'
            );
            return null;
        }
        if (found[0].IsVerified != true) {
            noteOnce(
                'Org-Wide Email Address ' + address + ' exists but has not been verified. ' +
                'Someone with that mailbox must click its verification email. ' +
                'Sending as the running user until then.'
            );
            return null;
        }
        return found[0].Id;
    }

    /** Config problems recur every chunk; the digest should say them once. */
    private void noteOnce(String failure) {
        if (!failures.contains(failure)) {
            failures.add(failure);
        }
    }

    private static String htmlList(List<String> items) {
        List<String> escaped = new List<String>();
        for (String item : items) {
            escaped.add('<li>' + escape(item) + '</li>');
        }
        return '<ul>' + String.join(escaped, '') + '</ul>';
    }

    private static String escape(String value) {
        return value == null ? '' : value.escapeHtml4();
    }
}