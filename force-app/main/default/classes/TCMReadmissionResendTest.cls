/**
 * On-demand resend: what the confirm dialog is told, and what actually happens when it sends.
 *
 * The report site address is overridden, so these run the same in an org with or without the
 * site deployed.
 */
@IsTest
private class TCMReadmissionResendTest {

    private static final String TZ = 'America/New_York';

    /**
     * Production shape by default: no sandbox redirect, so the assertions are about the real
     * facility contacts rather than about whichever org the suite runs in.
     */
    private static TCMReportConfig config(String deliveryMode) {
        TCMReadmissionResend.sandboxOverride = false;
        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true,
            Require_Facility_TCM__c = false,
            Delivery_Mode__c = deliveryMode,
            Link_Expiry_Hours__c = 24,
            Allow_Download__c = true,
            Notify_On_Visit__c = false,
            Max_Opens__c = 10,
            Internal_CC_Emails__c = 'internal.cc@luminacare.com',
            Digest_Recipients__c = 'digest@propela.tech',
            Subject_Template__c = 'Readmissions Report - {0} - {1}',
            Business_Timezone__c = TZ
        );
        return new TCMReportConfig();
    }

    @TestSetup
    static void setup() {
        Account parent = new Account(Name = 'Resend Parent', TCM__c = true);
        insert parent;

        List<Facility__c> facilities = new List<Facility__c>{
            // Has admissions and an administrator: the happy path.
            new Facility__c(Name = 'Resend Alpha', Parent_Company__c = parent.Id,
                Admin_Email__c = 'admin@alpha.com', TCM__c = true,
                Exclude_from_TCM_Reporting__c = false),
            // Has admissions but no address on file.
            new Facility__c(Name = 'Resend Bravo', Parent_Company__c = parent.Id,
                TCM__c = true, Exclude_from_TCM_Reporting__c = false),
            // Addressable but no admissions in the window.
            new Facility__c(Name = 'Resend Charlie', Parent_Company__c = parent.Id,
                Admin_Email__c = 'admin@charlie.com', TCM__c = true,
                Exclude_from_TCM_Reporting__c = false)
        };
        insert facilities;

        Map<String, Id> facilityIdByName = new Map<String, Id>();
        for (Facility__c f : facilities) {
            facilityIdByName.put(f.Name, f.Id);
        }

        List<Patient__c> patients = new List<Patient__c>{
            patient('Ann', 'Adams', facilityIdByName.get('Resend Alpha')),
            patient('Bob', 'Brown', facilityIdByName.get('Resend Alpha')),
            patient('Cal', 'Clark', facilityIdByName.get('Resend Bravo'))
        };
        insert patients;

        Map<String, Id> patientIdByName = new Map<String, Id>();
        for (Patient__c p : patients) {
            patientIdByName.put(p.First_Name__c, p.Id);
        }

        Datetime inWindow = new TCMReadmissionWindow(TZ).startUtc.addHours(2);
        insert new List<Hospital_Admission__c>{
            admission(patientIdByName.get('Ann'), 'Mercy General', inWindow),
            admission(patientIdByName.get('Bob'), 'St. Luke', inWindow),
            admission(patientIdByName.get('Cal'), 'County Hospital', inWindow)
        };
    }

    private static Patient__c patient(String first, String last, Id facilityId) {
        return new Patient__c(
            First_Name__c = first, Last_Name__c = last, Status__c = 'Inactive',
            Facility__c = facilityId, Hospice__c = false
        );
    }


    private static Hospital_Admission__c admission(Id patientId, String hospital, Datetime admitUtc) {
        return new Hospital_Admission__c(
            Patient__c = patientId,
            Facility__c = hospital,
            Admit_DateTime__c = admitUtc,
            Was_Discharged_Home_From_SNF__c = true
        );
    }

    private static Id facilityId(String name) {
        return [SELECT Id FROM Facility__c WHERE Name = :name LIMIT 1].Id;
    }

    @IsTest
    static void previewNamesEveryRecipientAndSendsNothing() {
        config('Link');
        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.preview(facilityId('Resend Alpha'));
        Test.stopTest();

        System.assertEquals(
            true, result.sendable,
            'facility has rows and an address; blocked by: ' + result.blockedReason +
            ' rows=' + result.rowCount
        );
        System.assertEquals(2, result.rowCount, 'two qualifying admissions');
        System.assertEquals(24, result.expiryHours);
        System.assertEquals(10, result.maxOpens);
        System.assertEquals(null, result.blockedReason);

        Set<String> addresses = new Set<String>();
        for (TCMReadmissionResend.Delivery delivery : result.deliveries) {
            addresses.add(delivery.email);
            System.assertEquals(false, delivery.sent, 'preview sends nothing');
        }
        System.assertEquals(
            new Set<String>{ 'admin@alpha.com', 'internal.cc@luminacare.com' },
            addresses,
            'administrator plus the internal cc, one link each'
        );
        System.assertEquals(
            0, [SELECT COUNT() FROM Readmission_Report_Link__c], 'preview writes nothing'
        );
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion], 'no file stored');
    }

    @IsTest
    static void previewBlocksWhenThereIsNoAddress() {
        config('Link');
        TCMReadmissionResend.Result result = TCMReadmissionResend.preview(facilityId('Resend Bravo'));

        System.assertEquals(false, result.sendable);
        System.assert(
            result.blockedReason.contains('No Admin_Email__c'),
            'names the missing field: ' + result.blockedReason
        );
    }

    @IsTest
    static void previewBlocksWhenThereAreNoAdmissions() {
        config('Link');
        TCMReadmissionResend.Result result = TCMReadmissionResend.preview(facilityId('Resend Charlie'));

        System.assertEquals(false, result.sendable);
        System.assertEquals(0, result.rowCount);
        System.assert(
            result.blockedReason.contains('No readmissions'),
            'explains the empty window: ' + result.blockedReason
        );
    }

    @IsTest
    static void previewBlocksOnAMissingFacility() {
        config('Link');
        Account orphan = new Account(Name = 'Not a facility');
        insert orphan;
        TCMReadmissionResend.Result missing = TCMReadmissionResend.preview(null);
        System.assertEquals('No facility was supplied.', missing.blockedReason);
    }

    @IsTest
    static void sendIssuesOneNewLinkPerRecipient() {
        config('Link');
        Id alpha = facilityId('Resend Alpha');

        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.send(alpha);
        Test.stopTest();

        System.assertEquals(
            true, result.sent,
            'mail went out; blocked=' + result.blockedReason + ' problems=' + result.problems +
            ' rows=' + result.rowCount
        );
        System.assertEquals(false, result.reusedStoredFile, 'nothing was stored beforehand');

        List<Readmission_Report_Link__c> links = [
            SELECT Recipient_Email__c, Recipient_Role__c, Facility__c, Access_Token_Hash__c,
                   Content_Version_Id__c, Expires_At__c, Opens__c, Downloads__c
            FROM Readmission_Report_Link__c
            ORDER BY Recipient_Email__c
        ];
        System.assertEquals(2, links.size(), 'one attribution row per recipient');
        System.assertEquals('admin@alpha.com', links[0].Recipient_Email__c);
        System.assertEquals('Administrator', links[0].Recipient_Role__c);
        System.assertEquals('internal.cc@luminacare.com', links[1].Recipient_Email__c);
        System.assertEquals('Internal', links[1].Recipient_Role__c);
        for (Readmission_Report_Link__c link : links) {
            System.assertEquals(alpha, link.Facility__c, 'row hangs off the facility');
            System.assertNotEquals(null, link.Access_Token_Hash__c, 'the row is the link');
            System.assertNotEquals(null, link.Content_Version_Id__c, 'and knows its file');
            System.assertEquals(0, link.Opens__c, 'a new link starts unopened');
        }
        System.assertNotEquals(
            links[0].Access_Token_Hash__c, links[1].Access_Token_Hash__c,
            'two distinct links'
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentVersion WHERE FirstPublishLocationId = :alpha],
            'one file, both links point at it'
        );
        for (TCMReadmissionResend.Delivery delivery : result.deliveries) {
            System.assertEquals(true, delivery.sent, delivery.email + ': ' + delivery.problem);
            System.assert(
                String.isNotBlank(delivery.expiresAt), 'the dialog reports the expiry back'
            );
        }
    }

    @IsTest
    static void sendReusesAReportAlreadyStoredOnTheRecord() {
        // Stands in for yesterday's daily run having already filed the PDF. Two sends cannot be
        // driven from one test method: the platform rejects a second batch of distributions
        // against the same file inside a single transaction, and every real click is its own.
        config('Link');
        Facility__c alpha = [SELECT Id, Name FROM Facility__c WHERE Name = 'Resend Alpha'];
        TCMReadmissionWindow window = new TCMReadmissionWindow(TZ);
        String title = new TCMReadmissionCsvBuilder(TZ)
            .fileName(alpha.Name, window.fileDateToken())
            .removeEndIgnoreCase('.csv');

        insert new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 stored by the daily run'),
            FirstPublishLocationId = alpha.Id
        );

        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.send(alpha.Id);
        Test.stopTest();

        System.assertEquals(true, result.sent, 'went out: ' + result.problems);
        System.assertEquals(true, result.reusedStoredFile, 'pointed at the stored report');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentVersion WHERE FirstPublishLocationId = :alpha.Id],
            'resending does not store the report a second time'
        );
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Readmission_Report_Link__c],
            'and still issues one fresh link per recipient'
        );
    }

    @IsTest
    static void aSandboxRunIssuesTheLinkToTheTesterAndRecordsWhoItWasFor() {
        config('Link');
        TCMReportConfig.overrideRecord.Sandbox_Redirect_Emails__c = 'tester@propela.tech';
        TCMReadmissionResend.sandboxOverride = true;

        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.send(facilityId('Resend Alpha'));
        Test.stopTest();

        System.assertEquals(true, result.redirected, 'the dialog warns it was redirected');
        System.assertEquals(true, result.sent, 'still sent: ' + result.problems);

        List<Readmission_Report_Link__c> links = [
            SELECT Recipient_Email__c, Recipient_Role__c, Intended_For__c
            FROM Readmission_Report_Link__c
        ];
        System.assertEquals(1, links.size(), 'one tester, one link');
        System.assertEquals('tester@propela.tech', links[0].Recipient_Email__c,
            'the link belongs to the mailbox that can open it');
        System.assertEquals('Sandbox Tester', links[0].Recipient_Role__c);
        System.assert(
            links[0].Intended_For__c.contains('admin@alpha.com'),
            'and records the facility contact it stands in for: ' + links[0].Intended_For__c
        );
    }

    @IsTest
    static void attachmentModeSendsTheCsvAndIssuesNoLink() {
        config('Attachment');
        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.send(facilityId('Resend Alpha'));
        Test.stopTest();

        System.assertEquals(true, result.sent, 'mail went out: ' + result.problems);
        System.assertEquals(
            0, [SELECT COUNT() FROM Readmission_Report_Link__c], 'and logs no link row'
        );
    }

    @IsTest
    static void reportsAConfiguredSenderThatDoesNotExist() {
        TCMReadmissionResend.sandboxOverride = false;
        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true,
            Require_Facility_TCM__c = false,
            Delivery_Mode__c = 'Link',
            Link_Expiry_Hours__c = 24,
            Allow_Download__c = true,
            Max_Opens__c = 0,
            Internal_CC_Emails__c = 'internal.cc@luminacare.com',
            From_Org_Wide_Address__c = 'nobody@luminacare.example',
            Sandbox_Redirect_Emails__c = 'tester@propela.tech',
            Subject_Template__c = 'Readmissions Report - {0} - {1}',
            Business_Timezone__c = TZ
        );

        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.send(facilityId('Resend Alpha'));
        Test.stopTest();

        System.assertEquals(true, result.sent, 'a setup gap must not silence the report');
        Boolean noted = false;
        for (String problem : result.problems) {
            noted = noted || problem.contains('nobody@luminacare.example');
        }
        System.assertEquals(true, noted, 'and the dialog says why: ' + result.problems);
    }

    @IsTest
    static void aFailedLinkMeansNoEmailAtAll() {
        config('Link');
        Id alpha = facilityId('Resend Alpha');
        // A publish that produced nothing usable. An email pointing at a link that does not
        // exist is worse than no email, so nothing may go out.
        TCMReadmissionLinkPublisher.Published broken =
            new TCMReadmissionLinkPublisher.Published();
        broken.facilityId = alpha;
        broken.failure = 'File could not be stored: STORAGE_LIMIT_EXCEEDED';
        TCMReadmissionLinkPublisher.publishOverride =
            new Map<Id, TCMReadmissionLinkPublisher.Published>{ alpha => broken };

        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.send(alpha);
        Integer sentInTransaction = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(false, result.sent, 'nothing may be sent');
        System.assertEquals(false, result.sendable);
        System.assert(
            result.blockedReason.contains('STORAGE_LIMIT_EXCEEDED'),
            'and the reason reaches the person who clicked: ' + result.blockedReason
        );
        System.assertEquals(0, sentInTransaction, 'no email invocation at all');
        System.assertEquals(
            0, [SELECT COUNT() FROM Readmission_Report_Link__c],
            'and no attribution row claiming a delivery that never happened'
        );
    }

    @IsTest
    static void attachmentModeMarksEveryRecipientOnTheOneEmail() {
        config('Attachment');
        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.send(facilityId('Resend Alpha'));
        Test.stopTest();

        System.assertEquals(true, result.sent, 'went out: ' + result.problems);
        System.assertEquals(2, result.deliveries.size(), 'administrator plus the internal copy');
        for (TCMReadmissionResend.Delivery delivery : result.deliveries) {
            System.assertEquals(
                true, delivery.sent,
                delivery.email + ' received the one email and must not be shown as unsent'
            );
            System.assertEquals(null, delivery.problem);
        }
        System.assert(
            result.summary.contains('one email'),
            'and the summary says it was a single message: ' + result.summary
        );
    }

    @IsTest
    static void emailBodyCarriesTheReissueLineAndNoPatientData() {
        TCMReportConfig config = config('Link');
        Facility__c facility = [SELECT Id, Name FROM Facility__c WHERE Name = 'Resend Alpha'];
        TCMReadmissionWindow window = new TCMReadmissionWindow(TZ);
        TCMReadmissionEmailBuilder builder = new TCMReadmissionEmailBuilder(
            config, TZ, window.describe(), window.fileDateToken()
        );

        TCMReadmissionLinkPublisher.Issued issued = new TCMReadmissionLinkPublisher.Issued();
        issued.email = 'admin@alpha.com';
        issued.publicUrl = 'https://example.com/sfc/dist/version/download/?oid=1';
        issued.expiresAt = Datetime.now().addHours(24);

        String reissued = builder.bodyFor(facility, 2, false, issued, 'admin@alpha.com', true);
        System.assert(reissued.contains('new link'), 'explains why it arrived off schedule');
        System.assert(reissued.contains('closes after 10 views'), 'states the view cap');
        System.assert(reissued.contains('admin@alpha.com'), 'names the mailbox it belongs to');
        System.assert(!reissued.contains('Adams'), 'no patient name in the email');

        String scheduled = builder.bodyFor(facility, 2, false, issued, 'admin@alpha.com', false);
        System.assert(!scheduled.contains('new link'), 'the daily email is unchanged');
        System.assertEquals(
            'Readmissions Report - Resend Alpha - ' + window.fileDateToken(),
            builder.subjectFor(facility)
        );
    }

    @IsTest
    static void aFacilityTheJobWouldSkipCannotBeResentTo() {
        config('Link');
        // The job requires facility TCM only when this switch is on, which is how production
        // is configured, so the button must refuse the same facilities it does.
        TCMReportConfig.overrideRecord.Require_Facility_TCM__c = true;
        Facility__c alpha = [SELECT Id, TCM__c FROM Facility__c WHERE Name = 'Resend Alpha'];
        alpha.TCM__c = false;
        update alpha;

        Test.startTest();
        TCMReadmissionResend.Result result = TCMReadmissionResend.preview(alpha.Id);
        Test.stopTest();

        System.assertEquals(false, result.sendable);
        System.assert(result.blockedReason.contains('TCM is not ticked'), result.blockedReason);
        System.assertEquals('Resend Alpha', result.facilityName, 'still names the facility');
        System.assertEquals(0, result.deliveries.size(), 'and offers nobody to send to');
    }

    @IsTest
    static void anExcludedFacilityCannotBeResentTo() {
        config('Link');
        Facility__c alpha = [SELECT Id FROM Facility__c WHERE Name = 'Resend Alpha'];
        alpha.Exclude_from_TCM_Reporting__c = true;
        update alpha;

        TCMReadmissionResend.Result result = TCMReadmissionResend.preview(alpha.Id);

        System.assertEquals(false, result.sendable);
        System.assert(result.blockedReason.contains('excluded from TCM reporting'), result.blockedReason);
    }

    @IsTest
    static void aFacilityWhoseParentIsNotEnrolledCannotBeResentTo() {
        config('Link');
        Account parent = [SELECT Id FROM Account WHERE Name = 'Resend Parent'];
        parent.TCM__c = false;
        update parent;

        TCMReadmissionResend.Result result =
            TCMReadmissionResend.preview(facilityId('Resend Alpha'));

        System.assertEquals(false, result.sendable);
        System.assert(result.blockedReason.contains('parent company is not enrolled'), result.blockedReason);
    }

    @IsTest
    static void theFacilityTcmCheckFollowsTheSameConfigTheJobUses() {
        // With the config switch off, the job does not require facility TCM, so neither may the
        // button: the two must agree on who is in scope.
        TCMReadmissionResend.sandboxOverride = false;
        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Require_Facility_TCM__c = false, Delivery_Mode__c = 'Link',
            Link_Expiry_Hours__c = 24, Allow_Download__c = true, Max_Opens__c = 0,
            Subject_Template__c = 'Readmissions Report - {0} - {1}', Business_Timezone__c = TZ
        );
        Facility__c alpha = [SELECT Id FROM Facility__c WHERE Name = 'Resend Alpha'];
        alpha.TCM__c = false;
        update alpha;

        TCMReadmissionResend.Result result = TCMReadmissionResend.preview(alpha.Id);

        System.assertEquals(true, result.sendable, 'blocked: ' + result.blockedReason);
    }

    @IsTest
    static void theResendAppliesTheSamePatientClassFilterAsTheJob() {
        config('Link');
        TCMReportConfig.overrideRecord.Required_Patient_Class__c = 'Inpatient';

        Test.startTest();
        TCMReadmissionResend.Result blocked =
            TCMReadmissionResend.preview(facilityId('Resend Alpha'));

        // Class one of Alpha's two rows and the report comes back with exactly that row.
        Hospital_Admission__c one = [
            SELECT Id FROM Hospital_Admission__c
            WHERE Patient__r.Facility__r.Name = 'Resend Alpha' LIMIT 1
        ];
        one.Patient_Class__c = 'Emergency, Inpatient';
        update one;
        TCMReadmissionResend.Result allowed =
            TCMReadmissionResend.preview(facilityId('Resend Alpha'));
        Test.stopTest();

        System.assertEquals(false, blocked.sendable, 'no Inpatient row means nothing to resend');
        System.assert(blocked.blockedReason.contains('No readmissions'), blocked.blockedReason);
        System.assertEquals(true, allowed.sendable, 'blocked: ' + allowed.blockedReason);
        System.assertEquals(1, allowed.rowCount, 'only the Inpatient row is reported');
    }

    @IsTest
    static void everyListedInternalRecipientGetsTheirOwnLinkAndTheirOwnCode() {
        config('Link');
        // Three named people plus the facility administrator. This is the option Lumina chose:
        // an identical email each, never a Cc, so one person's code never reaches another.
        TCMReportConfig.overrideRecord.Internal_CC_Emails__c =
            'ben@luminacare.com; kevin@luminacare.com, chayim@propela.tech';

        Test.startTest();
        TCMReadmissionResend.Result result =
            TCMReadmissionResend.preview(facilityId('Resend Alpha'));
        Test.stopTest();

        System.assertEquals(true, result.sendable, '' + result.blockedReason);
        Set<String> addresses = new Set<String>();
        for (TCMReadmissionResend.Delivery d : result.deliveries) {
            addresses.add(d.email);
        }
        System.assertEquals(
            new Set<String>{
                'admin@alpha.com', 'ben@luminacare.com', 'kevin@luminacare.com',
                'chayim@propela.tech'
            },
            addresses,
            'the administrator plus all three listed staff, separated by either separator'
        );
        System.assertEquals(
            4, result.deliveries.size(), 'one delivery each, so one link and one code each'
        );
    }
}