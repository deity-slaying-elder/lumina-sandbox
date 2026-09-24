/**
 * All logic lives in Trigger_Action__mdt records for Report_User_Region__c.
 * Add, reorder or deactivate behaviour in Setup, not here.
 *
 * TriggerContext.isBypassed is the org-wide incident lever, separate from the
 * framework's per-action and per-object switches. Both exist on purpose.
 */
trigger ReportUserRegionTrigger on Report_User_Region__c (before insert, before update) {
    if (TriggerContext.isBypassed('ReportUserRegionTrigger')) {
        return;
    }
    new MetadataTriggerHandler().run();
}
