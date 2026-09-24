/*
 * LMNA-581 containment. Closes the three report links that reached real facility contacts on
 * 2026-09-22 at 23:14 UTC, before Lumina had signed off on sending.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-close-premature-links.apex
 *
 * Those emails went out because the batch was run while the arm step had failed, so the real
 * reporting scope was still in force. Is_Active__c does not prevent this: only the scheduler
 * reads that flag, a manual Database.executeBatch does not.
 *
 * Named one by one rather than selected by a filter, so this cannot reach a row nobody looked
 * at. Closing a link makes it fail closed: isLive() checks Closed_Reason__c, so a closed link
 * can no longer issue a one-time code and its PDF endpoint refuses with the same 404 it gives
 * a stranger. Nothing is deleted, so the record of what was issued to whom survives.
 *
 * The internal links (james@, chayim@) are deliberately left open. They are ours.
 */
Set<String> names = new Set<String>{
    'RRL-00000016',  // The Waters of Indianapolis -> administrator@watersofindianapolis.com
    'RRL-00000013',  // Marshwood Center           -> nicholas.andrade@genesishcc.com
    'RRL-00000010'   // Holly Manor Center         -> sandra.lowden@genesishcc.com
};

List<Readmission_Report_Link__c> rows = [
    SELECT Id, Name, Facility__r.Name, Recipient_Email__c, Recipient_Role__c,
           Opens__c, Downloads__c, Codes_Sent__c, Closed_Reason__c
    FROM Readmission_Report_Link__c
    WHERE Name IN :names
];
if (rows.size() != names.size()) {
    System.debug(LoggingLevel.ERROR, 'Expected ' + names.size() + ' links, found ' + rows.size()
        + '. Stopping without closing anything.');
    return;
}

List<Readmission_Report_Link__c> toClose = new List<Readmission_Report_Link__c>();
for (Readmission_Report_Link__c row : rows) {
    System.debug(LoggingLevel.ERROR, row.Name + ' | ' + row.Facility__r.Name + ' | '
        + row.Recipient_Email__c + ' | role ' + row.Recipient_Role__c
        + ' | opens ' + row.Opens__c + ' downloads ' + row.Downloads__c
        + ' codes requested ' + row.Codes_Sent__c
        + ' | already closed: ' + row.Closed_Reason__c);
    if (row.Closed_Reason__c != null) {
        continue;
    }
    row.Closed_Reason__c = 'Manually revoked';
    row.Closed_At__c = System.now();
    toClose.add(row);
}
update toClose;
System.debug(LoggingLevel.ERROR, 'closed ' + toClose.size() + ' link(s). Each now refuses a '
    + 'code request, and its PDF endpoint returns 404.');
