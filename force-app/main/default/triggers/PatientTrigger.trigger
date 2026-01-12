trigger PatientTrigger on Patient__c (before insert, before update) {
    // Before Insert
    if(Trigger.isBefore && Trigger.isInsert){
        PatientTriggerHandler.setLocalAppointmentTimes(Trigger.new, null);
    }
    // Before Update
    if(Trigger.isBefore && Trigger.isUpdate){
        PatientTriggerHandler.setLocalAppointmentTimes(Trigger.new, Trigger.oldMap);
    }
}