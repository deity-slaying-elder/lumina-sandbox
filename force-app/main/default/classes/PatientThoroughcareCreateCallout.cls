public class PatientThoroughcareCreateCallout {
    @future(callout=true)
    public static void send(Id patientId, Boolean isCommunity) {
        Map<String, Object> payload =new Map<String, Object>();
        payload.put('Id', patientId);

        HttpRequest req = new HttpRequest();
        SObject config = EnvironmentMetadataSelector.getConfig();
        String baseUrl = config != null ? String.valueOf(config.get('BASE_URL__c')) : '';
        String apiKey = config != null ? String.valueOf(config.get('TC_API_KEY__c')) : '';
        if (isCommunity) {
            req.setEndpoint(baseUrl + '/tc/create-comm-patient');
        } else {
            req.setEndpoint(baseUrl + '/tc/create-patient');
        }
        req.setHeader('Authorization', 'Bearer '+ apiKey);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Thoroughcare callout failed: ' + ex.getMessage());
            return;
        }

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            System.debug(LoggingLevel.INFO, 'HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        } else {
            System.debug(LoggingLevel.ERROR, 'HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        }
    }
}