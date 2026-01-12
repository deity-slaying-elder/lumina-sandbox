trigger OpportunityTrigger on Opportunity (before insert, before update) {

    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            OpportunityTriggerHandler.beforeInsert(Trigger.new);
        }
        else if (Trigger.isUpdate) {
            OpportunityTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}