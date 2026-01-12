public with sharing class UploadConsentFileController {
    
    @TestVisible private static String lastAccountId;
    @TestVisible private static String lastConversionResult;

    public class InvocableRequest {
        @InvocableVariable
        public List<String> contentVersionsCollection;
    }
    
    public class InvocableResponse {
        @InvocableVariable
        public String status;
    }

    @InvocableMethod(label='Process Consent Upload File' description='Process Consent Upload File')
    public static List<String> processText(List<InvocableRequest> requests) {
        
        List<String> responses = new List<String>();
        String contentVersion = null;
        for (InvocableRequest request : requests) {
            contentVersion = request.contentVersionsCollection[0];
        }
        String encodedString = null;
        String conversionResult = getBase64DataFromContentVersion(contentVersion);

        if (conversionResult == null) {
            throw new IllegalArgumentException('Conversion is not possible. No base 64 Data found!');
        }
        
        //InvocableResponse response = new InvocableResponse();
        String status = sendConversionResult(conversionResult);
        responses.add(Status);
        
        return responses;
       	
    }
    
    public static String getBase64DataFromContentVersion(Id contentVersionId) {
        try {
            ContentVersion contentVersion = [
                SELECT VersionData
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];

            if (contentVersion != null) {
                String base64Data = EncodingUtil.base64Encode(contentVersion.VersionData);
                return base64Data;
            }
        } catch (QueryException e) {
            System.debug('Invalid ID provided: ' + e.getMessage());
            return null;
        } catch (StringException e) {
            System.debug('Invalid ID provided: ' + e.getMessage());
            return null;
        }

        return null;
    }

    public static string sendConversionResult(String conversionResult) {
        SObject config = EnvironmentMetadataSelector.getConfig();
        String baseUrl = config != null ? String.valueOf(config.get('BASE_URL__c')) : '';
        String endpointUrl = baseUrl + '/consent_to_services_file';
        String jsonPayload = JSON.serialize(new Map<String, String>{
            'Base64' => conversionResult
        });

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonPayload);

        Http http = new Http();
        HttpResponse res;
        
        try {
            res = http.send(req);
            if (res.getStatusCode() == 200) {
                System.debug('Response from server: ' + res.getBody());
                return 'Success';
            } else {
                System.debug('Error from server: ' + res.getStatusCode() + ' ' + res.getBody());
                return 'Failed';
            }
        } catch(System.CalloutException e) {
            System.debug('Callout error: ' + e.getMessage());
            return 'Failed';
        }
    }
}