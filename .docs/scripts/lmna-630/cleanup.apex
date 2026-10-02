// Removes anything the seed created, so it can be run again from clean.
// Scoped to the TST prefix, so nothing else is touched.
List<Onboarding_Visit__c> visits = [
  SELECT Id FROM Onboarding_Visit__c WHERE Facility__r.Name LIKE 'TST %'
];
if (!visits.isEmpty()) {
  delete visits;
}
List<Patient__c> pats = [SELECT Id FROM Patient__c WHERE Facility__r.Name LIKE 'TST %'];
if (!pats.isEmpty()) {
  delete pats;
}
List<License__c> lics = [SELECT Id FROM License__c WHERE Number__c LIKE 'TST-%'];
if (!lics.isEmpty()) {
  delete lics;
}
List<Provider__c> provs = [SELECT Id FROM Provider__c WHERE First_Name__c LIKE 'TST %'];
if (!provs.isEmpty()) {
  delete provs;
}
List<Facilitator__c> facs = [SELECT Id FROM Facilitator__c WHERE Name LIKE 'TST %'];
if (!facs.isEmpty()) {
  delete facs;
}
List<Facility__c> fs = [SELECT Id FROM Facility__c WHERE Name LIKE 'TST %'];
if (!fs.isEmpty()) {
  delete fs;
}
List<Account> accs = [SELECT Id FROM Account WHERE Name LIKE 'TST %'];
if (!accs.isEmpty()) {
  delete accs;
}
System.debug(
  LoggingLevel.ERROR,
  'CLEANED visits=' + visits.size() + ' patients=' + pats.size() +
  ' licences=' + lics.size() + ' providers=' + provs.size() +
  ' facilitators=' + facs.size() + ' facilities=' + fs.size() +
  ' accounts=' + accs.size()
);
