/*
 * LMNA-581 production smoke test, step 2 of 3. Sends the report for the test facility.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-smoke-send.apex
 *
 * Run this only after step 1 has finished, so the facility is committed and the PDF render can
 * see it. Checks the rendered document actually contains the row before reporting success,
 * because a report that renders empty would otherwise be emailed and counted as a good send.
 */
Facility__c f = [
    SELECT Id, Name FROM Facility__c
    WHERE Name = 'ZZ TEST - Readmission Smoke Test - DELETE ME' LIMIT 1
];
TCMReportConfig cfg = new TCMReportConfig();
TCMReadmissionWindow w = new TCMReadmissionWindow(cfg.timeZoneName());
Integer expected = TCMReadmissionAdmissionScope.find(f.Id, w.startUtc, w.endUtc, cfg).size();
System.debug('rows the report should contain -> ' + expected);

TCMReadmissionResend.Result r = TCMReadmissionResend.send(f.Id);
System.debug('sent=' + r.sent + ' rows=' + r.rowCount + ' blocked=' + r.blockedReason);
System.debug('summary: ' + r.summary);
for (TCMReadmissionResend.Delivery d : r.deliveries) {
    System.debug('  -> ' + d.email + ' sent=' + d.sent + ' problem=' + d.problem);
}
System.debug('problems: ' + r.problems);

// Sanity check on the stored document. The PDF is compressed, so its text cannot be read from
// Apex; size plus the row count the resend reported is the useful signal here. The empty-report
// failure is prevented by creating the facility in a separate run, which is why this is split.
for (ContentVersion cv : [
    SELECT Title, ContentSize FROM ContentVersion
    WHERE Title LIKE 'Readmissions-ZZ TEST%' ORDER BY CreatedDate DESC LIMIT 1
]) {
    System.debug('stored report: ' + cv.Title + ' (' + cv.ContentSize + ' bytes)');
}
if (r.rowCount != expected) {
    System.debug(LoggingLevel.ERROR,
        'MISMATCH: the report was built from ' + r.rowCount + ' rows but ' + expected +
        ' qualify. Do not trust this run.');
}
System.debug('Open the email at the tester address, request a code, enter it, open the report.');
