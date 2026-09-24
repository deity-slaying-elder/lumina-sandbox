/**
 * All logic lives in Trigger_Action__mdt records for Patient_Insurance__c.
 * Add, reorder or deactivate behaviour in Setup, not here.
 *
 * TriggerContext.isBypassed is the org-wide incident lever, separate from the
 * framework's per-action and per-object switches. Both exist on purpose.
 */
trigger PatientInsuranceTrigger on Patient_Insurance__c (before insert) {
    if (TriggerContext.isBypassed('PatientInsuranceTrigger')) {
        return;
    }
    new MetadataTriggerHandler().run();
}
