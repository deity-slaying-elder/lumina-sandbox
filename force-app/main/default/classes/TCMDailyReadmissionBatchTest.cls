/**
 * Batch behaviour: which facilities the locator selects, which admissions fall in the
 * window, how rows group per facility, and what gets skipped rather than sent.
 *
 * Admission timestamps are derived from a live TCMReadmissionWindow rather than hardcoded,
 * so the suite behaves the same whether it runs on a Monday or any other day.
 */
@IsTest
private class TCMDailyReadmissionBatchTest {

    private static final String TZ = 'America/New_York';

    private static TCMReadmissionWindow window() {
        return new TCMReadmissionWindow(TZ);
    }

    /** Link mode, the production default. */
    private static TCMReportConfig config() {
        return config('Link');
    }

    private static TCMReportConfig config(String deliveryMode) {
        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true,
            Require_Facility_TCM__c = false,
            Delivery_Mode__c = deliveryMode,
            Link_Expiry_Hours__c = 72,
            Allow_Download__c = true,
            Notify_On_Visit__c = false, Max_Opens__c = 0,
            Internal_CC_Emails__c = 'internal.cc@luminacare.com',
            NJ_GHC_CC_Email__c = 'nj.contact@example.com',
            NJ_GHC_Parent_Company_Name__c = 'GHC',
            Sandbox_Redirect_Email__c = 'sandbox@propela.tech',
            Digest_Recipients__c = 'digest@propela.tech',
            Subject_Template__c = 'Readmissions Report - {0} - {1}',
            Business_Timezone__c = TZ
        );
        return new TCMReportConfig();
    }

    @TestSetup
    static void setup() {
        Account enrolled = new Account(Name = 'Enrolled Parent', TCM__c = true);
        Account notEnrolled = new Account(Name = 'Unenrolled Parent', TCM__c = false);
        insert new List<Account>{ enrolled, notEnrolled };

        List<Facility__c> facilities = new List<Facility__c>{
            // Sends, via Admin_Email__c.
            new Facility__c(Name = 'Alpha SNF', Parent_Company__c = enrolled.Id,
                Admin_Email__c = 'admin@alpha.com', TCM__c = true,
                Exclude_from_TCM_Reporting__c = false),
            // Sends, falling back to DON_Email__c.
            new Facility__c(Name = 'Bravo SNF', Parent_Company__c = enrolled.Id,
                DON_Email__c = 'don@bravo.com', TCM__c = true,
                Exclude_from_TCM_Reporting__c = false),
            // Has rows but nowhere to send them.
            new Facility__c(Name = 'Charlie SNF', Parent_Company__c = enrolled.Id,
                TCM__c = true, Exclude_from_TCM_Reporting__c = false),
            // Excluded by the facility flag.
            new Facility__c(Name = 'Delta SNF', Parent_Company__c = enrolled.Id,
                Admin_Email__c = 'admin@delta.com', TCM__c = true,
                Exclude_from_TCM_Reporting__c = true),
            // Parent company not enrolled.
            new Facility__c(Name = 'Echo SNF', Parent_Company__c = notEnrolled.Id,
                Admin_Email__c = 'admin@echo.com', TCM__c = true,
                Exclude_from_TCM_Reporting__c = false),
            // Enrolled and addressable, but will have no admissions in the window.
            new Facility__c(Name = 'Foxtrot SNF', Parent_Company__c = enrolled.Id,
                Admin_Email__c = 'admin@foxtrot.com', TCM__c = true,
                Exclude_from_TCM_Reporting__c = false),
            // Parent company left blank.
            new Facility__c(Name = 'Golf SNF', Admin_Email__c = 'admin@golf.com',
                TCM__c = true, Exclude_from_TCM_Reporting__c = false)
        };
        insert facilities;

        Map<String, Id> facilityIdByName = new Map<String, Id>();
        for (Facility__c f : facilities) {
            facilityIdByName.put(f.Name, f.Id);
        }

        List<Patient__c> patients = new List<Patient__c>{
            patient('Ann', 'Adams', facilityIdByName.get('Alpha SNF'), false),
            patient('Bob', 'Adams', facilityIdByName.get('Alpha SNF'), false),
            patient('Cal', 'Brown', facilityIdByName.get('Bravo SNF'), false),
            patient('Dee', 'Clark', facilityIdByName.get('Charlie SNF'), false),
            patient('Eve', 'Davis', facilityIdByName.get('Delta SNF'), false),
            patient('Fay', 'Evans', facilityIdByName.get('Echo SNF'), false),
            patient('Gus', 'Frost', facilityIdByName.get('Golf SNF'), false),
            // Hospice patients must never appear.
            patient('Hal', 'Grant', facilityIdByName.get('Alpha SNF'), true)
        };
        insert patients;

        Map<String, Id> patientIdByName = new Map<String, Id>();
        for (Patient__c p : patients) {
            patientIdByName.put(p.First_Name__c, p.Id);
        }

        TCMReadmissionWindow w = new TCMReadmissionWindow(TZ);
        Datetime inWindow = w.startUtc.addHours(2);
        Datetime beforeWindow = w.startUtc.addDays(-5);
        Datetime atWindowEnd = w.endUtc;

        insert new List<Hospital_Admission__c>{
            // Alpha: two qualifying rows, so grouping has something to group.
            admission(patientIdByName.get('Ann'), 'Mercy General', inWindow, true),
            admission(patientIdByName.get('Bob'), 'St. Luke', inWindow, true),
            // Alpha: excluded because it was not a discharge home from the SNF.
            admission(patientIdByName.get('Ann'), 'Mercy General', inWindow, false),
            // Alpha: excluded because the patient is on hospice.
            admission(patientIdByName.get('Hal'), 'Mercy General', inWindow, true),
            // Alpha: excluded because it predates the window.
            admission(patientIdByName.get('Ann'), 'Mercy General', beforeWindow, true),
            // Alpha: excluded because the window end is exclusive.
            admission(patientIdByName.get('Ann'), 'Mercy General', atWindowEnd, true),
            admission(patientIdByName.get('Cal'), 'County Hospital', inWindow, true),
            admission(patientIdByName.get('Dee'), 'County Hospital', inWindow, true),
            admission(patientIdByName.get('Eve'), 'County Hospital', inWindow, true),
            admission(patientIdByName.get('Fay'), 'County Hospital', inWindow, true),
            admission(patientIdByName.get('Gus'), 'County Hospital', inWindow, true)
            // Foxtrot deliberately gets none.
        };
    }

    private static Patient__c patient(String first, String last, Id facilityId, Boolean hospice) {
        return new Patient__c(
            First_Name__c = first,
            Last_Name__c = last,
            Status__c = 'Inactive',
            Facility__c = facilityId,
            Hospice__c = hospice
        );
    }


    private static Hospital_Admission__c admission(
        Id patientId, String hospital, Datetime admitUtc, Boolean dischargedHome
    ) {
        return new Hospital_Admission__c(
            Patient__c = patientId,
            Facility__c = hospital,
            Admit_DateTime__c = admitUtc,
            Was_Discharged_Home_From_SNF__c = dischargedHome
        );
    }

    private static List<Facility__c> locatorFacilities(TCMDailyReadmissionBatch batch) {
        return Database.query(
            String.valueOf(batch.start(null).getQuery())
        );
    }

    @IsTest
    static void locatorSkipsExcludedAndUnenrolledFacilities() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config(), false);

        Set<String> selected = new Set<String>();
        for (Facility__c f : locatorFacilities(batch)) {
            selected.add(f.Name);
        }

        System.assert(selected.contains('Alpha SNF'), 'selected: ' + selected);
        System.assert(selected.contains('Foxtrot SNF'), 'zero-row facilities are still selected');
        System.assert(!selected.contains('Delta SNF'), 'Exclude_from_TCM_Reporting__c must filter out');
        System.assert(!selected.contains('Echo SNF'), 'unenrolled parent company must filter out');
        System.assert(!selected.contains('Golf SNF'), 'a blank parent company must filter out');
    }

    @IsTest
    static void requireFacilityTcmNarrowsTheLocator() {
        Facility__c alpha = [SELECT Id FROM Facility__c WHERE Name = 'Alpha SNF' LIMIT 1];
        update new Facility__c(Id = alpha.Id, TCM__c = false);

        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Require_Facility_TCM__c = true, Business_Timezone__c = TZ
        );
        TCMDailyReadmissionBatch batch =
            new TCMDailyReadmissionBatch(new TCMReportConfig(), false);

        Set<String> selected = new Set<String>();
        for (Facility__c f : locatorFacilities(batch)) {
            selected.add(f.Name);
        }

        System.assert(!selected.contains('Alpha SNF'), 'facility-level TCM gate should apply');
        System.assert(selected.contains('Bravo SNF'), 'selected: ' + selected);
    }

    @IsTest
    static void buildGroupsRowsPerFacilityAndAppliesEveryFilter() {
        // Attachment mode, because this asserts the one-message-with-Cc shape. Link mode
        // deliberately sends one message per recipient and is covered separately.
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Attachment'), false);
        List<Facility__c> facilities = locatorFacilities(batch);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result = batch.buildForFacilities(facilities);
        Test.stopTest();

        Map<String, Messaging.SingleEmailMessage> bySubject =
            new Map<String, Messaging.SingleEmailMessage>();
        for (Messaging.SingleEmailMessage message : result.messages) {
            bySubject.put(message.getSubject(), message);
        }

        System.assertEquals(2, result.messages.size(), 'Alpha and Bravo only: ' + bySubject.keySet());
        System.assertEquals(3, result.rowsReported, 'two Alpha rows plus one Bravo row');

        Messaging.SingleEmailMessage alpha = null;
        Messaging.SingleEmailMessage bravo = null;
        for (Messaging.SingleEmailMessage message : result.messages) {
            if (message.getSubject().contains('Alpha')) {
                alpha = message;
            } else if (message.getSubject().contains('Bravo')) {
                bravo = message;
            }
        }

        System.assertNotEquals(null, alpha, 'subjects: ' + bySubject.keySet());
        System.assertEquals(new List<String>{ 'admin@alpha.com' }, alpha.getToAddresses());
        System.assertEquals(
            new List<String>{ 'internal.cc@luminacare.com' }, alpha.getCcAddresses(),
            'internal CC should be on every message'
        );

        System.assertNotEquals(null, bravo);
        System.assertEquals(
            new List<String>{ 'don@bravo.com' }, bravo.getToAddresses(),
            'Bravo has no Admin_Email__c so DON should be used'
        );
    }

    @IsTest
    static void attachedCsvHoldsOnlyThatFacilityRows() {
        // Attachment mode is the fallback the client can flip to without a deploy, so it
        // must keep working exactly as it did.
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Attachment'), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        for (Messaging.SingleEmailMessage message : result.messages) {
            String csv = message.getFileAttachments()[0].getBody().toString();
            if (message.getSubject().contains('Alpha')) {
                System.assert(csv.contains('Ann Adams'), 'Alpha CSV: ' + csv);
                System.assert(csv.contains('Bob Adams'), 'Alpha CSV: ' + csv);
                System.assert(!csv.contains('Hal Grant'), 'hospice patient must not appear: ' + csv);
                System.assert(!csv.contains('Cal Brown'), 'no cross-facility leakage: ' + csv);
                System.assertEquals(
                    3, csv.split('\r\n').size(), 'header plus two rows: ' + csv
                );
                System.assert(
                    message.getFileAttachments()[0].getFileName().startsWith('Readmissions-Alpha SNF-'),
                    message.getFileAttachments()[0].getFileName()
                );
            } else if (message.getSubject().contains('Bravo')) {
                System.assert(csv.contains('Cal Brown'), 'Bravo CSV: ' + csv);
                System.assert(!csv.contains('Ann Adams'), 'no cross-facility leakage: ' + csv);
            }
        }
    }

    @IsTest
    static void linkModeSendsNoAttachmentAndPublishesOneLinkPerFacility() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Link'), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        // Alpha and Bravo each have a primary address plus the internal Cc, and link mode gives
        // every address its own link, so four messages rather than two.
        System.assertEquals(4, result.messages.size(), 'one message per recipient');
        System.assert(result.failures.isEmpty(), 'link publishing failed: ' + result.failures);

        System.assertEquals(
            2, [SELECT COUNT() FROM ContentVersion],
            'only one stored PDF per facility, shared by that facility links'
        );

        Set<String> urls = new Set<String>();
        Datetime lo = Datetime.now().addHours(71);
        Datetime hi = Datetime.now().addHours(73);
        for (Readmission_Report_Link__c link : [
            SELECT Access_Token_Hash__c, Expires_At__c, Content_Version_Id__c
            FROM Readmission_Report_Link__c
        ]) {
            System.assert(
                link.Expires_At__c > lo && link.Expires_At__c < hi,
                'expiry ~72h: ' + link.Expires_At__c
            );
            System.assertNotEquals(null, link.Content_Version_Id__c);
            urls.add(link.Access_Token_Hash__c);
        }
        System.assertEquals(
            4, urls.size(),
            'every recipient needs a DISTINCT link, otherwise an open cannot be attributed'
        );

        // One attribution row per recipient, naming the address and its role.
        Map<String, Readmission_Report_Link__c> byEmail =
            new Map<String, Readmission_Report_Link__c>();
        for (Readmission_Report_Link__c l : [
            SELECT Recipient_Email__c, Recipient_Role__c, Facility__r.Name
            FROM Readmission_Report_Link__c
        ]) {
            byEmail.put(l.Facility__r.Name + '|' + l.Recipient_Email__c, l);
        }
        System.assertEquals(4, byEmail.size(), 'rows: ' + byEmail.keySet());
        System.assertEquals(
            'Administrator', byEmail.get('Alpha SNF|admin@alpha.com').Recipient_Role__c
        );
        System.assertEquals(
            'Director of Nursing', byEmail.get('Bravo SNF|don@bravo.com').Recipient_Role__c,
            'Bravo falls back to the DON, and the row should say so'
        );
        System.assertEquals(
            'Internal', byEmail.get('Alpha SNF|internal.cc@luminacare.com').Recipient_Role__c
        );

        for (Messaging.SingleEmailMessage message : result.messages) {
            System.assert(
                message.getFileAttachments() == null || message.getFileAttachments().isEmpty(),
                'link mode must never attach the CSV: ' + message.getSubject()
            );
            System.assertEquals(
                1, message.getToAddresses().size(),
                'one recipient per message, so the link stays attributable'
            );
            System.assert(
                message.getCcAddresses() == null || message.getCcAddresses().isEmpty(),
                'no Cc in link mode, which also avoids the 4.5.3 multi-tenant rejection'
            );
            String body = message.getHtmlBody();
            System.assert(body.contains('View report'), body);
            System.assert(body.contains('This link expires on'), body);
            System.assert(body.contains('No patient information is included'), body);
            System.assert(
                body.contains('Reply to this email'),
                'the route to a new link must be in the message: ' + body
            );
            System.assert(
                body.contains('It was issued to ' + message.getToAddresses()[0]),
                'the body should name the address it was issued to: ' + body
            );
            System.assert(
                urls.contains(TCMReadmissionAccessToken.hashToken(unescapeUrl(body).substringAfter('?t='))),
                'body must carry the link that row was issued: ' + body
            );
        }
    }

    /** Pulls the href out of the View report button and un-escapes it. */
    private static String unescapeUrl(String body) {
        Integer hrefStart = body.indexOf('href="') + 6;
        Integer hrefEnd = body.indexOf('"', hrefStart);
        return body.substring(hrefStart, hrefEnd).replace('&amp;', '&');
    }

    @IsTest
    static void linkModeBodyCarriesNoPatientNames() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Link'), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        for (Messaging.SingleEmailMessage message : result.messages) {
            String body = message.getHtmlBody();
            for (String name : new List<String>{ 'Ann Adams', 'Bob Adams', 'Cal Brown', 'Adams', 'Brown' }) {
                System.assert(!body.contains(name), 'PHI leaked into the email body: ' + body);
            }
            System.assert(
                !message.getSubject().contains('Adams') && !message.getSubject().contains('Brown'),
                'PHI leaked into the subject: ' + message.getSubject()
            );
        }
    }

    @IsTest
    static void linkModeFileLandsOnTheFacilityRecord() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Link'), false);
        Facility__c alpha = [SELECT Id FROM Facility__c WHERE Name = 'Alpha SNF' LIMIT 1];

        Test.startTest();
        batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :alpha.Id
        ];
        System.assertEquals(1, links.size(), 'Alpha should hold exactly its own report');
        System.assert(
            links[0].ContentDocument.Title.startsWith('Readmissions-Alpha SNF-'),
            links[0].ContentDocument.Title
        );

        // Link mode publishes a PDF, because the public file viewer previews PDF and not CSV.
        // getContentAsPDF() is a placeholder in tests, so only the file type is asserted here;
        // the row scoping is covered by the controller test and the attachment-mode test.
        ContentVersion cv = [
            SELECT PathOnClient FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId LIMIT 1
        ];
        System.assert(cv.PathOnClient.endsWith('.pdf'), 'link mode must publish a PDF: ' + cv.PathOnClient);
    }

    @IsTest
    static void digestEntriesItemiseEverySend() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Link'), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        System.assertEquals(4, result.sent.size(), 'one digest line per recipient: ' + result.sent);
        String joined = String.join(result.sent, '\n');
        System.assert(
            joined.contains('Alpha SNF (2 row(s)) to admin@alpha.com [Administrator]'),
            'the digest must name the address AND its role: ' + joined
        );
        System.assert(
            joined.contains('Bravo SNF (1 row(s)) to don@bravo.com [Director of Nursing]'), joined
        );
        System.assert(
            joined.contains('to internal.cc@luminacare.com [Internal]'),
            'the internal copy gets its own line and its own link: ' + joined
        );
        System.assert(joined.contains('own link expires'), 'expiry must be listed: ' + joined);
        System.assert(!joined.contains('Charlie'), 'skipped facilities are not sends: ' + joined);
        System.assert(!joined.contains('Adams'), 'no PHI in the digest: ' + joined);
    }

    @IsTest
    static void everyRecipientGetsADifferentLinkSoOpensAreAttributable() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Link'), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        // The same address can appear for more than one facility, and each of those gets its
        // own link, so the key has to be facility plus address rather than address alone.
        Map<String, String> urlByFacilityAndRecipient = new Map<String, String>();
        for (Messaging.SingleEmailMessage m : result.messages) {
            String facility = m.getSubject().contains('Alpha') ? 'Alpha SNF' : 'Bravo SNF';
            urlByFacilityAndRecipient.put(
                facility + '|' + m.getToAddresses()[0], unescapeUrl(m.getHtmlBody())
            );
        }
        System.assertEquals(
            4, urlByFacilityAndRecipient.size(),
            'four facility-and-recipient pairs: ' + urlByFacilityAndRecipient.keySet()
        );

        for (Readmission_Report_Link__c link : [
            SELECT Recipient_Email__c, Access_Token_Hash__c, Facility__r.Name
            FROM Readmission_Report_Link__c
        ]) {
            String key = link.Facility__r.Name + '|' + link.Recipient_Email__c;
            String expected = urlByFacilityAndRecipient.get(key);
            System.assertNotEquals(null, expected, 'no message for ' + key);
            String token = expected.substringAfter('?t=');
            System.assertEquals(
                link.Access_Token_Hash__c, TCMReadmissionAccessToken.hashToken(token),
                'the row for ' + key + ' must be the link that address was emailed'
            );
        }

        // The shared internal address must get a DIFFERENT link for each facility, or one
        // facility's open would be indistinguishable from another's.
        System.assertNotEquals(
            urlByFacilityAndRecipient.get('Alpha SNF|internal.cc@luminacare.com'),
            urlByFacilityAndRecipient.get('Bravo SNF|internal.cc@luminacare.com'),
            'the same person on two facilities needs two links'
        );
    }

    @IsTest
    static void attachmentModeCreatesNoPublicLinks() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Attachment'), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        System.assertEquals(2, result.messages.size());
        System.assertEquals(0, [SELECT COUNT() FROM Readmission_Report_Link__c], 'attachment mode issues no link');
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion], 'and stores no file');
        for (Messaging.SingleEmailMessage message : result.messages) {
            System.assertEquals(1, message.getFileAttachments().size(), 'CSV must be attached');
            System.assert(message.getHtmlBody().contains('attached as a CSV'), message.getHtmlBody());
            System.assert(!message.getHtmlBody().contains('View report'), message.getHtmlBody());
        }
    }

    @IsTest
    static void facilityWithRowsButNoAddressIsSkippedWithAReason() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config(), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        System.assertEquals(1, result.skipped.size(), 'skipped: ' + result.skipped);
        String entry = result.skipped[0];
        System.assert(entry.contains('Charlie SNF'), entry);
        System.assert(entry.contains('1 row(s) unsent'), 'row count should be reported: ' + entry);
        System.assert(entry.contains('No Admin_Email__c or DON_Email__c'), entry);
    }

    @IsTest
    static void facilityWithNoRowsIsNeitherSentNorSkipped() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config(), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        for (Messaging.SingleEmailMessage message : result.messages) {
            System.assert(
                !message.getSubject().contains('Foxtrot'),
                'a facility with no admissions must not be emailed'
            );
        }
        System.assert(
            !String.join(result.skipped, '|').contains('Foxtrot'),
            'and must not clutter the digest either: ' + result.skipped
        );
    }

    @IsTest
    static void sandboxRunGivesEachTesterTheirOwnAttributableLink() {
        // Two testers, so a sandbox run must prove attribution the same way production does.
        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Require_Facility_TCM__c = false, Delivery_Mode__c = 'Link',
            Link_Expiry_Hours__c = 24, Allow_Download__c = true, Max_Opens__c = 0,
            Sandbox_Redirect_Emails__c = 'tester.one@propela.tech; tester.two@propela.tech',
            Subject_Template__c = 'Readmissions Report - {0} - {1}', Business_Timezone__c = TZ
        );
        TCMDailyReadmissionBatch batch =
            new TCMDailyReadmissionBatch(new TCMReportConfig(), true);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        Set<String> delivered = new Set<String>();
        for (Messaging.SingleEmailMessage m : result.messages) {
            System.assertEquals(1, m.getToAddresses().size(), 'one mailbox per message');
            delivered.add(m.getToAddresses()[0]);
        }
        System.assertEquals(
            new Set<String>{ 'tester.one@propela.tech', 'tester.two@propela.tech' }, delivered,
            'no facility address may survive a sandbox run'
        );

        List<Readmission_Report_Link__c> links = [
            SELECT Recipient_Email__c, Recipient_Role__c, Intended_For__c, Facility__r.Name
            FROM Readmission_Report_Link__c WHERE Facility__r.Name = 'Alpha SNF'
            ORDER BY Recipient_Email__c
        ];
        System.assertEquals(2, links.size(), 'one link per tester, so each tester is separable');
        System.assertEquals('tester.one@propela.tech', links[0].Recipient_Email__c);
        System.assertEquals('tester.two@propela.tech', links[1].Recipient_Email__c);
        for (Readmission_Report_Link__c l : links) {
            System.assertEquals(
                'Sandbox Tester', l.Recipient_Role__c,
                'the row must say the open came from a tester, not an administrator'
            );
            System.assert(
                l.Intended_For__c.contains('admin@alpha.com'),
                'and must still name the real facility contact: ' + l.Intended_For__c
            );
        }
    }

    @IsTest
    static void sandboxRunRedirectsEveryMessage() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config('Attachment'), true);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        System.assert(result.redirected, 'should be flagged as a redirected run');
        for (Messaging.SingleEmailMessage message : result.messages) {
            System.assertEquals(
                new List<String>{ 'sandbox@propela.tech' }, message.getToAddresses(),
                'no facility address may survive a sandbox run'
            );
            System.assert(
                message.getHtmlBody().contains('Sandbox run'),
                'the body should say so: ' + message.getHtmlBody()
            );
        }
    }

    @IsTest
    static void sandboxDigestGoesOnlyToTheRedirectAddress() {
        TCMReportConfig cfg = config();

        TCMDailyReadmissionBatch prodRun = new TCMDailyReadmissionBatch(cfg, false);
        System.assertEquals(
            new List<String>{ 'digest@propela.tech' }, prodRun.digestRecipientsFor(cfg),
            'production sends the digest to the configured list'
        );

        TCMDailyReadmissionBatch sandboxRun = new TCMDailyReadmissionBatch(cfg, true);
        System.assertEquals(
            new List<String>{ 'sandbox@propela.tech' }, sandboxRun.digestRecipientsFor(cfg),
            'a sandbox run must never email the digest list, which holds client addresses'
        );

        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Digest_Recipients__c = 'digest@propela.tech', Business_Timezone__c = TZ
        );
        TCMReportConfig noRedirect = new TCMReportConfig();
        System.assert(
            new TCMDailyReadmissionBatch(noRedirect, true).digestRecipientsFor(noRedirect).isEmpty(),
            'no redirect configured means the sandbox digest is dropped, not sent to clients'
        );

        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Business_Timezone__c = TZ,
            Digest_Recipients__c = 'digest@propela.tech',
            Sandbox_Redirect_Email__c = 'One@Example.com; two@example.com, one@example.com'
        );
        TCMReportConfig twoTesters = new TCMReportConfig();
        System.assertEquals(
            new List<String>{ 'one@example.com', 'two@example.com' },
            new TCMDailyReadmissionBatch(twoTesters, true).digestRecipientsFor(twoTesters),
            'redirect accepts a separated list, lowercased and de-duplicated, like the resolver'
        );
    }

    @IsTest
    static void emptyChunkIsHandled() {
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(config(), false);

        TCMDailyReadmissionBatch.ChunkResult empty = batch.buildForFacilities(new List<Facility__c>());
        System.assert(empty.messages.isEmpty());
        System.assert(empty.skipped.isEmpty());

        System.assert(batch.buildForFacilities(null).messages.isEmpty(), 'null must not throw');
    }

    @IsTest
    static void fullBatchRunPublishesLinksAndSendsMail() {
        config();

        Test.startTest();
        Database.executeBatch(new TCMDailyReadmissionBatch(config(), false), 25);
        Test.stopTest();

        // The previous version of this test asserted only that an email count was at least
        // zero, which cannot fail. Email invocations belong to the batch's own transactions and
        // are not visible from here, so the assertions below are on what the run left behind.
        Map<String, List<Readmission_Report_Link__c>> byFacility =
            new Map<String, List<Readmission_Report_Link__c>>();
        for (Readmission_Report_Link__c link : [
            SELECT Recipient_Email__c, Recipient_Role__c, Report_Date__c, Expires_At__c,
                   Opens__c, Facility__r.Name
            FROM Readmission_Report_Link__c
        ]) {
            String name = link.Facility__r.Name;
            if (!byFacility.containsKey(name)) {
                byFacility.put(name, new List<Readmission_Report_Link__c>());
            }
            byFacility.get(name).add(link);
        }

        System.assert(
            byFacility.containsKey('Alpha SNF'),
            'the addressable facility with admissions got links: ' + byFacility.keySet()
        );
        System.assert(
            !byFacility.containsKey('Charlie SNF'),
            'the facility with no address must get no link at all'
        );
        System.assert(
            !byFacility.containsKey('Foxtrot SNF'),
            'and neither must a facility with no admissions in the window'
        );

        Set<String> alphaRecipients = new Set<String>();
        for (Readmission_Report_Link__c link : byFacility.get('Alpha SNF')) {
            alphaRecipients.add(link.Recipient_Email__c);
            System.assertEquals(0, link.Opens__c, 'a freshly issued link starts unopened');
            System.assertNotEquals(null, link.Expires_At__c, 'and carries its expiry');
            System.assertEquals(
                new TCMReadmissionWindow(TZ).lastCoveredDate(), link.Report_Date__c
            );
        }
        System.assertEquals(
            new Set<String>{ 'admin@alpha.com', 'internal.cc@luminacare.com' },
            alphaRecipients,
            'one link per deliverable address, administrator and internal copy'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Readmission_Report_Link__c WHERE Access_Token_Hash__c = null],
            'every row is a working link with a token behind it'
        );
    }

    @IsTest
    static void schedulerHonoursTheKillSwitch() {
        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = false, Business_Timezone__c = TZ
        );

        Test.startTest();
        new TCMDailyReadmissionScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'TCMDailyReadmissionBatch'],
            'an inactive config must not enqueue the batch'
        );
    }

    @IsTest
    static void schedulerEnqueuesTheBatchWhenActive() {
        config();

        Test.startTest();
        new TCMDailyReadmissionScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'TCMDailyReadmissionBatch'],
            'an active config should enqueue exactly one batch'
        );
    }

    @IsTest
    static void thePatientClassFilterDropsRowsThatAreNotInpatient() {
        // Alpha has two qualifying rows in the window. Class one of them Inpatient and the
        // other Emergency only, then require Inpatient.
        TCMReadmissionWindow w = window();
        Datetime startUtc = w.startUtc;
        Datetime endUtc = w.endUtc;
        List<Hospital_Admission__c> alpha = [
            SELECT Id FROM Hospital_Admission__c
            WHERE Patient__r.Facility__r.Name = 'Alpha SNF'
              AND Was_Discharged_Home_From_SNF__c = true
              AND Patient__r.Hospice__c = false
              AND Admit_DateTime__c >= :startUtc
              AND Admit_DateTime__c < :endUtc
            ORDER BY Id
        ];
        System.assertEquals(2, alpha.size(), 'the fixture should give Alpha two rows');
        alpha[0].Patient_Class__c = 'Emergency, Inpatient';
        alpha[1].Patient_Class__c = 'Emergency, Observation';
        update alpha;

        config('Link');
        TCMReportConfig.overrideRecord.Required_Patient_Class__c = 'Inpatient';
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(new TCMReportConfig(), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        Boolean sawAlpha = false;
        for (String line : result.sent) {
            System.assert(!line.startsWith('Bravo SNF'), 'Bravo has no Inpatient row: ' + line);
            if (line.startsWith('Alpha SNF')) {
                sawAlpha = true;
                System.assert(
                    line.contains('(1 row(s))'),
                    'only the Inpatient row should be reported: ' + line
                );
            }
        }
        System.assert(sawAlpha, 'Alpha should still be emailed: ' + result.sent);
        System.assertEquals(1, result.rowsReported, 'one row across the whole run');
    }

    @IsTest
    static void anUnclassedRowIsDroppedWhenAClassIsRequired() {
        TCMReportConfig cfg = config('Link');
        TCMReportConfig.overrideRecord.Required_Patient_Class__c = 'Inpatient';
        TCMDailyReadmissionBatch batch = new TCMDailyReadmissionBatch(new TCMReportConfig(), false);

        Test.startTest();
        TCMDailyReadmissionBatch.ChunkResult result =
            batch.buildForFacilities(locatorFacilities(batch));
        Test.stopTest();

        // Nothing in the fixture carries a Patient Class, so requiring one empties the run.
        System.assertEquals(0, result.messages.size(), 'no facility has an Inpatient row');
        System.assertEquals(0, result.rowsReported);
        System.assert(result.skipped.isEmpty(), 'and a facility with no rows is not a skip');
    }

    @IsTest
    static void theDigestNamesTheClinicalScope() {
        TCMReportConfig cfg = config('Link');
        TCMReportConfig.overrideRecord.Required_Patient_Class__c = 'Inpatient';

        System.assertEquals(
            'Discharged home from the facility, not on hospice, patient class contains "Inpatient".',
            TCMReadmissionAdmissionScope.describe(new TCMReportConfig()),
            'the run digest should say which rows were counted'
        );
    }
}