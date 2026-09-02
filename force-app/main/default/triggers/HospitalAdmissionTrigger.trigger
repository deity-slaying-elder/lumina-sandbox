trigger HospitalAdmissionTrigger on Hospital_Admission__c (after insert, after update) {

    if (TriggerContext.isBypassed('HospitalAdmissionTrigger')) {
        return;
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            HospitalAdmissionTriggerHandler.afterInsert(Trigger.new);
        }
        else if (Trigger.isUpdate) {
            HospitalAdmissionTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
