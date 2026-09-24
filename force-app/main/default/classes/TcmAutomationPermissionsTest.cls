/**
 * Proves the converted TCM automation behaves like the flows it replaced for the
 * least-privileged user possible.
 *
 * Record-triggered flows run in system context: whoever saved the record, the flow's
 * writes landed. An Apex port that enforces the running user's field permissions
 * (stripInaccessible, WITH USER_MODE) silently drops those same writes for restricted
 * profiles - no error, no log, the field just stays empty. On a TCM billing field
 * that is money lost invisibly, and this org already has a field nobody can see:
 * Latest_Community_Episode__c carries no field permissions for any profile.
 *
 * So these tests run the full discharge cascade as a Minimum Access user, the most
 * restricted standard profile in the org, and assert every automated write landed -
 * including the write to the zero-FLS field, which is exactly the write user-mode
 * enforcement would have thrown away. If somebody reintroduces stripInaccessible or
 * USER_MODE into an action, this class fails.
 */
@isTest
private class TcmAutomationPermissionsTest {

    /**
     * Runs the discharge cascade as a user on each real business profile - the people
     * who actually save these records day to day. Minimum Access (below) proves the
     * worst case; this proves nobody's actual profile behaves differently.
     */
    @isTest
    static void dischargeCascadeRunsForEveryBusinessProfile() {
        List<Profile> profiles = [
            SELECT Id, Name FROM Profile
            WHERE Name IN ('Lumina Manager', 'Intake Coordinator', 'Intake Coordinator Manager',
                           'Lumina Sales', 'Scheduling')
        ];
        Assert.isFalse(profiles.isEmpty(), 'The business profiles should exist in this org');
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();

        List<User> users = new List<User>();
        for (Profile prof : profiles) {
            String stamp = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
            users.add(new User(
                Alias = 'tq' + String.valueOf(users.size()),
                Email = 'tcm.qa@example.invalid',
                Username = 'tcm.qa.' + stamp + '@lumina.test.invalid',
                LastName = 'Matrix' + prof.Name.replaceAll('[^A-Za-z]', ''),
                ProfileId = prof.Id,
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            ));
        }
        insert users;

        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < users.size(); i++) {
            patients.add(new Patient__c(
                First_Name__c = 'Matrix', Last_Name__c = 'Profile' + i, Status__c = 'Active',
                Community_Status__c = 'Working',
                Latest_Call_Outcome__c = Date.today().addDays(-40)
            ));
        }
        insert patients;

        Test.startTest();
        for (Integer i = 0; i < users.size(); i++) {
            System.runAs(users[i]) {
                insert new Admission_Discharge__c(
                    Patient__c = patients[i].Id, Type__c = 'Discharge',
                    Census_Date__c = Datetime.now().addDays(-1)
                );
            }
        }
        Test.stopTest();

        for (Integer i = 0; i < users.size(); i++) {
            Patient__c after = [
                SELECT Community_Status__c, Latest_Discharge__c, Latest_Community_Episode__c
                FROM Patient__c WHERE Id = :patients[i].Id
            ];
            String who = profiles[i].Name;
            Assert.areEqual('New', after.Community_Status__c,
                'Reclaim must run when saved by ' + who);
            Assert.areNotEqual(null, after.Latest_Discharge__c,
                'Latest discharge must be stamped when saved by ' + who);
            Assert.areNotEqual(null, after.Latest_Community_Episode__c,
                'Episode link must be written when saved by ' + who);
            Assert.areEqual(1,
                [SELECT COUNT() FROM Community_Episode__c WHERE Patient__c = :patients[i].Id],
                'Episode must be created when saved by ' + who);
        }
    }

    private static User minimumAccessUser() {
        Profile restricted = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        String stamp = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Alias = 'tcmqa',
            Email = 'tcm.qa@example.invalid',
            Username = 'tcm.qa.' + stamp + '@lumina.test.invalid',
            LastName = 'TcmQa',
            ProfileId = restricted.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    @isTest
    static void dischargeCascadeRunsInFullForARestrictedUser() {
        // Admin-owned data, saved by a restricted user - the flow-era arrangement.
        Patient__c patient = new Patient__c(
            First_Name__c = 'Restricted', Last_Name__c = 'Cascade', Status__c = 'Active',
            Community_Status__c = 'Working',
            Latest_Call_Outcome__c = Date.today().addDays(-40)
        );
        insert patient;
        TcmSettings.reclaimOwnerOverride = UserInfo.getUserId();
        User restricted = minimumAccessUser();

        Test.startTest();
        System.runAs(restricted) {
            // Plain Apex DML does not check object CRUD, so the insert itself goes
            // through; what a user-mode port would lose is every write AFTER it.
            insert new Admission_Discharge__c(
                Patient__c = patient.Id, Type__c = 'Discharge',
                Census_Date__c = Datetime.now().addDays(-1)
            );
        }
        Test.stopTest();

        // AdmissionDischargeCreateEpisode wrote the episode.
        List<Community_Episode__c> episodes = [
            SELECT Id, Community_Status__c FROM Community_Episode__c WHERE Patient__c = :patient.Id
        ];
        Assert.areEqual(1, episodes.size(),
            'The episode must be created no matter who saved the discharge');
        Assert.areEqual('New', episodes[0].Community_Status__c, 'Episode status lands');

        Patient__c after = [
            SELECT Community_Status__c, Community_Status_Updated_Date_Time__c,
                   Latest_Discharge__c, Latest_Community_Episode__c, OwnerId
            FROM Patient__c WHERE Id = :patient.Id
        ];
        // AdmissionDischargeSetLatest wrote the lookup.
        Assert.areNotEqual(null, after.Latest_Discharge__c,
            'Latest_Discharge__c must be stamped for a restricted user');
        // PatientSetStatusOnNewDischarge reclaimed the patient.
        Assert.areEqual('New', after.Community_Status__c,
            'The reclaim must run for a restricted user');
        Assert.areNotEqual(null, after.Community_Status_Updated_Date_Time__c,
            'The reclaim timestamp must land for a restricted user');
        // CommunityEpisodeSetLatestOnPatient wrote the field NO profile has FLS on.
        // This single assertion is the whole reason the actions run in system mode:
        // stripInaccessible would have dropped this write for every user in the org.
        Assert.areEqual(episodes[0].Id, after.Latest_Community_Episode__c,
            'The zero-FLS lookup must still be written, exactly as the flow wrote it');
    }

    @isTest
    static void countCallsRunsForARestrictedUser() {
        Patient__c patient = new Patient__c(
            First_Name__c = 'Restricted', Last_Name__c = 'Counter', Status__c = 'Active',
            Discharge_Date__c = Date.today().addDays(-1),
            Count_of_Calls__c = 1
        );
        insert patient;
        User restricted = minimumAccessUser();

        Test.startTest();
        System.runAs(restricted) {
            update new Patient__c(Id = patient.Id, Count_of_Calls__c = 2);
        }
        Test.stopTest();

        Patient__c after = [
            SELECT Count_of_Calls_Within_48_Hours__c FROM Patient__c WHERE Id = :patient.Id
        ];
        Assert.areEqual(1, after.Count_of_Calls_Within_48_Hours__c,
            'The 48-hour billing counter must increment no matter who logged the call');
    }
}
