/**
 * Mirrors every onboarding visit onto its shadow Event, whatever changed it - the
 * scheduling component, the record page, a list view, a flow or the data loader - and
 * tells the assigned people when the booking itself changed.
 *
 * After-context throughout: the visit must be committed before the Event can point at
 * it, and on delete the Event is found by its own lookup.
 */
trigger OnboardingVisitTrigger on Onboarding_Visit__c(
  after insert,
  after update,
  after delete,
  after undelete
) {
  if (Trigger.isDelete) {
    OnboardingVisitShadowSync.removeShadows(Trigger.oldMap.keySet());
  } else {
    OnboardingVisitShadowSync.syncVisits(Trigger.newMap.keySet());
    // Trigger.oldMap is null on insert and undelete, which the notifier reads as
    // "this booking is new".
    OnboardingVisitNotifier.onVisitChange(Trigger.new, Trigger.oldMap);
  }
}
