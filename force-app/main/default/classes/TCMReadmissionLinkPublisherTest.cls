/**
 * Publisher behaviour: one file per facility, one row and one distinct site link per
 * recipient, the raw token nowhere but the URL, superseding of the previous link to the same
 * address, and a request that cannot be published comes back as a failure rather than a
 * thrown exception.
 */
@IsTest
private class TCMReadmissionLinkPublisherTest {

    private static final String BASE = 'https://portal.example/report';

    private static TCMReportConfig config(Integer hours) {
        TCMReadmissionPortal.baseUrlOverride = BASE;
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true,
            Delivery_Mode__c = 'Link',
            Link_Expiry_Hours__c = hours,
            Allow_Download__c = true,
            Max_Opens__c = 0,
            Business_Timezone__c = 'America/New_York'
        );
        return new TCMReportConfig();
    }

    private static List<Facility__c> facilities(Integer count) {
        Account parent = new Account(Name = 'Parent', TCM__c = true);
        insert parent;
        List<Facility__c> out = new List<Facility__c>();
        for (Integer i = 0; i < count; i++) {
            out.add(new Facility__c(
                Name = 'Facility ' + i, Parent_Company__c = parent.Id,
                Admin_Email__c = 'admin' + i + '@example.com', TCM__c = true,
                Exclude_from_TCM_Reporting__c = false
            ));
        }
        insert out;
        return [SELECT Id, Name, Admin_Email__c FROM Facility__c WHERE Id IN :out ORDER BY Name];
    }

    private static TCMReadmissionLinkPublisher.Request request(Facility__c f) {
        TCMReadmissionLinkPublisher.Request r = new TCMReadmissionLinkPublisher.Request(
            f.Id, f.Name, 'Readmissions-' + f.Name + '-2026-09-07.pdf',
            Blob.valueOf('%PDF-1.4 placeholder'),
            Date.newInstance(2026, 9, 7)
        );
        r.recipients.add(new TCMReadmissionLinkPublisher.Recipient(
            f.Admin_Email__c, 'Administrator'
        ));
        return r;
    }

    private static Map<Id, TCMReadmissionLinkPublisher.Published> publish(
        TCMReportConfig cfg, List<TCMReadmissionLinkPublisher.Request> requests
    ) {
        return new TCMReadmissionLinkPublisher(cfg).publish(requests);
    }

    @IsTest
    static void publishesOneRowAndOneDistinctLinkPerRecipient() {
        List<Facility__c> fs = facilities(2);

        Test.startTest();
        Map<Id, TCMReadmissionLinkPublisher.Published> out = publish(
            config(48), new List<TCMReadmissionLinkPublisher.Request>{ request(fs[0]), request(fs[1]) }
        );
        Test.stopTest();

        System.assertEquals(2, out.size());
        Set<String> urls = new Set<String>();
        for (Facility__c f : fs) {
            TCMReadmissionLinkPublisher.Published p = out.get(f.Id);
            System.assertNotEquals(null, p, 'every request gets an entry');
            System.assertEquals(null, p.failure, 'failure: ' + p.failure);
            System.assert(p.hasAnyUsable(), 'should have a usable link');
            TCMReadmissionLinkPublisher.Issued issued = p.byEmail.get(f.Admin_Email__c);
            System.assertNotEquals(null, issued, 'link for ' + f.Admin_Email__c);
            System.assert(issued.publicUrl.startsWith(BASE + '?t='), issued.publicUrl);
            System.assertNotEquals(null, issued.linkId);
            urls.add(issued.publicUrl);

            // The URL carries the raw token; the row carries only its hash.
            String token = issued.publicUrl.substringAfter('?t=');
            System.assert(TCMReadmissionAccessToken.looksLikeToken(token), token);
            Readmission_Report_Link__c row = [
                SELECT Access_Token_Hash__c, Content_Version_Id__c, Expires_At__c, Opens__c,
                       Downloads__c, Codes_Sent__c, Failed_Attempts__c, Code_Hash__c,
                       Recipient_Email__c, Recipient_Role__c, Intended_For__c, Report_Date__c,
                       Facility__c
                FROM Readmission_Report_Link__c WHERE Id = :issued.linkId
            ];
            System.assertEquals(TCMReadmissionAccessToken.hashToken(token), row.Access_Token_Hash__c);
            System.assertNotEquals(token, row.Access_Token_Hash__c, 'the token is never stored');
            System.assertEquals(String.valueOf(p.contentVersionId), row.Content_Version_Id__c);
            System.assertEquals(f.Id, row.Facility__c);
            System.assertEquals(f.Admin_Email__c, row.Recipient_Email__c);
            System.assertEquals('Administrator', row.Recipient_Role__c);
            System.assertEquals(f.Admin_Email__c, row.Intended_For__c);
            System.assertEquals(Date.newInstance(2026, 9, 7), row.Report_Date__c);
            System.assertEquals(0, row.Opens__c);
            System.assertEquals(0, row.Downloads__c);
            System.assertEquals(0, row.Codes_Sent__c);
            System.assertEquals(0, row.Failed_Attempts__c);
            System.assertEquals(null, row.Code_Hash__c, 'no code until one is asked for');
            System.assert(
                row.Expires_At__c > Datetime.now().addHours(47)
                    && row.Expires_At__c < Datetime.now().addHours(49),
                'expiry ~48h: ' + row.Expires_At__c
            );
            System.assertEquals(row.Expires_At__c, issued.expiresAt);
        }
        System.assertEquals(2, urls.size(), 'distinct links');
        System.assertEquals(2, [SELECT COUNT() FROM ContentVersion], 'one file per facility');
    }

    @IsTest
    static void fileIsParkedOnTheFacilityRecordAndSharedByItsRecipients() {
        Facility__c f = facilities(1)[0];
        TCMReadmissionLinkPublisher.Request r = request(f);
        r.recipients.add(new TCMReadmissionLinkPublisher.Recipient('don@example.com', 'Director of Nursing'));

        Test.startTest();
        TCMReadmissionLinkPublisher.Published p = publish(
            config(72), new List<TCMReadmissionLinkPublisher.Request>{ r }
        ).get(f.Id);
        Test.stopTest();

        System.assert(p.hasAnyUsable(), p.failure);
        System.assertEquals(2, p.byEmail.size());
        System.assertNotEquals(
            p.byEmail.get(f.Admin_Email__c).publicUrl, p.byEmail.get('don@example.com').publicUrl,
            'each recipient must get a DIFFERENT url, or attribution is impossible'
        );

        ContentVersion cv = [
            SELECT Id, Title, PathOnClient, ContentDocumentId
            FROM ContentVersion WHERE Id = :p.contentVersionId
        ];
        System.assertEquals('Readmissions-Facility 0-2026-09-07', cv.Title, 'title drops .pdf');
        System.assert(cv.PathOnClient.endsWith('.pdf'), cv.PathOnClient);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDocumentLink
             WHERE ContentDocumentId = :cv.ContentDocumentId AND LinkedEntityId = :f.Id],
            'file must be linked to the facility'
        );
        System.assertEquals(1, [SELECT COUNT() FROM ContentVersion], 'the PDF is stored once');
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Readmission_Report_Link__c WHERE Content_Version_Id__c = :cv.Id],
            'both rows point at it'
        );
    }

    @IsTest
    static void aStoredVersionIsReusedRatherThanStoredAgain() {
        Facility__c f = facilities(1)[0];
        ContentVersion existing = new ContentVersion(
            Title = 'Readmissions-Facility 0-2026-09-07', PathOnClient = 'x.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 stored'), FirstPublishLocationId = f.Id
        );
        insert existing;
        TCMReadmissionLinkPublisher.Request r = new TCMReadmissionLinkPublisher.Request(
            f.Id, f.Name, 'Readmissions-Facility 0-2026-09-07.pdf', null, Date.newInstance(2026, 9, 7)
        );
        r.existingContentVersionId = existing.Id;
        r.recipients.add(new TCMReadmissionLinkPublisher.Recipient(f.Admin_Email__c, 'Administrator'));

        Test.startTest();
        TCMReadmissionLinkPublisher.Published p = publish(
            config(24), new List<TCMReadmissionLinkPublisher.Request>{ r }
        ).get(f.Id);
        Test.stopTest();

        System.assert(p.hasAnyUsable(), p.failure);
        System.assertEquals(existing.Id, p.contentVersionId);
        System.assertEquals(1, [SELECT COUNT() FROM ContentVersion], 'nothing new stored');
        System.assertEquals(
            String.valueOf(existing.Id),
            [SELECT Content_Version_Id__c FROM Readmission_Report_Link__c LIMIT 1].Content_Version_Id__c
        );
    }

    @IsTest
    static void reissuingToTheSameAddressSupersedesThePreviousLiveLink() {
        List<Facility__c> fs = facilities(2);
        TCMReportConfig cfg = config(24);
        // Same person on both facilities: only the reissued facility's link may be closed.
        TCMReadmissionLinkPublisher.Request first = request(fs[0]);
        first.recipients[0] = new TCMReadmissionLinkPublisher.Recipient('shared@example.com', 'Internal');
        TCMReadmissionLinkPublisher.Request other = request(fs[1]);
        other.recipients[0] = new TCMReadmissionLinkPublisher.Recipient('shared@example.com', 'Internal');
        publish(cfg, new List<TCMReadmissionLinkPublisher.Request>{ first, other });
        Id firstRow = [
            SELECT Id FROM Readmission_Report_Link__c WHERE Facility__c = :fs[0].Id
        ].Id;
        // The old link was mid-flight: a code out and an unlock open. Both must die with it.
        update new Readmission_Report_Link__c(
            Id = firstRow, Code_Hash__c = 'x', Code_Expires_At__c = Datetime.now().addMinutes(5),
            Unlocked_Until__c = Datetime.now().addMinutes(5)
        );

        Test.startTest();
        TCMReadmissionLinkPublisher.Request again = request(fs[0]);
        again.recipients[0] = new TCMReadmissionLinkPublisher.Recipient('shared@example.com', 'Internal');
        TCMReadmissionLinkPublisher.Published p = publish(
            cfg, new List<TCMReadmissionLinkPublisher.Request>{ again }
        ).get(fs[0].Id);
        Test.stopTest();

        System.assert(p.hasAnyUsable(), p.failure);
        System.assertEquals(null, p.failure);
        Readmission_Report_Link__c old = [
            SELECT Closed_Reason__c, Closed_At__c, Code_Hash__c, Code_Expires_At__c, Unlocked_Until__c
            FROM Readmission_Report_Link__c WHERE Id = :firstRow
        ];
        System.assertEquals('Superseded', old.Closed_Reason__c);
        System.assertNotEquals(null, old.Closed_At__c);
        System.assertEquals(null, old.Code_Hash__c);
        System.assertEquals(null, old.Code_Expires_At__c);
        System.assertEquals(null, old.Unlocked_Until__c);

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Readmission_Report_Link__c
             WHERE Facility__c = :fs[0].Id AND Closed_Reason__c = null],
            'exactly one live link for that facility and address'
        );
        System.assertEquals(
            null,
            [SELECT Closed_Reason__c FROM Readmission_Report_Link__c WHERE Facility__c = :fs[1].Id]
                .Closed_Reason__c,
            'the same address on another facility is untouched'
        );
        System.assertEquals(
            3, [SELECT COUNT() FROM Readmission_Report_Link__c],
            'rows are closed, never deleted'
        );
    }

    @IsTest
    static void aReissueLeavesAnAlreadyDeadLinkAlone() {
        Facility__c f = facilities(1)[0];
        TCMReportConfig cfg = config(24);
        publish(cfg, new List<TCMReadmissionLinkPublisher.Request>{ request(f) });
        Readmission_Report_Link__c dead = [SELECT Id FROM Readmission_Report_Link__c];
        dead.Closed_Reason__c = 'Locked';
        dead.Closed_At__c = Datetime.now().addHours(-1);
        update dead;

        publish(cfg, new List<TCMReadmissionLinkPublisher.Request>{ request(f) });

        System.assertEquals(
            'Locked',
            [SELECT Closed_Reason__c FROM Readmission_Report_Link__c WHERE Id = :dead.Id].Closed_Reason__c,
            'a locked link keeps its reason; it is not relabelled Superseded'
        );
    }

    @IsTest
    static void noSiteMeansNoLinksAndNoFile() {
        Facility__c f = facilities(1)[0];
        TCMReportConfig cfg = config(24);
        TCMReadmissionPortal.baseUrlOverride = '';

        Test.startTest();
        TCMReadmissionLinkPublisher.Published p = publish(
            cfg, new List<TCMReadmissionLinkPublisher.Request>{ request(f) }
        ).get(f.Id);
        Test.stopTest();

        System.assertNotEquals(null, p);
        System.assert(!p.hasAnyUsable(), 'nothing usable');
        System.assert(p.failure.contains('TCM_Readmission_Portal'), p.failure);
        System.assert(p.byEmail.isEmpty(), 'no recipient was issued anything');
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion], 'nothing stored either');
        System.assertEquals(0, [SELECT COUNT() FROM Readmission_Report_Link__c]);
    }

    @IsTest
    static void emptyAndNullInputsReturnEmpty() {
        TCMReadmissionLinkPublisher publisher = new TCMReadmissionLinkPublisher(config(72));
        System.assert(publisher.publish(null).isEmpty());
        System.assert(publisher.publish(new List<TCMReadmissionLinkPublisher.Request>()).isEmpty());
    }

    @IsTest
    static void blankAndDuplicateAddressesAreSkipped() {
        Facility__c f = facilities(1)[0];
        TCMReadmissionLinkPublisher.Request r = request(f);
        r.recipients.add(new TCMReadmissionLinkPublisher.Recipient(' ', 'Internal'));
        r.recipients.add(new TCMReadmissionLinkPublisher.Recipient(null, 'Internal'));
        r.recipients.add(new TCMReadmissionLinkPublisher.Recipient(f.Admin_Email__c.toUpperCase(), 'Internal'));

        TCMReadmissionLinkPublisher.Published p = publish(
            config(24), new List<TCMReadmissionLinkPublisher.Request>{ r }
        ).get(f.Id);

        System.assertEquals(1, p.byEmail.size(), 'one link for the one real address');
        System.assertEquals(1, [SELECT COUNT() FROM Readmission_Report_Link__c]);
    }

    @IsTest
    static void unstorableFileIsReportedNotThrown() {
        Facility__c f = facilities(1)[0];
        // A ContentVersion with no VersionData cannot be inserted. The publisher must record
        // that on the outcome and keep going rather than surface an exception to the batch.
        TCMReadmissionLinkPublisher.Request bad = new TCMReadmissionLinkPublisher.Request(
            f.Id, f.Name, 'bad.pdf', null, Date.today()
        );
        bad.recipients.add(new TCMReadmissionLinkPublisher.Recipient('x@example.com', 'Internal'));

        Test.startTest();
        TCMReadmissionLinkPublisher.Published p = publish(
            config(72), new List<TCMReadmissionLinkPublisher.Request>{ bad }
        ).get(f.Id);
        Test.stopTest();

        System.assertNotEquals(null, p);
        System.assert(!p.hasAnyUsable(), 'must not be usable');
        System.assert(p.failure.startsWith('File could not be stored'), p.failure);
        System.assertEquals(0, [SELECT COUNT() FROM Readmission_Report_Link__c], 'no orphan link');
    }

    @IsTest
    static void expiryFallsBackTo72HoursWhenUnset() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Business_Timezone__c = 'America/New_York'
        );
        TCMReportConfig cfg = new TCMReportConfig();
        System.assertEquals(72, cfg.linkExpiryHours());
        System.assert(cfg.deliverAsLink(), 'blank mode means Link');
        System.assertEquals(null, cfg.portalBaseUrl(), 'blank means derive from the org');

        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Delivery_Mode__c = 'Attachment', Link_Expiry_Hours__c = 0
        );
        cfg = new TCMReportConfig();
        System.assertEquals(72, cfg.linkExpiryHours(), 'zero is not a valid lifetime');
        System.assert(!cfg.deliverAsLink());
    }
}