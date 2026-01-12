public class ThoroughcareCreateController {
    // Define the @future method with the (callout=true) attribute to make an HTTP callout
    @future(callout=true)
    public static void sendPatientId(String patientId, Boolean isSandbox) {
        System.debug('Debug: Asynchronous HTTP Call for Patient ID: ' + patientId);
        
        String endpointUrl;
        if (isSandbox) {
            endpointUrl = 'https://lumina-be-368147deb4ac.herokuapp.com/create-thoroughcare-patient';
        } else {
            endpointUrl = 'https://lumina-production-16b22bde10a9.herokuapp.com/create-thoroughcare-patient';
        }
        
        String finalEndpointUrl = endpointUrl + '?sf_id=' + patientId;
        System.debug('Debug: Final Endpoint being used with Query Parameter: ' + finalEndpointUrl);
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(finalEndpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody('{}');
        
        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            System.debug('Debug: HTTP Response Status Code: ' + res.getStatusCode());
            System.debug('Debug: HTTP Response Body: ' + res.getBody());
        } catch (Exception e) {
            System.debug('Debug: Error during HTTP callout: ' + e.getMessage());
        }
    }
}