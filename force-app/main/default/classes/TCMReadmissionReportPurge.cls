/**
 * Deletes a stored report once every link to it is dead.
 *
 * The link expires, but the PDF behind it does not: `FirstPublishLocationId` files each report
 * on its Facility, so without this the facility record accumulates every readmission report
 * ever generated, all of it patient data, long outliving the delivery window it was created
 * for. Download is deliberately enabled, so a recipient's own copy is theirs; what this removes
 * is the copy Salesforce keeps.
 *
 * The rule that matters: one file serves every recipient of the same report, so it is deleted
 * only when no link to it is still live. A single recipient whose link is still open keeps the
 * file for everyone. Link rows are never deleted, only the document they pointed at, so the
 * accounting of disclosures survives the purge.
 *
 * Runs after a grace period, so that "the link expired" and "the report vanished" are not the
 * same moment for someone who asks for a reissue immediately afterwards. A reissue inside the
 * grace period reuses the stored file; after it, the report is rendered again.
 */
public with sharing class TCMReadmissionReportPurge implements Schedulable {

    /** Kept this long after the last link to a report has expired. */
    @TestVisible
    private static Integer graceDays = 7;

    public class Result {
        public Integer linksExamined = 0;
        public Integer documentsDeleted = 0;
        public Integer documentsKept = 0;
        public List<String> failures = new List<String>();
    }

    public void execute(SchedulableContext context) {
        run();
    }

    public static Result run() {
        Result result = new Result();
        Datetime cutoff = Datetime.now().addDays(-graceDays);

        // Every link that is dead and old enough to have stopped being useful.
        List<Readmission_Report_Link__c> stale = [
            SELECT Id, Content_Version_Id__c
            FROM Readmission_Report_Link__c
            WHERE Content_Version_Id__c != null
              AND Expires_At__c != null
              AND Expires_At__c < :cutoff
            ORDER BY Expires_At__c
            LIMIT 5000
        ];
        result.linksExamined = stale.size();
        if (stale.isEmpty()) {
            return result;
        }

        Set<Id> staleVersionIds = new Set<Id>();
        for (Readmission_Report_Link__c link : stale) {
            try {
                staleVersionIds.add(Id.valueOf(link.Content_Version_Id__c));
            } catch (Exception e) {
                continue;
            }
        }
        if (staleVersionIds.isEmpty()) {
            return result;
        }

        // Which document each dead link pointed at. A version already deleted simply drops out.
        Set<Id> candidateDocumentIds = new Set<Id>();
        for (ContentVersion version : [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :staleVersionIds
        ]) {
            candidateDocumentIds.add(version.ContentDocumentId);
        }
        if (candidateDocumentIds.isEmpty()) {
            return result;
        }

        // Any link on any version of the same document that is still live keeps the file.
        // This is the whole safety rule: expiry is per recipient, deletion is per file.
        Map<Id, Id> documentByVersion = new Map<Id, Id>();
        for (ContentVersion version : [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :candidateDocumentIds
        ]) {
            documentByVersion.put(version.Id, version.ContentDocumentId);
        }
        Datetime now = Datetime.now();
        Set<String> versionIdStrings = new Set<String>();
        for (Id versionId : documentByVersion.keySet()) {
            versionIdStrings.add(String.valueOf(versionId));
            versionIdStrings.add(String.valueOf(versionId).left(15));
        }
        Set<Id> keep = new Set<Id>();
        for (Readmission_Report_Link__c link : [
            SELECT Content_Version_Id__c
            FROM Readmission_Report_Link__c
            WHERE Content_Version_Id__c IN :versionIdStrings
              AND Closed_Reason__c = null
              AND Expires_At__c > :now
        ]) {
            Id documentId;
            try {
                documentId = documentByVersion.get(Id.valueOf(link.Content_Version_Id__c));
            } catch (Exception e) {
                continue;
            }
            if (documentId != null) {
                keep.add(documentId);
            }
        }

        List<ContentDocument> toDelete = new List<ContentDocument>();
        for (Id documentId : candidateDocumentIds) {
            if (keep.contains(documentId)) {
                result.documentsKept++;
            } else {
                toDelete.add(new ContentDocument(Id = documentId));
            }
        }
        if (toDelete.isEmpty()) {
            return result;
        }

        // Partial success: one undeletable document must not strand the rest. Deleting the
        // document removes its versions with it.
        for (Database.DeleteResult deleted : Database.delete(toDelete, false)) {
            if (deleted.isSuccess()) {
                result.documentsDeleted++;
            } else {
                result.failures.add(
                    'Could not delete report ' + deleted.getId() + ': ' +
                    (deleted.getErrors().isEmpty()
                        ? 'unknown error'
                        : deleted.getErrors()[0].getMessage())
                );
            }
        }
        return result;
    }
}