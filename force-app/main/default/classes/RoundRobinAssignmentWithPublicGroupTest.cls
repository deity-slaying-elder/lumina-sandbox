@isTest
public class RoundRobinAssignmentWithPublicGroupTest {

    @testSetup
    static void setup() {
        // Create a test user and insert it with runAs to avoid mixed DML issues
        Profile p = [SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1];
        
        User coordinator1 = new User(
            FirstName = 'Test',
            LastName = 'Coordinator1',
            Email = 'coordinator1@test.com',
            Username = 'coordinator1@test.com' + System.currentTimeMillis(),
            ProfileId = p.Id,
            Alias = 'coord1',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        
        User coordinator2 = new User(
            FirstName = 'Test',
            LastName = 'Coordinator2',
            Email = 'coordinator2@test.com',
            Username = 'coordinator2@test.com' + System.currentTimeMillis(),
            ProfileId = p.Id,
            Alias = 'coord2',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        
        // Insert the users inside a System.runAs block to prevent mixed DML issues
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{coordinator1, coordinator2};

            // Create a public group "Custom Coordinators" and add the users
            Group customCoordinatorsGroup = new Group(
                Name = 'Custom Coordinators',
                DeveloperName = 'Custom_Coordinators',
                Type = 'Regular'
            );
            insert customCoordinatorsGroup;

            GroupMember gm1 = new GroupMember(
                GroupId = customCoordinatorsGroup.Id,
                UserOrGroupId = coordinator1.Id
            );
            GroupMember gm2 = new GroupMember(
                GroupId = customCoordinatorsGroup.Id,
                UserOrGroupId = coordinator2.Id
            );

            insert new List<GroupMember>{gm1, gm2};
        }

        // Now insert non-setup objects like Patient__c in the regular context
        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < 5; i++) {
            patients.add(new Patient__c(Name = 'Test Patient ' + i, First_Name__c='Steven', Last_Name__c='Feld',Status__c='Active'));
        }
        insert patients;

        // Create or ensure a custom setting exists
        IcAssignment__c assignmentSetting = new IcAssignment__c();
        assignmentSetting.LastAssignedIC__c = 0;
        insert assignmentSetting;
    }

    @isTest
    static void testRoundRobinAssignment() {
        // Retrieve the test patient IDs
        List<Patient__c> patients = [SELECT Id FROM Patient__c];

        // Prepare the request with the custom group name "Custom Coordinators"
        RoundRobinAssignmentWithPublicGroup.RoundRobinRequest request = new RoundRobinAssignmentWithPublicGroup.RoundRobinRequest();
        request.patientIds = new List<Id>();
        request.groupName = 'Custom Coordinators';
        
        for (Patient__c patient : patients) {
            request.patientIds.add(patient.Id);
        }

        // Call the invocable method
        RoundRobinAssignmentWithPublicGroup.assignCoordinator(new List<RoundRobinAssignmentWithPublicGroup.RoundRobinRequest>{request});

        // Verify the assignments
        List<Patient__c> updatedPatients = [SELECT Id, OwnerId FROM Patient__c];
        List<User> coordinators = [SELECT Id FROM User WHERE Email LIKE '%coordinator%'];

        Integer coordinator1Count = 0;
        Integer coordinator2Count = 0;

        for (Patient__c patient : updatedPatients) {
            if (patient.OwnerId == coordinators[0].Id) {
                coordinator1Count++;
            } else if (patient.OwnerId == coordinators[1].Id) {
                coordinator2Count++;
            }
        }

        // Verify that the assignments were distributed between the coordinators
        System.assertEquals(3, coordinator1Count, 'Coordinator 1 should have 2 patients');
        System.assertEquals(2, coordinator2Count, 'Coordinator 2 should have 3 patients');
    }
    
    @isTest
    static void testFailsafeRoundRobinAssignment() {
        // Retrieve the test patient IDs
        List<Patient__c> patients = [SELECT Id FROM Patient__c LIMIT 1];

        // Prepare the request with the custom group name "Custom Coordinators"
        RoundRobinAssignmentWithPublicGroup.RoundRobinRequest request = new RoundRobinAssignmentWithPublicGroup.RoundRobinRequest();
        request.patientIds = new List<Id>{patients[0].Id};
        request.groupName = 'Custom Coordinators';

        // Try to get the custom setting record
        List<IcAssignment__c> assignmentSettingList = [SELECT Id, LastAssignedIC__c FROM IcAssignment__c LIMIT 1];
        if (!assignmentSettingList.isEmpty()) {
            // Corrupt custom setting to simulate a failsafe
            delete assignmentSettingList[0];
        }

        // Call the invocable method
        RoundRobinAssignmentWithPublicGroup.assignCoordinator(new List<RoundRobinAssignmentWithPublicGroup.RoundRobinRequest>{request});

        // Verify the patient was assigned using the failsafe
        Patient__c updatedPatient = [SELECT Id, OwnerId FROM Patient__c WHERE Id = :patients[0].Id];
        List<User> coordinators = [SELECT Id FROM User WHERE Email LIKE '%coordinator%'];

        System.assert(updatedPatient.OwnerId == coordinators[0].Id || updatedPatient.OwnerId == coordinators[1].Id, 
            'Patient should be assigned to one of the coordinators');
    }
}