/**
 * Controller for the report site's only page. Holds no logic of its own: every decision is
 * made by TCMReadmissionGateService, and this class turns its outcome into strings the page
 * can show. Runs with sharing; the service is what reaches the row.
 */
public with sharing class TCMReadmissionGateController {

    private final String token;
    private final String timeZoneName;

    public String codeInput { get; set; }

    public String status { get; private set; }
    public String message { get; private set; }
    public String error { get; private set; }
    public String facilityName { get; private set; }
    public String maskedEmail { get; private set; }

    /**
     * Mailboxes this link's code may go to, masked. One entry means no choice to make and the
     * page says nothing about it; more than one means the reader was Cc'd on the facility's
     * message and can have the code sent to their own mailbox instead.
     */
    public List<SelectOption> destinationOptions { get; private set; }

    /** The chosen position in that list. An index, never an address. */
    public String destinationKey { get; set; }

    public Boolean getHasDestinationChoice() {
        return destinationOptions != null && destinationOptions.size() > 1;
    }
    public String reportDateLabel { get; private set; }
    public String expiresLabel { get; private set; }
    public String unlockedUntilLabel { get; private set; }
    public Integer codeMinutes { get; private set; }
    public Boolean downloadAllowed { get; private set; }

    /**
     * The key that proves this is the browser which entered the code. A Site guest user has no
     * session of its own, so without this anyone holding the URL could walk into an unlocked
     * link. Read before every call, because a postback does not re-run the constructor.
     *
     * The cookie is the normal carrier. The query parameter is there for the browser that
     * refuses cookies: after a correct code we redirect it to a URL carrying its own key, so it
     * reads the report rather than looping back to the code form forever.
     */
    private static void carryBrowserToken() {
        String fromUrl = ApexPages.currentPage().getParameters()
            .get(TCMReadmissionGateService.KEY_PARAM);
        if (String.isNotBlank(fromUrl)) {
            TCMReadmissionGateService.setBrowserToken(fromUrl);
            return;
        }
        Map<String, Cookie> jar = ApexPages.currentPage().getCookies();
        // Salesforce stores an Apex cookie under an apex__ prefix; which name comes back
        // depends on the context, so both are tried.
        Cookie c = jar.get(TCMReadmissionGateService.BROWSER_COOKIE);
        if (c == null) {
            c = jar.get('apex__' + TCMReadmissionGateService.BROWSER_COOKIE);
        }
        TCMReadmissionGateService.setBrowserToken(c == null ? null : c.getValue());
    }

    /** Hands the browser its key the moment a code is accepted. Https only, this site is https. */
    private static void issueBrowserToken(TCMReadmissionGateService.Outcome outcome) {
        if (String.isBlank(outcome.issueBrowserToken)) {
            return;
        }
        ApexPages.currentPage().setCookies(new List<Cookie>{
            new Cookie(TCMReadmissionGateService.BROWSER_COOKIE, outcome.issueBrowserToken,
                       '/', 60 * 60 * 24, true)
        });
    }

    public TCMReadmissionGateController() {
        TCMReadmissionGateService.setCaller(ApexPages.currentPage().getHeaders());
        carryBrowserToken();
        token = ApexPages.currentPage().getParameters().get(TCMReadmissionPortal.TOKEN_PARAM);
        timeZoneName = new TCMReportConfig().timeZoneName();
        codeMinutes = TCMReadmissionGateService.CODE_LIFETIME_MINUTES;
        apply(TCMReadmissionGateService.look(token));
    }

    public PageReference requestCode() {
        TCMReadmissionGateService.setCaller(ApexPages.currentPage().getHeaders());
        carryBrowserToken();
        apply(TCMReadmissionGateService.requestCode(token, destinationKey));
        return null;
    }

    /**
     * On success the browser is sent back to the link's own URL rather than left on the
     * form's post response. A reload while reading then reopens the report inside the unlock
     * window instead of re-posting the code or landing on a page with no token.
     */
    public PageReference verifyCode() {
        TCMReadmissionGateService.setCaller(ApexPages.currentPage().getHeaders());
        carryBrowserToken();
        TCMReadmissionGateService.Outcome outcome =
            TCMReadmissionGateService.verify(token, codeInput);
        issueBrowserToken(outcome);
        apply(outcome);
        codeInput = null;
        if (status != TCMReadmissionGateService.STATUS_REPORT) {
            return null;
        }
        PageReference back = Page.TCMReadmissionReportGate;
        back.getParameters().put(TCMReadmissionPortal.TOKEN_PARAM, token);
        if (String.isNotBlank(outcome.issueBrowserToken)) {
            back.getParameters().put(
                TCMReadmissionGateService.KEY_PARAM, outcome.issueBrowserToken);
        }
        back.setRedirect(true);
        return back;
    }

    public Boolean getIsUnavailable() {
        return status == TCMReadmissionGateService.STATUS_UNAVAILABLE;
    }
    public Boolean getIsRequest() {
        return status == TCMReadmissionGateService.STATUS_REQUEST;
    }
    public Boolean getIsVerify() {
        return status == TCMReadmissionGateService.STATUS_VERIFY;
    }
    public Boolean getIsReport() {
        return status == TCMReadmissionGateService.STATUS_REPORT;
    }

    public String getPdfUrl() {
        return TCMReadmissionPortal.pdfPath(
            token, false, TCMReadmissionGateService.currentBrowserToken());
    }

    public String getDownloadUrl() {
        return TCMReadmissionPortal.pdfPath(
            token, true, TCMReadmissionGateService.currentBrowserToken());
    }

    private void apply(TCMReadmissionGateService.Outcome outcome) {
        status = outcome.status;
        message = outcome.message;
        error = outcome.error;
        facilityName = outcome.facilityName;
        maskedEmail = outcome.maskedEmail;
        destinationOptions = new List<SelectOption>();
        for (TCMReadmissionGateService.Destination d : outcome.destinations) {
            // Just the address. Saying which one was Cc'd tells the reader nothing they need
            // in order to choose, and spells out the distribution of the report to anyone who
            // opens the link.
            destinationOptions.add(new SelectOption(String.valueOf(d.key), d.maskedEmail));
        }
        if (String.isBlank(destinationKey) && !destinationOptions.isEmpty()) {
            destinationKey = destinationOptions[0].getValue();
        }
        downloadAllowed = outcome.downloadAllowed == true;
        reportDateLabel = outcome.reportDate == null
            ? null
            : Datetime.newInstance(outcome.reportDate, Time.newInstance(12, 0, 0, 0))
                .formatGmt('EEEE, MMMM d, yyyy');
        expiresLabel = local(outcome.expiresAt);
        unlockedUntilLabel = local(outcome.unlockedUntil);
    }

    private String local(Datetime value) {
        return value == null ? null : value.format('EEEE, MMMM d, yyyy h:mm a z', timeZoneName);
    }
}