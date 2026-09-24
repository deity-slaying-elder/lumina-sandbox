/**
 * Patient__c trigger.
 *
 * Two generations live side by side here on purpose.
 *
 * The legacy before-save calls to PatientTriggerHandler predate the trigger actions
 * framework and are left exactly as they were.
 *
 * Everything converted from the TCM flows runs through MetadataTriggerHandler and is
 * registered in Trigger_Action__mdt records - reorder or deactivate in Setup, not here.
 * The TriggerContext check is the org-wide incident lever and guards only the framework
 * dispatch; gating the legacy before-save logic would change behaviour nobody asked
 * to change.
 *
 * This is deliberately not the full Patient consolidation. Patient__c also carries
 * PatientThoroughcareCreateTrigger and ThoroughcareTriggerController, which make
 * ThoroughCare callouts and depend on a second save pass to do it. Folding those in
 * needs characterization tests first, because a naive recursion guard silently stops
 * community patients reaching ThoroughCare and the callout swallows its own errors.
 */
trigger PatientTrigger on Patient__c (before insert, before update, after update) {
    // Before Insert - legacy
    if(Trigger.isBefore && Trigger.isInsert){
        PatientTriggerHandler.setLocalAppointmentTimes(Trigger.new, null);
    }
    // Before Update - legacy first, then the framework actions
    if(Trigger.isBefore && Trigger.isUpdate){
        PatientTriggerHandler.setLocalAppointmentTimes(Trigger.new, Trigger.oldMap);
    }
    if (!TriggerContext.isBypassed('PatientTrigger')) {
        new MetadataTriggerHandler().run();
    }
}
