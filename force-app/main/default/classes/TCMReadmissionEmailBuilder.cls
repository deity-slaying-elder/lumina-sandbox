/**
 * Builds the subject and body of a facility readmission email.
 *
 * Extracted from the daily batch so the on-demand resend sends a byte-identical message
 * rather than a second copy of the same markup that drifts from it. The only difference
 * between the two is one extra line saying the link was reissued on request, which is what
 * the recipient asked for and what makes the message make sense out of schedule.
 *
 * Pure: no SOQL, no DML, no sending.
 */
public with sharing class TCMReadmissionEmailBuilder {

    private final TCMReportConfig config;
    private final String timeZoneName;
    private final String windowDescription;
    private final String fileDateToken;

    public TCMReadmissionEmailBuilder(
        TCMReportConfig config,
        String timeZoneName,
        String windowDescription,
        String fileDateToken
    ) {
        this.config = config == null ? new TCMReportConfig() : config;
        this.timeZoneName = timeZoneName;
        this.windowDescription = windowDescription;
        this.fileDateToken = fileDateToken;
    }

    public String subjectFor(Facility__c facility) {
        return String.format(
            config.subjectTemplate(),
            new List<String>{
                facility == null || facility.Name == null ? '' : facility.Name,
                fileDateToken
            }
        );
    }

    /**
     * issued is null in Attachment mode, where the CSV rides along instead of a link.
     * reissued adds the line explaining why this arrived off schedule.
     */
    public String bodyFor(
        Facility__c facility,
        Integer rowCount,
        Boolean redirected,
        TCMReadmissionLinkPublisher.Issued issued,
        String intendedAddress,
        Boolean reissued
    ) {
        String plural = rowCount == 1 ? 'admission' : 'admissions';
        String html =
            '<div style="font-family: Arial, sans-serif; color: #333;">';
        if (reissued == true) {
            html +=
                '<p>Here is a new link to your readmissions report. The previous one had ' +
                'expired.</p>';
        }
        html +=
                '<p><strong>' + rowCount + ' hospital ' + plural + '</strong> for ' +
                escape(facility == null ? null : facility.Name) + ' during ' +
                escape(windowDescription) + '.</p>' +
                '<p>These are patients discharged home from your facility who were ' +
                'subsequently admitted to a hospital.</p>';
        if (issued != null) {
            // The email itself carries no patient information and no secret beyond the link.
            // The report sits behind the site page, which opens only for a one-time code sent
            // to this same address when the recipient asks for it.
            html +=
                '<p><a href="' + issued.publicUrl.escapeHtml4() + '" style="display:inline-block;' +
                'background:#1f5fe0;color:#ffffff;padding:10px 16px;text-decoration:none;' +
                'border-radius:3px;font-weight:bold;">View report</a></p>' +
                '<p>When you open the link, choose <strong>Email me a code</strong>. A ' +
                'six-digit code will be sent to this address and works for ' +
                TCMReadmissionGateService.CODE_LIFETIME_MINUTES + ' minutes.</p>' +
                '<p style="color:#666;font-size:12px;">This link expires on ' +
                escape(formatLocal(issued.expiresAt)) + '.' + capNotice() +
                ' It was issued to ' + escape(intendedAddress) +
                ' and should not be forwarded. No patient information is included in this email.</p>' +
                // The unavailable page carries no way back, so the route to a new link has to
                // live here, in the message the recipient still has.
                '<p style="color:#666;font-size:12px;">Link expired or stopped working? ' +
                'Reply to this email and we will send a new one.</p>';
        } else {
            html += '<p>Full detail is attached as a CSV.</p>';
        }
        if (redirected == true) {
            html +=
                '<p style="color:#a00;"><strong>Sandbox run.</strong> This message was ' +
                'redirected and did not reach the facility.</p>';
        }
        return html + '</div>';
    }

    public String formatLocal(Datetime value) {
        return value == null ? '' : value.format('EEEE, MMMM d, yyyy h:mm a z', timeZoneName);
    }

    /** Mentions the open cap only when one is configured. */
    private String capNotice() {
        Integer cap = config.maxOpens();
        return cap <= 0
            ? ''
            : ' It also closes after ' + cap + ' views, whichever comes first.';
    }

    private static String escape(String value) {
        return value == null ? '' : value.escapeHtml4();
    }
}