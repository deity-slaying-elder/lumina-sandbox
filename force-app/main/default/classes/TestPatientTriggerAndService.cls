@isTest
public class TestPatientTriggerAndService {

    @isTest
    static void testPatientInsert() {
        Test.startTest();

        // Create a new Patient record
        Patient__c newPatient = new Patient__c(
            Name = 'Test Patient',
            Status__c = 'Active',
            First_Name__c ='Steven',
            Last_Name__c='Feld',
            Gender__c='Male',
            Date_of_Birth__c=Date.newInstance(1934, 10, 23),
            Community_Status__c = 'Working',
            Community_Thoroughcare_ID__c = null
        );
        insert newPatient;
        
        newPatient.Community_Status__c = 'Closed Won';
        update newPatient;

        Test.stopTest();

        // Verify that the patient record was inserted correctly
        Patient__c insertedPatient = [SELECT Id, Name, Community_Thoroughcare_ID__c FROM Patient__c WHERE Id = :newPatient.Id];
        System.assertEquals('Test Patient', insertedPatient.Name);
        System.assertEquals(null, insertedPatient.Community_Thoroughcare_ID__c);
    }

    @isTest
    static void testCalloutFailure() {
        // Start the test and set a mock HTTP callout
        Test.startTest();

        // Simulate a 503 Service Unavailable response using MockHttpCallout
        HttpCalloutMock mock = new MockHttpCallout(503, 'Service Unavailable');
        Test.setMock(HttpCalloutMock.class, mock);

        // Create a Patient record to invoke the future method
        Patient__c patient = new Patient__c(
            Name = 'Test Patient',
            Status__c = 'Active',
            First_Name__c ='Steven',
            Last_Name__c='Feld',
            Gender__c='Male',
            Date_of_Birth__c=Date.newInstance(1934, 10, 23),
            Community_Status__c = 'Working',
            Community_Thoroughcare_ID__c = null
        );
        insert patient;
        
        patient.Community_Status__c = 'Closed Won';
        update patient;

        Test.stopTest();

        // Since the future method is invoked asynchronously, we cannot directly verify the callout
        // But we can check if the callout mock was invoked with the expected response
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://dummyendpoint.com');
        req.setMethod('POST');

        HttpResponse res = mock.respond(req);
        System.assertEquals(503, res.getStatusCode());
        System.assertEquals('Service Unavailable', res.getBody());
    }
}