public with sharing class PatientTriggerHandler {

    public static void setLocalAppointmentTimes(List<Patient__c> newPatients, Map<Id, Patient__c> oldMap) {
        List<Patient__c> patientsWithAppointments = new List<Patient__c>();
        for (Patient__c patient : newPatients) {
            // Check if appointment time is new or changed
            if (patient.Appointment_Date_Time__c != null) {
                if (oldMap == null || 
                    patient.Appointment_Date_Time__c != oldMap.get(patient.Id).Appointment_Date_Time__c) {
                    patientsWithAppointments.add(patient);
                }
            }
        }
        
        if (!patientsWithAppointments.isEmpty()) {
            PatientTriggerHandler.updateAppointmentTimeText(patientsWithAppointments);
        }
    }
    
    /**
     * Updates the Appointment_Time_in_Text__c field with the localized time
     * based on the current user's timezone
     */
    public static void updateAppointmentTimeText(List<Patient__c> patients) {
        // Get the current user's timezone
        TimeZone userTZ = TimeZone.getTimeZone(UserInfo.getTimeZone().getID());
        
        for (Patient__c patient : patients) {
            if (patient.Appointment_Date_Time__c != null) {
                patient.Appointment_Time_in_Text__c = formatTimeInUserTimezone(
                    patient.Appointment_Date_Time__c, 
                    userTZ
                );
            }
        }
    }
    
    /**
     * Formats a DateTime value as a localized time string (e.g., "1:20 PM")
     */
    public static String formatTimeInUserTimezone(DateTime dt, TimeZone tz) {
        // Get the offset in milliseconds and convert to the local time
        Integer offsetMs = tz.getOffset(dt);
        DateTime localDt = dt.addSeconds(offsetMs / 1000);
        
        // Extract hours and minutes from the adjusted time
        String gmtFormatted = localDt.formatGmt('H:mm');
        List<String> timeParts = gmtFormatted.split(':');
        Integer hour24 = Integer.valueOf(timeParts[0]);
        String minutes = timeParts[1];
        
        // Convert to 12-hour format
        String period = hour24 >= 12 ? 'PM' : 'AM';
        Integer hour12 = Math.mod(hour24, 12);
        if (hour12 == 0) {
            hour12 = 12;
        }
        
        return hour12 + ':' + minutes + ' ' + period;
    }
}