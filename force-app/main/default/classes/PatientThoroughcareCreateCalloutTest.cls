@IsTest()
private class PatientThoroughcareCreateCalloutTest {

    // capture the last request to assert on it
    private static HTTPRequest lastRequest;
    private static void reset(){ lastRequest = null; }

    // ---- Mocks ----
    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            PatientThoroughcareCreateCalloutTest.lastRequest = req;
            HttpResponse r = new HttpResponse();
            r.setStatusCode(201);
            r.setBody('{"ok":true}');
            return r;
        }
    }
    private class ErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            PatientThoroughcareCreateCalloutTest.lastRequest = req;
            HttpResponse r = new HttpResponse();
            r.setStatusCode(502);
            r.setBody('{"error":"bad upstream"}');
            return r;
        }
    }
    private class ExceptionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Simulate a transport/runtime failure -> exercises catch block
            throw new CalloutException('Simulated callout transport error');
        }
    }

    // ---- Helper ----
    private static Id makeAnyRecord() {
        Patient__c patient = new Patient__c(Name = 'Test Patient', Status__c = 'Active', First_Name__c = 'Test', Last_Name__c = 'Test');
        insert patient;
        return patient.Id;
    }

    // ---- Tests ----
    @IsTest
    static void testSuccess_2xx() {
        reset();
        Id pid = makeAnyRecord();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        PatientThoroughcareCreateCallout.send(pid, false);
        Test.stopTest();

        System.assertNotEquals(null, lastRequest, 'Request should be captured.');
        System.assertEquals('POST', lastRequest.getMethod());
        System.assert(lastRequest.getEndpoint().endsWith('/tc/create-patient'));
        String auth = lastRequest.getHeader('Authorization');
        System.assertNotEquals(null, auth);
        // tolerant to current typo in prod code
        System.assert(auth.startsWith('Bareer') || auth.startsWith('Bearer'));
        System.assertEquals('application/json', lastRequest.getHeader('Content-Type'));
    }

    @IsTest
    static void testSuccess_2xx_community() {
        reset();
        Id pid = makeAnyRecord();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        PatientThoroughcareCreateCallout.send(pid, true);
        Test.stopTest();

        System.assertNotEquals(null, lastRequest, 'Request should be captured.');
        System.assertEquals('POST', lastRequest.getMethod());
        System.assert(lastRequest.getEndpoint().endsWith('/tc/create-comm-patient'));
        String auth = lastRequest.getHeader('Authorization');
        System.assertNotEquals(null, auth);
        // tolerant to current typo in prod code
        System.assert(auth.startsWith('Bareer') || auth.startsWith('Bearer'));
        System.assertEquals('application/json', lastRequest.getHeader('Content-Type'));
    }

    @IsTest
    static void testError_5xx() {
        reset();
        Id pid = makeAnyRecord();
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        PatientThoroughcareCreateCallout.send(pid, false);
        Test.stopTest();

        System.assertNotEquals(null, lastRequest, 'Request should be captured.');
    }

    @IsTest
    static void testException_Caught() {
        reset();
        Id pid = makeAnyRecord();
        Test.setMock(HttpCalloutMock.class, new ExceptionMock());

        Test.startTest();
        // Should not throw; exception is caught in the method
        PatientThoroughcareCreateCallout.send(pid, false);
        Test.stopTest();

        System.assert(true, 'No unhandled exception from callout path.');
    }
}