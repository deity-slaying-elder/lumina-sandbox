@isTest
private class UploadConsentFileCOntrollerTest {
    
    private class MockHttpCalloutSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('Success response');
            return response;
        }
    }

    private class MockHttpCalloutFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(400);
            response.setBody('Failure response');
            return response;
        }
    }

    private static ContentVersion createTestContentVersion(String contentVersionId) {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Test File';
        cv.PathOnClient = 'TestFile.txt';
        cv.VersionData = Blob.valueOf('Test data');
        insert cv;
        return cv;
    }


    @isTest
    static void testProcessTextSuccess() {
        
        Test.setMock(HttpCalloutMock.class, new MockHttpCalloutSuccess());
        ContentVersion cv = createTestContentVersion('dummyId');
        List<String> cvs = new List<String>{cv.Id};
        UploadConsentFileController.InvocableRequest request = new  UploadConsentFileController.InvocableRequest();
        request.contentVersionsCollection = cvs;
        List<UploadConsentFileController.InvocableRequest> requests = new List<UploadConsentFileController.InvocableRequest>{request};
        Test.startTest();
        List<String> response = UploadConsentFileController.processText(requests);
        Test.stopTest();
        System.assertEquals('Success', response[0]);
    }
    
    @isTest
    static void testProcessTextFail() {
        
        Test.setMock(HttpCalloutMock.class, new MockHttpCalloutFailure());
        ContentVersion cv = createTestContentVersion('dummyId');
        List<String> cvs = new List<String>{cv.Id};
        UploadConsentFileController.InvocableRequest request = new UploadConsentFileController.InvocableRequest();
        request.contentVersionsCollection = cvs;
        List<UploadConsentFileController.InvocableRequest> requests = new List<UploadConsentFileController.InvocableRequest>{request};
        Test.startTest();
        List<String> response = UploadConsentFileController.processText(requests);
        Test.stopTest();
        System.assertEquals('Failed', response[0]);
    }
    
}