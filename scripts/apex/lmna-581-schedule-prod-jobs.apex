/*
 * LMNA-581, production step 9: schedule the two jobs.
 *
 * The daily job fires at 07:00 in the timezone of whoever runs this, so run it as a user whose
 * personal timezone is America/New_York. Chayim asked for 7am on 2026-09-23.
 *
 * Run this only after the config record exists, the org-wide address is verified, the site is
 * live and one link has been opened end to end by hand. The daily job still does nothing until
 * Is_Active__c is ticked on the config record.
 */
System.debug('Daily report: ' + System.schedule(
    'TCM Email Readmission', '0 0 7 ? * 2,3,4,5,6', new TCMDailyReadmissionScheduler()
));
System.debug('Nightly purge: ' + System.schedule(
    'TCM Readmission Report Purge', '0 0 3 ? * *', new TCMReadmissionReportPurge()
));
