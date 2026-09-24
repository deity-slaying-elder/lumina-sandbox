/**
 * Totals and housekeeping over the per-recipient link rows.
 *
 * The report site writes each open and each download onto the row at the moment it happens,
 * so nothing here is derived from a platform log any more. What is left for the job: add up
 * the recent rows for the digest, and close any row that has reached the open cap but was
 * left open, which only happens when a recipient stopped exactly at the cap and never came
 * back for the refused open that would have closed it.
 *
 * Called from the batch's finish() and after an on-demand resend. Safe to run on demand.
 */
public with sharing class TCMReadmissionLinkAudit {

    /** How far back to report. Links live 24 to 72 hours, so a fortnight is ample. */
    @TestVisible
    private static final Integer LOOKBACK_DAYS = 14;

    public class Result {
        public Integer linksExamined = 0;
        public Integer linksUpdated = 0;
        public Integer opens = 0;
        public Integer downloads = 0;
        /** Links closed because they reached the configured open cap. */
        public Integer cappedEarly = 0;
        /** Links locked by too many wrong codes or too many code requests. */
        public Integer locked = 0;
        /**
         * Links that reached the cap but could not be closed. These are still open, so they
         * belong in the digest rather than in a debug log.
         */
        public List<String> closeFailures = new List<String>();
    }

    public static Result sync() {
        return sync([
            SELECT Id, Recipient_Email__c, Opens__c, Downloads__c, Closed_Reason__c,
                   Closed_At__c, Expires_At__c, Unlocked_Until__c
            FROM Readmission_Report_Link__c
            WHERE Access_Token_Hash__c != null
              AND CreatedDate = LAST_N_DAYS:14
        ], new TCMReportConfig().maxOpens());
    }

    @TestVisible
    private static Result sync(List<Readmission_Report_Link__c> links, Integer maxOpens) {
        Result result = new Result();
        if (links == null || links.isEmpty()) {
            return result;
        }
        result.linksExamined = links.size();
        Datetime now = Datetime.now();
        List<Readmission_Report_Link__c> toClose = new List<Readmission_Report_Link__c>();

        for (Readmission_Report_Link__c link : links) {
            result.opens += nz(link.Opens__c);
            result.downloads += nz(link.Downloads__c);
            if (link.Closed_Reason__c == 'Locked') {
                result.locked++;
            }
            if (link.Closed_Reason__c == 'View limit reached') {
                result.cappedEarly++;
            }

            // A link that has already run out of time is left alone: it is closed either way,
            // and labelling it "View limit reached" would put the wrong reason in a disclosure
            // record. A link still inside its unlock window is left alone too, so a recipient
            // reading the report on the final allowed open is not cut off mid-page.
            Boolean expired = link.Expires_At__c == null || link.Expires_At__c <= now;
            Boolean unlocked = link.Unlocked_Until__c != null && link.Unlocked_Until__c > now;
            Boolean hitCap = maxOpens > 0
                && nz(link.Opens__c) >= maxOpens
                && link.Closed_Reason__c == null
                && !expired
                && !unlocked;
            if (hitCap) {
                link.Closed_Reason__c = 'View limit reached';
                link.Closed_At__c = now;
                link.Code_Hash__c = null;
                link.Code_Expires_At__c = null;
                toClose.add(link);
            }
        }

        if (!toClose.isEmpty()) {
            // Partial success: one bad row must not leave the rest open past their cap.
            List<Database.SaveResult> closeResults = Database.update(toClose, false);
            for (Integer i = 0; i < closeResults.size(); i++) {
                if (closeResults[i].isSuccess()) {
                    result.linksUpdated++;
                    result.cappedEarly++;
                } else {
                    result.closeFailures.add(
                        toClose[i].Recipient_Email__c + ': the view cap was reached but the ' +
                        'link could not be closed (' + firstError(closeResults[i].getErrors()) +
                        ')'
                    );
                }
            }
        }
        return result;
    }

    private static String firstError(List<Database.Error> errors) {
        return errors == null || errors.isEmpty()
            ? 'unknown error'
            : errors[0].getStatusCode() + ' ' + errors[0].getMessage();
    }

    private static Integer nz(Decimal value) {
        return value == null ? 0 : value.intValue();
    }
}