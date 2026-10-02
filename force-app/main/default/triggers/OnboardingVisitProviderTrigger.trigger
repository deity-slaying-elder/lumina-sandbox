/**
 * Adding or removing a provider changes the shadow Event's subject and its single
 * Provider lookup, so the parent visit is resynced whenever an assignment changes.
 *
 * Without this, editing only the providers on a visit would leave the native calendar
 * naming the wrong people. The same change is what tells a provider they have been put
 * on, or taken off, a visit.
 */
trigger OnboardingVisitProviderTrigger on Onboarding_Visit_Provider__c(
  after insert,
  after update,
  after delete,
  after undelete
) {
  Set<Id> visitIds = new Set<Id>();
  Map<Id, Set<Id>> added = new Map<Id, Set<Id>>();
  Map<Id, Set<Id>> removed = new Map<Id, Set<Id>>();

  for (
    Onboarding_Visit_Provider__c a : (Trigger.isDelete
      ? Trigger.old
      : Trigger.new)
  ) {
    if (a.Onboarding_Visit__c == null) {
      continue;
    }
    visitIds.add(a.Onboarding_Visit__c);
    Map<Id, Set<Id>> bucket = Trigger.isDelete ? removed : added;
    if (!bucket.containsKey(a.Onboarding_Visit__c)) {
      bucket.put(a.Onboarding_Visit__c, new Set<Id>());
    }
    if (a.Provider__c != null) {
      bucket.get(a.Onboarding_Visit__c).add(a.Provider__c);
    }
  }

  // A reparent would leave the old visit stale too, so both sides are resynced. The
  // old parent counts as a removal and the new one as an addition.
  if (Trigger.isUpdate) {
    for (Onboarding_Visit_Provider__c a : Trigger.old) {
      if (a.Onboarding_Visit__c == null) {
        continue;
      }
      visitIds.add(a.Onboarding_Visit__c);
      Onboarding_Visit_Provider__c now = Trigger.newMap.get(a.Id);
      if (now != null && now.Onboarding_Visit__c != a.Onboarding_Visit__c) {
        if (!removed.containsKey(a.Onboarding_Visit__c)) {
          removed.put(a.Onboarding_Visit__c, new Set<Id>());
        }
        if (a.Provider__c != null) {
          removed.get(a.Onboarding_Visit__c).add(a.Provider__c);
        }
      }
    }
  }

  OnboardingVisitShadowSync.syncVisits(visitIds);
  OnboardingVisitNotifier.onRosterChange(added, removed);
}
