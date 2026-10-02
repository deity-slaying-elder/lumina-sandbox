// Seeds a realistic scheduling dataset in lumDev.
//
// Everything carries the TST prefix so it is obviously test data and can be removed
// with one filter. Shapes follow production: facility names like "<Place> Health Care
// Center" under a parent company, states across IL, KS, MO and OH, census in the low
// hundreds. No patient record is copied from production; every patient below is
// invented, and none of these names belong to a real person.

final String P = 'TST ';

// ---------------------------------------------------------------- parent companies
List<Account> parents = new List<Account>{
  new Account(Name = P + 'Accolade Healthcare'),
  new Account(Name = P + 'Reliant Care Management'),
  new Account(Name = P + 'AOM Healthcare')
};
insert parents;

// ---------------------------------------------------------------- facilities
List<String> placeNames = new List<String>{
  'Brightwater Health Care Center',
  'Danville Nursing & Rehabilitation',
  'Paxton Senior Living',
  'Easton Health Care Center',
  'Nortonville Care Center',
  'Grand Manor Nursing & Rehabilitation',
  'Piketon Nursing Care Center',
  'Cedar Hollow Skilled Nursing',
  'Willow Creek Health Center',
  'Marbury Rehabilitation Center',
  'Ridgeline Care Center',
  'Stonebridge Nursing Home'
};
List<String> states = new List<String>{ 'IL', 'KS', 'MO', 'OH' };

List<Facility__c> facilities = new List<Facility__c>();
for (Integer i = 0; i < placeNames.size(); i++) {
  Facility__c f = new Facility__c(
    Name = P + placeNames[i],
    Status__c = 'Onboarding',
    Parent_Company__c = parents[Math.mod(i, parents.size())].Id,
    // Two deliberately have no rollout date, because production is full of those and
    // the list must still show them.
    Scheduled_Rollout_Date__c = (i == 4 || i == 9)
      ? null
      : Date.today().addDays(3 + (i * 4))
  );
  f.put('Address__StateCode__s', states[Math.mod(i, states.size())]);
  f.put('Address__CountryCode__s', 'US');
  facilities.add(f);
}
insert facilities;

// Programme statuses are FORMULAS. TCM_Status__c reads IF(TCM__c, "Active", ...),
// so the checkbox underneath is what has to be set. Spread rather than uniform, so
// the "not active at this facility" path is still visible in the dialog.
//
// Worth noting for the team: in production these checkboxes are false on every
// onboarding facility, which is why every programme status there is blank.
List<Facility__c> toFlag = new List<Facility__c>();
for (Integer i = 0; i < facilities.size(); i++) {
  toFlag.add(
    new Facility__c(
      Id = facilities[i].Id,
      TCM__c = true,
      CCM__c = Math.mod(i, 2) == 0,
      BHI__c = Math.mod(i, 3) == 0,
      COCM__c = Math.mod(i, 4) == 0
    )
  );
}
update toFlag;

// ---------------------------------------------------------------- providers
List<String> firsts = new List<String>{
  'Ada', 'Ben', 'Cara', 'Devon', 'Elena', 'Femi', 'Grace', 'Hugo'
};
List<String> lasts = new List<String>{
  'Rowe', 'Ilo', 'Nkemdi', 'Farr', 'Castile', 'Okafor', 'Wren', 'Mbeki'
};
List<Provider__c> providers = new List<Provider__c>();
for (Integer i = 0; i < firsts.size(); i++) {
  providers.add(
    new Provider__c(
      First_Name__c = P + firsts[i],
      Last_Name__c = lasts[i],
      License_Title__c = Math.mod(i, 3) == 0 ? 'NP' : 'MD'
    )
  );
}
insert providers;

// State licences, so provider eligibility has something to check. Production has
// none of these at all, which is worth raising separately.
Map<String, String> stateName = new Map<String, String>{
  'IL' => 'Illinois',
  'KS' => 'Kansas',
  'MO' => 'Missouri',
  'OH' => 'Ohio'
};
List<License__c> licences = new List<License__c>();
for (Integer i = 0; i < providers.size(); i++) {
  for (String st : states) {
    // Not everyone is licensed everywhere, so the hidden counts stay meaningful.
    if (Math.mod(i + st.length(), 3) == 0) {
      continue;
    }
    licences.add(
      new License__c(
        Provider__c = providers[i].Id,
        Type__c = 'State License',
        State__c = stateName.get(st),
        Number__c = 'TST-' + st + '-' + i,
        Issue_Date__c = Date.today().addYears(-2),
        Expiration_Date__c = Date.today().addYears(1),
        Programs__c = Math.mod(i, 2) == 0 ? 'TCM;CCM' : 'TCM;BHI'
      )
    );
  }
}
insert licences;

// ---------------------------------------------------------------- facilitators
List<Facilitator__c> facilitators = new List<Facilitator__c>{
  new Facilitator__c(
    Name = P + 'Okafor, T.',
    First_Name__c = P + 'Tope',
    Last_Name__c = 'Okafor',
    Active__c = true
  ),
  new Facilitator__c(
    Name = P + 'Lindqvist, M.',
    First_Name__c = P + 'Maja',
    Last_Name__c = 'Lindqvist',
    Active__c = true
  )
};
insert facilitators;

// ---------------------------------------------------------------- patients
// Invented people, so census, seen and consented have something to draw. Counts are
// in the low hundreds to match the production spread.
List<String> pFirst = new List<String>{
  'Alma', 'Boris', 'Clara', 'Dmitri', 'Esme', 'Frank', 'Gita', 'Hal',
  'Ines', 'Jonas', 'Kira', 'Lev'
};
List<String> pLast = new List<String>{
  'Hartley', 'Okonkwo', 'Varga', 'Sandoval', 'Reyes', 'Nilsen'
};
List<Patient__c> patients = new List<Patient__c>();
for (Integer i = 0; i < facilities.size(); i++) {
  Integer census = 40 + (i * 17);
  Integer seen = (census * (30 + Math.mod(i * 13, 55))) / 100;
  Integer consented = (seen * (45 + Math.mod(i * 7, 40))) / 100;
  for (Integer n = 0; n < census; n++) {
    Boolean wasSeen = n < seen;
    Boolean didConsent = n < consented;
    patients.add(
      new Patient__c(
        First_Name__c = P + pFirst[Math.mod(n, pFirst.size())],
        Last_Name__c = pLast[Math.mod(n + i, pLast.size())] + ' ' + n,
        Status__c = 'Active',
        Facility__c = facilities[i].Id,
        Count_of_Initial_VIsits__c = wasSeen ? 1 : 0,
        Consent_Status__c = didConsent ? 'Approved' : 'Pending'
      )
    );
  }
}
insert patients;

System.debug(
  LoggingLevel.ERROR,
  'SEEDED parents=' + parents.size() +
  ' facilities=' + facilities.size() +
  ' providers=' + providers.size() +
  ' licences=' + licences.size() +
  ' facilitators=' + facilitators.size() +
  ' patients=' + patients.size()
);
