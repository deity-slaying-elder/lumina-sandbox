/**
 * Keeps the shadow Event in step with its Onboarding_Visit__c.
 *
 * The visit is the source of truth. The Event exists only so a visit appears on the
 * native Salesforce calendar, and it is rewritten from the visit rather than edited
 * in its own right.
 *
 * Until 2026-09-24 this ran only inside FacilitySchedulingController, so a visit
 * cancelled or completed from the record page, a list view, a flow or the data loader
 * left the Event untouched - a cancelled visit went on showing as a live appointment.
 * Running it from triggers makes the component just one caller among several.
 *
 * Sharing: this runs WITHOUT sharing and in system mode deliberately. The Event is
 * derived data, not the user's own record; the user's authority to change the VISIT is
 * the gate. Enforcing FLS here would instead fail an otherwise valid visit edit for
 * anyone who cannot write Event, which would leave the two out of step - the exact
 * problem this class exists to prevent.
 *
 * The shadow is located by Event.Onboarding_Visit__c rather than by
 * Onboarding_Visit__c.Shadow_Event_Id__c, so a cleared or stale id cannot orphan it.
 */
public without sharing class OnboardingVisitShadowSync {
  /** Guards the write-back of Shadow_Event_Id__c, which would otherwise re-enter. */
  private static Boolean running = false;

  public static void syncVisits(Set<Id> visitIds) {
    if (running || visitIds == null || visitIds.isEmpty()) {
      return;
    }
    running = true;
    try {
      rebuild(visitIds);
    } finally {
      running = false;
    }
  }

  /**
   * Removes the shadow Events for visits that have gone. Called from after delete, so
   * the visit rows themselves are already unavailable - the Event's own lookup is what
   * identifies them.
   */
  public static void removeShadows(Set<Id> visitIds) {
    if (running || visitIds == null || visitIds.isEmpty()) {
      return;
    }
    running = true;
    try {
      List<Event> orphans = [
        SELECT Id
        FROM Event
        WHERE Onboarding_Visit__c IN :visitIds
      ];
      if (!orphans.isEmpty()) {
        delete orphans;
      }
    } finally {
      running = false;
    }
  }

  /** The programmes on a visit, split out of the multi-select picklist value. */
  private static List<String> programsOf(String multiselect) {
    List<String> out = new List<String>();
    if (String.isBlank(multiselect)) {
      return out;
    }
    for (String part : multiselect.split(';')) {
      String t = part.trim();
      if (String.isNotBlank(t)) {
        out.add(t);
      }
    }
    return out;
  }

  private static void rebuild(Set<Id> visitIds) {
    List<Onboarding_Visit__c> visits = [
      SELECT
        Id,
        Status__c,
        Programs__c,
        Start__c,
        End__c,
        Facilitator__c,
        Facility__c,
        Facility__r.Name,
        Shadow_Event_Id__c,
        (
          SELECT
            Provider__c,
            Provider__r.Name,
            Provider__r.First_Name__c,
            Provider__r.Last_Name__c
          FROM Providers__r
          ORDER BY CreatedDate
        )
      FROM Onboarding_Visit__c
      WHERE Id IN :visitIds
    ];
    if (visits.isEmpty()) {
      return;
    }

    // One query for every existing shadow, so this stays bulk safe.
    Map<Id, Event> shadowByVisit = new Map<Id, Event>();
    for (Event e : [
      SELECT Id, Onboarding_Visit__c
      FROM Event
      WHERE Onboarding_Visit__c IN :visitIds
    ]) {
      shadowByVisit.put(e.Onboarding_Visit__c, e);
    }

    List<Event> toInsert = new List<Event>();
    List<Event> toUpdate = new List<Event>();
    Map<Id, Onboarding_Visit__c> needsIdWriteBack = new Map<Id, Onboarding_Visit__c>();

    for (Onboarding_Visit__c v : visits) {
      List<Id> slots = new List<Id>();
      List<String> names = new List<String>();
      for (Onboarding_Visit_Provider__c a : v.Providers__r) {
        if (a.Provider__c == null) {
          continue;
        }
        slots.add(a.Provider__c);
        if (a.Provider__r != null) {
          String nm = ((a.Provider__r.First_Name__c == null
              ? ''
              : a.Provider__r.First_Name__c) +
            ' ' +
            (a.Provider__r.Last_Name__c == null
              ? ''
              : a.Provider__r.Last_Name__c))
            .trim();
          // Same fallback as the component: a provider with no first or last name
          // still has a record Name, and "(unnamed)" on a calendar entry is useless.
          if (String.isBlank(nm)) {
            nm = a.Provider__r.Name;
          }
          names.add(String.isBlank(nm) ? '(no name on record)' : nm);
        }
      }

      String facilityName = v.Facility__r == null ? '' : v.Facility__r.Name;
      Event e = shadowByVisit.get(v.Id);
      Boolean isNew = e == null;
      if (isNew) {
        e = new Event(OwnerId = UserInfo.getUserId());
      }
      e.Subject =
        'Facility onboarding - ' +
        facilityName +
        (names.isEmpty() ? '' : ' (' + String.join(names, ', ') + ')');
      e.WhatId = v.Facility__c;
      e.StartDateTime = v.Start__c;
      e.EndDateTime = v.End__c;
      e.Facilitator__c = v.Facilitator__c;
      // The platform allows only one Provider lookup on Activity, so slot 1 goes on
      // the Event and the rest are named in the subject.
      e.Provider__c = slots.isEmpty() ? null : slots[0];
      // Activity fields are shared with Task, so Onboarding_Program__c was left a
      // single picklist rather than converted when the visit gained several
      // programmes. It carries the first one, which keeps existing calendar filters
      // and reports working, and the Event description carries the full list.
      List<String> visitPrograms = programsOf(v.Programs__c);
      e.Onboarding_Program__c = visitPrograms.isEmpty()
        ? null
        : visitPrograms[0];
      e.Description = visitPrograms.isEmpty()
        ? 'Programs: not set'
        : 'Programs: ' + String.join(visitPrograms, ', ');
      e.Onboarding_Status__c = v.Status__c;
      e.Onboarding_Visit__c = v.Id;

      if (isNew) {
        toInsert.add(e);
        needsIdWriteBack.put(v.Id, v);
      } else {
        toUpdate.add(e);
        if (v.Shadow_Event_Id__c != e.Id) {
          needsIdWriteBack.put(v.Id, v);
        }
      }
    }

    if (!toInsert.isEmpty()) {
      insert toInsert;
    }
    if (!toUpdate.isEmpty()) {
      update toUpdate;
    }

    // Keep the convenience id on the visit accurate. Guarded by `running`, so this
    // update does not re-enter the sync.
    if (!needsIdWriteBack.isEmpty()) {
      Map<Id, Id> eventByVisit = new Map<Id, Id>();
      for (Event e : toInsert) {
        eventByVisit.put(e.Onboarding_Visit__c, e.Id);
      }
      for (Event e : toUpdate) {
        eventByVisit.put(e.Onboarding_Visit__c, e.Id);
      }
      List<Onboarding_Visit__c> stamp = new List<Onboarding_Visit__c>();
      for (Id vid : needsIdWriteBack.keySet()) {
        if (eventByVisit.containsKey(vid)) {
          stamp.add(
            new Onboarding_Visit__c(
              Id = vid,
              Shadow_Event_Id__c = eventByVisit.get(vid)
            )
          );
        }
      }
      if (!stamp.isEmpty()) {
        update stamp;
      }
    }
  }
}
