/**
 * Controller for the facility scheduling component (rough draft, 2026-09-16).
 *
 * Security posture:
 *  - `with sharing` + AccessLevel.USER_MODE on every query and DML, so record
 *    visibility and FLS are enforced by the platform rather than by this class.
 *  - The caller is never taken from the request; where identity matters it comes
 *    from UserInfo.
 *  - No dynamic SOQL is concatenated from user input. The one dynamic query is
 *    assembled from field names controlled here, with every user value passed as
 *    a named bind via Database.queryWithBinds.
 *  - Returns counts only from Patient__c. No patient-level data crosses the wire.
 *  - Database exceptions are logged server-side and reported to the client as a
 *    generic message plus a correlation id.
 *
 * Eligibility FAILS CLOSED: because every new field is optional (decision
 * 2026-09-16), a missing credential is treated as "not eligible", never as a pass.
 */
public with sharing class FacilitySchedulingController {
  private static final String STATE_MAP_RAW =
    'AL:Alabama,AK:Alaska,AZ:Arizona,AR:Arkansas,CA:California,CO:Colorado,CT:Connecticut,' +
    'DE:Delaware,DC:District of Columbia,FL:Florida,GA:Georgia,HI:Hawaii,ID:Idaho,IL:Illinois,' +
    'IN:Indiana,IA:Iowa,KS:Kansas,KY:Kentucky,LA:Louisiana,ME:Maine,MD:Maryland,' +
    'MA:Massachusetts,MI:Michigan,MN:Minnesota,MS:Mississippi,MO:Missouri,MT:Montana,' +
    'NE:Nebraska,NV:Nevada,NH:New Hampshire,NJ:New Jersey,NM:New Mexico,NY:New York,' +
    'NC:North Carolina,ND:North Dakota,OH:Ohio,OK:Oklahoma,OR:Oregon,PA:Pennsylvania,' +
    'RI:Rhode Island,SC:South Carolina,SD:South Dakota,TN:Tennessee,TX:Texas,UT:Utah,' +
    'VT:Vermont,VA:Virginia,WA:Washington,WV:West Virginia,WI:Wisconsin,WY:Wyoming';

  /**
   * Conflicting programme pairs, from Program_Conflict__mdt so they can be corrected
   * without a deploy (Dorothy, 2026-09-24: "these details change pretty frequently").
   * Still pending open question Q4a - only BHI/CoCM was named on the call, and it is
   * seeded as the single row. The credential block/warn rules deliberately stay in
   * Apex; only the pair list is configurable.
   *
   * Each pair is held twice (A|B and B|A) so lookup is order-independent.
   */
  private static Set<String> conflictPairs {
    get {
      if (conflictPairs == null) {
        conflictPairs = new Set<String>();
        for (
          Program_Conflict__mdt c : Program_Conflict__mdt.getAll().values()
        ) {
          if (
            c.Active__c &&
            String.isNotBlank(c.Program_A__c) &&
            String.isNotBlank(c.Program_B__c)
          ) {
            conflictPairs.add(c.Program_A__c + '|' + c.Program_B__c);
            conflictPairs.add(c.Program_B__c + '|' + c.Program_A__c);
          }
        }
      }
      return conflictPairs;
    }
    set;
  }

  /**
   * Maps a program to the Facility__c status field that records it. Field names are
   * defined here, never taken from the client, so they are safe to interpolate into
   * the dynamic worklist query. Programs absent from this map (Community Full-Time,
   * IPV Onboarding) have no facility-level field and so cannot filter the worklist.
   */
  private static final Map<String, String> FACILITY_PROGRAM_FIELD = new Map<String, String>{
    'TCM' => 'TCM_Status__c',
    'CCM' => 'CCM_Status__c',
    'BHI' => 'BHI_Status__c',
    'CoCM' => 'COCM_Status__c',
    'Telepsych' => 'Telepsych_Status__c',
    'After Hours Telehealth' => 'AHTH_Status__c'
  };

  /**
   * Every programme the dialog can offer, in display order. Two of them carry no
   * facility field, so the facility cannot say whether it runs them; they are offered
   * anyway rather than being silently unavailable, and the UI says why.
   */
  private static final List<String> ALL_PROGRAMS = new List<String>{
    'TCM',
    'CCM',
    'BHI',
    'CoCM',
    'Telepsych',
    'After Hours Telehealth',
    'Community Full-Time',
    'IPV Onboarding'
  };

  /** The value a facility programme status field carries when the programme is live. */
  private static final String PROGRAM_ACTIVE = 'Active';

  private static Map<String, String> stateByCode {
    get {
      if (stateByCode == null) {
        stateByCode = new Map<String, String>();
        for (String pair : STATE_MAP_RAW.split(',')) {
          List<String> kv = pair.split(':');
          stateByCode.put(kv[0], kv[1]);
        }
      }
      return stateByCode;
    }
    set;
  }

  // ================================================================= DTOs
  public class FacilityRow {
    @AuraEnabled
    public Id facilityId { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String parentCompany { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public Date rolloutDate { get; set; }
    @AuraEnabled
    public String stateCode { get; set; }
    @AuraEnabled
    public Integer census { get; set; }
    @AuraEnabled
    public Integer seen { get; set; }
    @AuraEnabled
    public Integer consented { get; set; }
    @AuraEnabled
    public Boolean facilitationComplete { get; set; }
    @AuraEnabled
    public Integer eventCount { get; set; }
    @AuraEnabled
    public Datetime nextEventStart { get; set; }
  }

  public class EventRow {
    @AuraEnabled
    public Id eventId { get; set; }
    @AuraEnabled
    public String subject { get; set; }
    @AuraEnabled
    public Datetime startTime { get; set; }
    @AuraEnabled
    public Datetime endTime { get; set; }
    @AuraEnabled
    public Id facilityId { get; set; }
    @AuraEnabled
    public String facilityName { get; set; }
    @AuraEnabled
    public Id facilitatorId { get; set; }
    @AuraEnabled
    public String facilitatorName { get; set; }
    @AuraEnabled
    public Id providerId { get; set; } // slot 1, for click-through
    @AuraEnabled
    public List<Id> providerIds { get; set; } // every populated slot
    @AuraEnabled
    public String providerName { get; set; } // first provider only
    @AuraEnabled
    public Integer providerExtra { get; set; } // how many beyond the first
    @AuraEnabled
    public String providerNamesFull { get; set; } // all, for the tooltip
    @AuraEnabled
    public List<String> programs { get; set; }
    @AuraEnabled
    public String programLabel { get; set; } // all of them, comma joined
    @AuraEnabled
    public String onboardingStatus { get; set; }
  }

  public class Check {
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String level { get; set; } // ok | warning | blocked
    @AuraEnabled
    public String detail { get; set; }
    public Check(String label, String level, String detail) {
      this.label = label;
      this.level = level;
      this.detail = detail;
    }
  }

  public class Eligibility {
    @AuraEnabled
    public Boolean allowed { get; set; }
    @AuraEnabled
    public List<Check> checks { get; set; }
    public Eligibility() {
      this.allowed = true;
      this.checks = new List<Check>();
    }
    public void add(String label, String level, String detail) {
      checks.add(new Check(label, level, detail));
      if (level == 'blocked') {
        allowed = false;
      }
    }
  }

  /**
   * The provider picker result. Carries the hidden counts as well as the options, so
   * the UI can explain an empty or short list rather than just showing nothing.
   */
  public class FacilitatorChoices {
    @AuraEnabled
    public List<PickOption> options { get; set; }
    @AuraEnabled
    public Integer hiddenBooked { get; set; }
    public FacilitatorChoices() {
      this.options = new List<PickOption>();
      this.hiddenBooked = 0;
    }
  }

  public class ProviderChoices {
    @AuraEnabled
    public List<PickOption> options { get; set; }
    @AuraEnabled
    public String stateName { get; set; }
    @AuraEnabled
    public Integer hiddenUntagged { get; set; }
    @AuraEnabled
    public Integer hiddenUnlicensed { get; set; }
    @AuraEnabled
    public Integer hiddenConflicted { get; set; }
    @AuraEnabled
    public Integer hiddenBooked { get; set; }
    public ProviderChoices() {
      this.options = new List<PickOption>();
      this.hiddenUntagged = 0;
      this.hiddenUnlicensed = 0;
      this.hiddenConflicted = 0;
      this.hiddenBooked = 0;
    }
  }

  public class Summary {
    @AuraEnabled
    public Integer awaiting { get; set; }
    @AuraEnabled
    public Integer unscheduled { get; set; }
    @AuraEnabled
    public Integer bookedThisWeek { get; set; }
    @AuraEnabled
    public Date nextRolloutDate { get; set; }
    @AuraEnabled
    public String nextRolloutFacility { get; set; }
  }

  public class ProgramOption {
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String value { get; set; }
    @AuraEnabled
    public Boolean available { get; set; }
    @AuraEnabled
    public String reason { get; set; }
  }

  public class PickOption {
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String value { get; set; }
    public PickOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  // ================================================================= worklist
  /**
   * Facilities that scheduling needs to act on. All filter values arrive as named
   * binds; the query text itself is built only from field names defined here.
   */
  @AuraEnabled(cacheable=true)
  public static List<FacilityRow> getWorklist(
    String parentCompanyId,
    Date fromDate,
    Date toDate,
    String program,
    String searchTerm
  ) {
    try {
      Map<String, Object> binds = new Map<String, Object>();
      List<String> wheres = new List<String>{ 'Status__c != null' };

      // Escaped for the LIKE wildcards, so typing % or _ searches for those
      // characters rather than matching everything.
      if (String.isNotBlank(searchTerm) && searchTerm.trim().length() >= 2) {
        binds.put(
          'term',
          '%' +
            searchTerm.trim()
              .replace('\\', '\\\\')
              .replace('%', '\\%')
              .replace('_', '\\_') +
            '%'
        );
        wheres.add('(Name LIKE :term OR Parent_Company__r.Name LIKE :term)');
      }

      if (String.isNotBlank(parentCompanyId)) {
        binds.put('pc', (Id) parentCompanyId);
        wheres.add('Parent_Company__c = :pc');
      }
      // The worklist is by definition facilities still awaiting onboarding - they
      // drop off it once active with Seen populated - so there was nothing for a
      // status filter to usefully select. Removed 2026-09-24 (Dorothy: "maybe we
      // shouldn't show it if they can't change it").
      wheres.add('Status__c IN (\'Onboarding\', \'Opportunity\')');
      // A facility with no rollout date is the one nobody has planned yet, so it is
      // the first thing scheduling needs to see. Treating the blank as "does not
      // match" hid thirteen of fifteen facilities behind the default date filter.
      if (fromDate != null) {
        binds.put('fd', fromDate);
        wheres.add(
          '(Scheduled_Rollout_Date__c >= :fd OR Scheduled_Rollout_Date__c = null)'
        );
      }
      if (toDate != null) {
        binds.put('td', toDate);
        wheres.add(
          '(Scheduled_Rollout_Date__c <= :td OR Scheduled_Rollout_Date__c = null)'
        );
      }
      // A facility runs many programs, each with its own status field. Filtering on
      // a program means "this facility runs that program and it is live", so a
      // programme recorded but paused no longer matches (2026-09-30).
      if (
        String.isNotBlank(program) &&
        FACILITY_PROGRAM_FIELD.containsKey(program)
      ) {
        binds.put('progActive', PROGRAM_ACTIVE);
        wheres.add(FACILITY_PROGRAM_FIELD.get(program) + ' = :progActive');
      }

      String soql =
        'SELECT Id, Name, Status__c, Scheduled_Rollout_Date__c, Facilitation_Complete__c, ' +
        'Parent_Company__r.Name, Address__StateCode__s ' +
        'FROM Facility__c WHERE ' +
        String.join(wheres, ' AND ') +
        ' ORDER BY Scheduled_Rollout_Date__c NULLS LAST, Name LIMIT 200';

      List<Facility__c> facilities = Database.queryWithBinds(
        soql,
        binds,
        AccessLevel.USER_MODE
      );

      Map<Id, FacilityRow> rows = new Map<Id, FacilityRow>();
      for (Facility__c f : facilities) {
        FacilityRow r = new FacilityRow();
        r.facilityId = f.Id;
        r.name = f.Name;
        r.status = f.Status__c;
        r.rolloutDate = f.Scheduled_Rollout_Date__c;
        r.stateCode = f.Address__StateCode__s;
        r.parentCompany = f.Parent_Company__r == null
          ? null
          : f.Parent_Company__r.Name;
        r.facilitationComplete = f.Facilitation_Complete__c == true;
        r.census = 0;
        r.seen = 0;
        r.consented = 0;
        r.eventCount = 0;
        r.nextEventStart = null;
        rows.put(f.Id, r);
      }
      if (rows.isEmpty()) {
        return new List<FacilityRow>();
      }

      // Census / Seen / Consented read Patient__c. A user without access to that
      // object (or to the fields behind these counts) should still get a usable
      // worklist, so the counts degrade to zero rather than failing the whole call.
      try {
        applyPatientCounts(rows);
      } catch (System.QueryException qe) {
        System.debug(
          LoggingLevel.WARN,
          'FacilityScheduling: patient counts skipped, caller lacks access - ' +
          qe.getTypeName()
        );
      } catch (System.SecurityException se) {
        System.debug(
          LoggingLevel.WARN,
          'FacilityScheduling: patient counts skipped, caller lacks access - ' +
          se.getTypeName()
        );
      }
      applyEventCounts(rows);
      return rows.values();
    } catch (Exception e) {
      throw serverError(e, 'getWorklist');
    }
  }

  /**
   * Census / Seen / Consented, as agreed on 2026-09-16:
   *   Census    = Patient__c.Status__c = 'Active'
   *   Seen      = the above with Count_of_Initial_VIsits__c > 0   (note the API typo)
   *   Consented = the above with Consent_Status__c LIKE 'Approved%'
   * Scoped to active patients so Consented <= Seen <= Census always holds.
   * Aggregates only - no patient record ever leaves this method.
   */
  private static void applyPatientCounts(Map<Id, FacilityRow> rows) {
    Set<Id> ids = rows.keySet();

    for (AggregateResult ar : [
      SELECT Facility__c fid, COUNT(Id) total
      FROM Patient__c
      WHERE Facility__c IN :ids AND Status__c = 'Active'
      WITH USER_MODE
      GROUP BY Facility__c
    ]) {
      rows.get((Id) ar.get('fid')).census = (Integer) ar.get('total');
    }

    for (AggregateResult ar : [
      SELECT Facility__c fid, COUNT(Id) total
      FROM Patient__c
      WHERE
        Facility__c IN :ids
        AND Status__c = 'Active'
        AND Count_of_Initial_VIsits__c > 0
      WITH USER_MODE
      GROUP BY Facility__c
    ]) {
      rows.get((Id) ar.get('fid')).seen = (Integer) ar.get('total');
    }

    for (AggregateResult ar : [
      SELECT Facility__c fid, COUNT(Id) total
      FROM Patient__c
      WHERE
        Facility__c IN :ids
        AND Status__c = 'Active'
        AND Consent_Status__c LIKE 'Approved%'
      WITH USER_MODE
      GROUP BY Facility__c
    ]) {
      rows.get((Id) ar.get('fid')).consented = (Integer) ar.get('total');
    }
  }

  private static void applyEventCounts(Map<Id, FacilityRow> rows) {
    Set<Id> ids = rows.keySet();
    for (AggregateResult ar : [
      SELECT Facility__c fid, COUNT(Id) total
      FROM Onboarding_Visit__c
      WHERE Facility__c IN :ids AND Status__c != 'Cancelled'
      WITH USER_MODE
      GROUP BY Facility__c
    ]) {
      Id fid = (Id) ar.get('fid');
      if (rows.containsKey(fid)) {
        rows.get(fid).eventCount = (Integer) ar.get('total');
      }
    }
    // "2 events" with no date makes you open the row to find out whether the next one
    // is tomorrow or three weeks away, so the earliest still to come rides along with
    // the count.
    Datetime fromNow = Datetime.now();
    for (AggregateResult ar : [
      SELECT Facility__c fid, MIN(Start__c) soonest
      FROM Onboarding_Visit__c
      WHERE
        Facility__c IN :ids
        AND Status__c != 'Cancelled'
        AND Start__c >= :fromNow
      WITH USER_MODE
      GROUP BY Facility__c
    ]) {
      Id fid = (Id) ar.get('fid');
      if (rows.containsKey(fid)) {
        rows.get(fid).nextEventStart = (Datetime) ar.get('soonest');
      }
    }
  }

  /**
   * Census, Seen and Consented for one facility, for the booking dialog. The worklist
   * already shows these per row; the dialog needs them too, because the person booking
   * decides how many providers to send from exactly these numbers and should not have
   * to close the dialog to read them.
   *
   * Aggregates only. No patient record leaves this method.
   */
  @AuraEnabled(cacheable=true)
  public static FacilityRow getFacilitySnapshot(Id facilityId) {
    try {
      if (facilityId == null) {
        return null;
      }
      List<Facility__c> found = [
        SELECT
          Id,
          Name,
          Status__c,
          Scheduled_Rollout_Date__c,
          Facilitation_Complete__c,
          Parent_Company__r.Name,
          Address__StateCode__s
        FROM Facility__c
        WHERE Id = :facilityId
        WITH USER_MODE
        LIMIT 1
      ];
      if (found.isEmpty()) {
        return null;
      }
      Facility__c f = found[0];
      FacilityRow r = new FacilityRow();
      r.facilityId = f.Id;
      r.name = f.Name;
      r.status = f.Status__c;
      r.rolloutDate = f.Scheduled_Rollout_Date__c;
      r.stateCode = f.Address__StateCode__s;
      r.parentCompany = f.Parent_Company__r == null
        ? null
        : f.Parent_Company__r.Name;
      r.facilitationComplete = f.Facilitation_Complete__c == true;
      r.census = 0;
      r.seen = 0;
      r.consented = 0;
      r.eventCount = 0;
      r.nextEventStart = null;

      Map<Id, FacilityRow> one = new Map<Id, FacilityRow>{ f.Id => r };
      // Same degradation as the worklist: a caller without Patient access still
      // gets a usable dialog, with zeroes rather than an error.
      try {
        applyPatientCounts(one);
      } catch (System.QueryException qe) {
        System.debug(
          LoggingLevel.WARN,
          'FacilityScheduling: snapshot counts skipped - ' + qe.getTypeName()
        );
      } catch (System.SecurityException se) {
        System.debug(
          LoggingLevel.WARN,
          'FacilityScheduling: snapshot counts skipped - ' + se.getTypeName()
        );
      }
      applyEventCounts(one);
      return r;
    } catch (Exception e) {
      throw serverError(e, 'getFacilitySnapshot');
    }
  }

  /**
   * The four numbers across the top of the worklist.
   *
   * Deliberately unfiltered: the strip says what is true of the whole queue, so it
   * stays still while you narrow the list underneath it. Counting in Apex rather than
   * from the loaded rows matters because the list stops at 200.
   */
  @AuraEnabled(cacheable=true)
  public static Summary getSummary() {
    try {
      Summary out = new Summary();

      List<AggregateResult> waiting = [
        SELECT COUNT(Id) total
        FROM Facility__c
        WHERE Status__c IN ('Onboarding', 'Opportunity')
        WITH USER_MODE
      ];
      out.awaiting = waiting.isEmpty() ? 0 : (Integer) waiting[0].get('total');

      // Facilities in the queue that have no live visit against them.
      Set<Id> booked = new Set<Id>();
      for (AggregateResult ar : [
        SELECT Facility__c fid
        FROM Onboarding_Visit__c
        WHERE Status__c != 'Cancelled'
        WITH USER_MODE
        GROUP BY Facility__c
      ]) {
        booked.add((Id) ar.get('fid'));
      }
      Integer unscheduled = 0;
      Date soonest = null;
      String soonestName = null;
      for (Facility__c f : [
        SELECT Id, Name, Scheduled_Rollout_Date__c
        FROM Facility__c
        WHERE Status__c IN ('Onboarding', 'Opportunity')
        WITH USER_MODE
        ORDER BY Scheduled_Rollout_Date__c NULLS LAST
        LIMIT 2000
      ]) {
        if (!booked.contains(f.Id)) {
          unscheduled++;
        }
        if (
          f.Scheduled_Rollout_Date__c != null &&
          f.Scheduled_Rollout_Date__c >= Date.today() &&
          soonest == null
        ) {
          soonest = f.Scheduled_Rollout_Date__c;
          soonestName = f.Name;
        }
      }
      out.unscheduled = unscheduled;
      out.nextRolloutDate = soonest;
      out.nextRolloutFacility = soonestName;

      Datetime weekStart = Datetime.newInstance(
        Date.today().toStartOfWeek(),
        Time.newInstance(0, 0, 0, 0)
      );
      Datetime weekEnd = weekStart.addDays(7);
      List<AggregateResult> thisWeek = [
        SELECT COUNT(Id) total
        FROM Onboarding_Visit__c
        WHERE
          Status__c != 'Cancelled'
          AND Start__c >= :weekStart
          AND Start__c < :weekEnd
        WITH USER_MODE
      ];
      out.bookedThisWeek = thisWeek.isEmpty()
        ? 0
        : (Integer) thisWeek[0].get('total');
      return out;
    } catch (Exception e) {
      throw serverError(e, 'getSummary');
    }
  }

  // ================================================================= calendar
  /**
   * Events between two dates, for whichever span the calendar is showing. The week
   * view was the only span until the calendar gained month and day, so getWeek now
   * delegates here rather than carrying its own copy of the query.
   */
  @AuraEnabled(cacheable=true)
  public static List<EventRow> getEvents(
    Date fromDate,
    Date toDate,
    String program
  ) {
    try {
      Date startDay = fromDate == null ? Date.today() : fromDate;
      Date endDay = toDate == null ? startDay.addDays(7) : toDate;
      Datetime windowStart = Datetime.newInstance(
        startDay,
        Time.newInstance(0, 0, 0, 0)
      );
      Datetime windowEnd = Datetime.newInstance(
        endDay.addDays(1),
        Time.newInstance(0, 0, 0, 0)
      );

      List<Onboarding_Visit__c> found;
      if (String.isBlank(program)) {
        found = [
          SELECT
            Id,
            Name,
            Start__c,
            End__c,
            Status__c,
            Programs__c,
            Facility__c,
            Facility__r.Name,
            Facilitator__c,
            Facilitator__r.Name,
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
          WHERE Start__c >= :windowStart AND Start__c < :windowEnd
          WITH USER_MODE
          ORDER BY Start__c
          LIMIT 2000
        ];
      } else {
        found = [
          SELECT
            Id,
            Name,
            Start__c,
            End__c,
            Status__c,
            Programs__c,
            Facility__c,
            Facility__r.Name,
            Facilitator__c,
            Facilitator__r.Name,
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
          WHERE
            Start__c >= :windowStart
            AND Start__c < :windowEnd
            AND Programs__c INCLUDES (:program)
          WITH USER_MODE
          ORDER BY Start__c
          LIMIT 2000
        ];
      }
      return toRows(found);
    } catch (Exception e) {
      throw serverError(e, 'getEvents');
    }
  }

  /** Maps visit records to the shape the calendar renders. */
  private static List<EventRow> toRows(List<Onboarding_Visit__c> found) {
    List<EventRow> out = new List<EventRow>();
    for (Onboarding_Visit__c v : found) {
      EventRow r = new EventRow();
      r.eventId = v.Id;
      r.subject = v.Name;
      r.startTime = v.Start__c;
      r.endTime = v.End__c;
      r.facilityId = v.Facility__c;
      r.facilityName = v.Facility__r == null ? null : v.Facility__r.Name;
      r.facilitatorId = v.Facilitator__c;
      r.facilitatorName = v.Facilitator__r == null
        ? null
        : v.Facilitator__r.Name;
      r.providerIds = new List<Id>();
      List<String> names = new List<String>();
      for (Onboarding_Visit_Provider__c a : v.Providers__r) {
        if (a.Provider__c == null) {
          continue;
        }
        r.providerIds.add(a.Provider__c);
        if (a.Provider__r != null) {
          names.add(providerName(a.Provider__r));
        }
      }
      // First provider plus a count, so a four-provider visit still fits a calendar
      // cell one seventh of the grid wide. The full list is the tooltip.
      r.providerId = r.providerIds.isEmpty() ? null : r.providerIds[0];
      r.providerName = names.isEmpty() ? null : names[0];
      r.providerExtra = names.size() > 1 ? names.size() - 1 : 0;
      r.providerNamesFull = names.isEmpty() ? null : String.join(names, ', ');
      r.programs = orderedPrograms(v.Programs__c);
      r.programLabel = r.programs.isEmpty()
        ? null
        : String.join(r.programs, ', ');
      r.onboardingStatus = v.Status__c;
      out.add(r);
    }
    return out;
  }

  /**
   * The week the calendar used to be fixed to. Kept so existing callers and tests
   * keep working; the span now comes from getEvents.
   */
  @AuraEnabled(cacheable=true)
  public static List<EventRow> getWeek(Date weekStart, String program) {
    Date startDay = weekStart == null
      ? Date.today().toStartOfWeek()
      : weekStart;
    return getEvents(startDay, startDay.addDays(6), program);
  }

  // ================================================================= availability
  /**
   * Resources already committed in the given window. One query serves both pickers
   * and the save-time check, so the picker and the enforcement can never diverge.
   * A null window means "no time chosen yet", so nothing is treated as booked.
   * excludeVisitId keeps an event being edited from blocking its own resources.
   */
  private static void loadBooked(
    Datetime startTime,
    Datetime endTime,
    Id excludeVisitId,
    Set<Id> bookedProviders,
    Set<Id> bookedFacilitators
  ) {
    if (startTime == null || endTime == null) {
      return;
    }
    List<Onboarding_Visit__c> busy;
    if (excludeVisitId == null) {
      busy = [
        SELECT Id, Facilitator__c, (SELECT Provider__c FROM Providers__r)
        FROM Onboarding_Visit__c
        WHERE
          Status__c != 'Cancelled'
          AND Start__c < :endTime
          AND End__c > :startTime
        WITH USER_MODE
        LIMIT 2000
      ];
    } else {
      busy = [
        SELECT Id, Facilitator__c, (SELECT Provider__c FROM Providers__r)
        FROM Onboarding_Visit__c
        WHERE
          Status__c != 'Cancelled'
          AND Start__c < :endTime
          AND End__c > :startTime
          AND Id != :excludeVisitId
        WITH USER_MODE
        LIMIT 2000
      ];
    }
    // Every provider on an overlapping visit is busy, however many there are.
    for (Onboarding_Visit__c v : busy) {
      if (v.Facilitator__c != null) {
        bookedFacilitators.add(v.Facilitator__c);
      }
      for (Onboarding_Visit_Provider__c a : v.Providers__r) {
        if (a.Provider__c != null) {
          bookedProviders.add(a.Provider__c);
        }
      }
    }
  }

  // ================================================================= pickers
  /**
   * Facilities that can be scheduled, for the modal's picker. Opened from the top-right
   * Schedule button there is no row to inherit, so the facility must be chosen here;
   * opened from a row it arrives pre-selected (2026-09-24).
   */
  /**
   * Type-ahead over the facilities that can be scheduled. Scoped to the same statuses
   * as the worklist, so the ~10,000 status-less facilities awaiting cleanup can never
   * be booked against (Dorothy, 2026-09-24).
   *
   * The term is passed as a bind, never concatenated, and is escaped for the LIKE
   * wildcards so a user typing % or _ searches for those characters rather than
   * matching everything.
   */
  @AuraEnabled(cacheable=true)
  public static List<PickOption> searchFacilities(String term) {
    try {
      List<PickOption> out = new List<PickOption>();
      if (String.isBlank(term) || term.trim().length() < 2) {
        return out;
      }
      String pattern =
        '%' +
        term.trim()
          .replace('\\', '\\\\')
          .replace('%', '\\%')
          .replace('_', '\\_') +
        '%';
      for (Facility__c f : [
        SELECT Id, Name, Address__StateCode__s, Status__c
        FROM Facility__c
        WHERE Status__c IN ('Onboarding', 'Opportunity') AND Name LIKE :pattern
        WITH USER_MODE
        ORDER BY Name
        LIMIT 50
      ]) {
        String st = f.Address__StateCode__s;
        out.add(
          new PickOption(
            f.Name + (String.isBlank(st) ? ' (no state)' : ' - ' + st),
            f.Id
          )
        );
      }
      return out;
    } catch (Exception e) {
      throw serverError(e, 'searchFacilities');
    }
  }

  /**
   * Active facilitators who are free in the given window. Facilitators carry no
   * licensing or programme restriction - recording 2 established they are available
   * unless already booked - so availability is the only filter.
   */
  @AuraEnabled(cacheable=true)
  public static FacilitatorChoices getFacilitators(
    Datetime startTime,
    Datetime endTime,
    Id excludeVisitId
  ) {
    try {
      FacilitatorChoices out = new FacilitatorChoices();

      Set<Id> bookedProviders = new Set<Id>();
      Set<Id> bookedFacilitators = new Set<Id>();
      loadBooked(
        startTime,
        endTime,
        excludeVisitId,
        bookedProviders,
        bookedFacilitators
      );

      for (Facilitator__c f : [
        SELECT Id, Name
        FROM Facilitator__c
        WHERE Active__c = TRUE
        WITH USER_MODE
        ORDER BY Name
        LIMIT 500
      ]) {
        if (bookedFacilitators.contains(f.Id)) {
          out.hiddenBooked++;
        } else {
          out.options.add(new PickOption(f.Name, f.Id));
        }
      }
      return out;
    } catch (Exception e) {
      throw serverError(e, 'getFacilitators');
    }
  }

  /**
   * Providers who can actually take this booking: tagged for the program AND holding a
   * current State License in the facility's state AND without a conflicting program
   * combination. Filtering here mirrors the server-side eligibility rules, so the
   * picker stops offering people who would only be rejected on save.
   *
   * Hidden counts are returned so the UI can explain a short or empty list.
   */
  @AuraEnabled(cacheable=true)
  public static ProviderChoices getProviders(
    List<String> programs,
    Id facilityId,
    Datetime startTime,
    Datetime endTime,
    Id excludeVisitId
  ) {
    try {
      ProviderChoices out = new ProviderChoices();
      List<String> wanted = cleanPrograms(programs);

      Set<Id> bookedProviders = new Set<Id>();
      Set<Id> bookedFacilitators = new Set<Id>();
      loadBooked(
        startTime,
        endTime,
        excludeVisitId,
        bookedProviders,
        bookedFacilitators
      );

      // Facility state drives the licensing check.
      if (facilityId != null) {
        List<Facility__c> fs = [
          SELECT Id, Address__StateCode__s
          FROM Facility__c
          WHERE Id = :facilityId
          WITH USER_MODE
          LIMIT 1
        ];
        if (!fs.isEmpty()) {
          out.stateName = stateByCode.get(fs[0].Address__StateCode__s);
        }
      }

      List<Provider__c> candidates = [
        SELECT Id, Name, First_Name__c, Last_Name__c
        FROM Provider__c
        WITH USER_MODE
        ORDER BY Last_Name__c
        LIMIT 2000
      ];

      // With no state on the facility we can verify neither licence nor programme,
      // since both now live on the licence row. Offer everyone free at the time -
      // checkEligibility still blocks the save and explains why.
      if (out.stateName == null) {
        for (Provider__c p : candidates) {
          if (bookedProviders.contains(p.Id)) {
            out.hiddenBooked++;
          } else {
            out.options.add(new PickOption(providerName(p), p.Id));
          }
        }
        return out;
      }

      // One pass over the state's licences. Programme approval and licensure are a
      // single test now, not two independent ones (decision 2026-09-24): being
      // approved for a programme somewhere no longer implies approval here.
      //
      // With several programmes on one visit the bar is ALL of them: a provider who
      // covers two of the three booked programmes cannot take the visit, because
      // there would be no one approved for the third.
      Map<Id, Provider__c> byId = new Map<Id, Provider__c>(candidates);
      String stateName = out.stateName;
      Set<Id> licensedHere = new Set<Id>();
      Set<Id> conflicted = new Set<Id>();
      Map<Id, Set<String>> coveredByProvider = new Map<Id, Set<String>>();

      for (License__c l : [
        SELECT Provider__c, Programs__c, Expiration_Date__c
        FROM License__c
        WHERE
          Provider__c IN :byId.keySet()
          AND State__c = :stateName
          AND Type__c = 'State License'
        WITH USER_MODE
        LIMIT 5000
      ]) {
        if (
          l.Expiration_Date__c != null &&
          l.Expiration_Date__c < Date.today()
        ) {
          continue;
        }
        licensedHere.add(l.Provider__c);
        if (!coveredByProvider.containsKey(l.Provider__c)) {
          coveredByProvider.put(l.Provider__c, new Set<String>());
        }
        coveredByProvider.get(l.Provider__c).addAll(programSet(l.Programs__c));
        for (String w : wanted) {
          if (
            programSet(l.Programs__c).contains(w) &&
            hasProgramConflict(l.Programs__c, w)
          ) {
            conflicted.add(l.Provider__c);
          }
        }
      }

      Set<Id> eligible = new Set<Id>();
      Set<Id> untagged = new Set<Id>();
      for (Id pid : licensedHere) {
        if (conflicted.contains(pid)) {
          continue;
        }
        if (wanted.isEmpty()) {
          eligible.add(pid);
          continue;
        }
        Set<String> covered = coveredByProvider.get(pid);
        Boolean coversAll = true;
        for (String w : wanted) {
          if (covered == null || !covered.contains(w)) {
            coversAll = false;
            break;
          }
        }
        if (coversAll) {
          eligible.add(pid);
        } else {
          untagged.add(pid);
        }
      }

      // A provider may hold more than one licence row in a state, so one qualifying
      // licence is enough - eligible wins over the rejection buckets.
      for (Provider__c p : candidates) {
        if (eligible.contains(p.Id)) {
          if (bookedProviders.contains(p.Id)) {
            out.hiddenBooked++;
          } else {
            out.options.add(new PickOption(providerName(p), p.Id));
          }
        } else if (conflicted.contains(p.Id)) {
          out.hiddenConflicted++;
        } else if (untagged.contains(p.Id)) {
          out.hiddenUntagged++;
        } else {
          out.hiddenUnlicensed++;
        }
      }
      return out;
    } catch (Exception e) {
      throw serverError(e, 'getProviders');
    }
  }

  /**
   * The programmes on a visit, in the display order of ALL_PROGRAMS rather than the
   * order the platform happens to store them, so two visits with the same programmes
   * always read the same way.
   */
  private static List<String> orderedPrograms(String multiselect) {
    Set<String> held = programSet(multiselect);
    List<String> out = new List<String>();
    for (String p : ALL_PROGRAMS) {
      if (held.remove(p)) {
        out.add(p);
      }
    }
    // Anything not in the known list still shows, rather than vanishing.
    List<String> leftovers = new List<String>(held);
    leftovers.sort();
    out.addAll(leftovers);
    return out;
  }

  /** Drops blanks and duplicates, and keeps display order. */
  private static List<String> cleanPrograms(List<String> programs) {
    if (programs == null || programs.isEmpty()) {
      return new List<String>();
    }
    Set<String> given = new Set<String>();
    for (String p : programs) {
      if (String.isNotBlank(p)) {
        given.add(p.trim());
      }
    }
    List<String> out = new List<String>();
    for (String p : ALL_PROGRAMS) {
      if (given.remove(p)) {
        out.add(p);
      }
    }
    out.addAll(new List<String>(given));
    return out;
  }

  /** The semicolon-joined form the multi-select picklist stores. */
  private static String programsValue(List<String> programs) {
    List<String> clean = cleanPrograms(programs);
    return clean.isEmpty() ? null : String.join(clean, ';');
  }

  /**
   * Splits a multi-select picklist value into its members. Membership is tested on
   * whole values rather than with String.contains, which would let one programme name
   * match inside another as a substring.
   */
  private static Set<String> programSet(String multiselect) {
    Set<String> out = new Set<String>();
    if (String.isBlank(multiselect)) {
      return out;
    }
    for (String s : multiselect.split(';')) {
      String t = s.trim();
      if (String.isNotBlank(t)) {
        out.add(t);
      }
    }
    return out;
  }

  /**
   * Conflict is evaluated against the programmes on ONE licence, so two conflicting
   * programmes held in different states are not a conflict - only both on the same
   * state licence are.
   */
  private static Boolean hasProgramConflict(
    String licencePrograms,
    String program
  ) {
    if (String.isBlank(program)) {
      return false;
    }
    for (String other : programSet(licencePrograms)) {
      if (other != program && conflictPairs.contains(program + '|' + other)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 26 of the 315 providers carry no first or last name, here and in production,
   * but their record Name is populated ("Funsch, Daniel"), so that is the fallback.
   * "(unnamed)" told a coordinator nothing and made the picker useless for them.
   */
  private static String providerName(Provider__c p) {
    String nm = ((p.First_Name__c == null ? '' : p.First_Name__c) +
      ' ' +
      (p.Last_Name__c == null ? '' : p.Last_Name__c))
      .trim();
    if (String.isNotBlank(nm)) {
      return nm;
    }
    return String.isBlank(p.Name) ? '(no name on record)' : p.Name;
  }

  // ================================================================= eligibility
  /**
   * Fails closed. Every credential field is optional, so absence is treated as
   * "not eligible" rather than silently passing.
   */
  @AuraEnabled(cacheable=true)
  public static Eligibility checkEligibility(
    List<Id> providerIds,
    Id facilitatorId,
    Id facilityId,
    List<String> programs,
    Datetime startTime,
    Datetime endTime,
    Id excludeVisitId
  ) {
    try {
      Eligibility result = new Eligibility();
      if (facilityId == null) {
        result.add('Facility', 'blocked', 'A facility is required.');
        return result;
      }
      List<String> wanted = cleanPrograms(programs);

      // Two programmes that conflict with each other cannot sit on one visit at
      // all, whoever is assigned, so this is tested before anyone is looked at.
      for (Integer i = 0; i < wanted.size(); i++) {
        for (Integer j = i + 1; j < wanted.size(); j++) {
          if (conflictPairs.contains(wanted[i] + '|' + wanted[j])) {
            result.add(
              'Programs conflict',
              'blocked',
              wanted[i] +
                ' and ' +
                wanted[j] +
                ' cannot be billed on the same visit. Book them separately.'
            );
          }
        }
      }

      // A facility that does not run a programme should not be booked for it. This
      // warns rather than blocks: the facility record can lag the real rollout.
      warnIfFacilityDoesNotRun(result, facilityId, wanted);

      List<Facility__c> fs = [
        SELECT Id, Name, Address__StateCode__s
        FROM Facility__c
        WHERE Id = :facilityId
        WITH USER_MODE
        LIMIT 1
      ];
      if (fs.isEmpty()) {
        result.add(
          'Facility',
          'blocked',
          'Facility not found or not visible to you.'
        );
        return result;
      }
      String stateName = stateByCode.get(fs[0].Address__StateCode__s);

      // The four provider slots are optional and independent, so drop the empty
      // ones and reject a provider booked into two slots on the same event.
      List<Id> providers = new List<Id>();
      Set<Id> seen = new Set<Id>();
      if (providerIds != null) {
        for (Id pid : providerIds) {
          if (pid == null) {
            continue;
          }
          if (!seen.add(pid)) {
            result.add(
              'Duplicate provider',
              'blocked',
              'The same provider is assigned to more than one slot.'
            );
          } else {
            providers.add(pid);
          }
        }
      }

      // No provider chosen yet: the form is simply incomplete, so run only the
      // checks that do not need one rather than reporting a failure.
      if (providers.isEmpty()) {
        result.add(
          'No provider selected yet',
          'warning',
          'Pick a provider to run the licensing and program checks.'
        );
        if (startTime != null && endTime != null) {
          checkDoubleBooking(
            result,
            null,
            facilitatorId,
            startTime,
            endTime,
            excludeVisitId
          );
        }
        return result;
      }

      if (stateName == null) {
        result.add(
          'Facility state',
          'blocked',
          'Facility has no state on its address, so licensing cannot be verified.'
        );
      }

      Map<Id, Provider__c> provById = new Map<Id, Provider__c>(
        [
          SELECT Id, Name, First_Name__c, Last_Name__c, License_Title__c
          FROM Provider__c
          WHERE Id IN :providers
          WITH USER_MODE
        ]
      );

      // Every populated slot is checked on its own. With more than one provider the
      // checks are labelled, so a failure points at the provider that caused it.
      Boolean several = providers.size() > 1;
      for (Id pid : providers) {
        Provider__c prov = provById.get(pid);
        if (prov == null) {
          result.add(
            'Provider',
            'blocked',
            'Provider not found or not visible to you.'
          );
          continue;
        }
        if (stateName != null) {
          String prefix = several ? providerName(prov) + ' - ' : '';
          checkCredentials(result, prefix, pid, stateName, wanted, prov);
        }
      }

      // --- double booking
      if (startTime != null && endTime != null) {
        checkDoubleBooking(
          result,
          providers,
          facilitatorId,
          startTime,
          endTime,
          excludeVisitId
        );
      }
      return result;
    } catch (Exception e) {
      throw serverError(e, 'checkEligibility');
    }
  }

  private static void checkProgramConflict(
    Eligibility result,
    String prefix,
    String licencePrograms,
    String program
  ) {
    for (String other : programSet(licencePrograms)) {
      if (other != program && conflictPairs.contains(program + '|' + other)) {
        result.add(
          prefix + 'Program conflict',
          'blocked',
          'This licence also covers ' +
            other +
            ', which conflicts with ' +
            program +
            ' on billing. (Conflict list is provisional - open question Q4a.)'
        );
      }
    }
  }

  /**
   * Licensing AND programme approval for one provider in the facility's state.
   *
   * These were two independent tests until 2026-09-24, which meant a provider approved
   * for a programme anywhere passed for a facility anywhere they held any licence.
   * Programme approval now lives on the licence row, so both are answered from the
   * same records and a provider must be approved for this programme *in this state*.
   */
  private static void checkCredentials(
    Eligibility result,
    String prefix,
    Id providerId,
    String stateName,
    List<String> programs,
    Provider__c prov
  ) {
    List<License__c> licences = [
      SELECT
        Id,
        Type__c,
        State__c,
        Number__c,
        Programs__c,
        Issue_Date__c,
        Expiration_Date__c,
        Collaborative_Status__c
      FROM License__c
      WHERE Provider__c = :providerId AND State__c = :stateName
      WITH USER_MODE
      LIMIT 50
    ];

    // A state may carry several State License rows, so they are kept as a list and
    // the programme test picks the one that actually covers this booking.
    List<License__c> stateLicences = new List<License__c>();
    Map<String, License__c> byType = new Map<String, License__c>();
    for (License__c l : licences) {
      if (l.Type__c == 'State License') {
        stateLicences.add(l);
      } else {
        byType.put(l.Type__c, l);
      }
    }

    List<License__c> current = new List<License__c>();
    Date latestExpiry = null;
    for (License__c l : stateLicences) {
      if (
        l.Expiration_Date__c == null ||
        l.Expiration_Date__c >= Date.today()
      ) {
        current.add(l);
      }
      if (
        l.Expiration_Date__c != null &&
        (latestExpiry == null ||
        l.Expiration_Date__c > latestExpiry)
      ) {
        latestExpiry = l.Expiration_Date__c;
      }
    }

    License__c chosen = null;

    // State licence is mandatory - absence blocks.
    if (stateLicences.isEmpty()) {
      result.add(
        prefix + 'State licence',
        'blocked',
        'No State License on record for ' + stateName + '.'
      );
    } else if (current.isEmpty()) {
      result.add(
        prefix + 'State licence expired',
        'blocked',
        'Expired ' + latestExpiry.format() + '.'
      );
    } else if (programs == null || programs.isEmpty()) {
      chosen = current[0];
      result.add(prefix + 'Licensed in ' + stateName, 'ok', null);
      result.add(
        prefix + 'Program',
        'warning',
        'No program selected, so program checks were skipped.'
      );
    } else {
      // Every programme on the visit is answered on its own, so a failure names the
      // programme that caused it rather than just saying the provider is no good.
      List<String> missing = new List<String>();
      for (String program : programs) {
        License__c hit = null;
        for (License__c l : current) {
          if (programSet(l.Programs__c).contains(program)) {
            hit = l;
            break;
          }
        }
        if (hit == null) {
          missing.add(program);
        } else {
          if (chosen == null) {
            chosen = hit;
          }
          result.add(
            prefix + program + ' approved in ' + stateName,
            'ok',
            null
          );
          checkProgramConflict(result, prefix, hit.Programs__c, program);
        }
      }
      if (!missing.isEmpty()) {
        // Licensed in the state, but not for this programme - the exact case the
        // old provider-level check let through.
        result.add(
          prefix + 'Program approval',
          'blocked',
          'Licensed in ' +
            stateName +
            ', but no licence there covers ' +
            String.join(missing, ' or ') +
            '.'
        );
      }
      if (chosen == null) {
        chosen = current[0];
      }
    }
    if (chosen != null) {
      warnIfExpiringSoon(
        result,
        prefix + 'State licence',
        chosen.Expiration_Date__c
      );
    }

    // DEA and CSR warn rather than block - not every provider needs them.
    for (String t : new List<String>{ 'DEA', 'CSR' }) {
      License__c l = byType.get(t);
      if (l == null) {
        result.add(
          prefix + t + ' not on record',
          'warning',
          'No ' + t + ' entry for ' + stateName + '.'
        );
      } else if (
        l.Expiration_Date__c != null &&
        l.Expiration_Date__c < Date.today()
      ) {
        result.add(
          prefix + t + ' expired',
          'warning',
          'Expired ' + l.Expiration_Date__c.format() + '.'
        );
      } else {
        result.add(prefix + t + ' current', 'ok', null);
        warnIfExpiringSoon(result, prefix + t, l.Expiration_Date__c);
      }
    }

    // Collaborative status is read from the State License row (decision 2026-09-16)
    // so that a state with several rows resolves deterministically.
    String title = prov.License_Title__c == null
      ? ''
      : prov.License_Title__c.toUpperCase();
    if (title.contains('NP') || title.contains('NURSE')) {
      String collab = chosen == null ? null : chosen.Collaborative_Status__c;
      if (collab == 'Complete' || collab == 'Exempt') {
        result.add(
          prefix + 'Collaborating physician: ' + collab.toLowerCase(),
          'ok',
          null
        );
      } else {
        result.add(
          prefix + 'Collaborating physician',
          'warning',
          'Status is ' +
            (collab == null ? 'not recorded' : collab) +
            ' for ' +
            stateName +
            '.'
        );
      }
    }
  }

  /**
   * Says so when a visit is booked for a programme the facility is not recorded as
   * running. A warning rather than a block, because the Facility record often lags the
   * real rollout by a day or two and blocking would stop legitimate bookings.
   */
  private static void warnIfFacilityDoesNotRun(
    Eligibility result,
    Id facilityId,
    List<String> programs
  ) {
    if (facilityId == null || programs == null || programs.isEmpty()) {
      return;
    }
    Map<String, Boolean> active = facilityProgramState(facilityId);
    List<String> notRun = new List<String>();
    for (String p : programs) {
      // A programme with no facility field cannot be answered either way, so it is
      // not reported as "not run".
      if (active.containsKey(p) && active.get(p) != true) {
        notRun.add(p);
      }
    }
    if (!notRun.isEmpty()) {
      result.add(
        'Facility program',
        'warning',
        'This facility is not marked active for ' +
          String.join(notRun, ' or ') +
          '. Check the facility record if that looks wrong.'
      );
    }
  }

  /**
   * Which programmes the facility runs, read from its per-programme status fields.
   * Programmes with no facility field are absent from the map rather than false, so a
   * caller can tell "not run" from "cannot say".
   */
  private static Map<String, Boolean> facilityProgramState(Id facilityId) {
    Map<String, Boolean> out = new Map<String, Boolean>();
    if (facilityId == null) {
      return out;
    }
    List<String> fields = new List<String>(FACILITY_PROGRAM_FIELD.values());
    String soql =
      'SELECT Id, ' +
      String.join(fields, ', ') +
      ' FROM Facility__c WHERE Id = :fid LIMIT 1';
    List<Facility__c> found = Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'fid' => facilityId },
      AccessLevel.USER_MODE
    );
    if (found.isEmpty()) {
      return out;
    }
    for (String program : FACILITY_PROGRAM_FIELD.keySet()) {
      Object raw = found[0].get(FACILITY_PROGRAM_FIELD.get(program));
      String value = raw == null ? null : String.valueOf(raw);
      out.put(program, PROGRAM_ACTIVE.equalsIgnoreCase(value));
    }
    return out;
  }

  // ================================================================= facility programs
  /**
   * The programme choices for one facility, for the booking dialog. Every programme is
   * returned, with a flag and a reason, rather than only the available ones: a
   * coordinator needs to see that CoCM exists and is off here, not have it silently
   * missing from the list.
   */
  @AuraEnabled(cacheable=true)
  public static List<ProgramOption> getFacilityPrograms(Id facilityId) {
    try {
      Map<String, Boolean> state = facilityProgramState(facilityId);
      List<ProgramOption> out = new List<ProgramOption>();
      for (String program : ALL_PROGRAMS) {
        ProgramOption o = new ProgramOption();
        o.value = program;
        o.label = program;
        if (facilityId == null) {
          o.available = true;
          o.reason = 'Choose a facility to see which programs it runs.';
        } else if (!state.containsKey(program)) {
          // Community Full-Time and IPV Onboarding have no facility field.
          o.available = true;
          o.reason = 'Not tracked on the facility record.';
        } else if (state.get(program) == true) {
          o.available = true;
          o.reason = null;
        } else {
          o.available = false;
          o.reason = 'Not active at this facility.';
        }
        out.add(o);
      }
      return out;
    } catch (Exception e) {
      throw serverError(e, 'getFacilityPrograms');
    }
  }

  private static void warnIfExpiringSoon(
    Eligibility result,
    String label,
    Date expiry
  ) {
    if (expiry == null) {
      return;
    }
    Integer days = Date.today().daysBetween(expiry);
    if (days >= 0 && days <= 30) {
      result.add(label + ' expires in ' + days + ' days', 'warning', null);
    }
  }

  private static void checkDoubleBooking(
    Eligibility result,
    List<Id> providerIds,
    Id facilitatorId,
    Datetime startTime,
    Datetime endTime,
    Id excludeVisitId
  ) {
    Set<Id> bookedProviders = new Set<Id>();
    Set<Id> bookedFacilitators = new Set<Id>();
    loadBooked(
      startTime,
      endTime,
      excludeVisitId,
      bookedProviders,
      bookedFacilitators
    );

    // Named per provider, so with four slots it is clear which one clashes.
    List<String> clashing = new List<String>();
    if (providerIds != null) {
      Map<Id, Provider__c> named = new Map<Id, Provider__c>(
        [
          SELECT Id, Name, First_Name__c, Last_Name__c
          FROM Provider__c
          WHERE Id IN :providerIds
          WITH USER_MODE
        ]
      );
      for (Id pid : providerIds) {
        if (pid != null && bookedProviders.contains(pid)) {
          Provider__c p = named.get(pid);
          clashing.add(p == null ? 'Provider' : providerName(p));
        }
      }
    }
    Boolean providerClash = !clashing.isEmpty();
    Boolean facilitatorClash =
      facilitatorId != null && bookedFacilitators.contains(facilitatorId);

    if (providerClash) {
      result.add(
        String.join(clashing, ', ') + ' already booked',
        'blocked',
        'Another onboarding event overlaps that window.'
      );
    }
    if (facilitatorClash) {
      result.add(
        'Facilitator already booked',
        'blocked',
        'This facilitator has another onboarding event overlapping that window.'
      );
    }
    if (!providerClash && !facilitatorClash) {
      result.add('No scheduling conflict', 'ok', null);
    }
  }

  // ================================================================= save
  /**
   * Normalises the four provider slots to the populated ones and rejects an
   * over-long list. Order is preserved so slot 1 stays slot 1.
   */
  private static List<Id> normaliseSlots(List<Id> providerIds) {
    List<Id> slots = new List<Id>();
    if (providerIds != null) {
      for (Id pid : providerIds) {
        if (pid != null) {
          slots.add(pid);
        }
      }
    }
    if (slots.size() > 4) {
      throw new AuraHandledException(
        'At most four providers can be assigned to a visit.'
      );
    }
    return slots;
  }

  private static void refuseIfBlocked(Eligibility check) {
    if (check.allowed) {
      return;
    }
    String why = '';
    for (Check c : check.checks) {
      if (c.level == 'blocked') {
        why +=
          (why == '' ? '' : ' ') +
          c.label +
          (c.detail == null ? '' : ': ' + c.detail);
      }
    }
    throw new AuraHandledException('Cannot save. ' + why);
  }

  private static void writeAssignments(Id visitId, List<Id> slots) {
    // Replace rather than merge, so removing a provider in the UI removes the row.
    List<Onboarding_Visit_Provider__c> existing = [
      SELECT Id
      FROM Onboarding_Visit_Provider__c
      WHERE Onboarding_Visit__c = :visitId
      WITH USER_MODE
    ];
    if (!existing.isEmpty()) {
      Database.delete(existing, AccessLevel.USER_MODE);
    }
    List<Onboarding_Visit_Provider__c> rows = new List<Onboarding_Visit_Provider__c>();
    for (Id pid : slots) {
      rows.add(
        new Onboarding_Visit_Provider__c(
          Onboarding_Visit__c = visitId,
          Provider__c = pid
        )
      );
    }
    if (!rows.isEmpty()) {
      Database.insert(rows, AccessLevel.USER_MODE);
    }
  }

  /**
   * Creates the onboarding visit, its provider assignments and the shadow Event.
   * Re-runs eligibility server-side - the LWC result is advisory only and is never
   * trusted as the authorisation. OwnerId is taken from UserInfo, never the request.
   */
  @AuraEnabled
  public static Id saveVisit(
    Id facilityId,
    Id facilitatorId,
    List<Id> providerIds,
    List<String> programs,
    Datetime startTime,
    Datetime endTime
  ) {
    if (facilityId == null || startTime == null || endTime == null) {
      throw new AuraHandledException('Facility, start and end are required.');
    }
    if (endTime <= startTime) {
      throw new AuraHandledException(
        'The end time must be after the start time.'
      );
    }
    List<Id> slots = normaliseSlots(providerIds);
    List<String> wanted = cleanPrograms(programs);
    refuseIfBlocked(
      checkEligibility(
        slots,
        facilitatorId,
        facilityId,
        wanted,
        startTime,
        endTime,
        null
      )
    );

    try {
      // Confirm the caller can actually see the facility before writing against it.
      List<Facility__c> fs = [
        SELECT Id, Name
        FROM Facility__c
        WHERE Id = :facilityId
        WITH USER_MODE
        LIMIT 1
      ];
      if (fs.isEmpty()) {
        throw new AuraHandledException(
          'Facility not found or not visible to you.'
        );
      }

      Onboarding_Visit__c visit = new Onboarding_Visit__c(
        Facility__c = facilityId,
        Facilitator__c = facilitatorId,
        Programs__c = programsValue(wanted),
        Start__c = startTime,
        End__c = endTime,
        Status__c = 'Scheduled'
      );
      Database.insert(visit, AccessLevel.USER_MODE);
      // The shadow Event is written by OnboardingVisitTrigger, so a visit
      // changed outside this component stays in step too.
      writeAssignments(visit.Id, slots);
      return visit.Id;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw serverError(e, 'saveVisit');
    }
  }

  /**
   * Updates an existing visit. Re-runs eligibility server-side, ignoring this visit's
   * own booking so editing it does not clash with itself. The record is fetched
   * WITH USER_MODE first, so a user who cannot see it cannot edit it.
   */
  @AuraEnabled
  public static Id updateVisit(
    Id visitId,
    Id facilitatorId,
    List<Id> providerIds,
    List<String> programs,
    Datetime startTime,
    Datetime endTime,
    String onboardingStatus
  ) {
    if (visitId == null || startTime == null || endTime == null) {
      throw new AuraHandledException('Visit, start and end are required.');
    }
    if (endTime <= startTime) {
      throw new AuraHandledException(
        'The end time must be after the start time.'
      );
    }
    List<Id> slots = normaliseSlots(providerIds);
    List<String> wanted = cleanPrograms(programs);

    List<Onboarding_Visit__c> existing;
    try {
      existing = [
        SELECT Id, Facility__c, Facility__r.Name, Shadow_Event_Id__c
        FROM Onboarding_Visit__c
        WHERE Id = :visitId
        WITH USER_MODE
        LIMIT 1
      ];
    } catch (Exception e) {
      throw serverError(e, 'updateVisit');
    }
    if (existing.isEmpty()) {
      throw new AuraHandledException('Visit not found or not visible to you.');
    }

    refuseIfBlocked(
      checkEligibility(
        slots,
        facilitatorId,
        existing[0].Facility__c,
        wanted,
        startTime,
        endTime,
        visitId
      )
    );

    try {
      Onboarding_Visit__c visit = new Onboarding_Visit__c(
        Id = visitId,
        Facilitator__c = facilitatorId,
        Programs__c = programsValue(wanted),
        Start__c = startTime,
        End__c = endTime,
        Status__c = String.isBlank(onboardingStatus)
          ? 'Scheduled'
          : onboardingStatus
      );
      Database.update(visit, AccessLevel.USER_MODE);
      writeAssignments(visitId, slots);
      return visitId;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw serverError(e, 'updateVisit');
    }
  }

  // ================================================================= errors
  /**
   * Logs the real detail server-side and hands the client a generic message plus a
   * correlation id. Driver text, SOQL and stack traces never reach the browser.
   */
  public class SchedulingException extends Exception {
  }

  private static Exception serverError(Exception e, String op) {
    String correlationId = String.valueOf(Crypto.getRandomInteger())
      .replace('-', '');
    System.debug(
      LoggingLevel.ERROR,
      'FacilityScheduling[' +
        correlationId +
        '] ' +
        op +
        ' failed: ' +
        e.getTypeName() +
        ' ' +
        e.getMessage() +
        '\n' +
        e.getStackTraceString()
    );

    // AuraHandledException cannot be thrown outside an Aura/LWC context, and it
    // would hide the cause from test output anyway. In tests, surface the real
    // detail; at runtime the client still sees only the generic message.
    if (Test.isRunningTest()) {
      return new SchedulingException(
        op + ' failed: ' + e.getTypeName() + ' - ' + e.getMessage()
      );
    }
    String friendly =
      'Something went wrong loading scheduling data. Quote reference ' +
      correlationId +
      '.';
    AuraHandledException ex = new AuraHandledException(friendly);
    ex.setMessage(friendly);
    return ex;
  }
}
