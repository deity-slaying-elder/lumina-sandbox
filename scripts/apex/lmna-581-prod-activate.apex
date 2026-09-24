/*
 * LMNA-581 GO LIVE. This is the step that starts real mail to real facilities.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-activate.apex
 *
 * Run it only after the daily job is scheduled. Is_Active__c is read by the scheduler and by
 * nothing else, so ticking it without a scheduled job changes nothing, and a scheduled job
 * without it fires and sends nothing.
 *
 * Everything below the checks is one field. The checks are here because the alternative is
 * ticking a box in Setup with no idea whether the pieces behind it are in place, and on
 * 2026-09-22 that assumption cost three real facilities an email they should not have had.
 */
List<String> problems = new List<String>();

TCMReportConfig cfg = new TCMReportConfig();
if (cfg.isActive()) {
    System.debug(LoggingLevel.ERROR, 'Already active. Nothing to do.');
    return;
}

// 1. The daily job has to exist, or this flag has nothing to switch on.
List<CronTrigger> daily = [
    SELECT Id, CronExpression, State, NextFireTime
    FROM CronTrigger
    WHERE CronJobDetail.Name = 'TCM Email Readmission'
];
if (daily.isEmpty()) {
    problems.add('The daily job is not scheduled. Run lmna-581-schedule-prod-jobs.apex first.');
} else {
    System.debug(LoggingLevel.ERROR, 'daily job: ' + daily[0].CronExpression
        + ' | ' + daily[0].State + ' | next fire ' + daily[0].NextFireTime);
}

// 2. Without a verified sending address the report still goes, as the running user, which is
//    not who Lumina's facilities expect to hear from.
String fromAddress = cfg.orgWideAddress();
if (String.isBlank(fromAddress)) {
    problems.add('No From_Org_Wide_Address__c configured.');
} else {
    List<OrgWideEmailAddress> owa = [
        SELECT Address, IsAllowAllProfiles FROM OrgWideEmailAddress WHERE Address = :fromAddress
    ];
    if (owa.isEmpty()) {
        problems.add('From_Org_Wide_Address__c is ' + fromAddress
            + ' but no verified org-wide address matches it.');
    } else if (owa[0].IsAllowAllProfiles != true) {
        problems.add(fromAddress + ' is not open to all profiles, so the site guest user cannot send '
            + 'the one-time code from it.');
    }
}

// 3. No site, no link, and the publisher refuses rather than emailing a dead URL.
List<Site> sites = [
    SELECT Id, Status, GuestUserId FROM Site WHERE Name = :TCMReadmissionPortal.SITE_NAME
];
if (sites.isEmpty() || sites[0].Status != 'Active' || sites[0].GuestUserId == null) {
    problems.add('The report site is missing, inactive, or has no guest user.');
}

// 4. Say out loud who is about to start receiving mail. Nobody should tick this without
//    seeing these three lines.
System.debug(LoggingLevel.ERROR, 'facility report goes to: the facility admin or DON');
System.debug(LoggingLevel.ERROR, 'own link and code also to: ' + cfg.internalCc());
System.debug(LoggingLevel.ERROR, 'copied without a link to: ' + cfg.globalCc());
System.debug(LoggingLevel.ERROR, 'daily digest to: ' + cfg.digestRecipients());
System.debug(LoggingLevel.ERROR, 'scope: patient class contains '
    + cfg.requiredPatientClass() + ', facility TCM required: ' + cfg.requireFacilityTcm());

if (!problems.isEmpty()) {
    throw new CalloutException('NOT ACTIVATING. ' + String.join(problems, ' '));
}

TCM_Report_Config__mdt current = TCM_Report_Config__mdt.getInstance('Default');
Map<String, Object> values = current.getPopulatedFieldsAsMap().clone();
values.put('Is_Active__c', true);

Metadata.CustomMetadata record = new Metadata.CustomMetadata();
record.fullName = 'TCM_Report_Config.Default';
record.label = current.Label;
Set<String> skip = new Set<String>{'Id','DeveloperName','MasterLabel','Label','QualifiedApiName',
    'NamespacePrefix','SystemModstamp','Language','attributes'};
for (String field : values.keySet()) {
    if (skip.contains(field)) { continue; }
    Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
    v.field = field; v.value = values.get(field);
    record.values.add(v);
}
Metadata.DeployContainer c = new Metadata.DeployContainer();
c.addMetadata(record);
Metadata.Operations.enqueueDeployment(c, null);

System.debug(LoggingLevel.ERROR, 'ACTIVATION QUEUED. The write is asynchronous. '
    + 'Re-read Is_Active__c and confirm it reads true before 7am.');
