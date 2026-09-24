/**
 * Where the report site lives, and how a link and a PDF request on it are spelled.
 *
 * The site's address differs per org, so it is read from the org: the Site named
 * TCM_Readmission_Portal and the domain it is served on. A config value can override that for
 * an org where the site sits behind a custom domain. No site, no URL, and the publisher then
 * refuses to issue links rather than emailing a link that goes nowhere.
 */
public with sharing class TCMReadmissionPortal {

    public static final String SITE_NAME = 'TCM_Readmission_Portal';
    public static final String TOKEN_PARAM = 't';
    public static final String DOWNLOAD_PARAM = 'dl';
    /** The Apex REST endpoint that streams the PDF, relative to the site host. */
    public static final String PDF_PATH = '/services/apexrest/tcm/report';

    @TestVisible
    private static String baseUrlOverride;

    /** The gate page URL without a query string, or null when the site cannot be found. */
    public static String baseUrl(TCMReportConfig config) {
        if (baseUrlOverride != null) {
            return baseUrlOverride;
        }
        String configured = config == null ? null : config.portalBaseUrl();
        if (configured != null) {
            return configured.removeEnd('/');
        }
        List<Site> sites = [
            SELECT Id, UrlPathPrefix
            FROM Site
            WHERE Name = :SITE_NAME AND Status = 'Active'
            LIMIT 1
        ];
        if (sites.isEmpty()) {
            return null;
        }
        String host;
        for (DomainSite ds : [
            SELECT Domain.Domain FROM DomainSite WHERE SiteId = :sites[0].Id
        ]) {
            String candidate = ds.Domain.Domain;
            if (host == null || candidate.contains('salesforce-sites')) {
                host = candidate;
            }
        }
        if (host == null) {
            return null;
        }
        String prefix = sites[0].UrlPathPrefix;
        return 'https://' + host + (String.isBlank(prefix) ? '' : '/' + prefix.removeStart('/'));
    }

    public static String linkFor(String baseUrl, String rawToken) {
        return baseUrl + '?' + TOKEN_PARAM + '=' + rawToken;
    }

    /**
     * Relative URL of the PDF for an unlocked link, inline or as a download.
     *
     * The unlock key rides in the query string because Apex REST never sees cookies. This URL
     * is only ever written into the page of the browser that entered the code, so the emailed
     * link on its own still gets the code form.
     */
    public static String pdfPath(String rawToken, Boolean download, String unlockKey) {
        String path = PDF_PATH + '?' + TOKEN_PARAM + '=' + rawToken;
        if (String.isNotBlank(unlockKey)) {
            path += '&' + TCMReadmissionGateService.KEY_PARAM
                 + '=' + EncodingUtil.urlEncode(unlockKey, 'UTF-8');
        }
        return download == true ? path + '&' + DOWNLOAD_PARAM + '=1' : path;
    }
}