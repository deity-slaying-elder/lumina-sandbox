/**
 * Purge rule: a stored report is deleted only when every link to it is dead and the grace
 * period has passed. Link rows themselves are never deleted.
 */
@IsTest
private class TCMReadmissionReportPurgeTest {

    private static Facility__c facility() {
        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Delivery_Mode__c = 'Link', Link_Expiry_Hours__c = 24,
            Allow_Download__c = true, Max_Opens__c = 0, Business_Timezone__c = 'America/New_York'
        );
        Account parent = new Account(Name = 'Parent', TCM__c = true);
        insert parent;
        Facility__c f = new Facility__c(
            Name = 'Purge Facility', Parent_Company__c = parent.Id,
            Admin_Email__c = 'admin@purge.example', TCM__c = true,
            Exclude_from_TCM_Reporting__c = false
        );
        insert f;
        return f;
    }

    /** Publishes one report to these addresses, then sets each link's expiry. */
    private static Id publish(Facility__c f, Map<String, Datetime> expiryByEmail) {
        TCMReadmissionLinkPublisher.Request r = new TCMReadmissionLinkPublisher.Request(
            f.Id, f.Name, 'Readmissions-Purge-2026-09-01.pdf',
            Blob.valueOf('%PDF-1.4 purge placeholder'), Date.newInstance(2026, 9, 1)
        );
        for (String email : expiryByEmail.keySet()) {
            r.recipients.add(new TCMReadmissionLinkPublisher.Recipient(email, 'Administrator'));
        }
        TCMReadmissionLinkPublisher.Published p =
            new TCMReadmissionLinkPublisher(new TCMReportConfig())
                .publish(new List<TCMReadmissionLinkPublisher.Request>{ r }).get(f.Id);
        System.assert(p.hasAnyUsable(), 'publish failed: ' + p.failure);

        List<Readmission_Report_Link__c> rows = [
            SELECT Id, Recipient_Email__c FROM Readmission_Report_Link__c WHERE Facility__c = :f.Id
        ];
        for (Readmission_Report_Link__c row : rows) {
            row.Expires_At__c = expiryByEmail.get(row.Recipient_Email__c);
        }
        update rows;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :p.contentVersionId]
            .ContentDocumentId;
    }

    private static Id publish(Facility__c f, List<String> emails, Datetime expiry) {
        Map<String, Datetime> byEmail = new Map<String, Datetime>();
        for (String email : emails) {
            byEmail.put(email, expiry);
        }
        return publish(f, byEmail);
    }

    private static Integer documentsLeft(Id documentId) {
        return [SELECT COUNT() FROM ContentDocument WHERE Id = :documentId];
    }

    @IsTest
    static void deletesAReportOnceEveryLinkToItIsDead() {
        Facility__c f = facility();
        Id documentId = publish(
            f, new List<String>{ 'admin@purge.example', 'don@purge.example' },
            Datetime.now().addDays(-20)
        );

        Test.startTest();
        TCMReadmissionReportPurge.Result result = TCMReadmissionReportPurge.run();
        Test.stopTest();

        System.assertEquals(2, result.linksExamined, 'both dead links seen');
        System.assertEquals(1, result.documentsDeleted, 'one file behind both links');
        System.assertEquals(0, result.documentsKept);
        System.assertEquals(0, documentsLeft(documentId), 'the stored report is gone');
        System.assertEquals(
            2, [SELECT COUNT() FROM Readmission_Report_Link__c],
            'the link rows survive, because the disclosure still happened'
        );
    }

    @IsTest
    static void oneLiveLinkKeepsTheReportForEveryone() {
        Facility__c f = facility();
        // Two recipients of the same report: one link long dead, one with time left. A single
        // file serves both, so deleting it would break a link that has not expired.
        Id documentId = publish(f, new Map<String, Datetime>{
            'admin@purge.example' => Datetime.now().addDays(-20),
            'live@purge.example' => Datetime.now().addHours(12)
        });

        Test.startTest();
        TCMReadmissionReportPurge.Result result = TCMReadmissionReportPurge.run();
        Test.stopTest();

        System.assertEquals(0, result.documentsDeleted, 'nothing may be deleted');
        System.assertEquals(1, result.documentsKept);
        System.assertEquals(1, documentsLeft(documentId), 'the report is still there');
    }

    @IsTest
    static void aClosedLinkDoesNotKeepTheReportAlive() {
        Facility__c f = facility();
        Id documentId = publish(f, new Map<String, Datetime>{
            'admin@purge.example' => Datetime.now().addDays(-20),
            'locked@purge.example' => Datetime.now().addHours(12)
        });
        Readmission_Report_Link__c locked = [
            SELECT Id FROM Readmission_Report_Link__c WHERE Recipient_Email__c = 'locked@purge.example'
        ];
        locked.Closed_Reason__c = 'Locked';
        locked.Closed_At__c = Datetime.now();
        update locked;

        Test.startTest();
        TCMReadmissionReportPurge.Result result = TCMReadmissionReportPurge.run();
        Test.stopTest();

        System.assertEquals(1, result.documentsDeleted, 'unexpired but locked is dead too');
        System.assertEquals(0, documentsLeft(documentId));
    }

    @IsTest
    static void aLinkInsideTheGracePeriodIsLeftAlone() {
        Facility__c f = facility();
        // Expired, but only yesterday. A reissue asked for straight afterwards should still
        // find the stored file rather than rendering a fresh one.
        Id documentId = publish(
            f, new List<String>{ 'admin@purge.example' }, Datetime.now().addDays(-1)
        );

        Test.startTest();
        TCMReadmissionReportPurge.Result result = TCMReadmissionReportPurge.run();
        Test.stopTest();

        System.assertEquals(0, result.linksExamined, 'too recent to be considered');
        System.assertEquals(0, result.documentsDeleted);
        System.assertEquals(1, documentsLeft(documentId));
    }

    @IsTest
    static void aLinkThatNeverExpiresIsNeverPurged() {
        Facility__c f = facility();
        Id documentId = publish(
            f, new List<String>{ 'admin@purge.example' }, Datetime.now().addDays(-20)
        );
        Readmission_Report_Link__c row = [SELECT Id FROM Readmission_Report_Link__c LIMIT 1];
        row.Expires_At__c = null;
        update row;

        Test.startTest();
        TCMReadmissionReportPurge.Result result = TCMReadmissionReportPurge.run();
        Test.stopTest();

        System.assertEquals(0, result.linksExamined);
        System.assertEquals(1, documentsLeft(documentId));
    }

    @IsTest
    static void aMalformedFileIdIsSkippedNotFatal() {
        Facility__c f = facility();
        insert new Readmission_Report_Link__c(
            Facility__c = f.Id,
            Recipient_Email__c = 'broken@purge.example',
            Access_Token_Hash__c = TCMReadmissionAccessToken.hashToken(TCMReadmissionAccessToken.mintToken()),
            Content_Version_Id__c = 'not-an-id',
            Expires_At__c = Datetime.now().addDays(-20),
            Opens__c = 0,
            Downloads__c = 0
        );

        Test.startTest();
        TCMReadmissionReportPurge.Result result = TCMReadmissionReportPurge.run();
        Test.stopTest();

        System.assertEquals(1, result.linksExamined);
        System.assertEquals(0, result.documentsDeleted, 'nothing to delete, and no exception');
        System.assertEquals(0, result.failures.size());
    }

    @IsTest
    static void aPhaseOneRowWithNoFileIdIsIgnored() {
        Facility__c f = facility();
        insert new Readmission_Report_Link__c(
            Facility__c = f.Id,
            Recipient_Email__c = 'legacy@purge.example',
            Distribution_Id__c = '05D000000000000AAA',
            Expires_At__c = Datetime.now().addDays(-20),
            Opens__c = 0,
            Downloads__c = 0
        );

        TCMReadmissionReportPurge.Result result = TCMReadmissionReportPurge.run();

        System.assertEquals(0, result.linksExamined);
    }

    @IsTest
    static void aFileAlreadyGoneIsNotAFailure() {
        Facility__c f = facility();
        Id documentId = publish(
            f, new List<String>{ 'admin@purge.example' }, Datetime.now().addDays(-20)
        );
        delete new ContentDocument(Id = documentId);

        TCMReadmissionReportPurge.Result result = TCMReadmissionReportPurge.run();

        System.assertEquals(1, result.linksExamined);
        System.assertEquals(0, result.documentsDeleted);
        System.assertEquals(0, result.failures.size());
    }

    @IsTest
    static void theScheduledEntryPointRuns() {
        Test.startTest();
        String jobId = System.schedule(
            'TCM Readmission Report Purge test',
            '0 0 3 ? * *',
            new TCMReadmissionReportPurge()
        );
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId],
            'the class is schedulable, which is how it will actually run'
        );
    }
}