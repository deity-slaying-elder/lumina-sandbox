trigger FacilityMapperTrigger on Facility_Mapper__c (after update) {

    if (TriggerContext.isBypassed('FacilityMapperTrigger')) {
        return;
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        FacilityMapperTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
