/**
 * On-demand resend of a single facility's readmission report.
 *
 * A link expires by design, and the unavailable page offers no way back, so the only route
 * to a fresh link used to be a reply to the email and a manual rerun of the daily job for
 * every facility. This does the same work for one facility, from the Facility record,
 * and issues a brand new link per recipient rather than extending the old one. The previous
 * link to the same address is closed as superseded by the publisher.
 *
 * Every reissue writes its own Readmission_Report_Link__c row, so the accounting of
 * disclosures shows each delivery separately instead of one row being edited over time.
 *
 * Synchronous on purpose: the person clicking the button needs to know whether it went out.
 * Rendering the PDF happens before any DML, which getContentAsPDF() requires.
 */
public with sharing class TCMReadmissionResend {

    /**
     * Test seam. Whether the org is a sandbox decides where mail goes, and asserting on the
     * recipient list has to be independent of which org the suite happens to run in.
     */
    @TestVisible
    private static Boolean sandboxOverride;

    /**
     * Cc list with anything already in To removed, so nobody is both. Exchange Online treats a
     * duplicated address as a delivery fault.
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

    /** One delivery, as the dialog reports it back. */
    public class Delivery {
        @AuraEnabled public String email;
        @AuraEnabled public String role;
        @AuraEnabled public String expiresAt;
        @AuraEnabled public String intendedFor;
        @AuraEnabled public Boolean sent = false;
        @AuraEnabled public String problem;
    }

    public class Result {
        @AuraEnabled public Boolean sendable = false;
        @AuraEnabled public Boolean sent = false;
        @AuraEnabled public String facilityName;
        @AuraEnabled public String windowLabel;
        @AuraEnabled public Integer rowCount = 0;
        @AuraEnabled public Integer expiryHours = 0;
        @AuraEnabled public Integer maxOpens = 0;
        @AuraEnabled public Boolean redirected = false;
        @AuraEnabled public String blockedReason;
        @AuraEnabled public String summary;
        /** True when the links point at the PDF already filed on the record. */
        @AuraEnabled public Boolean reusedStoredFile = false;
        @AuraEnabled public List<Delivery> deliveries = new List<Delivery>();
        @AuraEnabled public List<String> problems = new List<String>();
    }

    /**
     * What a resend would do, with no DML, no PDF render and no mail. Drives the dialog the
     * user confirms, so nobody sends a report to an address they did not expect.
     */
    @AuraEnabled(cacheable=false)
    public static Result preview(Id facilityId) {
        try {
            return describe(facilityId, false);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Issues a new link per recipient and sends it. */
    @AuraEnabled(cacheable=false)
    public static Result send(Id facilityId) {
        try {
            return describe(facilityId, true);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @TestVisible
    private static Result describe(Id facilityId, Boolean actuallySend) {
        Result result = new Result();
        if (facilityId == null) {
            result.blockedReason = 'No facility was supplied.';
            return result;
        }
        if (!Schema.SObjectType.Facility__c.isAccessible()) {
            result.blockedReason = 'You do not have access to Facility records.';
            return result;
        }

        TCMReportConfig config = new TCMReportConfig();
        Boolean isSandbox = sandboxOverride != null
            ? sandboxOverride
            : [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        TCMReadmissionWindow window = new TCMReadmissionWindow(config.timeZoneName());

        List<Facility__c> facilities = [
            SELECT Id, Name, Admin_Email__c, DON_Email__c, Address__StateCode__s,
                   TCM__c, Exclude_from_TCM_Reporting__c,
                   Parent_Company__c, Parent_Company__r.Name, Parent_Company__r.TCM__c
            FROM Facility__c
            WHERE Id = :facilityId
            LIMIT 1
        ];
        if (facilities.isEmpty()) {
            result.blockedReason = 'Facility not found.';
            return result;
        }
        Facility__c facility = facilities[0];

        // The button must not be able to send for a facility the nightly job would never pick
        // up. Without this a resend could deliver a readmissions report to a facility that is
        // not enrolled in TCM, or one deliberately excluded from this reporting.
        String outOfScope = scopeProblem(facility, config);
        if (outOfScope != null) {
            result.facilityName = facility.Name;
            result.blockedReason = outOfScope;
            return result;
        }
        result.facilityName = facility.Name;
        result.windowLabel = window.describe();
        result.expiryHours = config.linkExpiryHours();
        result.maxOpens = config.maxOpens();

        // Same filters as the daily job, from the one shared definition, so a resend cannot
        // report a different set of rows than the original email did.
        List<Hospital_Admission__c> rows = TCMReadmissionAdmissionScope.find(
            facilityId, window.startUtc, window.endUtc, config
        );
        result.rowCount = rows.size();
        if (rows.isEmpty()) {
            result.blockedReason =
                'No readmissions for this facility during ' + window.describe() +
                ', so there is no report to resend.';
            return result;
        }

        TCMReadmissionRecipientResolver.Resolution recipients =
            new TCMReadmissionRecipientResolver(config, isSandbox).resolve(facility);
        result.redirected = recipients.redirected;
        if (!recipients.isSendable()) {
            result.blockedReason = recipients.skipReason;
            return result;
        }

        List<String> intended = orderedRecipients(recipients);
        List<String> deliverTo = recipients.redirected ? recipients.toAddresses : intended;
        String representing = String.join(intended, ', ');

        for (String address : deliverTo) {
            Delivery delivery = new Delivery();
            delivery.email = address;
            delivery.role = recipients.redirected ? 'Sandbox Tester' : recipients.roleFor(address);
            delivery.intendedFor = recipients.redirected ? representing : address;
            result.deliveries.add(delivery);
        }
        result.sendable = true;

        if (!actuallySend) {
            result.summary = result.rowCount + ' row(s) ready to send to ' +
                result.deliveries.size() + ' recipient(s).';
            return result;
        }

        // ---- from here on the resend actually happens ------------------------------------
        if (!Schema.SObjectType.Readmission_Report_Link__c.isCreateable()) {
            result.sendable = false;
            result.blockedReason =
                'You do not have permission to create Readmission Report Link records, ' +
                'which is where the delivery is logged.';
            return result;
        }

        String fileName = new TCMReadmissionCsvBuilder(window.timeZoneName)
            .fileName(facility.Name, window.fileDateToken());
        Boolean asLink = config.deliverAsLink();
        TCMReadmissionEmailBuilder builder = new TCMReadmissionEmailBuilder(
            config, window.timeZoneName, window.describe(), window.fileDateToken()
        );
        Id orgWideId = orgWideAddressId(config, isSandbox, result.problems);
        // Same rule as the daily job: a true Cc that is issued no link of its own, and never
        // used in a sandbox, where it would be the one address still reaching a real mailbox.
        List<String> globalCc = isSandbox ? new List<String>() : config.globalCc();

        if (!asLink) {
            // Attachment mode, kept working so the config switch means the same thing here as
            // it does in the daily job.
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setToAddresses(recipients.toAddresses);
            List<String> cc = new List<String>(recipients.ccAddresses);
            cc.addAll(globalCc);
            if (!cc.isEmpty()) {
                message.setCcAddresses(dedupe(cc, message.getToAddresses()));
            }
            message.setSubject(builder.subjectFor(facility));
            message.setHtmlBody(
                builder.bodyFor(facility, rows.size(), recipients.redirected, null, null, true)
            );
            message.setSaveAsActivity(false);
            if (orgWideId != null) {
                message.setOrgWideEmailAddressId(orgWideId);
            }
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(fileName);
            attachment.setBody(new TCMReadmissionCsvBuilder(window.timeZoneName).build(rows));
            attachment.setContentType('text/csv');
            message.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
            // One message carries the report to every recipient here, so the single send result
            // decides all of them. Pairing them positionally, as link mode does, would mark
            // everyone after the first as unsent when they had in fact received it.
            dispatchShared(message, result);
            return result;
        }

        // Prefer the PDF already filed on the facility by the daily run. Reissuing links
        // against the stored version keeps one file per report however many times it is
        // resent, and avoids rendering a PDF, which is a callout and not always permitted in
        // the request the button runs in.
        String title = pdfTitle(fileName);
        Id storedVersionId = storedVersionFor(facility.Id, title);
        TCMReadmissionLinkPublisher.Request request;
        if (storedVersionId != null) {
            result.reusedStoredFile = true;
            request = new TCMReadmissionLinkPublisher.Request(
                facility.Id, facility.Name, pdfFileName(fileName), null,
                window.lastCoveredDate()
            );
            request.existingContentVersionId = storedVersionId;
        } else {
            // No stored report for that day, so render one. Before any DML, which
            // getContentAsPDF() requires.
            Blob pdf;
            try {
                pdf = renderPdf(facility.Id, window);
            } catch (Exception e) {
                result.sendable = false;
                result.blockedReason =
                    'No report file is stored for ' + window.describe() + ' and one could not ' +
                    'be generated here (' + e.getMessage() + '). Run the daily job for this ' +
                    'window and then resend.';
                return result;
            }
            request = new TCMReadmissionLinkPublisher.Request(
                facility.Id, facility.Name, pdfFileName(fileName), pdf, window.lastCoveredDate()
            );
        }
        for (Delivery delivery : result.deliveries) {
            request.recipients.add(new TCMReadmissionLinkPublisher.Recipient(
                delivery.email, delivery.role, delivery.intendedFor
            ));
        }

        Map<Id, TCMReadmissionLinkPublisher.Published> published =
            new TCMReadmissionLinkPublisher(config)
                .publish(new List<TCMReadmissionLinkPublisher.Request>{ request });
        TCMReadmissionLinkPublisher.Published issuedForFacility = published.get(facility.Id);

        if (issuedForFacility == null || !issuedForFacility.hasAnyUsable()) {
            // Never send an email pointing at a link that does not exist.
            result.sendable = false;
            result.blockedReason = issuedForFacility == null
                ? 'The link could not be created, so nothing was sent.'
                : (issuedForFacility.failure != null
                    ? issuedForFacility.failure
                    : 'No usable link was created, so nothing was sent.');
            return result;
        }
        if (issuedForFacility.failure != null) {
            result.problems.add(issuedForFacility.failure);
        }

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Delivery> ordered = new List<Delivery>();
        for (Delivery delivery : result.deliveries) {
            TCMReadmissionLinkPublisher.Issued issued =
                issuedForFacility.byEmail.get(delivery.email);
            if (issued == null || !issued.isUsable()) {
                delivery.problem = issued != null && issued.failure != null
                    ? issued.failure
                    : 'No link was issued for this address.';
                result.problems.add(delivery.email + ': ' + delivery.problem);
                continue;
            }
            delivery.expiresAt = builder.formatLocal(issued.expiresAt);

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            // One recipient per message, so the open stays attributable to one mailbox.
            message.setToAddresses(new List<String>{ delivery.email });
            if (!globalCc.isEmpty()) {
                message.setCcAddresses(dedupe(globalCc, message.getToAddresses()));
            }
            message.setSubject(builder.subjectFor(facility));
            message.setHtmlBody(builder.bodyFor(
                facility, rows.size(), recipients.redirected, issued, delivery.email, true
            ));
            message.setSaveAsActivity(false);
            if (orgWideId != null) {
                message.setOrgWideEmailAddressId(orgWideId);
            }
            messages.add(message);
            ordered.add(delivery);
        }

        if (messages.isEmpty()) {
            result.sendable = false;
            result.blockedReason = 'No usable link was created, so nothing was sent.';
            return result;
        }
        dispatch(messages, ordered, result);
        refreshAudit(result);
        return result;
    }

    /**
     * Refreshes the attribution counts and applies the view cap.
     *
     * Without this the cap would depend entirely on the nightly job: links issued by this button
     * would go uncounted and uncapped until the next run, and not at all while the job is off.
     * Failure here must not undo a send that already happened, so it is reported, not thrown.
     */
    private static void refreshAudit(Result result) {
        try {
            TCMReadmissionLinkAudit.Result audit = TCMReadmissionLinkAudit.sync();
            result.problems.addAll(audit.closeFailures);
        } catch (Exception e) {
            result.problems.add('The link audit could not be refreshed: ' + e.getMessage());
        }
    }

    /** Sends one message addressed to several recipients, and gives them all its outcome. */
    private static void dispatchShared(Messaging.SingleEmailMessage message, Result result) {
        Boolean sent = false;
        String problem;
        try {
            List<Messaging.SendEmailResult> sendResults =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ message }, false);
            sent = !sendResults.isEmpty() && sendResults[0].isSuccess();
            if (!sent && !sendResults.isEmpty()) {
                List<String> reasons = new List<String>();
                for (Messaging.SendEmailError error : sendResults[0].getErrors()) {
                    reasons.add(error.getMessage());
                }
                problem = String.join(reasons, '; ');
            }
        } catch (Exception e) {
            problem = 'sendEmail threw: ' + e.getMessage();
        }
        for (Delivery delivery : result.deliveries) {
            delivery.sent = sent;
            delivery.problem = sent ? null : problem;
        }
        result.sent = sent;
        if (problem != null) {
            result.problems.add(problem);
        }
        result.summary = sent
            ? 'Sent to ' + result.deliveries.size() + ' recipient(s) in one email with the ' +
              'report attached.'
            : 'Nothing was sent.';
    }

    /** Sends with partial success, and marks each Delivery with what happened to it. */
    private static void dispatch(
        List<Messaging.SingleEmailMessage> messages,
        List<Delivery> ordered,
        Result result
    ) {
        Integer succeeded = 0;
        try {
            List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(messages, false);
            for (Integer i = 0; i < sendResults.size(); i++) {
                Delivery delivery = i < ordered.size() ? ordered[i] : null;
                if (sendResults[i].isSuccess()) {
                    succeeded++;
                    if (delivery != null) {
                        delivery.sent = true;
                    }
                    continue;
                }
                List<String> reasons = new List<String>();
                for (Messaging.SendEmailError error : sendResults[i].getErrors()) {
                    reasons.add(error.getMessage());
                }
                String why = String.join(reasons, '; ');
                if (delivery != null) {
                    delivery.problem = why;
                }
                result.problems.add(
                    (delivery == null ? '(unknown recipient)' : delivery.email) + ': ' + why
                );
            }
        } catch (Exception e) {
            result.problems.add('sendEmail threw: ' + e.getMessage());
        }
        result.sent = succeeded > 0;
        result.summary = succeeded == 0
            ? 'Nothing was sent.'
            : 'Sent to ' + succeeded + ' recipient(s), each with their own new link.';
    }

    /**
     * Why this facility is out of scope for the daily job, or null when it is in scope. Mirrors
     * the locator's WHERE clause, so the button and the job agree on who gets a report.
     */
    private static String scopeProblem(Facility__c facility, TCMReportConfig config) {
        if (facility.Exclude_from_TCM_Reporting__c == true) {
            return 'This facility is excluded from TCM reporting, so no report is sent for it.';
        }
        if (facility.Parent_Company__r == null || facility.Parent_Company__r.TCM__c != true) {
            return 'This facility\'s parent company is not enrolled in TCM, so no report is ' +
                'sent for it.';
        }
        if (config.requireFacilityTcm() && facility.TCM__c != true) {
            return 'TCM is not ticked on this facility, so no report is sent for it.';
        }
        return null;
    }

    /** Intended addresses, primary first, de-duplicated. Mirrors the daily job's ordering. */
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

    /**
     * A configured sender that is missing or unverified is reported and the mail goes out as
     * the running user, because setting an unverified address makes Salesforce reject the
     * whole send. Same rule the daily job applies.
     */
    private static Id orgWideAddressId(
        TCMReportConfig config,
        Boolean isSandbox,
        List<String> problems
    ) {
        String address = config.orgWideAddressFor(isSandbox);
        if (String.isBlank(address)) {
            return null;
        }
        List<OrgWideEmailAddress> found = [
            SELECT Id, IsVerified FROM OrgWideEmailAddress WHERE Address = :address LIMIT 1
        ];
        if (found.isEmpty()) {
            problems.add(
                'The configured sending address ' + address + ' does not exist as an ' +
                'Org-Wide Email Address. Sent as you instead.'
            );
            return null;
        }
        if (found[0].IsVerified != true) {
            problems.add(
                'The sending address ' + address + ' has not been verified yet. Sent as you ' +
                'instead.'
            );
            return null;
        }
        return found[0].Id;
    }

    /** Same page and parameters the daily job renders, so both produce the same document. */
    private static Blob renderPdf(Id facilityId, TCMReadmissionWindow window) {
        PageReference page = Page.TCMReadmissionReportPdf;
        Map<String, String> params = page.getParameters();
        params.put(TCMReadmissionReportPdfController.PARAM_FACILITY, facilityId);
        params.put(
            TCMReadmissionReportPdfController.PARAM_REPORT_DATE,
            String.valueOf(window.lastCoveredDate())
        );
        if (Test.isRunningTest()) {
            return Blob.valueOf('%PDF-1.4 test placeholder');
        }
        return page.getContentAsPDF();
    }

    /**
     * The latest version of the report already filed on this facility, or null. Titles are
     * what the publisher writes: the file name with its extension removed.
     */
    private static Id storedVersionFor(Id facilityId, String title) {
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :facilityId
        ]) {
            documentIds.add(link.ContentDocumentId);
        }
        if (documentIds.isEmpty()) {
            return null;
        }
        List<ContentVersion> versions = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
              AND IsLatest = true
              AND Title = :title
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0].Id;
    }

    /** Same title the publisher gives the stored file. */
    private static String pdfTitle(String csvFileName) {
        String base = pdfFileName(csvFileName);
        return base.endsWithIgnoreCase('.pdf') ? base.left(base.length() - 4) : base;
    }

    private static String pdfFileName(String csvFileName) {
        String base = csvFileName == null ? 'Readmissions' : csvFileName;
        if (base.endsWithIgnoreCase('.csv')) {
            base = base.left(base.length() - 4);
        }
        return base + '.pdf';
    }
}