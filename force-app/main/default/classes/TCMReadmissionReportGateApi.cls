/**
 * Streams the PDF behind an unlocked link. Reached through the report site, so the caller is
 * the site's guest user. The token in the query string is the only credential, and it works
 * here only inside the minutes after a correct code, which the service enforces.
 *
 * Every refusal is the same 404 with the same short body, so the response cannot be used to
 * tell a bad token from an expired link.
 */
@RestResource(urlMapping='/tcm/report')
global with sharing class TCMReadmissionReportGateApi {

    @HttpGet
    global static void serve() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        TCMReadmissionGateService.setCaller(request.headers);
        // The unlock key comes in the query string, not a cookie. Apex REST does not expose the
        // Cookie header: a staged unlock in the sandbox on 2026-09-23 refused the right cookie
        // value exactly as it refused no cookie at all. The page writes this key into the URL
        // it renders, so only the browser that entered the code ever holds it.
        TCMReadmissionGateService.setBrowserToken(
            request.params.get(TCMReadmissionGateService.KEY_PARAM));
        String token = request.params.get(TCMReadmissionPortal.TOKEN_PARAM);
        Boolean download = '1'.equals(request.params.get(TCMReadmissionPortal.DOWNLOAD_PARAM));

        response.addHeader('Cache-Control', 'no-store, private');
        response.addHeader('X-Content-Type-Options', 'nosniff');

        TCMReadmissionGateService.Served served;
        try {
            served = TCMReadmissionGateService.serve(token, download);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'TCM report serve failed: ' + e.getMessage());
            served = null;
        }
        if (served == null) {
            response.statusCode = 404;
            response.addHeader('Content-Type', 'text/plain; charset=utf-8');
            response.responseBody = Blob.valueOf(TCMReadmissionGateService.UNAVAILABLE_MESSAGE);
            return;
        }
        response.statusCode = 200;
        response.addHeader('Content-Type', 'application/pdf');
        response.addHeader(
            'Content-Disposition',
            (download ? 'attachment' : 'inline') + '; filename="' + served.fileName + '"'
        );
        response.responseBody = served.body;
    }
}