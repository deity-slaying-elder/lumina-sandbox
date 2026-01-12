@RestResource(urlMapping='/Login/*')
global with sharing class UserLogin {
    
    @HttpPost
    global static void LoginUser() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Deserialize the request body
            Map<String, Object> requestBodyMap = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            String email = (String) requestBodyMap.get('email');
            String password = (String) requestBodyMap.get('password');
            Boolean isConsent = False ;
            // Query for the user
            List<Front_End_User__c> feuList = [SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Password__c FROM Front_End_User__c WHERE Email__c = :email LIMIT 1];

            if (!feuList.isEmpty()) {


                Front_End_User__c feu = feuList[0];
                String feuID = feu.Id;
                List<FE_User_Role__c> feuRoleList = [SELECT Id, Name, Role__r.Name FROM FE_User_Role__c WHERE Front_End_User__c = :feuID AND Role__r.Name = 'Consent Gatherer'  LIMIT 1];
                if (!feuRoleList.isEmpty()) {
                    isConsent = True;
                
                }
                // Check if credentials match
                if (feu.Password__c.equals(password)) {
                    // Successful login
                    res.statusCode = 200;
                    res.addHeader('Content-Type', 'application/json');
                    
                    // Construct response JSON
                    Map<String, Object> responseMap = new Map<String, Object>();
                    responseMap.put('userId', feu.Id);
                    responseMap.put('userName', feu.Name);
                    responseMap.put('firstName', feu.First_Name__c);
                    responseMap.put('lastName', feu.Last_Name__c);
                    responseMap.put('email', feu.Email__c);
                    responseMap.put('isConsent', isConsent);
                    String jsonResponse = JSON.serialize(responseMap);
                    res.responseBody = Blob.valueOf(jsonResponse);
                } else {
                    // Incorrect password
                    res.statusCode = 401;
                    res.addHeader('Content-Type', 'application/json');
                    
                    Map<String, String> errorMap = new Map<String, String>();
                    errorMap.put('error', 'Incorrect Credentials');
                    
                    String jsonResponse = JSON.serialize(errorMap);
                    res.responseBody = Blob.valueOf(jsonResponse);
                }
            } else {
                // User not found
                res.statusCode = 401;
                res.addHeader('Content-Type', 'application/json');
                
                Map<String, String> errorMap = new Map<String, String>();
                errorMap.put('error', 'User not found');
                
                String jsonResponse = JSON.serialize(errorMap);
                res.responseBody = Blob.valueOf(jsonResponse);
            }
            
        } catch (Exception e) {
            // Error occurred
            res.statusCode = 500; // Internal Server Error
            res.addHeader('Content-Type', 'application/json');
            
            Map<String, String> errorMap = new Map<String, String>();
            errorMap.put('error', 'An error occurred');
            
            String jsonResponse = JSON.serialize(errorMap);
            res.responseBody = Blob.valueOf(jsonResponse);
        }
    }
}