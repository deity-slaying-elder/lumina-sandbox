trigger VisitTrigger on Visit__c (after insert, after update) {

    if (TriggerContext.isBypassed('VisitTrigger')) {
        return;
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            VisitTriggerHandler.afterInsert(Trigger.new);
        }
        else if (Trigger.isUpdate) {
            VisitTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
