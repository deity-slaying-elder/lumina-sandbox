// Books visits across the current month so the calendar has a realistic spread:
// some days empty, some with one, a couple with more than three so the "+n more"
// path is visible.
//
// The notifier will fire on insert, but the seeded facilitators and providers carry
// no email address, so nothing is actually sent.

List<Facility__c> fs = [
  SELECT Id, Name FROM Facility__c WHERE Name LIKE 'TST %' ORDER BY Name
];
List<Provider__c> ps = [
  SELECT Id FROM Provider__c WHERE First_Name__c LIKE 'TST %' ORDER BY Last_Name__c
];
List<Facilitator__c> facs = [SELECT Id FROM Facilitator__c WHERE Name LIKE 'TST %'];

Date monthStart = Date.today().toStartOfMonth();
List<String> programs = new List<String>{ 'TCM', 'TCM;CCM', 'BHI', 'TCM;BHI', 'CCM' };

List<Onboarding_Visit__c> visits = new List<Onboarding_Visit__c>();
Integer n = 0;
for (Integer day = 0; day < 28; day++) {
  // Roughly every third day gets something, with two busy days.
  Integer onThisDay = 0;
  if (Math.mod(day, 3) == 0) {
    onThisDay = 1;
  }
  if (day == 9 || day == 17) {
    onThisDay = 5;
  }
  for (Integer k = 0; k < onThisDay; k++) {
    Datetime start = Datetime.newInstance(
      monthStart.addDays(day),
      Time.newInstance(9 + Math.mod(k * 2, 8), 0, 0, 0)
    );
    visits.add(
      new Onboarding_Visit__c(
        Facility__c = fs[Math.mod(n, fs.size())].Id,
        Facilitator__c = facs.isEmpty()
          ? null
          : facs[Math.mod(n, facs.size())].Id,
        Programs__c = programs[Math.mod(n, programs.size())],
        Start__c = start,
        End__c = start.addHours(2),
        Status__c = Math.mod(n, 11) == 0 ? 'Cancelled' : 'Scheduled'
      )
    );
    n++;
  }
}
insert visits;

// One or two providers on each, so the chips and the tooltip have content.
List<Onboarding_Visit_Provider__c> links = new List<Onboarding_Visit_Provider__c>();
for (Integer i = 0; i < visits.size(); i++) {
  links.add(
    new Onboarding_Visit_Provider__c(
      Onboarding_Visit__c = visits[i].Id,
      Provider__c = ps[Math.mod(i, ps.size())].Id
    )
  );
  if (Math.mod(i, 4) == 0) {
    links.add(
      new Onboarding_Visit_Provider__c(
        Onboarding_Visit__c = visits[i].Id,
        Provider__c = ps[Math.mod(i + 3, ps.size())].Id
      )
    );
  }
}
insert links;

System.debug(
  LoggingLevel.ERROR,
  'VISITS created=' + visits.size() + ' assignments=' + links.size()
);
