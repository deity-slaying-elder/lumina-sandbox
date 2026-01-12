@IsTest
private class UserLoginTest {
    
    @IsTest
    static void testSuccessfulLogin() {
        Front_End_User__c testUser = new Front_End_User__c(
            First_Name__c = 'Test',
            Last_Name__c = 'User',
            Email__c = 'testuser@example.com',
            Password__c = 'password123'
        );
        insert testUser;
        
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('{"email": "testuser@example.com", "password": "password123"}');
        RestContext.request = req;
        
        // Set up the response
        RestResponse res = new RestResponse();
        RestContext.response = res;
        
        // Call the method
        UserLogin.LoginUser();
        
        // Verify response
        System.assertEquals(200, res.statusCode);
        String responseBody = res.responseBody.toString();
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        
        System.assertEquals(testUser.Id, responseMap.get('userId'));
        System.assertEquals(testUser.First_Name__c, responseMap.get('firstName'));
        System.assertEquals(testUser.Last_Name__c, responseMap.get('lastName'));
        System.assertEquals(testUser.Email__c, responseMap.get('email'));
    }
    
    @IsTest
    static void testIncorrectPassword() {
        // Set up test data
        Front_End_User__c testUser = new Front_End_User__c(
            First_Name__c = 'Test',
            Last_Name__c = 'User',
            Email__c = 'testuser@example.com',
            Password__c = 'password123'
        );
        insert testUser;
        
        // Set up the request
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('{"email": "testuser@example.com", "password": "wrongpassword"}');
        RestContext.request = req;
        
        // Set up the response
        RestResponse res = new RestResponse();
        RestContext.response = res;
        
        // Call the method
        UserLogin.LoginUser();
        
        // Verify response
        System.assertEquals(401, res.statusCode);
        String responseBody = res.responseBody.toString();
        Map<String, object> responseMap = (Map<String, object>) JSON.deserializeUntyped(responseBody);
        
        System.assertEquals('Incorrect Credentials', responseMap.get('error'));
    }
    
    @IsTest
    static void testUserNotFound() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('{"email": "nonexistent@example.com", "password": "password123"}');
        RestContext.request = req;
        
        RestResponse res = new RestResponse();
        RestContext.response = res;
        
        UserLogin.LoginUser();
        
        System.assertEquals(401, res.statusCode);
        String responseBody = res.responseBody.toString();
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        
        System.assertEquals('User not found', responseMap.get('error'));
    }
    
    @IsTest
    static void testErrorHandling() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('{"email": 12344543, "password": "password123"}');
        RestContext.request = req;
        
        RestResponse res = new RestResponse();
        RestContext.response = res;
        
        Test.startTest();
        Test.setMock(HTTPCalloutMock.class, new MockHttpResponseGenerator());
        Test.stopTest();
        
        UserLogin.LoginUser();
        
        System.assertEquals(500, res.statusCode);
        String responseBody = res.responseBody.toString();
        Map<String, object> responseMap = (Map<String, object>) JSON.deserializeUntyped(responseBody);
        
        System.assertEquals('An error occurred', responseMap.get('error'));
    }
}