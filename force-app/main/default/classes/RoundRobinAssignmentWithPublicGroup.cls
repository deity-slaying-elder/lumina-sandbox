public with sharing class RoundRobinAssignmentWithPublicGroup {

    // List of Intake Coordinators
    private static List<User> intakeCoordinators;

    // Invocable class to pass parameters like patient IDs and group name
    public class RoundRobinRequest {
        @InvocableVariable(label='Patient IDs' required=true)
        public List<Id> patientIds;

        @InvocableVariable(label='Group Name' required=true)
        public String groupName;
    }

    @InvocableMethod(label='Assign Intake Coordinator' description='Assign a Patient to an Intake Coordinator in round robin')
    public static void assignCoordinator(List<RoundRobinRequest> requests) {
        for (RoundRobinRequest request : requests) {
            Integer currentCoordinatorIndex;
            Boolean usedFailsafe = false;

            // Get the list of Intake Coordinators from the provided Public Group
            if (intakeCoordinators == null) {
                // Step 1: Get the UserOrGroupId for all active users in the provided public group
                List<GroupMember> groupMembers = [SELECT UserOrGroupId 
                                                  FROM GroupMember 
                                                  WHERE Group.Name = :request.groupName 
                                                  AND UserOrGroupId IN (SELECT Id FROM User WHERE IsActive = TRUE)];

                // Step 2: Extract the UserOrGroupIds and query the User records
                List<Id> coordinatorIds = new List<Id>();
                for (GroupMember gm : groupMembers) {
                    coordinatorIds.add(gm.UserOrGroupId);
                }

                intakeCoordinators = [SELECT Id FROM User WHERE Id IN :coordinatorIds AND IsActive = TRUE];
            }

            if (intakeCoordinators.isEmpty()) {
                throw new AuraHandledException('No active Intake Coordinators found in the public group: ' + request.groupName);
            }

            Integer coordinatorCount = intakeCoordinators.size();

            // Try to lock and fetch the latest round robin index from custom settings with FOR UPDATE
            try {
                IcAssignment__c roundRobinSetting = [SELECT LastAssignedIC__c FROM IcAssignment__c LIMIT 1 FOR UPDATE];

                if (roundRobinSetting == null) {
                    roundRobinSetting = new IcAssignment__c();
                    roundRobinSetting.LastAssignedIC__c = 0;
                }

                // Get the current coordinator index from the setting and cast to Integer
                currentCoordinatorIndex = Integer.valueOf(roundRobinSetting.LastAssignedIC__c);
            } catch (QueryException e) {
                // Failsafe: If the custom setting is locked, start from index 0
                currentCoordinatorIndex = 0;
                usedFailsafe = true;
            }

            List<Patient__c> patientsToUpdate = new List<Patient__c>();

            for (Id patientId : request.patientIds) {
                // Get the next coordinator in round robin
                User assignedCoordinator = intakeCoordinators[currentCoordinatorIndex];

                // Create a Patient__c record to be updated
                Patient__c patient = new Patient__c(
                    Id = patientId,
                    OwnerId = assignedCoordinator.Id
                );

                patientsToUpdate.add(patient);

                currentCoordinatorIndex++;
                if (currentCoordinatorIndex >= coordinatorCount) {
                    currentCoordinatorIndex = 0; // Wrap around if we exceed the number of coordinators
                }
            }

            // Update the patient records with the assigned coordinators
            if (!patientsToUpdate.isEmpty()) {
                update patientsToUpdate;
            }

            List<IcAssignment__c> existingSettings = [SELECT Id, LastAssignedIC__c FROM IcAssignment__c LIMIT 1];

            if (!existingSettings.isEmpty()) {
                // If a record exists, update the existing custom setting
                IcAssignment__c existingSetting = existingSettings[0];
                existingSetting.LastAssignedIC__c = currentCoordinatorIndex;
                update existingSetting;
            } else if (!usedFailsafe) {
                // If no existing record is found, insert a new one
                IcAssignment__c roundRobinSettingToUpdate = new IcAssignment__c();
                roundRobinSettingToUpdate.LastAssignedIC__c = currentCoordinatorIndex;
                insert roundRobinSettingToUpdate;
            }
        }
    }
}