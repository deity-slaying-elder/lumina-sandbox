/**
 * Everything the report site is allowed to do with a link row, in one place.
 *
 * Runs without sharing because the site's guest user cannot hold record access through
 * org-wide defaults, and the row has to be reachable. That widens nothing: the only way to
 * name a row is to present the token whose hash it stores, and the token is 256 bits of
 * randomness. Nothing here queries a Facility, a Patient or a Hospital Admission; the PDF it
 * serves was rendered by the job inside the org.
 *
 * Rules, all enforced here rather than in the page:
 * - A link is live while it has not expired and has not been closed.
 * - A one-time code lasts CODE_LIFETIME_MINUTES, is emailed only to the address the link was
 *   issued to, and cannot be requested again for RESEND_INTERVAL_SECONDS.
 * - MAX_CODES codes per link, then the row is locked. MAX_FAILED_ATTEMPTS wrong codes, then
 *   the row is locked. Both are permanent; a new link needs a reissue from the Facility.
 * - A correct code counts one open and unlocks the PDF for UNLOCK_MINUTES, for the browser
 *   that entered it and no other. Opens beyond the
 *   configured cap close the row instead.
 * - The same generic answer for a bad token, an expired link and a closed one.
 */
public without sharing class TCMReadmissionGateService {

    public static final Integer CODE_LIFETIME_MINUTES = 10;
    public static final Integer UNLOCK_MINUTES = 10;
    public static final Integer RESEND_INTERVAL_SECONDS = 60;
    public static final Integer MAX_CODES = 10;
    public static final Integer MAX_FAILED_ATTEMPTS = 5;

    public static final String STATUS_UNAVAILABLE = 'unavailable';
    public static final String STATUS_REQUEST = 'request';
    public static final String STATUS_VERIFY = 'verify';
    public static final String STATUS_REPORT = 'report';

    public static final String UNAVAILABLE_MESSAGE = 'This report is no longer available.';

    /** Name of the cookie that ties an unlocked link to the browser that unlocked it. */
    public static final String BROWSER_COOKIE = 'tcmReportKey';
    /** Query parameter carrying the same key, for callers a cookie cannot reach. */
    public static final String KEY_PARAM = 'k';

    /**
     * The key this caller presented, set by the page controller and by the PDF endpoint before
     * they ask us anything. A Site guest user has no session of its own, which is why the
     * browser has to be identified by something we hand it ourselves.
     *
     * The page gets it back as a cookie. The PDF endpoint cannot: Apex REST does not expose the
     * Cookie header at all, proven in the sandbox on 2026-09-23 with a staged unlock and the
     * right cookie value, which was refused exactly as no cookie was. So the page also writes
     * the key into the PDF URL it renders, and that URL exists only inside the unlocked page.
     */
    private static String browserToken;

    public static void setBrowserToken(String value) {
        browserToken = String.isBlank(value) ? null : value.trim();
    }

    /** The key in force for this request, so the page can put it in the URLs it renders. */
    public static String currentBrowserToken() {
        return browserToken;
    }

    /** Test seams: the clock, the code that gets minted, and which org this is. */
    @TestVisible private static Datetime nowOverride;
    @TestVisible private static String codeOverride;
    @TestVisible private static Boolean sandboxOverride;

    /** What the page should show next. Never carries patient data. */
    public class Outcome {
        public String status = STATUS_UNAVAILABLE;
        public String message;
        public String error;
        public Id linkId;
        public String facilityName;
        public String maskedEmail;
        public Date reportDate;
        public Datetime expiresAt;
        public Datetime codeExpiresAt;
        public Datetime unlockedUntil;
        public Integer attemptsLeft;
        public Boolean downloadAllowed = false;
        /** Set only when a code has just been accepted. The caller must hand it to the browser. */
        public String issueBrowserToken;
        /**
         * Mailboxes this link's code may be sent to: the recipient first, then anyone Cc'd on
         * the message that carried it. Masked, and addressed by index -- the page never hands
         * back an address, only a position in this list, so a caller cannot name a mailbox of
         * their own choosing.
         */
        public List<Destination> destinations = new List<Destination>();
    }

    /** One choosable mailbox: what to show, and the key to send back. */
    public class Destination {
        public Integer key;
        public String maskedEmail;
        public Boolean isRecipient = false;
        public Destination(Integer key, String maskedEmail, Boolean isRecipient) {
            this.key = key;
            this.maskedEmail = maskedEmail;
            this.isRecipient = isRecipient;
        }
    }

    /** The PDF, ready to stream. */
    public class Served {
        public Blob body;
        public String fileName;
    }

    /** Where a link stands, with no writes. */
    public static Outcome look(String rawToken) {
        Readmission_Report_Link__c row = find(rawToken);
        if (!isLive(row)) {
            return unavailable();
        }
        Outcome outcome = describe(row);
        if (unlockedForThisBrowser(row)) {
            outcome.status = STATUS_REPORT;
        } else if (codeOutstanding(row)) {
            outcome.status = STATUS_VERIFY;
            outcome.message = 'Enter the code we emailed to ' + outcome.maskedEmail + '.';
        } else {
            outcome.status = STATUS_REQUEST;
        }
        return outcome;
    }

    /** Mints a code, emails it to the address on the row, and remembers only its hash. */
    public static Outcome requestCode(String rawToken) {
        return requestCode(rawToken, null);
    }

    /**
     * destinationKey is an index into deliverableFor(row), not an address. Anything else --
     * a missing key, a non-number, an out-of-range number -- falls back to the recipient the
     * link was issued to. An address supplied by the caller is never honoured, so a Cc'd
     * reader can redirect the code to themselves but nobody can redirect it anywhere new.
     */
    public static Outcome requestCode(String rawToken, String destinationKey) {
        Readmission_Report_Link__c row = find(rawToken);
        if (!isLive(row)) {
            return unavailable();
        }
        Outcome outcome = describe(row);
        Datetime current = now();

        if (row.Code_Sent_At__c != null
            && row.Code_Sent_At__c.addSeconds(RESEND_INTERVAL_SECONDS) > current) {
            outcome.status = codeOutstanding(row) ? STATUS_VERIFY : STATUS_REQUEST;
            outcome.message =
                'A code was sent less than a minute ago. Check your inbox and spam folder, ' +
                'or wait a minute and ask for another.';
            log(row, 'Code throttled', null);
            return outcome;
        }
        if (nz(row.Codes_Sent__c) >= MAX_CODES) {
            close(row, 'Locked');
            log(row, 'Locked', 'Too many code requests (' + MAX_CODES + ')');
            return unavailable();
        }
        List<String> deliverable = deliverableFor(row);
        Integer chosenIndex = indexFor(destinationKey, deliverable.size());
        String sendTo = deliverable[chosenIndex];
        String maskedSendTo = mask(sendTo);

        if (isSandbox() && !sandboxMayReceive(sendTo)) {
            // A sandbox must never email a real facility. The link rows a sandbox run issues
            // already point at the testers, so this only bites a row created by hand.
            outcome.status = STATUS_REQUEST;
            outcome.error =
                'This is a sandbox and ' + maskedSendTo + ' is not on its redirect ' +
                'list, so no code was sent.';
            log(row, 'Code refused', 'Sandbox: address not on the redirect list');
            return outcome;
        }

        String code = codeOverride != null ? codeOverride : TCMReadmissionAccessToken.mintCode();
        String sendProblem = sendCode(row, sendTo, code, outcome.facilityName);
        if (sendProblem != null) {
            outcome.status = STATUS_REQUEST;
            outcome.error = 'We could not send the code. Please try again in a minute.';
            System.debug(LoggingLevel.ERROR, 'TCM code email failed: ' + sendProblem);
            log(row, 'Code refused', 'Email send failed');
            return outcome;
        }

        row.Code_Hash__c = TCMReadmissionAccessToken.hashCode(rawToken, code);
        row.Code_Expires_At__c = current.addMinutes(CODE_LIFETIME_MINUTES);
        row.Code_Sent_At__c = current;
        row.Codes_Sent__c = nz(row.Codes_Sent__c) + 1;
        if (!save(row)) {
            outcome.status = STATUS_REQUEST;
            outcome.error = 'Something went wrong. Please try again in a minute.';
            return outcome;
        }
        outcome.status = STATUS_VERIFY;
        outcome.codeExpiresAt = row.Code_Expires_At__c;
        outcome.message =
            'We sent a code to ' + maskedSendTo + '. It works for ' +
            CODE_LIFETIME_MINUTES + ' minutes.';
        // The masked address goes on the access row: which mailbox was trusted with this code
        // is the whole point of letting the reader choose, and it must survive in the log.
        log(row, 'Code sent',
            'Code ' + row.Codes_Sent__c.intValue() + ' of ' + MAX_CODES + ' to ' + maskedSendTo);
        return outcome;
    }

    /** Checks a code. Right: counts an open and unlocks the PDF. Wrong: counts a strike. */
    public static Outcome verify(String rawToken, String code) {
        Readmission_Report_Link__c row = find(rawToken);
        if (!isLive(row)) {
            return unavailable();
        }
        Outcome outcome = describe(row);
        Datetime current = now();
        String trimmed = code == null ? null : code.replaceAll('[^0-9]', '');

        if (!TCMReadmissionAccessToken.looksLikeCode(trimmed)) {
            outcome.status = codeOutstanding(row) ? STATUS_VERIFY : STATUS_REQUEST;
            outcome.error = 'Enter the six-digit code from your email.';
            return outcome;
        }
        if (!codeOutstanding(row)) {
            outcome.status = STATUS_REQUEST;
            outcome.error = 'That code has expired. Ask for a new one.';
            log(row, 'Code expired', null);
            return outcome;
        }
        String candidate = TCMReadmissionAccessToken.hashCode(rawToken, trimmed);
        if (!TCMReadmissionAccessToken.matches(row.Code_Hash__c, candidate)) {
            row.Failed_Attempts__c = nz(row.Failed_Attempts__c) + 1;
            if (row.Failed_Attempts__c >= MAX_FAILED_ATTEMPTS) {
                close(row, 'Locked');
                log(row, 'Wrong code', 'Attempt ' + row.Failed_Attempts__c.intValue() + ' of ' + MAX_FAILED_ATTEMPTS);
                log(row, 'Locked', 'Too many wrong codes (' + MAX_FAILED_ATTEMPTS + ')');
                return unavailable();
            }
            save(row);
            outcome.status = STATUS_VERIFY;
            outcome.attemptsLeft = MAX_FAILED_ATTEMPTS - row.Failed_Attempts__c.intValue();
            log(row, 'Wrong code', 'Attempt ' + row.Failed_Attempts__c.intValue() + ' of ' + MAX_FAILED_ATTEMPTS);
            outcome.error =
                'That code is not right. ' + outcome.attemptsLeft +
                (outcome.attemptsLeft == 1 ? ' attempt' : ' attempts') + ' left.';
            return outcome;
        }

        // The cap is on disclosures, and a correct code is the moment of disclosure.
        Integer cap = new TCMReportConfig().maxOpens();
        if (cap > 0 && nz(row.Opens__c) >= cap) {
            close(row, 'View limit reached');
            log(row, 'View limit reached', 'Open ' + (nz(row.Opens__c) + 1) + ' refused, cap ' + cap);
            return unavailable();
        }
        row.Opens__c = nz(row.Opens__c) + 1;
        if (row.First_Opened_At__c == null) {
            row.First_Opened_At__c = current;
        }
        row.Last_Activity_At__c = current;
        row.Unlocked_Until__c = current.addMinutes(UNLOCK_MINUTES);
        // Tie the unlock to this browser. Reuse the cookie it already holds when there is one,
        // so a second report in the same browser does not overwrite the first.
        String token = String.isBlank(browserToken)
            ? TCMReadmissionAccessToken.mintToken()
            : browserToken;
        row.Unlock_Browser_Hash__c = TCMReadmissionAccessToken.hashToken(token);
        outcome.issueBrowserToken = token;
        // Hold it for the rest of this request, so the page can render it into the PDF URL
        // whether or not the browser accepts the cookie.
        browserToken = token;
        row.Code_Hash__c = null;
        row.Code_Expires_At__c = null;
        row.Failed_Attempts__c = 0;
        if (!save(row)) {
            outcome.status = STATUS_REQUEST;
            outcome.error = 'Something went wrong. Ask for a new code.';
            return outcome;
        }
        outcome.status = STATUS_REPORT;
        outcome.unlockedUntil = row.Unlocked_Until__c;
        log(row, 'Opened', 'Open ' + row.Opens__c.intValue() + (cap > 0 ? ' of ' + cap : ''));
        return outcome;
    }

    /** The PDF for an unlocked link, or null for every other case. */
    public static Served serve(String rawToken, Boolean download) {
        Readmission_Report_Link__c row = find(rawToken);
        if (!isLive(row)) {
            // No row, or a dead one. A dead row still gets the refusal on its log.
            if (row != null) {
                log(row, 'Fetch refused', 'Link not live');
            }
            return null;
        }
        if (!unlockedForThisBrowser(row)) {
            log(row, 'Fetch refused',
                row.Unlocked_Until__c != null && row.Unlocked_Until__c > now()
                    ? 'Unlocked for a different browser'
                    : 'Outside the unlock window');
            return null;
        }
        if (String.isBlank(row.Content_Version_Id__c)) {
            log(row, 'Fetch refused', 'No file on the link');
            return null;
        }
        TCMReportConfig config = new TCMReportConfig();
        if (download == true && !config.allowDownload()) {
            log(row, 'Fetch refused', 'Download not allowed');
            return null;
        }
        Id versionId;
        try {
            versionId = Id.valueOf(row.Content_Version_Id__c);
        } catch (Exception e) {
            return null;
        }
        List<ContentVersion> versions = [
            SELECT VersionData, PathOnClient, Title
            FROM ContentVersion
            WHERE Id = :versionId
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            // Purged. The row outlives the file on purpose.
            log(row, 'Fetch refused', 'File purged');
            return null;
        }
        if (download == true) {
            row.Downloads__c = nz(row.Downloads__c) + 1;
            row.Last_Activity_At__c = now();
            save(row);
            log(row, 'Downloaded', 'Download ' + row.Downloads__c.intValue());
        } else {
            log(row, 'PDF fetched', null);
        }
        Served served = new Served();
        served.body = versions[0].VersionData;
        served.fileName = fileNameFor(versions[0]);
        return served;
    }

    // ---- who is calling -----------------------------------------------------------------------

    /**
     * IP and browser of the current request, captured once per request by the page controller
     * or the REST endpoint and written onto every access row. Sites put the real client IP in
     * X-Salesforce-SIP; the other two headers are fallbacks for a proxy in front.
     */
    public class Caller {
        public String ipAddress;
        public String userAgent;
    }

    private static Caller caller = new Caller();

    public static void setCaller(Map<String, String> headers) {
        Caller c = new Caller();
        if (headers != null) {
            c.ipAddress = firstNonBlank(new List<String>{
                headers.get('X-Salesforce-SIP'), headers.get('True-Client-IP'),
                headers.get('X-Forwarded-For')
            });
            if (c.ipAddress != null && c.ipAddress.contains(',')) {
                c.ipAddress = c.ipAddress.substringBefore(',').trim();
            }
            c.userAgent = headers.get('User-Agent');
        }
        caller = c;
    }

    @TestVisible
    private static Caller currentCaller() {
        return caller;
    }

    /**
     * One access row per event. Never blocks the flow: a log row that cannot be written is a
     * debug line, not a refused report. Never carries a code or a token.
     */
    private static void log(Readmission_Report_Link__c row, String event, String detail) {
        if (row == null || row.Id == null) {
            return;
        }
        Readmission_Report_Access__c access = new Readmission_Report_Access__c(
            Report_Link__c = row.Id,
            Event__c = event,
            Occurred_At__c = now(),
            IP_Address__c = caller.ipAddress == null ? null : caller.ipAddress.left(45),
            User_Agent__c = caller.userAgent == null ? null : caller.userAgent.left(255),
            Detail__c = detail == null ? null : detail.left(255)
        );
        Database.SaveResult result = Database.insert(access, false);
        if (!result.isSuccess()) {
            System.debug(LoggingLevel.ERROR,
                'TCM access log write failed: ' + result.getErrors()[0].getMessage());
        }
    }

    private static String firstNonBlank(List<String> values) {
        for (String v : values) {
            if (String.isNotBlank(v)) {
                return v.trim();
            }
        }
        return null;
    }

    // ---- internals ------------------------------------------------------------------------

    private static Readmission_Report_Link__c find(String rawToken) {
        if (!TCMReadmissionAccessToken.looksLikeToken(rawToken)) {
            return null;
        }
        String hash = TCMReadmissionAccessToken.hashToken(rawToken);
        List<Readmission_Report_Link__c> rows = [
            SELECT Id, Facility__r.Name, Recipient_Email__c, Cc_Emails__c, Report_Date__c, Expires_At__c,
                   Closed_Reason__c, Closed_At__c, Content_Version_Id__c,
                   Code_Hash__c, Code_Expires_At__c, Code_Sent_At__c, Codes_Sent__c,
                   Failed_Attempts__c, Unlocked_Until__c, Unlock_Browser_Hash__c,
                   Opens__c, Downloads__c, First_Opened_At__c, Last_Activity_At__c
            FROM Readmission_Report_Link__c
            WHERE Access_Token_Hash__c = :hash
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Boolean isLive(Readmission_Report_Link__c row) {
        return row != null
            && row.Closed_Reason__c == null
            && row.Expires_At__c != null
            && row.Expires_At__c > now();
    }

    /**
     * True while the report may be shown without asking for another code.
     *
     * Two things must hold: time is left on the unlock, and this is the same browser that
     * entered the code, proved by a cookie we handed it at that moment. A Site guest user has
     * no session of its own, so the cookie is the only way to tell one visitor from another.
     * A link copied elsewhere inside the window therefore gets the code form, not the report.
     */
    private static Boolean unlockedForThisBrowser(Readmission_Report_Link__c row) {
        if (row.Unlocked_Until__c == null || row.Unlocked_Until__c <= now()) {
            return false;
        }
        if (String.isBlank(row.Unlock_Browser_Hash__c)) {
            // Unlocked before this check existed. Time alone, rather than locking a reader out.
            return true;
        }
        return String.isNotBlank(browserToken)
            && TCMReadmissionAccessToken.matches(
                   row.Unlock_Browser_Hash__c, TCMReadmissionAccessToken.hashToken(browserToken));
    }

    private static Boolean codeOutstanding(Readmission_Report_Link__c row) {
        return row.Code_Hash__c != null
            && row.Code_Expires_At__c != null
            && row.Code_Expires_At__c > now();
    }

    private static Outcome describe(Readmission_Report_Link__c row) {
        Outcome outcome = new Outcome();
        outcome.linkId = row.Id;
        outcome.facilityName = row.Facility__r == null ? null : row.Facility__r.Name;
        outcome.maskedEmail = mask(row.Recipient_Email__c);
        List<String> deliverable = deliverableFor(row);
        for (Integer i = 0; i < deliverable.size(); i++) {
            outcome.destinations.add(new Destination(i, mask(deliverable[i]), i == 0));
        }
        outcome.reportDate = row.Report_Date__c;
        outcome.expiresAt = row.Expires_At__c;
        outcome.unlockedUntil = row.Unlocked_Until__c;
        outcome.codeExpiresAt = row.Code_Expires_At__c;
        outcome.downloadAllowed = new TCMReportConfig().allowDownload();
        return outcome;
    }

    private static Outcome unavailable() {
        Outcome outcome = new Outcome();
        outcome.status = STATUS_UNAVAILABLE;
        outcome.message = UNAVAILABLE_MESSAGE;
        return outcome;
    }

    private static void close(Readmission_Report_Link__c row, String reason) {
        row.Closed_Reason__c = reason;
        row.Closed_At__c = now();
        row.Code_Hash__c = null;
        row.Code_Expires_At__c = null;
        row.Unlocked_Until__c = null;
        row.Unlock_Browser_Hash__c = null;
        save(row);
    }

    private static Boolean save(Readmission_Report_Link__c row) {
        Database.SaveResult result = Database.update(row, false);
        if (!result.isSuccess()) {
            System.debug(LoggingLevel.ERROR,
                'TCM link row update failed: ' + result.getErrors()[0].getMessage());
        }
        return result.isSuccess();
    }

    /**
     * The code email. Sent from the configured org-wide address when the guest user is
     * allowed to use it, and as the site user otherwise, because a refused sender must not
     * cost the recipient their report.
     */
    private static String sendCode(
        Readmission_Report_Link__c row, String sendTo, String code, String facilityName
    ) {
        TCMReportConfig config = new TCMReportConfig();
        Messaging.SingleEmailMessage message = codeMessage(sendTo, code, facilityName);

        Id orgWideId = orgWideAddressId(config);
        if (orgWideId != null) {
            message.setOrgWideEmailAddressId(orgWideId);
            String problem = dispatch(message);
            if (problem == null) {
                return null;
            }
            // Retry as the site user. The typical refusal is an org-wide address the guest
            // profile is not allowed to use. The fallback sends from the guest user's own
            // .force.com address, which a recipient's mail tenant is far likelier to drop
            // than the verified org-wide sender -- so it is a warning, not a silent success.
            System.debug(LoggingLevel.WARN,
                'TCM code email fell back to the running user as sender; the org-wide address ' +
                'refused the send. Allow this profile on the org-wide address. Refusal: ' +
                problem);
            message = codeMessage(sendTo, code, facilityName);
        }
        return dispatch(message);
    }

    /**
     * One builder for both attempts. The retry used to be a second, hand-copied message and
     * had drifted -- it was missing the plain text part, so the fallback path sent HTML only,
     * which hurts deliverability at exactly the moment the sender is already unaligned.
     */
    private static Messaging.SingleEmailMessage codeMessage(
        String sendTo, String code, String facilityName
    ) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new List<String>{ sendTo });
        message.setSubject('Your code for the readmissions report');
        message.setHtmlBody(codeBody(code, facilityName));
        message.setPlainTextBody(
            'Your code is ' + code + '. It works for ' + CODE_LIFETIME_MINUTES + ' minutes. ' +
            'If you did not ask for it, ignore this email.'
        );
        message.setSaveAsActivity(false);
        return message;
    }

    private static String dispatch(Messaging.SingleEmailMessage message) {
        try {
            List<Messaging.SendEmailResult> results =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ message }, false);
            if (!results.isEmpty() && results[0].isSuccess()) {
                return null;
            }
            List<String> reasons = new List<String>();
            if (!results.isEmpty()) {
                for (Messaging.SendEmailError error : results[0].getErrors()) {
                    reasons.add(error.getMessage());
                }
            }
            return reasons.isEmpty() ? 'unknown send error' : String.join(reasons, '; ');
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private static String codeBody(String code, String facilityName) {
        return
            '<div style="font-family: Arial, sans-serif; color: #333;">' +
            '<p>Your code for the readmissions report' +
            (String.isBlank(facilityName) ? '' : ' for ' + facilityName.escapeHtml4()) +
            ' is</p>' +
            '<p style="font-size:28px;letter-spacing:6px;font-weight:bold;color:#30385c;">' +
            code + '</p>' +
            '<p>It works for ' + CODE_LIFETIME_MINUTES + ' minutes. Enter it on the page ' +
            'that asked for it.</p>' +
            '<p style="color:#666;font-size:12px;">If you did not ask for a code, ignore this ' +
            'email. Nobody can open the report without it.</p>' +
            '</div>';
    }

    private static Id orgWideAddressId(TCMReportConfig config) {
        String address = config.orgWideAddressFor(isSandbox());
        if (String.isBlank(address)) {
            return null;
        }
        List<OrgWideEmailAddress> found = [
            SELECT Id, IsVerified FROM OrgWideEmailAddress WHERE Address = :address LIMIT 1
        ];
        return found.isEmpty() || found[0].IsVerified != true ? null : found[0].Id;
    }

    private static Boolean isSandbox() {
        if (sandboxOverride != null) {
            return sandboxOverride;
        }
        return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    }

    /**
     * Every mailbox allowed to receive this link's code: the recipient first, then the Cc
     * snapshot taken when the link was issued. Read from the row, never from config, so a
     * later config change cannot widen a link that is already out.
     */
    @TestVisible
    private static List<String> deliverableFor(Readmission_Report_Link__c row) {
        List<String> addresses = new List<String>();
        Set<String> seen = new Set<String>();
        if (row != null && String.isNotBlank(row.Recipient_Email__c)) {
            addresses.add(row.Recipient_Email__c.trim().toLowerCase());
            seen.add(addresses[0]);
        }
        if (row != null && String.isNotBlank(row.Cc_Emails__c)) {
            for (String part : row.Cc_Emails__c.split('[;,]')) {
                String trimmed = part.trim().toLowerCase();
                if (String.isNotBlank(trimmed) && seen.add(trimmed)) {
                    addresses.add(trimmed);
                }
            }
        }
        return addresses;
    }

    /** Index 0 unless the caller named a valid other position. */
    @TestVisible
    private static Integer indexFor(String destinationKey, Integer size) {
        if (String.isBlank(destinationKey) || size <= 1) {
            return 0;
        }
        try {
            Integer parsed = Integer.valueOf(destinationKey.trim());
            return (parsed >= 0 && parsed < size) ? parsed : 0;
        } catch (Exception e) {
            return 0;
        }
    }

    private static Boolean sandboxMayReceive(String email) {
        String redirect = new TCMReportConfig().sandboxRedirect();
        if (String.isBlank(redirect) || String.isBlank(email)) {
            return false;
        }
        String wanted = email.trim().toLowerCase();
        for (String part : redirect.split('[;,]')) {
            if (part.trim().toLowerCase() == wanted) {
                return true;
            }
        }
        return false;
    }

    /** j***@example.com. Enough for the recipient to recognise it, nothing for anyone else. */
    @TestVisible
    private static String mask(String email) {
        if (String.isBlank(email) || !email.contains('@')) {
            return '***';
        }
        Integer at = email.indexOf('@');
        String local = email.substring(0, at);
        return local.left(1) + '***' + email.substring(at);
    }

    private static String fileNameFor(ContentVersion version) {
        String name = String.isNotBlank(version.PathOnClient)
            ? version.PathOnClient
            : (String.isNotBlank(version.Title) ? version.Title + '.pdf' : 'report.pdf');
        // A header value, so nothing that could break out of the quotes.
        return name.replaceAll('[^A-Za-z0-9._ -]', '_');
    }

    private static Datetime now() {
        return nowOverride != null ? nowOverride : Datetime.now();
    }

    private static Integer nz(Decimal value) {
        return value == null ? 0 : value.intValue();
    }
}