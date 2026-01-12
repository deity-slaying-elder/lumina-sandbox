public class MockHttpCallout implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;

    // Constructor to set the status code and response body
    public MockHttpCallout(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
    }

    // This method is called when the HTTP request is sent
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(responseBody);
        return res;
    }
}