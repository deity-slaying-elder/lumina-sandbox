/**
 * Scheduled entry point for the daily readmission email.
 *
 * Follows the RemindSalesrepScheduler convention: the scheduler decides nothing except
 * whether to run, and hands everything else to the batch.
 */
public with sharing class TCMDailyReadmissionScheduler implements Schedulable {

    @TestVisible
    private static final Integer SCOPE = 25;

    public void execute(SchedulableContext context) {
        if (!new TCMReportConfig().isActive()) {
            // Kill switch. Flip Is_Active__c on TCM_Report_Config__mdt.Default to resume.
            // This guards the scheduled path only -- running the batch by hand bypasses it.
            System.debug(LoggingLevel.WARN, 'TCM readmission email skipped: Is_Active__c is false.');
            return;
        }
        Database.executeBatch(new TCMDailyReadmissionBatch(), SCOPE);
    }
}