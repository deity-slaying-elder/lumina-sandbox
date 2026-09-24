/**
 * All logic lives in Trigger_Action__mdt records for Provider__c.
 * Add, reorder or deactivate behaviour in Setup, not here.
 *
 * TriggerContext.isBypassed is the org-wide incident lever, separate from the
 * framework's per-action and per-object switches. Both exist on purpose.
 */
trigger ProviderTrigger on Provider__c (before insert) {
    if (TriggerContext.isBypassed('ProviderTrigger')) {
        return;
    }
    new MetadataTriggerHandler().run();
}
