/**
 * Emails the people assigned to an onboarding visit when the booking changes.
 *
 * Why a buffer rather than sending straight from each trigger: creating a visit and
 * writing its provider rows happen in one transaction, and both fire triggers. Sending
 * from each one would put two emails in a provider's inbox for a single booking. So
 * every trigger adds to a static buffer, the first one to do so enqueues a single
 * Queueable, and that Queueable sends one message per person once the transaction has
 * settled and the roster is final.
 *
 * Sharing: WITHOUT SHARING on purpose. The notification is derived from a visit the
 * user was already allowed to change, and the addresses belong to staff records the
 * user may not be able to read. Enforcing FLS here would silently drop notifications
 * for exactly the coordinators this feature exists for.
 *
 * No patient data is ever included. The message names the facility, the window, the
 * programmes and the people, and nothing else.
 */
public without sharing class OnboardingVisitNotifier {
  /** Set while the Queueable is running, so a re-entrant save cannot loop. */
  @TestVisible
  private static Boolean suppressed = false;

  /** visitId -> the strongest change seen for it this transaction. */
  private static Map<Id, String> pending = new Map<Id, String>();

  /** visitId -> providers added / removed this transaction, for roster-only changes. */
  private static Map<Id, Set<Id>> addedProviders = new Map<Id, Set<Id>>();
  private static Map<Id, Set<Id>> removedProviders = new Map<Id, Set<Id>>();

  private static Boolean queued = false;

  // Strongest wins, so a visit both rescheduled and cancelled reports as cancelled.
  private static final Map<String, Integer> RANK = new Map<String, Integer>{
    'roster' => 1,
    'updated' => 2,
    'scheduled' => 3,
    'cancelled' => 4
  };

  /** Fields whose change is worth an email. Anything else is a silent save. */
  private static final Set<String> WATCHED = new Set<String>{
    'Start__c',
    'End__c',
    'Programs__c',
    'Facility__c',
    'Facilitator__c'
  };

  // ============================================================ entry points
  public static void onVisitChange(
    List<Onboarding_Visit__c> updated,
    Map<Id, Onboarding_Visit__c> oldMap
  ) {
    if (suppressed || updated == null || updated.isEmpty()) {
      return;
    }
    for (Onboarding_Visit__c v : updated) {
      Onboarding_Visit__c before = oldMap == null ? null : oldMap.get(v.Id);
      String kind = classify(v, before);
      if (kind != null) {
        record(v.Id, kind);
      }
    }
    enqueueOnce();
  }

  public static void onRosterChange(
    Map<Id, Set<Id>> added,
    Map<Id, Set<Id>> removed
  ) {
    if (suppressed) {
      return;
    }
    mergeInto(addedProviders, added);
    mergeInto(removedProviders, removed);
    for (Id visitId : added.keySet()) {
      record(visitId, 'roster');
    }
    for (Id visitId : removed.keySet()) {
      record(visitId, 'roster');
    }
    enqueueOnce();
  }

  // ============================================================ classification
  /**
   * Returns the kind of email this change deserves, or null for a save that is not
   * worth an inbox. A visit that was already cancelled and is saved cancelled again
   * is the main no-op this guards.
   */
  private static String classify(
    Onboarding_Visit__c now,
    Onboarding_Visit__c before
  ) {
    Boolean isNew = (before == null);
    Boolean cancelledNow = (now.Status__c == 'Cancelled');
    Boolean cancelledBefore = (!isNew && before.Status__c == 'Cancelled');

    if (cancelledNow && cancelledBefore) {
      return null; // already cancelled, nothing changed for anyone
    }
    if (cancelledNow) {
      return 'cancelled';
    }
    if (isNew) {
      return 'scheduled';
    }
    if (cancelledBefore) {
      return 'scheduled'; // reinstated, so it reads as a new booking
    }
    for (String f : WATCHED) {
      if (now.get(f) != before.get(f)) {
        return 'updated';
      }
    }
    return null;
  }

  private static void record(Id visitId, String kind) {
    String held = pending.get(visitId);
    if (held == null || RANK.get(kind) > RANK.get(held)) {
      pending.put(visitId, kind);
    }
  }

  private static void mergeInto(
    Map<Id, Set<Id>> target,
    Map<Id, Set<Id>> source
  ) {
    if (source == null) {
      return;
    }
    for (Id k : source.keySet()) {
      if (!target.containsKey(k)) {
        target.put(k, new Set<Id>());
      }
      target.get(k).addAll(source.get(k));
    }
  }

  /**
   * One Queueable per transaction. Queueables cannot be chained from a Queueable in
   * a test context, and a trigger firing inside the send would be pointless work, so
   * the send runs inline when we are already async or under test.
   */
  private static void enqueueOnce() {
    if (queued || pending.isEmpty()) {
      return;
    }
    queued = true;
    if (
      System.isQueueable() ||
      System.isBatch() ||
      System.isFuture() ||
      Test.isRunningTest()
    ) {
      send(
        pending.clone(),
        cloneRoster(addedProviders),
        cloneRoster(removedProviders)
      );
      reset();
    } else {
      System.enqueueJob(
        new Sender(
          pending.clone(),
          cloneRoster(addedProviders),
          cloneRoster(removedProviders)
        )
      );
      reset();
    }
  }

  private static Map<Id, Set<Id>> cloneRoster(Map<Id, Set<Id>> src) {
    Map<Id, Set<Id>> out = new Map<Id, Set<Id>>();
    for (Id k : src.keySet()) {
      out.put(k, new Set<Id>(src.get(k)));
    }
    return out;
  }

  private static void reset() {
    pending = new Map<Id, String>();
    addedProviders = new Map<Id, Set<Id>>();
    removedProviders = new Map<Id, Set<Id>>();
    queued = false;
  }

  // ============================================================ queueable
  public class Sender implements Queueable {
    private Map<Id, String> kinds;
    private Map<Id, Set<Id>> added;
    private Map<Id, Set<Id>> removed;

    public Sender(
      Map<Id, String> kinds,
      Map<Id, Set<Id>> added,
      Map<Id, Set<Id>> removed
    ) {
      this.kinds = kinds;
      this.added = added;
      this.removed = removed;
    }

    public void execute(QueueableContext ctx) {
      send(kinds, added, removed);
    }
  }

  // ============================================================ send
  @TestVisible
  private static void send(
    Map<Id, String> kinds,
    Map<Id, Set<Id>> added,
    Map<Id, Set<Id>> removed
  ) {
    if (kinds == null || kinds.isEmpty()) {
      return;
    }
    suppressed = true;
    try {
      List<Onboarding_Visit__c> visits = [
        SELECT
          Id,
          Name,
          Status__c,
          Programs__c,
          Start__c,
          End__c,
          Facility__c,
          Facility__r.Name,
          Facility__r.Address__StateCode__s,
          Facilitator__c,
          Facilitator__r.Name,
          Facilitator__r.Email__c,
          (
            SELECT
              Provider__c,
              Provider__r.First_Name__c,
              Provider__r.Last_Name__c,
              Provider__r.Email__c
            FROM Providers__r
            ORDER BY CreatedDate
          )
        FROM Onboarding_Visit__c
        WHERE Id IN :kinds.keySet()
      ];

      // Providers dropped from a visit are no longer children of it, so their
      // addresses have to be fetched on their own.
      Set<Id> droppedIds = new Set<Id>();
      for (Set<Id> s : removed.values()) {
        droppedIds.addAll(s);
      }
      Map<Id, Provider__c> dropped = droppedIds.isEmpty()
        ? new Map<Id, Provider__c>()
        : new Map<Id, Provider__c>(
            [
              SELECT Id, First_Name__c, Last_Name__c, Email__c
              FROM Provider__c
              WHERE Id IN :droppedIds
            ]
          );

      List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();

      for (Onboarding_Visit__c v : visits) {
        String kind = kinds.get(v.Id);
        Set<Id> justAdded = added.containsKey(v.Id)
          ? added.get(v.Id)
          : new Set<Id>();
        Set<Id> justRemoved = removed.containsKey(v.Id)
          ? removed.get(v.Id)
          : new Set<Id>();

        // A roster-only change tells the people who joined and the people who
        // left, not the whole standing roster.
        Boolean rosterOnly = (kind == 'roster');

        for (Onboarding_Visit_Provider__c a : v.Providers__r) {
          if (a.Provider__r == null || String.isBlank(a.Provider__r.Email__c)) {
            continue;
          }
          if (rosterOnly && !justAdded.contains(a.Provider__c)) {
            continue;
          }
          String verb = rosterOnly ? 'added' : kind;
          outbox.add(
            build(a.Provider__r.Email__c, providerName(a.Provider__r), verb, v)
          );
        }

        for (Id pid : justRemoved) {
          Provider__c p = dropped.get(pid);
          if (p != null && String.isNotBlank(p.Email__c)) {
            outbox.add(build(p.Email__c, providerName(p), 'removed', v));
          }
        }

        if (
          !rosterOnly &&
          v.Facilitator__r != null &&
          String.isNotBlank(v.Facilitator__r.Email__c)
        ) {
          outbox.add(
            build(v.Facilitator__r.Email__c, v.Facilitator__r.Name, kind, v)
          );
        }
      }

      if (!outbox.isEmpty()) {
        // allOrNone false: one bad address must not lose the rest of the batch.
        Messaging.sendEmail(outbox, false);
      }
    } catch (Exception e) {
      // A failed notification must never roll back a booking the user made.
      System.debug(
        LoggingLevel.ERROR,
        'OnboardingVisitNotifier: send failed - ' +
          e.getTypeName() +
          ': ' +
          e.getMessage()
      );
    } finally {
      suppressed = false;
    }
  }

  // ============================================================ message
  private static final Map<String, String> SUBJECT_VERB = new Map<String, String>{
    'scheduled' => 'Onboarding visit scheduled',
    'updated' => 'Onboarding visit changed',
    'cancelled' => 'Onboarding visit cancelled',
    'added' => 'You have been added to an onboarding visit',
    'removed' => 'You have been taken off an onboarding visit'
  };

  private static final Map<String, String> OPENING = new Map<String, String>{
    'scheduled' => 'You are booked for an onboarding visit.',
    'updated' => 'An onboarding visit you are on has changed.',
    'cancelled' => 'An onboarding visit you were on has been cancelled.',
    'added' => 'You have been added to an onboarding visit.',
    'removed' => 'You are no longer on this onboarding visit.'
  };

  private static Messaging.SingleEmailMessage build(
    String address,
    String personName,
    String kind,
    Onboarding_Visit__c v
  ) {
    String facility = v.Facility__r == null
      ? 'the facility'
      : v.Facility__r.Name;
    String subject = SUBJECT_VERB.get(kind) + ': ' + facility;

    List<String> lines = new List<String>();
    lines.add(
      'Hi ' + (String.isBlank(personName) ? 'there' : personName) + ','
    );
    lines.add('');
    lines.add(OPENING.get(kind));
    lines.add('');
    lines.add(
      'Facility: ' +
        facility +
        (v.Facility__r != null &&
          String.isNotBlank(v.Facility__r.Address__StateCode__s)
          ? ' (' + v.Facility__r.Address__StateCode__s + ')'
          : '')
    );
    lines.add('When: ' + window(v));
    lines.add(
      'Programs: ' +
      (String.isBlank(v.Programs__c)
        ? 'Not set'
        : v.Programs__c.replace(';', ', '))
    );
    lines.add(
      'Facilitator: ' +
      (v.Facilitator__r == null ? 'Not assigned' : v.Facilitator__r.Name)
    );
    lines.add(
      'Status: ' + (String.isBlank(v.Status__c) ? 'Scheduled' : v.Status__c)
    );
    lines.add('');
    lines.add(
      'Open the visit: ' +
        URL.getOrgDomainUrl().toExternalForm() +
        '/lightning/r/Onboarding_Visit__c/' +
        v.Id +
        '/view'
    );

    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new List<String>{ address });
    mail.setSubject(subject);
    mail.setPlainTextBody(String.join(lines, '\n'));
    mail.setSaveAsActivity(false);
    return mail;
  }

  /**
   * Times are rendered in the running user's time zone, which is the coordinator
   * making the change rather than the recipient. The zone is named so a reader in
   * another zone can tell.
   */
  private static String window(Onboarding_Visit__c v) {
    if (v.Start__c == null) {
      return 'Not set';
    }
    String zone = UserInfo.getTimeZone().getDisplayName();
    String startText = v.Start__c.format('EEE d MMM yyyy, h:mm a');
    if (v.End__c == null) {
      return startText + ' (' + zone + ')';
    }
    return startText + ' to ' + v.End__c.format('h:mm a') + ' (' + zone + ')';
  }

  private static String providerName(Provider__c p) {
    String nm = ((p.First_Name__c == null ? '' : p.First_Name__c) +
      ' ' +
      (p.Last_Name__c == null ? '' : p.Last_Name__c))
      .trim();
    return String.isBlank(nm) ? 'there' : nm;
  }
}
