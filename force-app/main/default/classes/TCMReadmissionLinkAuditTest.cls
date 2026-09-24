/**
 * Audit sync over the link rows: totals for the digest, and closing a row that reached the
 * open cap but was left open.
 */
@IsTest
private class TCMReadmissionLinkAuditTest {

    private static Facility__c facility() {
        Account parent = new Account(Name = 'Parent', TCM__c = true);
        insert parent;
        Facility__c f = new Facility__c(
            Name = 'Audit Facility', Parent_Company__c = parent.Id,
            Admin_Email__c = 'admin@example.com', TCM__c = true,
            Exclude_from_TCM_Reporting__c = false
        );
        insert f;
        return f;
    }

    private static Readmission_Report_Link__c row(
        Facility__c f, String email, Integer opens, Integer downloads
    ) {
        return new Readmission_Report_Link__c(
            Facility__c = f.Id,
            Recipient_Email__c = email,
            Intended_For__c = email,
            Access_Token_Hash__c = TCMReadmissionAccessToken.hashToken(
                TCMReadmissionAccessToken.mintToken()
            ),
            Content_Version_Id__c = '068000000000000AAA',
            Expires_At__c = Datetime.now().addHours(12),
            Opens__c = opens,
            Downloads__c = downloads,
            Codes_Sent__c = 0,
            Failed_Attempts__c = 0
        );
    }

    private static List<Readmission_Report_Link__c> fresh() {
        return [
            SELECT Id, Recipient_Email__c, Opens__c, Downloads__c, Closed_Reason__c,
                   Closed_At__c, Expires_At__c, Unlocked_Until__c
            FROM Readmission_Report_Link__c
            ORDER BY Recipient_Email__c
        ];
    }

    @IsTest
    static void totalsAddUpAcrossEveryRow() {
        Facility__c f = facility();
        insert new List<Readmission_Report_Link__c>{
            row(f, 'a@example.com', 3, 1),
            row(f, 'b@example.com', 0, 0),
            row(f, 'c@example.com', 2, 2)
        };

        Test.startTest();
        TCMReadmissionLinkAudit.Result first = TCMReadmissionLinkAudit.sync(fresh(), 0);
        TCMReadmissionLinkAudit.Result second = TCMReadmissionLinkAudit.sync(fresh(), 0);
        Test.stopTest();

        System.assertEquals(3, first.linksExamined);
        System.assertEquals(5, first.opens);
        System.assertEquals(3, first.downloads);
        System.assertEquals(0, first.cappedEarly);
        System.assertEquals(0, first.linksUpdated, 'nothing to write with no cap');
        System.assertEquals(5, second.opens, 'running it again reports the same, not double');
        System.assertEquals(0, second.linksUpdated);
    }

    @IsTest
    static void aRowLeftOpenAtTheCapIsClosed() {
        Facility__c f = facility();
        insert new List<Readmission_Report_Link__c>{
            row(f, 'capped@example.com', 10, 0),
            row(f, 'under@example.com', 9, 0)
        };

        Test.startTest();
        TCMReadmissionLinkAudit.Result result = TCMReadmissionLinkAudit.sync(fresh(), 10);
        TCMReadmissionLinkAudit.Result again = TCMReadmissionLinkAudit.sync(fresh(), 10);
        Test.stopTest();

        System.assertEquals(1, result.cappedEarly);
        System.assertEquals(1, result.linksUpdated);
        System.assert(result.closeFailures.isEmpty(), '' + result.closeFailures);
        List<Readmission_Report_Link__c> rows = fresh();
        System.assertEquals('View limit reached', rows[0].Closed_Reason__c);
        System.assertNotEquals(null, rows[0].Closed_At__c);
        System.assert(rows[0].Expires_At__c > Datetime.now(), 'the issued expiry is kept');
        System.assertEquals(null, rows[1].Closed_Reason__c, 'nine of ten stays open');
        System.assertEquals(1, again.cappedEarly, 'reported as capped, not closed twice');
        System.assertEquals(0, again.linksUpdated);
    }

    @IsTest
    static void aRowStillInsideItsUnlockWindowIsNotCutOff() {
        Facility__c f = facility();
        Readmission_Report_Link__c reading = row(f, 'reading@example.com', 10, 0);
        reading.Unlocked_Until__c = Datetime.now().addMinutes(5);
        insert reading;

        TCMReadmissionLinkAudit.Result result = TCMReadmissionLinkAudit.sync(fresh(), 10);

        System.assertEquals(0, result.cappedEarly, 'the final allowed open is still on screen');
        System.assertEquals(null, fresh()[0].Closed_Reason__c);

        reading.Unlocked_Until__c = Datetime.now().addMinutes(-1);
        update reading;
        result = TCMReadmissionLinkAudit.sync(fresh(), 10);
        System.assertEquals(1, result.cappedEarly, 'closed once the window has passed');
    }

    @IsTest
    static void anExpiredRowIsNotRelabelledAsCapped() {
        Facility__c f = facility();
        Readmission_Report_Link__c expired = row(f, 'expired@example.com', 10, 0);
        expired.Expires_At__c = Datetime.now().addMinutes(-1);
        insert expired;

        TCMReadmissionLinkAudit.Result result = TCMReadmissionLinkAudit.sync(fresh(), 10);

        System.assertEquals(0, result.cappedEarly);
        System.assertEquals(null, fresh()[0].Closed_Reason__c, 'it timed out; say so, not "cap"');
        System.assertEquals(10, result.opens, 'its opens still count in the totals');
    }

    @IsTest
    static void lockedRowsAreCountedForTheDigest() {
        Facility__c f = facility();
        Readmission_Report_Link__c locked = row(f, 'locked@example.com', 0, 0);
        locked.Closed_Reason__c = 'Locked';
        locked.Closed_At__c = Datetime.now();
        Readmission_Report_Link__c capped = row(f, 'capped@example.com', 10, 0);
        capped.Closed_Reason__c = 'View limit reached';
        capped.Closed_At__c = Datetime.now();
        insert new List<Readmission_Report_Link__c>{ locked, capped };

        TCMReadmissionLinkAudit.Result result = TCMReadmissionLinkAudit.sync(fresh(), 10);

        System.assertEquals(1, result.locked);
        System.assertEquals(1, result.cappedEarly);
        System.assertEquals(0, result.linksUpdated, 'already closed rows are not rewritten');
    }

    @IsTest
    static void theDatabaseEntryPointFindsRecentTokenRowsOnly() {
        Facility__c f = facility();
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Max_Opens__c = 10, Business_Timezone__c = 'America/New_York'
        );
        Readmission_Report_Link__c legacy = new Readmission_Report_Link__c(
            Facility__c = f.Id, Recipient_Email__c = 'legacy@example.com',
            Distribution_Id__c = '05D000000000000AAA', Opens__c = 4, Downloads__c = 0,
            Expires_At__c = Datetime.now().addHours(1)
        );
        insert new List<Readmission_Report_Link__c>{ row(f, 'token@example.com', 2, 1), legacy };

        Test.startTest();
        TCMReadmissionLinkAudit.Result result = TCMReadmissionLinkAudit.sync();
        Test.stopTest();

        System.assertEquals(1, result.linksExamined, 'the phase-one row has no token and is ignored');
        System.assertEquals(2, result.opens);
        System.assertEquals(1, result.downloads);
    }

    @IsTest
    static void emptyInputIsSafe() {
        TCMReadmissionLinkAudit.Result result =
            TCMReadmissionLinkAudit.sync(new List<Readmission_Report_Link__c>(), 10);
        System.assertEquals(0, result.linksExamined);
        System.assertEquals(0, TCMReadmissionLinkAudit.sync(null, 10).linksExamined);
    }
}