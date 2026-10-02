/**
 * Tests for FacilitySchedulingController.
 *
 * All data is created in-test. No patient data is queried from the org, and no
 * assertion references real records.
 */
@IsTest
private class FacilitySchedulingControllerTest {
  private static Facility__c makeFacility(
    String name,
    String stateCode,
    String status
  ) {
    Facility__c f = new Facility__c(
      Name = name,
      Status__c = status,
      Scheduled_Rollout_Date__c = Date.today().addDays(7)
    );
    f.put('Address__StateCode__s', stateCode);
    f.put('Address__CountryCode__s', 'US');
    return f;
  }

  private static Provider__c makeProvider(
    String first,
    String last,
    String title
  ) {
    return new Provider__c(
      First_Name__c = first,
      Last_Name__c = last,
      License_Title__c = title
    );
  }

  private static License__c makeLicence(
    Id providerId,
    String type,
    String state,
    Date expiry,
    String programs
  ) {
    return new License__c(
      Provider__c = providerId,
      Type__c = type,
      State__c = state,
      Number__c = 'TEST-' + type,
      Issue_Date__c = Date.today().addYears(-2),
      Expiration_Date__c = expiry,
      Programs__c = programs
    );
  }

  /**
   * A user to run the controller as.
   *
   * The controller queries WITH USER_MODE, so whoever runs it must hold the
   * component's permission set. Assigning it to the *running* user inside the test
   * does not work - a user's permission context is fixed when the test transaction
   * begins - so the tests run as a purpose-made user instead, granted the permission
   * set in @TestSetup and entered through System.runAs.
   *
   * Without this the suite passes in a sandbox where the developer already holds the
   * permission set and fails in any org where nobody does yet - a production
   * validation, or a scratch org - reporting every field as "No such column", which
   * reads like a missing field rather than a missing grant.
   *
   * The profile is copied from whoever is running the tests, so this makes no
   * assumption about which profiles the target org happens to have.
   */
  private static User cachedScheduler;

  private static User scheduler() {
    if (cachedScheduler == null) {
      cachedScheduler = [
        SELECT Id
        FROM User
        WHERE Username LIKE 'sched.runner.%@example.invalid'
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
    }
    return cachedScheduler;
  }

  private static void createSchedulerUser() {
    User u = new User(
      FirstName = 'Sched',
      LastName = 'Runner',
      Alias = 'schedr',
      Email = 'sched.runner@example.invalid',
      Username = 'sched.runner.' +
        String.valueOf(Datetime.now().getTime()) +
        '@example.invalid',
      ProfileId = UserInfo.getProfileId(),
      TimeZoneSidKey = 'America/New_York',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    // Setup objects cannot share a DML context with the records below.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      List<PermissionSet> ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Facility_Scheduling'
        LIMIT 1
      ];
      if (!ps.isEmpty()) {
        insert new PermissionSetAssignment(
          AssigneeId = u.Id,
          PermissionSetId = ps[0].Id
        );
      }
    }
  }

  @TestSetup
  static void setup() {
    createSchedulerUser();

    Facility__c f = makeFacility(
      'Test Onboarding Facility',
      'KS',
      'Onboarding'
    );
    insert f;

    Provider__c eligible = makeProvider('Ada', 'Eligible', 'MD');
    Provider__c unlicensed = makeProvider('Bob', 'Unlicensed', 'MD');
    Provider__c conflicted = makeProvider('Cal', 'Conflicted', 'MD');
    // Licensed in both states, but for a different programme in each - the case the
    // old provider-level programme check let through.
    Provider__c crossState = makeProvider('Dee', 'CrossState', 'MD');
    insert new List<Provider__c>{
      eligible,
      unlicensed,
      conflicted,
      crossState
    };

    insert new List<License__c>{
      makeLicence(
        eligible.Id,
        'State License',
        'Kansas',
        Date.today().addYears(1),
        'BHI;TCM'
      ),
      makeLicence(eligible.Id, 'DEA', 'Kansas', Date.today().addYears(1), null),
      makeLicence(
        conflicted.Id,
        'State License',
        'Kansas',
        Date.today().addYears(1),
        'BHI;CoCM'
      ),
      makeLicence(
        crossState.Id,
        'State License',
        'Kansas',
        Date.today().addYears(1),
        'TCM'
      ),
      makeLicence(
        crossState.Id,
        'State License',
        'Pennsylvania',
        Date.today().addYears(1),
        'BHI'
      )
    };

    insert new Facilitator__c(
      Name = 'Test Facilitator',
      First_Name__c = 'Fay',
      Last_Name__c = 'Facilitator',
      Active__c = true
    );
  }

  private static Provider__c provider(String lastName) {
    return [
      SELECT Id, License_Title__c
      FROM Provider__c
      WHERE Last_Name__c = :lastName
      LIMIT 1
    ];
  }

  private static Facility__c facility() {
    return [
      SELECT Id, Name
      FROM Facility__c
      WHERE Name = 'Test Onboarding Facility'
      LIMIT 1
    ];
  }

  @IsTest
  static void worklistReturnsOnboardingFacilities() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Test.startTest();
      List<FacilitySchedulingController.FacilityRow> rows = FacilitySchedulingController.getWorklist(
        null,
        null,
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isFalse(
        rows.isEmpty(),
        'Expected at least the onboarding facility'
      );
      Boolean found = false;
      for (FacilitySchedulingController.FacilityRow r : rows) {
        if (r.name == 'Test Onboarding Facility') {
          found = true;
          Assert.areEqual(
            0,
            r.census,
            'No patients created, so census should be zero'
          );
          Assert.areEqual(
            0,
            r.seen,
            'No patients created, so seen should be zero'
          );
          Assert.areEqual(
            0,
            r.consented,
            'No patients created, so consented should be zero'
          );
        }
      }
      Assert.isTrue(
        found,
        'The onboarding facility should appear in the worklist'
      );
    }
  }

  @IsTest
  static void worklistHonoursDateFilters() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Test.startTest();
      List<FacilitySchedulingController.FacilityRow> none = FacilitySchedulingController.getWorklist(
        null,
        Date.today().addDays(30),
        Date.today().addDays(60),
        null,
        null
      );
      Test.stopTest();
      Assert.isTrue(
        none.isEmpty(),
        'Rollout date is 7 days out, so a 30-60 day window matches nothing'
      );
    }
  }

  @IsTest
  static void eligibleProviderPasses() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Eligible');
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ p.Id },
        null,
        f.Id,
        new List<String>{ 'BHI' },
        Datetime.now().addDays(1),
        Datetime.now().addDays(1).addHours(2),
        null
      );
      Test.stopTest();

      Assert.isTrue(
        result.allowed,
        'Licensed, tagged, unconflicted provider should be allowed'
      );
    }
  }

  @IsTest
  static void missingStateLicenceBlocks() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Unlicensed');
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ p.Id },
        null,
        f.Id,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isFalse(result.allowed, 'No licence on record must fail closed');
    }
  }

  @IsTest
  static void untaggedProgramBlocks() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Eligible');
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ p.Id },
        null,
        f.Id,
        new List<String>{ 'Telepsych' },
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isFalse(
        result.allowed,
        'Provider is not tagged for Telepsych, so it must block'
      );
    }
  }

  @IsTest
  static void conflictingProgramsBlock() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Conflicted');
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ p.Id },
        null,
        f.Id,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isFalse(
        result.allowed,
        'BHI plus CoCM on one provider must block the booking'
      );
    }
  }

  /**
   * The regression this whole change exists for. Dee holds a current State License in
   * Kansas (TCM only) and another in Pennsylvania (BHI only). Booking BHI at the Kansas
   * facility must fail: programme approval and licensure have to be satisfied by the
   * SAME licence. The old provider-level check passed this, because the provider was
   * tagged BHI somewhere and licensed in Kansas somehow.
   */
  @IsTest
  static void programmeApprovedInAnotherStateStillBlocks() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('CrossState');
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ p.Id },
        null,
        f.Id,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isFalse(
        result.allowed,
        'BHI is licensed in Pennsylvania, not Kansas, so a Kansas booking must block'
      );
    }
  }

  @IsTest
  static void programmeApprovedInThisStatePasses() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('CrossState');
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ p.Id },
        null,
        f.Id,
        new List<String>{ 'TCM' },
        Datetime.now().addDays(2),
        Datetime.now().addDays(2).addHours(2),
        null
      );
      Test.stopTest();

      Assert.isTrue(
        result.allowed,
        'TCM is on the Kansas licence, so it must be allowed'
      );
    }
  }

  /**
   * Conflict is now a property of one licence. Two conflicting programmes split across
   * two states are not a conflict.
   */
  @IsTest
  static void conflictAcrossSeparateStatesDoesNotBlock() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c split = new Provider__c(
        First_Name__c = 'Eve',
        Last_Name__c = 'Split',
        License_Title__c = 'MD'
      );
      insert split;
      insert new List<License__c>{
        makeLicence(
          split.Id,
          'State License',
          'Kansas',
          Date.today().addYears(1),
          'BHI'
        ),
        makeLicence(
          split.Id,
          'State License',
          'Pennsylvania',
          Date.today().addYears(1),
          'CoCM'
        )
      };
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ split.Id },
        null,
        f.Id,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isTrue(
        result.allowed,
        'BHI in Kansas and CoCM in Pennsylvania are not a conflict'
      );
    }
  }

  @IsTest
  static void duplicateProviderSlotsBlock() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Eligible');
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ p.Id, p.Id },
        null,
        f.Id,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isFalse(
        result.allowed,
        'The same provider in two slots must be refused'
      );
    }
  }

  @IsTest
  static void severalProvidersAreEachChecked() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c good = provider('Eligible');
      Provider__c bad = provider('Unlicensed');
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
        new List<Id>{ good.Id, bad.Id },
        null,
        f.Id,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isFalse(
        result.allowed,
        'One ineligible provider in any slot must block the whole event'
      );
    }
  }

  @IsTest
  static void saveCreatesEventThenBlocksTheOverlap() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Eligible');
      Facility__c f = facility();
      Facilitator__c fac = [SELECT Id FROM Facilitator__c LIMIT 1];
      Datetime start = Datetime.now().addDays(2);
      Datetime finish = start.addHours(3);

      Test.startTest();
      Id eventId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        finish
      );
      Assert.isNotNull(eventId, 'The event should be created');

      // Same provider, overlapping window - must now be refused.
      Boolean blocked = false;
      try {
        FacilitySchedulingController.saveVisit(
          f.Id,
          fac.Id,
          new List<Id>{ p.Id },
          new List<String>{ 'BHI' },
          start.addMinutes(30),
          finish.addMinutes(30)
        );
      } catch (Exception e) {
        blocked = true;
      }
      Test.stopTest();

      Assert.isTrue(
        blocked,
        'An overlapping booking for the same provider must be refused'
      );

      Onboarding_Visit__c created = [
        SELECT
          Id,
          Facility__c,
          Status__c,
          Shadow_Event_Id__c,
          (SELECT Provider__c FROM Providers__r)
        FROM Onboarding_Visit__c
        WHERE Id = :eventId
      ];
      Assert.areEqual(
        f.Id,
        created.Facility__c,
        'Visit should relate to the facility'
      );
      Assert.areEqual(
        1,
        created.Providers__r.size(),
        'One provider should be assigned'
      );
      Assert.isNotNull(
        created.Shadow_Event_Id__c,
        'A shadow Event should have been written'
      );

      Event shadow = [
        SELECT Id, WhatId, OwnerId, Onboarding_Visit__c
        FROM Event
        WHERE Id = :created.Shadow_Event_Id__c
      ];
      Assert.areEqual(
        f.Id,
        shadow.WhatId,
        'Shadow Event should relate to the facility'
      );
      Assert.areEqual(
        created.Id,
        shadow.Onboarding_Visit__c,
        'Shadow Event must point back at its visit'
      );
      Assert.areEqual(
        UserInfo.getUserId(),
        shadow.OwnerId,
        'Owner must come from the session, never from the request'
      );
      Assert.areEqual(
        'Scheduled',
        created.Status__c,
        'New visits start as Scheduled'
      );
    }
  }

  /**
   * The reason for the visit object: several providers on one onboarding visit, which
   * standard Event cannot hold. Checks the junction rows and the shadow Event.
   */
  @IsTest
  static void visitHoldsSeveralProviders() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Provider__c a = provider('Eligible');
      Provider__c b = provider('CrossState');
      Datetime start = Datetime.now().addDays(9);

      Test.startTest();
      // Both are licensed in Kansas for TCM, so both should pass.
      Id visitId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ a.Id, b.Id },
        new List<String>{ 'TCM' },
        start,
        start.addHours(2)
      );
      Test.stopTest();

      Onboarding_Visit__c visit = [
        SELECT Id, Shadow_Event_Id__c, (SELECT Provider__c FROM Providers__r)
        FROM Onboarding_Visit__c
        WHERE Id = :visitId
      ];
      Assert.areEqual(
        2,
        visit.Providers__r.size(),
        'Both providers should be assigned'
      );

      Set<Id> assigned = new Set<Id>();
      for (Onboarding_Visit_Provider__c row : visit.Providers__r) {
        assigned.add(row.Provider__c);
      }
      Assert.isTrue(
        assigned.contains(a.Id) && assigned.contains(b.Id),
        'Both providers should appear in the junction'
      );

      Event shadow = [
        SELECT Subject, Provider__c
        FROM Event
        WHERE Id = :visit.Shadow_Event_Id__c
      ];
      Assert.areEqual(
        a.Id,
        shadow.Provider__c,
        'Slot 1 goes on the Event lookup - the platform allows only one'
      );
      Assert.isTrue(
        shadow.Subject.contains('CrossState'),
        'The shadow subject should name the providers the lookup cannot hold'
      );
    }
  }

  @IsTest
  static void removingAProviderRemovesItsAssignment() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Provider__c a = provider('Eligible');
      Provider__c b = provider('CrossState');
      Datetime start = Datetime.now().addDays(10);

      Test.startTest();
      Id visitId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ a.Id, b.Id },
        new List<String>{ 'TCM' },
        start,
        start.addHours(2)
      );
      FacilitySchedulingController.updateVisit(
        visitId,
        fac.Id,
        new List<Id>{ a.Id },
        new List<String>{ 'TCM' },
        start,
        start.addHours(2),
        'Confirmed'
      );
      Test.stopTest();

      Onboarding_Visit__c visit = [
        SELECT Id, (SELECT Provider__c FROM Providers__r)
        FROM Onboarding_Visit__c
        WHERE Id = :visitId
      ];
      Assert.areEqual(
        1,
        visit.Providers__r.size(),
        'Dropping a provider in the UI must delete its assignment, not leave it behind'
      );
      Assert.areEqual(
        a.Id,
        visit.Providers__r[0].Provider__c,
        'The kept provider should remain'
      );
    }
  }

  /**
   * Proves the permission set is actually sufficient. Every other test runs as the
   * developer, who is an administrator with several other permission sets, so it
   * cannot show whether a scheduling-only user can use the component. This one runs
   * as a user holding the Scheduling profile plus Facility_Scheduling and nothing else.
   *
   * If a field is missing from the permission set, WITH USER_MODE reports it as
   * "No such column" and this fails.
   */
  @IsTest
  static void schedulingOnlyUserCanRunTheComponent() {
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Profile pr = [SELECT Id FROM Profile WHERE Name = 'Scheduling' LIMIT 1];
      u = new User(
        FirstName = 'Sched',
        LastName = 'OnlyUser',
        Alias = 'schedo',
        Email = 'sched.only@example.invalid',
        Username = 'sched.only.' +
          String.valueOf(Datetime.now().getTime()) +
          '@example.invalid',
        ProfileId = pr.Id,
        TimeZoneSidKey = 'America/New_York',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      );
      insert u;
      PermissionSet ps = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Facility_Scheduling'
        LIMIT 1
      ];
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = ps.Id
      );
    }

    Facility__c f = facility();
    Provider__c p = provider('Eligible');
    Facilitator__c fac = [
      SELECT Id
      FROM Facilitator__c
      WHERE Active__c = TRUE
      LIMIT 1
    ];
    Datetime start = Datetime.now().addDays(12);
    Id visitId;

    Test.startTest();
    System.runAs(u) {
      FacilitySchedulingController.getWorklist(null, null, null, null, null);
      FacilitySchedulingController.searchFacilities('ZZ TEST');
      FacilitySchedulingController.getWeek(Date.today(), null);
      FacilitySchedulingController.getFacilitators(
        Datetime.now(),
        Datetime.now().addHours(2),
        null
      );
      FacilitySchedulingController.getProviders(
        new List<String>{ 'BHI' },
        f.Id,
        Datetime.now(),
        Datetime.now().addHours(2),
        null
      );
      FacilitySchedulingController.checkEligibility(
        new List<Id>{ p.Id },
        null,
        f.Id,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );

      // The write path matters more than the reads - this is what the scheduler
      // actually does, and it creates a visit, its assignments and a shadow Event.
      visitId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        start.addHours(2)
      );
    }
    Test.stopTest();

    Assert.isNotNull(
      visitId,
      'A scheduling-only user must be able to create a visit'
    );
    Onboarding_Visit__c created = [
      SELECT Id, Shadow_Event_Id__c, (SELECT Provider__c FROM Providers__r)
      FROM Onboarding_Visit__c
      WHERE Id = :visitId
    ];
    Assert.areEqual(
      1,
      created.Providers__r.size(),
      'The assignment must be writable by a scheduling-only user'
    );
    Assert.isNotNull(
      created.Shadow_Event_Id__c,
      'The shadow Event must be writable by a scheduling-only user'
    );
  }

  @IsTest
  static void facilitySearchIsScopedAndSafe() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Test.startTest();
      List<FacilitySchedulingController.PickOption> hits = FacilitySchedulingController.searchFacilities(
        'Test Onboarding'
      );
      List<FacilitySchedulingController.PickOption> tooShort = FacilitySchedulingController.searchFacilities(
        'a'
      );
      List<FacilitySchedulingController.PickOption> wildcard = FacilitySchedulingController.searchFacilities(
        '%'
      );
      Test.stopTest();

      Assert.isFalse(
        hits.isEmpty(),
        'The onboarding facility should be found by name'
      );
      Assert.isTrue(
        tooShort.isEmpty(),
        'A single character must not run a query'
      );
      Assert.isTrue(
        wildcard.isEmpty(),
        'A bare wildcard must be escaped, not match every facility'
      );
    }
  }

  /**
   * The shadow Event must follow the visit however the visit was changed - not only
   * through the component. Before the trigger existed, a visit cancelled from the
   * record page left the Event showing a live appointment on the native calendar.
   */
  @IsTest
  static void directEditKeepsTheShadowEventInStep() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Provider__c p = provider('Eligible');
      Datetime start = Datetime.now().addDays(15);

      Id visitId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        start.addHours(2)
      );

      Test.startTest();
      // Exactly what an inline edit or a data loader would do - no controller involved.
      update new Onboarding_Visit__c(Id = visitId, Status__c = 'Cancelled');
      Test.stopTest();

      Event shadow = [
        SELECT Onboarding_Status__c
        FROM Event
        WHERE Onboarding_Visit__c = :visitId
      ];
      Assert.areEqual(
        'Cancelled',
        shadow.Onboarding_Status__c,
        'A direct edit must still update the shadow Event'
      );
    }
  }

  @IsTest
  static void deletingTheVisitDeletesTheShadowEvent() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Provider__c p = provider('Eligible');
      Datetime start = Datetime.now().addDays(16);

      Id visitId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        start.addHours(2)
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Event WHERE Onboarding_Visit__c = :visitId],
        'The visit should have a shadow Event to begin with'
      );

      Test.startTest();
      delete new Onboarding_Visit__c(Id = visitId);
      Test.stopTest();

      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Event WHERE Onboarding_Visit__c = :visitId],
        'Deleting the visit must remove its shadow Event, not orphan it on the calendar'
      );
    }
  }

  @IsTest
  static void changingProvidersUpdatesTheShadowSubject() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Provider__c a = provider('Eligible');
      Provider__c b = provider('CrossState');
      Datetime start = Datetime.now().addDays(17);

      Id visitId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ a.Id },
        new List<String>{ 'TCM' },
        start,
        start.addHours(2)
      );

      Test.startTest();
      insert new Onboarding_Visit_Provider__c(
        Onboarding_Visit__c = visitId,
        Provider__c = b.Id
      );
      Test.stopTest();

      Event shadow = [
        SELECT Subject
        FROM Event
        WHERE Onboarding_Visit__c = :visitId
      ];
      Assert.isTrue(
        shadow.Subject.contains('CrossState'),
        'Adding a provider must be reflected on the shadow Event subject'
      );
    }
  }

  @IsTest
  static void shadowSyncIsBulkSafe() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Datetime start = Datetime.now().addDays(20);

      List<Onboarding_Visit__c> many = new List<Onboarding_Visit__c>();
      for (Integer i = 0; i < 150; i++) {
        many.add(
          new Onboarding_Visit__c(
            Facility__c = f.Id,
            Facilitator__c = fac.Id,
            Programs__c = 'BHI',
            Start__c = start.addDays(i),
            End__c = start.addDays(i).addHours(2),
            Status__c = 'Scheduled'
          )
        );
      }

      Test.startTest();
      insert many; // one shadow each
      for (Onboarding_Visit__c v : many) {
        v.Status__c = 'Cancelled';
      }
      update many; // all resynced
      Test.stopTest();

      Assert.areEqual(
        150,
        [SELECT COUNT() FROM Event WHERE Onboarding_Visit__c IN :many],
        'Every visit in a bulk insert should get exactly one shadow Event'
      );
      Assert.areEqual(
        150,
        [
          SELECT COUNT()
          FROM Event
          WHERE
            Onboarding_Visit__c IN :many
            AND Onboarding_Status__c = 'Cancelled'
        ],
        'A bulk update must resync every shadow Event'
      );
    }
  }

  /**
   * Swapping the provider on an existing assignment - an update rather than an insert
   * or delete - must also refresh the shadow Event. This is the branch of
   * OnboardingVisitProviderTrigger that resyncs on update, including the old parent
   * so a reparented row cannot leave the previous visit stale.
   */
  @IsTest
  static void updatingAnAssignmentRefreshesTheShadow() {
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Provider__c a = provider('Eligible');
      Provider__c b = provider('CrossState');
      Datetime start = Datetime.now().addDays(25);

      Id visitId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ a.Id },
        new List<String>{ 'TCM' },
        start,
        start.addHours(2)
      );

      Onboarding_Visit_Provider__c row = [
        SELECT Id, Provider__c
        FROM Onboarding_Visit_Provider__c
        WHERE Onboarding_Visit__c = :visitId
        LIMIT 1
      ];

      Test.startTest();
      row.Provider__c = b.Id;
      update row;
      Test.stopTest();

      Event shadow = [
        SELECT Subject, Provider__c
        FROM Event
        WHERE Onboarding_Visit__c = :visitId
      ];
      Assert.areEqual(
        b.Id,
        shadow.Provider__c,
        'Swapping the assigned provider must update the shadow Event lookup'
      );
      Assert.isTrue(
        shadow.Subject.contains('CrossState'),
        'The shadow subject must name the provider now assigned'
      );
    }
  }

  @IsTest
  static void saveRejectsBadTimeWindow() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Boolean rejected = false;

      Test.startTest();
      try {
        FacilitySchedulingController.saveVisit(
          f.Id,
          null,
          null,
          new List<String>{ 'BHI' },
          Datetime.now().addDays(1),
          Datetime.now()
        );
      } catch (Exception e) {
        rejected = true;
      }
      Test.stopTest();

      Assert.isTrue(rejected, 'End before start must be rejected');
    }
  }

  @IsTest
  static void pickersAndCalendarReturnData() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Test.startTest();
      FacilitySchedulingController.FacilitatorChoices facilitators = FacilitySchedulingController.getFacilitators(
        null,
        null,
        null
      );
      FacilitySchedulingController.ProviderChoices providers = FacilitySchedulingController.getProviders(
        new List<String>{ 'BHI' },
        null,
        null,
        null,
        null
      );
      FacilitySchedulingController.ProviderChoices allProviders = FacilitySchedulingController.getProviders(
        null,
        null,
        null,
        null,
        null
      );
      List<FacilitySchedulingController.EventRow> week = FacilitySchedulingController.getWeek(
        Date.today().toStartOfWeek(),
        null
      );
      Test.stopTest();

      Assert.areEqual(
        1,
        facilitators.options.size(),
        'One active facilitator was created'
      );
      Assert.isFalse(
        providers.options.isEmpty(),
        'BHI-tagged providers should be returned'
      );
      Assert.areEqual(
        4,
        allProviders.options.size(),
        'Four providers were created in setup'
      );
      Assert.isNotNull(week, 'The calendar query should return a list');
    }
  }

  @IsTest
  static void eligibilityNeedsAFacility() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();

      Test.startTest();
      // No facility at all -> blocked.
      FacilitySchedulingController.Eligibility noFacility = FacilitySchedulingController.checkEligibility(
        null,
        null,
        null,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );
      // Facility but no provider yet -> incomplete, not a failure.
      FacilitySchedulingController.Eligibility noProvider = FacilitySchedulingController.checkEligibility(
        null,
        null,
        f.Id,
        new List<String>{ 'BHI' },
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.isFalse(noFacility.allowed, 'A missing facility must fail closed');
      Assert.isTrue(
        noProvider.allowed,
        'A not-yet-chosen provider is an incomplete form, not an eligibility failure'
      );
      Assert.areEqual(
        'warning',
        noProvider.checks[0].level,
        'It should read as a warning rather than a block'
      );
    }
  }

  @IsTest
  static void programFilterNarrowsTheCalendar() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Eligible');
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Datetime start = Datetime.now().addDays(1);

      Test.startTest();
      FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        start.addHours(2)
      );
      List<FacilitySchedulingController.EventRow> bhi = FacilitySchedulingController.getWeek(
        Date.today().toStartOfWeek(),
        'BHI'
      );
      List<FacilitySchedulingController.EventRow> tcm = FacilitySchedulingController.getWeek(
        Date.today().toStartOfWeek(),
        'TCM'
      );
      Test.stopTest();

      Assert.isFalse(
        bhi.isEmpty(),
        'Filtering on BHI should return the BHI event'
      );
      // A visit can now carry several programmes, so the filter means "covers TCM"
      // rather than "is only TCM". Every row it returns must include TCM.
      for (FacilitySchedulingController.EventRow r : tcm) {
        Assert.isTrue(
          r.programs != null && r.programs.contains('TCM'),
          'A TCM filter must only return visits that cover TCM'
        );
      }
    }
  }

  @IsTest
  static void editingAnEventDoesNotClashWithItself() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Eligible');
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Datetime start = Datetime.now().addDays(4);

      Test.startTest();
      Id eventId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        start.addHours(2)
      );

      // Same provider, overlapping its own slot - allowed, because it IS that event.
      Id same = FacilitySchedulingController.updateVisit(
        eventId,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start.addMinutes(30),
        start.addHours(3),
        'Confirmed'
      );
      Test.stopTest();

      Assert.areEqual(
        eventId,
        same,
        'Editing an event must not conflict with itself'
      );
      Onboarding_Visit__c updated = [
        SELECT Status__c, Start__c, Shadow_Event_Id__c
        FROM Onboarding_Visit__c
        WHERE Id = :eventId
      ];
      Assert.areEqual(
        'Confirmed',
        updated.Status__c,
        'Status should be updated'
      );

      Event shadow = [
        SELECT Onboarding_Status__c, StartDateTime
        FROM Event
        WHERE Id = :updated.Shadow_Event_Id__c
      ];
      Assert.areEqual(
        'Confirmed',
        shadow.Onboarding_Status__c,
        'The shadow Event must track the visit rather than drift from it'
      );
      Assert.areEqual(
        updated.Start__c,
        shadow.StartDateTime,
        'Shadow Event start must match the visit'
      );
    }
  }

  @IsTest
  static void updateRejectsBadWindowAndUnknownEvent() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Provider__c p = provider('Eligible');
      Datetime start = Datetime.now().addDays(5);
      Boolean badWindow = false;

      Test.startTest();
      Id eventId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        start.addHours(2)
      );
      try {
        FacilitySchedulingController.updateVisit(
          eventId,
          fac.Id,
          new List<Id>{ p.Id },
          new List<String>{ 'BHI' },
          start.addHours(2),
          start,
          'Scheduled'
        );
      } catch (Exception e) {
        badWindow = true;
      }
      Test.stopTest();

      Assert.isTrue(
        badWindow,
        'End before start must be rejected on update too'
      );
    }
  }

  @IsTest
  static void providerPickerExcludesUnlicensedAndConflicted() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Facility__c f = facility();

      Test.startTest();
      FacilitySchedulingController.ProviderChoices bhiHere = FacilitySchedulingController.getProviders(
        new List<String>{ 'BHI' },
        f.Id,
        null,
        null,
        null
      );
      FacilitySchedulingController.ProviderChoices bhiAnywhere = FacilitySchedulingController.getProviders(
        new List<String>{ 'BHI' },
        null,
        null,
        null,
        null
      );
      Test.stopTest();

      Assert.areEqual(
        'Kansas',
        bhiHere.stateName,
        'Facility state should resolve to Kansas'
      );

      // "Eligible" is tagged BHI and licensed in Kansas -> offered.
      // "Unlicensed" is tagged BHI but has no Kansas licence -> hidden.
      // "Conflicted" is BHI+CoCM -> hidden as a program conflict.
      Assert.areEqual(
        1,
        bhiHere.options.size(),
        'Only the licensed, unconflicted BHI provider should be offered'
      );
      Assert.areEqual(
        1,
        bhiHere.hiddenUnlicensed,
        'The unlicensed provider should be hidden'
      );
      Assert.areEqual(
        1,
        bhiHere.hiddenConflicted,
        'The conflicted provider should be hidden'
      );

      // Without a facility there is no state, so licensing cannot be checked.
      Assert.isTrue(
        bhiAnywhere.options.size() >= bhiHere.options.size(),
        'Without a facility the list cannot be narrowed by licence'
      );
    }
  }

  @IsTest
  static void bookedResourcesDropOutOfBothPickers() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Eligible');
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Datetime start = Datetime.now().addDays(8);
      Datetime finish = start.addHours(2);

      Test.startTest();
      // Before booking, both are offered for that window.
      FacilitySchedulingController.FacilitatorChoices freeBefore = FacilitySchedulingController.getFacilitators(
        start,
        finish,
        null
      );
      FacilitySchedulingController.ProviderChoices provBefore = FacilitySchedulingController.getProviders(
        new List<String>{ 'BHI' },
        f.Id,
        start,
        finish,
        null
      );
      Assert.areEqual(
        1,
        freeBefore.options.size(),
        'Facilitator should be free before booking'
      );
      Assert.areEqual(
        1,
        provBefore.options.size(),
        'Provider should be free before booking'
      );

      Id eventId = FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        finish
      );

      // Overlapping window: both are now committed, so neither is offered.
      FacilitySchedulingController.FacilitatorChoices freeAfter = FacilitySchedulingController.getFacilitators(
        start.addMinutes(30),
        finish,
        null
      );
      FacilitySchedulingController.ProviderChoices provAfter = FacilitySchedulingController.getProviders(
        new List<String>{ 'BHI' },
        f.Id,
        start.addMinutes(30),
        finish,
        null
      );

      // Editing that same event must still offer its own resources back.
      FacilitySchedulingController.FacilitatorChoices freeEditing = FacilitySchedulingController.getFacilitators(
        start,
        finish,
        eventId
      );
      Test.stopTest();

      Assert.areEqual(
        0,
        freeAfter.options.size(),
        'A booked facilitator must not be offered'
      );
      Assert.areEqual(
        1,
        freeAfter.hiddenBooked,
        'And should be reported as hidden'
      );
      Assert.areEqual(
        0,
        provAfter.options.size(),
        'A booked provider must not be offered'
      );
      Assert.areEqual(
        1,
        provAfter.hiddenBooked,
        'And should be reported as hidden'
      );
      Assert.areEqual(
        1,
        freeEditing.options.size(),
        'Editing an event must still offer the resources it already holds'
      );
    }
  }

  @IsTest
  static void doubleBookedFacilitatorBlocksTheSave() {
    // Runs as a user holding the permission set, because the controller
    // enforces FLS with USER_MODE.
    System.runAs(scheduler()) {
      Provider__c p = provider('Eligible');
      Facility__c f = facility();
      Facilitator__c fac = [
        SELECT Id
        FROM Facilitator__c
        WHERE Active__c = TRUE
        LIMIT 1
      ];
      Datetime start = Datetime.now().addDays(9);
      Boolean blocked = false;

      Test.startTest();
      FacilitySchedulingController.saveVisit(
        f.Id,
        fac.Id,
        new List<Id>{ p.Id },
        new List<String>{ 'BHI' },
        start,
        start.addHours(2)
      );
      // Same facilitator, overlapping window, no provider at all -> the facilitator
      // clash alone must be enough to stop it.
      try {
        FacilitySchedulingController.saveVisit(
          f.Id,
          fac.Id,
          null,
          new List<String>{ 'BHI' },
          start.addMinutes(30),
          start.addHours(3)
        );
      } catch (Exception e) {
        blocked = true;
      }
      Test.stopTest();

      Assert.isTrue(
        blocked,
        'An overlapping facilitator booking must be refused'
      );
    }
  }
}
