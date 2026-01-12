@isTest
public class SendPatientIdToThoroughCareTest {
    
    @isTest
    static void testSendPatientIdInSandbox() {
        // Create a mock HTTP response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());

        // Create a dummy Patient__c record
        Patient__c patient = new Patient__c(Name='Test Patient', First_Name__c='Test',Last_Name__c='Steven',
                                            Status__c='Inactive',Date_of_Birth__c=Date.newInstance(1934, 10, 23), Gender__c='Male');
        insert patient;

        // Simulate sandbox environment
        Test.setCurrentPageReference(new PageReference('https://sandbox.salesforce.com'));

        // Create a PatientDataWrapper object
        SendPatientIdToThoroughCare.PatientDataWrapper wrapper = new SendPatientIdToThoroughCare.PatientDataWrapper();
        wrapper.patientId = patient.Id;
        wrapper.isSandbox = true;

        // Create a list with the wrapper object to simulate the flow passing it
        List<SendPatientIdToThoroughCare.PatientDataWrapper> inputs = new List<SendPatientIdToThoroughCare.PatientDataWrapper>{wrapper};

        // Call the invocable method
        Test.startTest();
        SendPatientIdToThoroughCare.sendPatientId(inputs);
        Test.stopTest();
    }
    
    @isTest
    static void testSendPatientIdInProduction() {
        // Create a mock HTTP response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());

        // Create a dummy Patient__c record
        Patient__c patient = new Patient__c(Name='Test Patient', First_Name__c='Test',Last_Name__c='Steven',
                                            Status__c='Inactive',Date_of_Birth__c=Date.newInstance(1934, 10, 23), Gender__c='Male');
        insert patient;

        // Simulate production environment
        Test.setCurrentPageReference(new PageReference('https://salesforce.com'));

        // Create a PatientDataWrapper object
        SendPatientIdToThoroughCare.PatientDataWrapper wrapper = new SendPatientIdToThoroughCare.PatientDataWrapper();
        wrapper.patientId = patient.Id;
        wrapper.isSandbox = false;

        // Create a list with the wrapper object to simulate the flow passing it
        List<SendPatientIdToThoroughCare.PatientDataWrapper> inputs = new List<SendPatientIdToThoroughCare.PatientDataWrapper>{wrapper};

        // Call the invocable method
        Test.startTest();
        SendPatientIdToThoroughCare.sendPatientId(inputs);
        Test.stopTest();
    }
    
    // Mock HTTP response class
    private class MockHttpResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }
}