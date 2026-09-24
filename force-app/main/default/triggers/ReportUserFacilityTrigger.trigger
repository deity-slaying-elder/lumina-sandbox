/**
 * All logic lives in Trigger_Action__mdt records for Report_User_Facility__c.
 * Add, reorder or deactivate behaviour in Setup, not here.
 *
 * TriggerContext.isBypassed is the org-wide incident lever, separate from the
 * framework's per-action and per-object switches. Both exist on purpose.
 */
trigger ReportUserFacilityTrigger on Report_User_Facility__c (before insert, before update) {
    if (TriggerContext.isBypassed('ReportUserFacilityTrigger')) {
        return;
    }
    new MetadataTriggerHandler().run();
}
