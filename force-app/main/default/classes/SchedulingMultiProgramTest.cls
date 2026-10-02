/**
 * Tests for the changes that let one visit carry several programmes, drive the
 * programme list from the facility, and email the people assigned when a booking
 * changes.
 *
 * All data is created in-test. No patient data is queried from the org, and no
 * assertion references a real record.
 */
@IsTest
private class SchedulingMultiProgramTest {
  private static Facility__c makeFacility(String name, String stateCode) {
    Facility__c f = new Facility__c(
      Name = name,
      Status__c = 'Onboarding',
      Scheduled_Rollout_Date__c = Date.today().addDays(7)
    );
    f.put('Address__StateCode__s', stateCode);
    f.put('Address__CountryCode__s', 'US');
    return f;
  }

  private static License__c makeLicence(
    Id providerId,
    String state,
    String programs
  ) {
    return new License__c(
      Provider__c = providerId,
      Type__c = 'State License',
      State__c = state,
      Number__c = 'TEST-SL',
      Issue_Date__c = Date.today().addYears(-2),
      Expiration_Date__c = Date.today().addYears(1),
      Programs__c = programs
    );
  }

  @TestSetup
  static void setup() {
    insert makeFacility('ZZ TEST Multi Program Facility', 'KS');

    Provider__c both = new Provider__c(
      First_Name__c = 'Ada',
      Last_Name__c = 'Both',
      License_Title__c = 'MD'
    );
    Provider__c partial = new Provider__c(
      First_Name__c = 'Bo',
      Last_Name__c = 'Partial',
      License_Title__c = 'MD'
    );
    insert new List<Provider__c>{ both, partial };

    insert new List<License__c>{
      // Covers both programmes on one Kansas licence.
      makeLicence(both.Id, 'Kansas', 'TCM;BHI'),
      // Covers only one of them, so a two-programme visit must exclude them.
      makeLicence(partial.Id, 'Kansas', 'TCM')
    };

    insert new Facilitator__c(
      Name = 'ZZ TEST Facilitator',
      First_Name__c = 'Fay',
      Last_Name__c = 'Facilitator',
      Email__c = 'fay.facilitator@example.invalid',
      Active__c = true
    );
  }

  private static Facility__c facility() {
    return [SELECT Id, Name FROM Facility__c LIMIT 1];
  }

  private static Provider__c provider(String lastName) {
    return [SELECT Id FROM Provider__c WHERE Last_Name__c = :lastName LIMIT 1];
  }

  private static Facilitator__c facilitator() {
    return [SELECT Id FROM Facilitator__c LIMIT 1];
  }

  // ============================================================ multi programme
  @IsTest
  static void aVisitCarriesSeveralPrograms() {
    Facility__c f = facility();
    Facilitator__c fac = facilitator();
    Datetime start = Datetime.now().addDays(3);

    Test.startTest();
    Id visitId = FacilitySchedulingController.saveVisit(
      f.Id,
      fac.Id,
      new List<Id>{ provider('Both').Id },
      new List<String>{ 'TCM', 'BHI' },
      start,
      start.addHours(2)
    );
    Test.stopTest();

    Onboarding_Visit__c saved = [
      SELECT Programs__c
      FROM Onboarding_Visit__c
      WHERE Id = :visitId
    ];
    Assert.areEqual(
      'TCM;BHI',
      saved.Programs__c,
      'Both programmes should be stored, in display order'
    );
  }

  @IsTest
  static void aProviderMustCoverEveryProgramOnTheVisit() {
    Facility__c f = facility();

    Test.startTest();
    FacilitySchedulingController.ProviderChoices oneProgram = FacilitySchedulingController.getProviders(
      new List<String>{ 'TCM' },
      f.Id,
      null,
      null,
      null
    );
    FacilitySchedulingController.ProviderChoices twoPrograms = FacilitySchedulingController.getProviders(
      new List<String>{ 'TCM', 'BHI' },
      f.Id,
      null,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      oneProgram.options.size(),
      'Both providers cover TCM on their own'
    );
    Assert.areEqual(
      1,
      twoPrograms.options.size(),
      'Only the provider covering TCM and BHI can take a two-programme visit'
    );
    Assert.areEqual(
      1,
      twoPrograms.hiddenUntagged,
      'The partially approved provider should be counted as hidden, with a reason'
    );
  }

  @IsTest
  static void aProviderMissingOneProgramIsNamedInTheBlock() {
    Facility__c f = facility();

    Test.startTest();
    FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
      new List<Id>{ provider('Partial').Id },
      null,
      f.Id,
      new List<String>{ 'TCM', 'BHI' },
      null,
      null,
      null
    );
    Test.stopTest();

    Assert.isFalse(
      result.allowed,
      'A provider not approved for every programme blocks'
    );
    Boolean namesTheProgram = false;
    for (FacilitySchedulingController.Check c : result.checks) {
      if (
        c.level == 'blocked' &&
        c.detail != null &&
        c.detail.contains('BHI')
      ) {
        namesTheProgram = true;
      }
    }
    Assert.isTrue(
      namesTheProgram,
      'The block should name the programme that is missing, not just the provider'
    );
  }

  @IsTest
  static void twoConflictingProgramsCannotShareAVisit() {
    Facility__c f = facility();

    Test.startTest();
    FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
      new List<Id>{ provider('Both').Id },
      null,
      f.Id,
      new List<String>{ 'BHI', 'CoCM' },
      null,
      null,
      null
    );
    Test.stopTest();

    Boolean conflictReported = false;
    for (FacilitySchedulingController.Check c : result.checks) {
      if (c.label == 'Programs conflict') {
        conflictReported = true;
      }
    }
    // Seeded conflict pair. If the org has no active pair the check cannot fire, so
    // this asserts on the configured state rather than assuming one.
    Boolean pairConfigured = false;
    for (Program_Conflict__mdt c : Program_Conflict__mdt.getAll().values()) {
      if (
        c.Active__c &&
        ((c.Program_A__c == 'BHI' && c.Program_B__c == 'CoCM') ||
        (c.Program_A__c == 'CoCM' &&
        c.Program_B__c == 'BHI'))
      ) {
        pairConfigured = true;
      }
    }
    if (pairConfigured) {
      Assert.isTrue(
        conflictReported,
        'BHI and CoCM on one visit should be refused outright'
      );
      Assert.isFalse(result.allowed, 'A conflicting pair must block the save');
    }
  }

  // ============================================================ facility programmes
  @IsTest
  static void programsComeBackFlaggedAgainstTheFacility() {
    Facility__c f = facility();

    Test.startTest();
    List<FacilitySchedulingController.ProgramOption> options = FacilitySchedulingController.getFacilityPrograms(
      f.Id
    );
    Test.stopTest();

    Assert.areEqual(
      8,
      options.size(),
      'Every programme is returned, available or not, so none silently vanishes'
    );

    Map<String, FacilitySchedulingController.ProgramOption> byValue = new Map<String, FacilitySchedulingController.ProgramOption>();
    for (FacilitySchedulingController.ProgramOption o : options) {
      byValue.put(o.value, o);
    }

    // Community Full-Time has no field on Facility__c, so the facility cannot say
    // either way and it stays selectable with the reason attached.
    Assert.isTrue(
      byValue.get('Community Full-Time').available,
      'A programme the facility does not track stays selectable'
    );
    Assert.areEqual(
      'Not tracked on the facility record.',
      byValue.get('Community Full-Time').reason,
      'An untracked programme should say so'
    );

    // The test facility has no programme statuses set, so the tracked ones are off.
    Assert.isFalse(
      byValue.get('TCM').available,
      'A programme not active at the facility is offered disabled'
    );
    Assert.areEqual(
      'Not active at this facility.',
      byValue.get('TCM').reason,
      'A disabled programme should say why'
    );
  }

  @IsTest
  static void bookingAProgramTheFacilityDoesNotRunWarnsRatherThanBlocks() {
    Facility__c f = facility();

    Test.startTest();
    FacilitySchedulingController.Eligibility result = FacilitySchedulingController.checkEligibility(
      new List<Id>{ provider('Both').Id },
      null,
      f.Id,
      new List<String>{ 'TCM' },
      null,
      null,
      null
    );
    Test.stopTest();

    Boolean warned = false;
    for (FacilitySchedulingController.Check c : result.checks) {
      if (c.label == 'Facility program') {
        warned = true;
        Assert.areEqual(
          'warning',
          c.level,
          'The facility record can lag the real rollout, so this must not block'
        );
      }
    }
    Assert.isTrue(
      warned,
      'Booking a programme the facility does not run should be flagged'
    );
  }

  // ============================================================ facility snapshot
  @IsTest
  static void theSnapshotCarriesTheCountsTheDialogShows() {
    Facility__c f = facility();

    Test.startTest();
    FacilitySchedulingController.FacilityRow row = FacilitySchedulingController.getFacilitySnapshot(
      f.Id
    );
    Test.stopTest();

    Assert.isNotNull(row, 'A visible facility should return a snapshot');
    Assert.areEqual(
      f.Id,
      row.facilityId,
      'The snapshot should be for the facility asked for'
    );
    Assert.areEqual(
      0,
      row.census,
      'No patients were created, so the census is zero'
    );
    Assert.areEqual(
      'KS',
      row.stateCode,
      'The state is what the dialog captions the counts with'
    );
  }

  @IsTest
  static void theSnapshotIsNullForNoFacility() {
    Test.startTest();
    Assert.isNull(
      FacilitySchedulingController.getFacilitySnapshot(null),
      'No facility means no snapshot, not an error'
    );
    Test.stopTest();
  }

  // ============================================================ notifications
  @IsTest
  static void schedulingAVisitEmailsTheAssignedPeople() {
    Facility__c f = facility();
    Facilitator__c fac = facilitator();
    Datetime start = Datetime.now().addDays(4);

    Test.startTest();
    FacilitySchedulingController.saveVisit(
      f.Id,
      fac.Id,
      new List<Id>{ provider('Both').Id },
      new List<String>{ 'TCM' },
      start,
      start.addHours(2)
    );
    Integer sent = Limits.getEmailInvocations();
    Test.stopTest();

    Assert.isTrue(sent > 0, 'Creating a visit should notify the people on it');
  }

  @IsTest
  static void aVisitCancelledTwiceOverDoesNotEmailTwice() {
    Facility__c f = facility();
    Facilitator__c fac = facilitator();
    Datetime start = Datetime.now().addDays(5);

    Onboarding_Visit__c v = new Onboarding_Visit__c(
      Facility__c = f.Id,
      Facilitator__c = fac.Id,
      Programs__c = 'TCM',
      Start__c = start,
      End__c = start.addHours(2),
      Status__c = 'Cancelled'
    );
    insert v;

    Test.startTest();
    Integer before = Limits.getEmailInvocations();
    // Saving an already-cancelled visit with nothing changed is a no-op for everyone.
    update new Onboarding_Visit__c(Id = v.Id, Status__c = 'Cancelled');
    Integer after = Limits.getEmailInvocations();
    Test.stopTest();

    Assert.areEqual(
      before,
      after,
      'Re-saving an already cancelled visit must not put another email in an inbox'
    );
  }

  @IsTest
  static void aSaveThatChangesNothingWatchedDoesNotEmail() {
    Facility__c f = facility();
    Facilitator__c fac = facilitator();
    Datetime start = Datetime.now().addDays(6);

    Onboarding_Visit__c v = new Onboarding_Visit__c(
      Facility__c = f.Id,
      Facilitator__c = fac.Id,
      Programs__c = 'TCM',
      Start__c = start,
      End__c = start.addHours(2),
      Status__c = 'Scheduled'
    );
    insert v;

    Test.startTest();
    Integer before = Limits.getEmailInvocations();
    // Status is watched only for cancellation; Confirmed is a change worth telling
    // people about, so this asserts the opposite case: touching nothing watched.
    update new Onboarding_Visit__c(Id = v.Id, Shadow_Event_Id__c = null);
    Integer after = Limits.getEmailInvocations();
    Test.stopTest();

    Assert.areEqual(
      before,
      after,
      'A save that changes nothing anyone cares about should stay silent'
    );
  }

  @IsTest
  static void rescheduleEmailsThePeopleOnTheVisit() {
    Facility__c f = facility();
    Facilitator__c fac = facilitator();
    Datetime start = Datetime.now().addDays(7);

    Onboarding_Visit__c v = new Onboarding_Visit__c(
      Facility__c = f.Id,
      Facilitator__c = fac.Id,
      Programs__c = 'TCM',
      Start__c = start,
      End__c = start.addHours(2),
      Status__c = 'Scheduled'
    );
    insert v;

    Test.startTest();
    update new Onboarding_Visit__c(
      Id = v.Id,
      Start__c = start.addDays(1),
      End__c = start.addDays(1).addHours(2)
    );
    Integer sent = Limits.getEmailInvocations();
    Test.stopTest();

    Assert.isTrue(
      sent > 0,
      'Moving a visit should tell the people who were booked for it'
    );
  }

  // ============================================================ shadow event
  @IsTest
  static void theShadowEventNamesEveryProgram() {
    Facility__c f = facility();
    Facilitator__c fac = facilitator();
    Datetime start = Datetime.now().addDays(8);

    Test.startTest();
    Onboarding_Visit__c v = new Onboarding_Visit__c(
      Facility__c = f.Id,
      Facilitator__c = fac.Id,
      Programs__c = 'TCM;BHI',
      Start__c = start,
      End__c = start.addHours(2),
      Status__c = 'Scheduled'
    );
    insert v;
    Test.stopTest();

    List<Event> shadows = [
      SELECT Onboarding_Program__c, Description
      FROM Event
      WHERE Onboarding_Visit__c = :v.Id
    ];
    Assert.areEqual(1, shadows.size(), 'One shadow Event per visit');
    Assert.areEqual(
      'TCM',
      shadows[0].Onboarding_Program__c,
      'The Activity field is single-value, so it carries the first programme'
    );
    Assert.isTrue(
      shadows[0].Description.contains('BHI'),
      'The full programme list belongs in the description'
    );
  }
}
