@isTest
private class PatientTriggerHandlerTest {

    @isTest
    static void testSetLocalAppointmentTimes_NewPatients() {
        // Create test patients with appointment times
        List<Patient__c> newPatients = new List<Patient__c>();
        DateTime appointmentTime = DateTime.now().addDays(7);

        for (Integer i = 0; i < 5; i++) {
            Patient__c patient = new Patient__c(
                First_Name__c = 'Test',
                Last_Name__c = 'Patient ' + i,
                Status__c = 'Active',
                Appointment_Date_Time__c = appointmentTime.addHours(i)
            );
            newPatients.add(patient);
        }

        insert newPatients;

        Test.startTest();
        PatientTriggerHandler.setLocalAppointmentTimes(newPatients, null);
        Test.stopTest();

        // Verify that appointment time text was set
        List<Patient__c> updatedPatients = [
            SELECT Id, Appointment_Time_in_Text__c
            FROM Patient__c
            WHERE Id IN :newPatients
        ];

        for (Patient__c patient : updatedPatients) {
            System.assertNotEquals(null, patient.Appointment_Time_in_Text__c,
                'Appointment time text should be set');
        }
    }

    @isTest
    static void testSetLocalAppointmentTimes_UpdatedPatients() {
        // Create and insert test patient
        Patient__c patient = new Patient__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Patient',
            Status__c = 'Active',
            Appointment_Date_Time__c = DateTime.now().addDays(5)
        );
        insert patient;

        // Create old map simulating the before state
        Map<Id, Patient__c> oldMap = new Map<Id, Patient__c>();
        oldMap.put(patient.Id, patient.clone(true, true, true, true));

        // Update appointment time
        DateTime newAppointmentTime = DateTime.now().addDays(10);
        patient.Appointment_Date_Time__c = newAppointmentTime;

        Test.startTest();
        PatientTriggerHandler.setLocalAppointmentTimes(
            new List<Patient__c>{ patient },
            oldMap
        );
        Test.stopTest();

        System.assertNotEquals(null, patient.Appointment_Time_in_Text__c,
            'Appointment time text should be updated');
    }

    @isTest
    static void testSetLocalAppointmentTimes_UnchangedAppointment() {
        // Create and insert test patient
        Patient__c patient = new Patient__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Patient',
            Status__c = 'Active',
            Appointment_Date_Time__c = DateTime.now().addDays(5),
            Appointment_Time_in_Text__c = '10:00 AM'
        );
        insert patient;

        // Create old map with same appointment time
        Map<Id, Patient__c> oldMap = new Map<Id, Patient__c>();
        Patient__c oldPatient = patient.clone(true, true, true, true);
        oldMap.put(patient.Id, oldPatient);

        String originalTimeText = patient.Appointment_Time_in_Text__c;

        Test.startTest();
        PatientTriggerHandler.setLocalAppointmentTimes(
            new List<Patient__c>{ patient },
            oldMap
        );
        Test.stopTest();

        // Should not have changed since appointment time didn't change
        System.assertEquals(originalTimeText, patient.Appointment_Time_in_Text__c,
            'Appointment time text should remain unchanged');
    }

    @isTest
    static void testSetLocalAppointmentTimes_NullAppointment() {
        // Create test patient without appointment time
        Patient__c patient = new Patient__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Patient',
            Status__c = 'Active'
        );
        insert patient;

        Test.startTest();
        PatientTriggerHandler.setLocalAppointmentTimes(
            new List<Patient__c>{ patient },
            null
        );
        Test.stopTest();

        Patient__c updatedPatient = [
            SELECT Id, Appointment_Time_in_Text__c
            FROM Patient__c
            WHERE Id = :patient.Id
        ];

        System.assertEquals(null, updatedPatient.Appointment_Time_in_Text__c,
            'Appointment time text should be null when appointment is null');
    }

    @isTest
    static void testUpdateAppointmentTimeText() {
        // Create test patients
        List<Patient__c> patients = new List<Patient__c>();
        DateTime appointmentTime = DateTime.newInstance(2025, 6, 15, 13, 30, 0);

        for (Integer i = 0; i < 3; i++) {
            Patient__c patient = new Patient__c(
                Name = 'Test Patient ' + i,
                Appointment_Date_Time__c = appointmentTime.addHours(i)
            );
            patients.add(patient);
        }

        Test.startTest();
        PatientTriggerHandler.updateAppointmentTimeText(patients);
        Test.stopTest();

        // Verify all patients have appointment time text set
        for (Patient__c patient : patients) {
            System.assertNotEquals(null, patient.Appointment_Time_in_Text__c,
                'Appointment time text should be populated');
            System.assert(patient.Appointment_Time_in_Text__c.contains('AM') ||
                         patient.Appointment_Time_in_Text__c.contains('PM'),
                'Time should include AM/PM indicator');
        }
    }

    @isTest
    static void testFormatTimeInUserTimezone_Morning() {
        TimeZone userTZ = TimeZone.getTimeZone(UserInfo.getTimeZone().getID());
        DateTime morningTime = DateTime.newInstance(2025, 6, 15, 9, 15, 0);

        Test.startTest();
        String formattedTime = PatientTriggerHandler.formatTimeInUserTimezone(
            morningTime,
            userTZ
        );
        Test.stopTest();

        System.assertNotEquals(null, formattedTime, 'Formatted time should not be null');
        System.assert(formattedTime.contains(':'), 'Time should contain colon separator');
        System.assert(formattedTime.contains('AM') || formattedTime.contains('PM'),
            'Time should include AM/PM indicator');
    }

    @isTest
    static void testFormatTimeInUserTimezone_Afternoon() {
        TimeZone userTZ = TimeZone.getTimeZone(UserInfo.getTimeZone().getID());
        DateTime afternoonTime = DateTime.newInstance(2025, 6, 15, 15, 45, 0);

        Test.startTest();
        String formattedTime = PatientTriggerHandler.formatTimeInUserTimezone(
            afternoonTime,
            userTZ
        );
        Test.stopTest();

        System.assertNotEquals(null, formattedTime, 'Formatted time should not be null');
        System.assert(formattedTime.contains(':'), 'Time should contain colon separator');
        System.assert(formattedTime.contains('AM') || formattedTime.contains('PM'),
            'Time should include AM/PM indicator');
    }

    @isTest
    static void testFormatTimeInUserTimezone_Midnight() {
        TimeZone userTZ = TimeZone.getTimeZone(UserInfo.getTimeZone().getID());
        DateTime midnightTime = DateTime.newInstance(2025, 6, 15, 0, 0, 0);

        Test.startTest();
        String formattedTime = PatientTriggerHandler.formatTimeInUserTimezone(
            midnightTime,
            userTZ
        );
        Test.stopTest();

        System.assertNotEquals(null, formattedTime, 'Formatted time should not be null');
        System.assert(formattedTime.contains('12:'), 'Midnight should display as 12');
        System.assert(formattedTime.contains('AM'), 'Midnight should be AM');
    }

    @isTest
    static void testFormatTimeInUserTimezone_Noon() {
        TimeZone userTZ = TimeZone.getTimeZone(UserInfo.getTimeZone().getID());
        DateTime noonTime = DateTime.newInstance(2025, 6, 15, 12, 0, 0);

        Test.startTest();
        String formattedTime = PatientTriggerHandler.formatTimeInUserTimezone(
            noonTime,
            userTZ
        );
        Test.stopTest();

        System.assertNotEquals(null, formattedTime, 'Formatted time should not be null');
        System.assert(formattedTime.contains('12:'), 'Noon should display as 12');
        System.assert(formattedTime.contains('PM'), 'Noon should be PM');
    }

    @isTest
    static void testBulkProcessing() {
        // Test with larger volume to ensure bulk processing works
        List<Patient__c> patients = new List<Patient__c>();
        DateTime baseTime = DateTime.now().addDays(14);

        for (Integer i = 0; i < 200; i++) {
            Patient__c patient = new Patient__c(
                First_Name__c = 'Bulk',
                Last_Name__c = 'Patient ' + i,
                Status__c = 'Active',
                Appointment_Date_Time__c = baseTime.addMinutes(i * 30)
            );
            patients.add(patient);
        }

        insert patients;

        Test.startTest();
        PatientTriggerHandler.setLocalAppointmentTimes(patients, null);
        Test.stopTest();

        List<Patient__c> updatedPatients = [
            SELECT Id, Appointment_Time_in_Text__c
            FROM Patient__c
            WHERE Id IN :patients
        ];

        System.assertEquals(200, updatedPatients.size(),
            'All patients should be processed');

        for (Patient__c patient : updatedPatients) {
            System.assertNotEquals(null, patient.Appointment_Time_in_Text__c,
                'All appointment times should be formatted');
        }
    }
}