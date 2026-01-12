public class SendPatientIdToThoroughCare implements Queueable, Database.AllowsCallouts {

    private Id patientId;
    private Boolean isSandbox;

    // Constructor to initialize the patient ID and environment boolean
    public SendPatientIdToThoroughCare(Id patientId, Boolean isSandbox) {
        this.patientId = patientId;
        this.isSandbox = isSandbox;
    }

    // Invocable method to receive inputs from the Flow and queue the job
    @InvocableMethod(label='Send Patient ID to ThoroughCare' description='Send a Patient record ID to the ThoroughCare endpoint')
    public static void sendPatientId(List<PatientDataWrapper> inputs) {
        // Ensure we have at least one input
        if (inputs == null || inputs.isEmpty()) {
            throw new IllegalArgumentException('Input data is required');
        }

        // Get the first input object from the list
        PatientDataWrapper input = inputs[0];
        System.debug('Debug: Patient ID being sent: ' + input.patientId);
        System.debug('Debug: isSandbox: ' + input.isSandbox);

        // Queue the job for asynchronous processing
        System.enqueueJob(new SendPatientIdToThoroughCare(input.patientId, input.isSandbox));
    }

    // Queueable interface execute method for asynchronous processing
    public void execute(QueueableContext context) {
        System.debug('Debug: Asynchronous Job Running for Patient ID: ' + patientId);
        System.debug('Debug: isSandbox: ' + isSandbox);

        // Determine the endpoint based on the sandbox boolean
        String endpointUrl;
        if (isSandbox) {
            endpointUrl = 'https://lumina-be-368147deb4ac.herokuapp.com/create-thoroughcare-patient';
            System.debug('Debug: Environment detected as Sandbox');
        } else {
            endpointUrl = 'https://lumina-production-16b22bde10a9.herokuapp.com/create-thoroughcare-patient';
            System.debug('Debug: Environment detected as Production');
        }

        // Add the `sf_id` as a query parameter to the endpoint URL
        String finalEndpointUrl = endpointUrl + '?sf_id=' + patientId;
        System.debug('Debug: Final Endpoint being used with Query Parameter: ' + finalEndpointUrl);

        // Create HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint(finalEndpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        
        // Assuming no body is needed for the POST request
        req.setBody('{}');  // Or you can leave this empty if the API doesn't expect a body

        System.debug('Debug: HTTP Request Body: ' + req.getBody());

        Integer retryCount = 0;
        Boolean success = false;

        // Retry logic for handling 503 errors (without System.sleep())
        while (retryCount < 3 && !success) {
            Http http = new Http();
            try {
                HttpResponse res = http.send(req);
                System.debug('Debug: HTTP Response Status Code: ' + res.getStatusCode());
                System.debug('Debug: HTTP Response Body: ' + res.getBody());

                if (res.getStatusCode() == 200) {
                    success = true; // Exit the loop if successful
                }
            } catch (Exception e) {
                System.debug('Debug: Error during HTTP callout: ' + e.getMessage());
                throw new CalloutException('Error occurred during HTTP callout: ' + e.getMessage());
            }
        }

        if (!success) {
            throw new CalloutException('Failed to send patient ID after multiple attempts due to Service Unavailability (503).');
        }
    }

    // Wrapper class for the inputs
    public class PatientDataWrapper {
        @InvocableVariable
        public Id patientId;

        @InvocableVariable
        public Boolean isSandbox;
    }
}