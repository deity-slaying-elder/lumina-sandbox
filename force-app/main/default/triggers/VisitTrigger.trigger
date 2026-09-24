/**
 * All logic lives in Trigger_Action__mdt records for Visit__c.
 * Add, reorder or deactivate behaviour in Setup, not here - ticking Bypass Execution
 * on an action record now works, because MetadataTriggerHandler reads the records.
 *
 * TriggerContext.isBypassed stays as the org-wide incident lever: the All_Triggers
 * record in Trigger_Bypass__mdt stops every converted trigger in one move, separate
 * from the framework's per-action and per-object switches. Both exist on purpose.
 */
trigger VisitTrigger on Visit__c (after insert, after update) {
    if (TriggerContext.isBypassed('VisitTrigger')) {
        return;
    }
    new MetadataTriggerHandler().run();
}
