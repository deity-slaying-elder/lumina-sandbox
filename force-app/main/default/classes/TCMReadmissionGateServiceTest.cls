/**
 * The report site's rules, end to end against real rows: what a bad token gets, how a code is
 * issued and checked, the lockouts, the open cap, the unlock window, and the PDF stream. Also
 * drives the page controller and the REST endpoint, and runs the flow as the site's guest
 * user when the site exists in the org.
 */
@IsTest
private class TCMReadmissionGateServiceTest {

    private static final String TZ = 'America/New_York';
    private static final String TESTER = 'tester@propela.example';

    private static TCMReportConfig config(Integer maxOpens, Boolean download) {
        TCMReadmissionGateService.sandboxOverride = false;
        TCMReadmissionPortal.baseUrlOverride = 'https://portal.example/report';
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Delivery_Mode__c = 'Link', Link_Expiry_Hours__c = 24,
            Allow_Download__c = download, Max_Opens__c = maxOpens,
            Sandbox_Redirect_Emails__c = TESTER,
            Business_Timezone__c = TZ
        );
        return new TCMReportConfig();
    }

    /** A facility, a stored PDF on it, and one live link row whose raw token we know. */
    private class Fixture {
        Facility__c facility;
        Id versionId;
        Id documentId;
        String token;
        Id linkId;
    }

    private static Fixture fixture(String recipient) {
        Fixture f = new Fixture();
        Account parent = new Account(Name = 'Parent', TCM__c = true);
        insert parent;
        f.facility = new Facility__c(
            Name = 'Gate Facility', Parent_Company__c = parent.Id,
            Admin_Email__c = recipient, TCM__c = true, Exclude_from_TCM_Reporting__c = false
        );
        insert f.facility;

        ContentVersion version = new ContentVersion(
            Title = 'Readmissions-Gate Facility-2026-09-14',
            PathOnClient = 'Readmissions-Gate Facility-2026-09-14.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 gate placeholder'),
            FirstPublishLocationId = f.facility.Id
        );
        insert version;
        f.versionId = version.Id;
        f.documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id]
            .ContentDocumentId;

        f.token = TCMReadmissionAccessToken.mintToken();
        Readmission_Report_Link__c row = new Readmission_Report_Link__c(
            Facility__c = f.facility.Id,
            Recipient_Email__c = recipient,
            Recipient_Role__c = 'Administrator',
            Intended_For__c = recipient,
            Content_Version_Id__c = version.Id,
            Access_Token_Hash__c = TCMReadmissionAccessToken.hashToken(f.token),
            Report_Date__c = Date.newInstance(2026, 9, 14),
            Expires_At__c = Datetime.now().addHours(24),
            Opens__c = 0, Downloads__c = 0, Codes_Sent__c = 0, Failed_Attempts__c = 0
        );
        insert row;
        f.linkId = row.Id;
        return f;
    }

    private static Readmission_Report_Link__c row(Id linkId) {
        return [
            SELECT Id, Opens__c, Downloads__c, Codes_Sent__c, Failed_Attempts__c, Code_Hash__c,
                   Code_Expires_At__c, Code_Sent_At__c, Unlocked_Until__c, Closed_Reason__c,
                   Closed_At__c, First_Opened_At__c, Last_Activity_At__c, Expires_At__c
            FROM Readmission_Report_Link__c WHERE Id = :linkId
        ];
    }

    private static void set(Id linkId, Readmission_Report_Link__c changes) {
        changes.Id = linkId;
        update changes;
    }

    /** Requests a code with a known value and returns the outcome. */
    private static TCMReadmissionGateService.Outcome issueCode(String token, String code) {
        TCMReadmissionGateService.codeOverride = code;
        return TCMReadmissionGateService.requestCode(token);
    }

    // ---- refusals -------------------------------------------------------------------------

    @IsTest
    static void aBadTokenGetsTheGenericAnswerAndWritesNothing() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        String garbage = 'z'.repeat(64);
        String wellFormedButUnknown = TCMReadmissionAccessToken.mintToken();

        Test.startTest();
        for (String bad : new List<String>{ null, '', 'abc', garbage, wellFormedButUnknown }) {
            TCMReadmissionGateService.Outcome look = TCMReadmissionGateService.look(bad);
            System.assertEquals(TCMReadmissionGateService.STATUS_UNAVAILABLE, look.status);
            System.assertEquals(TCMReadmissionGateService.UNAVAILABLE_MESSAGE, look.message);
            System.assertEquals(null, look.facilityName, 'no facility name for a stranger');
            System.assertEquals(
                TCMReadmissionGateService.STATUS_UNAVAILABLE,
                TCMReadmissionGateService.requestCode(bad).status
            );
            System.assertEquals(
                TCMReadmissionGateService.STATUS_UNAVAILABLE,
                TCMReadmissionGateService.verify(bad, '123456').status
            );
            System.assertEquals(null, TCMReadmissionGateService.serve(bad, false));
        }
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(0, emails, 'no code mailed to anyone');
        System.assertEquals(0, row(f.linkId).Codes_Sent__c, 'the real row is untouched');
    }

    @IsTest
    static void anExpiredOrClosedLinkLooksExactlyLikeABadOne() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        TCMReadmissionGateService.Outcome stranger =
            TCMReadmissionGateService.look(TCMReadmissionAccessToken.mintToken());

        set(f.linkId, new Readmission_Report_Link__c(
            Expires_At__c = Datetime.now().addMinutes(-1)
        ));
        TCMReadmissionGateService.Outcome expired = TCMReadmissionGateService.look(f.token);

        set(f.linkId, new Readmission_Report_Link__c(
            Expires_At__c = Datetime.now().addHours(1), Closed_Reason__c = 'Superseded'
        ));
        TCMReadmissionGateService.Outcome closed = TCMReadmissionGateService.look(f.token);

        for (TCMReadmissionGateService.Outcome o :
            new List<TCMReadmissionGateService.Outcome>{ expired, closed }) {
            System.assertEquals(stranger.status, o.status);
            System.assertEquals(stranger.message, o.message);
            System.assertEquals(stranger.facilityName, o.facilityName);
            System.assertEquals(stranger.maskedEmail, o.maskedEmail);
        }
        System.assertEquals(null, TCMReadmissionGateService.serve(f.token, false));
    }

    // ---- requesting a code ----------------------------------------------------------------

    @IsTest
    static void aLiveLinkStartsAtRequestAndShowsOnlyTheFacilityAndAMaskedAddress() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');

        TCMReadmissionGateService.Outcome look = TCMReadmissionGateService.look(f.token);

        System.assertEquals(TCMReadmissionGateService.STATUS_REQUEST, look.status);
        System.assertEquals('Gate Facility', look.facilityName);
        System.assertEquals('a***@gate.example', look.maskedEmail);
        System.assertEquals(Date.newInstance(2026, 9, 14), look.reportDate);
        System.assertEquals(true, look.downloadAllowed);
        System.assertEquals(null, look.error);
    }

    @IsTest
    static void requestingACodeEmailsTheAddressOnTheRowAndStoresOnlyItsHash() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        Datetime before = Datetime.now();

        Test.startTest();
        TCMReadmissionGateService.Outcome outcome = issueCode(f.token, '123456');
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_VERIFY, outcome.status, '' + outcome.error);
        System.assert(outcome.message.contains('a***@gate.example'), '' + outcome.message);
        System.assert(outcome.message.contains('10 minutes'), '' + outcome.message);
        System.assertEquals(1, emails, 'one code email');

        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals(1, saved.Codes_Sent__c);
        System.assertEquals(
            TCMReadmissionAccessToken.hashCode(f.token, '123456'), saved.Code_Hash__c,
            'the hash, salted with the token'
        );
        System.assertNotEquals('123456', saved.Code_Hash__c, 'never the code itself');
        System.assert(
            saved.Code_Expires_At__c >= before.addMinutes(9)
                && saved.Code_Expires_At__c <= Datetime.now().addMinutes(11),
            'ten minutes: ' + saved.Code_Expires_At__c
        );
        System.assertNotEquals(null, saved.Code_Sent_At__c);
        System.assertEquals(0, saved.Opens__c, 'asking for a code is not an open');

        // A second look now lands on the code form rather than the request button.
        System.assertEquals(
            TCMReadmissionGateService.STATUS_VERIFY, TCMReadmissionGateService.look(f.token).status
        );
    }

    @IsTest
    static void aSecondCodeInsideAMinuteIsRefusedWithoutSending() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');

        Test.startTest();
        issueCode(f.token, '111111');
        TCMReadmissionGateService.Outcome again = issueCode(f.token, '222222');
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_VERIFY, again.status);
        System.assert(again.message.contains('less than a minute'), '' + again.message);
        System.assertEquals(1, emails, 'only the first was mailed');
        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals(1, saved.Codes_Sent__c);
        System.assertEquals(
            TCMReadmissionAccessToken.hashCode(f.token, '111111'), saved.Code_Hash__c,
            'the first code still stands'
        );
    }

    @IsTest
    static void aNewCodeAfterAMinuteReplacesTheOldOne() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '111111');
        set(f.linkId, new Readmission_Report_Link__c(
            Code_Sent_At__c = Datetime.now().addSeconds(-61)
        ));

        Test.startTest();
        TCMReadmissionGateService.Outcome again = issueCode(f.token, '222222');
        TCMReadmissionGateService.Outcome oldCode =
            TCMReadmissionGateService.verify(f.token, '111111');
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_VERIFY, again.status);
        System.assertEquals(2, row(f.linkId).Codes_Sent__c);
        System.assertEquals(TCMReadmissionGateService.STATUS_VERIFY, oldCode.status);
        System.assert(oldCode.error.contains('not right'), 'the replaced code is dead: ' + oldCode.error);
        System.assertEquals(
            TCMReadmissionGateService.STATUS_REPORT,
            TCMReadmissionGateService.verify(f.token, '222222').status,
            'the new one works'
        );
    }

    @IsTest
    static void theSixthCodeRequestLocksTheLink() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        set(f.linkId, new Readmission_Report_Link__c(
            Codes_Sent__c = TCMReadmissionGateService.MAX_CODES,
            Code_Sent_At__c = Datetime.now().addMinutes(-5)
        ));

        Test.startTest();
        TCMReadmissionGateService.Outcome outcome = issueCode(f.token, '123456');
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_UNAVAILABLE, outcome.status);
        System.assertEquals(0, emails, 'nothing sent');
        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals('Locked', saved.Closed_Reason__c);
        System.assertNotEquals(null, saved.Closed_At__c);
        System.assertEquals(null, saved.Code_Hash__c, 'no code left behind');
    }

    @IsTest
    static void aSandboxRefusesToMailAnAddressOffItsRedirectList() {
        config(10, true);
        TCMReadmissionGateService.sandboxOverride = true;
        Fixture real = fixture('admin@gate.example');

        Test.startTest();
        TCMReadmissionGateService.Outcome refused = issueCode(real.token, '123456');
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_REQUEST, refused.status);
        System.assert(refused.error.contains('sandbox'), '' + refused.error);
        System.assertEquals(0, emails, 'a sandbox never mails a facility');
        System.assertEquals(0, row(real.linkId).Codes_Sent__c);
    }

    @IsTest
    static void aSandboxMailsATesterOnTheRedirectList() {
        config(10, true);
        TCMReadmissionGateService.sandboxOverride = true;
        Fixture tester = fixture(TESTER);

        Test.startTest();
        TCMReadmissionGateService.Outcome sent = issueCode(tester.token, '123456');
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_VERIFY, sent.status, '' + sent.error);
        System.assertEquals(1, emails);
    }

    // ---- checking a code ------------------------------------------------------------------

    @IsTest
    static void aWrongCodeCountsAStrikeAndTheFifthLocksTheLink() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '123456');

        Test.startTest();
        for (Integer attempt = 1; attempt < TCMReadmissionGateService.MAX_FAILED_ATTEMPTS; attempt++) {
            TCMReadmissionGateService.Outcome wrong =
                TCMReadmissionGateService.verify(f.token, '000000');
            System.assertEquals(TCMReadmissionGateService.STATUS_VERIFY, wrong.status);
            System.assertEquals(
                TCMReadmissionGateService.MAX_FAILED_ATTEMPTS - attempt, wrong.attemptsLeft
            );
            System.assert(wrong.error.contains(wrong.attemptsLeft + ' attempt'), '' + wrong.error);
            System.assertEquals(attempt, row(f.linkId).Failed_Attempts__c);
        }
        TCMReadmissionGateService.Outcome fifth = TCMReadmissionGateService.verify(f.token, '000000');
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_UNAVAILABLE, fifth.status);
        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals('Locked', saved.Closed_Reason__c);
        System.assertEquals(0, saved.Opens__c, 'never opened');
        System.assertEquals(
            TCMReadmissionGateService.STATUS_UNAVAILABLE,
            TCMReadmissionGateService.verify(f.token, '123456').status,
            'the right code no longer helps once locked'
        );
    }

    @IsTest
    static void strikesCarryAcrossCodesSoANewCodeIsNotAFreshStart() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '123456');
        for (Integer i = 0; i < 3; i++) {
            TCMReadmissionGateService.verify(f.token, '000000');
        }
        set(f.linkId, new Readmission_Report_Link__c(
            Code_Sent_At__c = Datetime.now().addSeconds(-61)
        ));
        issueCode(f.token, '654321');

        Test.startTest();
        TCMReadmissionGateService.Outcome fourth = TCMReadmissionGateService.verify(f.token, '000000');
        TCMReadmissionGateService.Outcome fifth = TCMReadmissionGateService.verify(f.token, '000000');
        Test.stopTest();

        System.assertEquals(1, fourth.attemptsLeft, 'three earlier strikes still count');
        System.assertEquals(TCMReadmissionGateService.STATUS_UNAVAILABLE, fifth.status);
        System.assertEquals('Locked', row(f.linkId).Closed_Reason__c);
    }

    @IsTest
    static void anExpiredCodeIsRefusedEvenWhenCorrect() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '123456');
        set(f.linkId, new Readmission_Report_Link__c(
            Code_Expires_At__c = Datetime.now().addSeconds(-1)
        ));

        Test.startTest();
        TCMReadmissionGateService.Outcome outcome = TCMReadmissionGateService.verify(f.token, '123456');
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_REQUEST, outcome.status);
        System.assert(outcome.error.contains('expired'), '' + outcome.error);
        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals(0, saved.Opens__c);
        System.assertEquals(0, saved.Failed_Attempts__c, 'an expired code is not a wrong guess');
        System.assertEquals(
            TCMReadmissionGateService.STATUS_REQUEST, TCMReadmissionGateService.look(f.token).status,
            'back to the request button'
        );
    }

    @IsTest
    static void aMalformedCodeIsRejectedBeforeItIsCompared() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '123456');

        Test.startTest();
        for (String bad : new List<String>{ null, '', '12', '1234567', 'abcdef' }) {
            TCMReadmissionGateService.Outcome outcome = TCMReadmissionGateService.verify(f.token, bad);
            System.assertEquals(TCMReadmissionGateService.STATUS_VERIFY, outcome.status);
            System.assert(outcome.error.contains('six-digit'), '' + outcome.error);
        }
        // Spaces and dashes people type between digits are forgiven.
        TCMReadmissionGateService.Outcome spaced = TCMReadmissionGateService.verify(f.token, '123 456');
        Test.stopTest();

        System.assertEquals(0, row(f.linkId).Failed_Attempts__c, 'malformed input is not a strike');
        System.assertEquals(TCMReadmissionGateService.STATUS_REPORT, spaced.status, '' + spaced.error);
    }

    @IsTest
    static void theRightCodeCountsOneOpenClearsTheCodeAndUnlocksForTenMinutes() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '123456');
        Datetime before = Datetime.now();

        Test.startTest();
        TCMReadmissionGateService.Outcome outcome = TCMReadmissionGateService.verify(f.token, '123456');
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_REPORT, outcome.status, '' + outcome.error);
        System.assertNotEquals(null, outcome.unlockedUntil);
        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals(1, saved.Opens__c);
        System.assertNotEquals(null, saved.First_Opened_At__c);
        System.assertNotEquals(null, saved.Last_Activity_At__c);
        System.assertEquals(null, saved.Code_Hash__c, 'a code works once');
        System.assertEquals(null, saved.Code_Expires_At__c);
        System.assertEquals(0, saved.Failed_Attempts__c);
        System.assert(
            saved.Unlocked_Until__c >= before.addMinutes(9)
                && saved.Unlocked_Until__c <= Datetime.now().addMinutes(11),
            'unlocked ten minutes: ' + saved.Unlocked_Until__c
        );
        System.assertEquals(
            TCMReadmissionGateService.STATUS_REPORT, TCMReadmissionGateService.look(f.token).status,
            'a reload inside the window shows the report without another code'
        );
        System.assertEquals(
            TCMReadmissionGateService.STATUS_REQUEST,
            TCMReadmissionGateService.verify(f.token, '123456').status,
            'and the used code cannot be replayed'
        );
    }

    @IsTest
    static void theOpenCapRefusesTheNextCodeAndClosesTheLink() {
        config(3, true);
        Fixture f = fixture('admin@gate.example');
        set(f.linkId, new Readmission_Report_Link__c(Opens__c = 3));
        issueCode(f.token, '123456');

        Test.startTest();
        TCMReadmissionGateService.Outcome outcome = TCMReadmissionGateService.verify(f.token, '123456');
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_UNAVAILABLE, outcome.status);
        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals('View limit reached', saved.Closed_Reason__c);
        System.assertNotEquals(null, saved.Closed_At__c);
        System.assertEquals(3, saved.Opens__c, 'the refused open is not counted');
        System.assertEquals(null, saved.Unlocked_Until__c);
    }

    @IsTest
    static void theCapAllowsExactlyMaxOpens() {
        config(2, true);
        Fixture f = fixture('admin@gate.example');

        Test.startTest();
        for (Integer i = 1; i <= 2; i++) {
            set(f.linkId, new Readmission_Report_Link__c(
                Code_Sent_At__c = null, Unlocked_Until__c = null
            ));
            issueCode(f.token, '123456');
            System.assertEquals(
                TCMReadmissionGateService.STATUS_REPORT,
                TCMReadmissionGateService.verify(f.token, '123456').status,
                'open ' + i + ' of 2 is allowed'
            );
        }
        set(f.linkId, new Readmission_Report_Link__c(Code_Sent_At__c = null, Unlocked_Until__c = null));
        issueCode(f.token, '123456');
        TCMReadmissionGateService.Outcome third = TCMReadmissionGateService.verify(f.token, '123456');
        Test.stopTest();

        System.assertEquals(TCMReadmissionGateService.STATUS_UNAVAILABLE, third.status);
        System.assertEquals(2, row(f.linkId).Opens__c);
        System.assertEquals('View limit reached', row(f.linkId).Closed_Reason__c);
    }

    @IsTest
    static void noCapMeansNoCap() {
        config(0, true);
        Fixture f = fixture('admin@gate.example');
        set(f.linkId, new Readmission_Report_Link__c(Opens__c = 99));
        issueCode(f.token, '123456');

        TCMReadmissionGateService.Outcome outcome = TCMReadmissionGateService.verify(f.token, '123456');

        System.assertEquals(TCMReadmissionGateService.STATUS_REPORT, outcome.status);
        System.assertEquals(100, row(f.linkId).Opens__c);
    }

    // ---- serving the PDF ------------------------------------------------------------------

    @IsTest
    static void thePdfIsServedOnlyInsideTheUnlockWindow() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');

        System.assertEquals(
            null, TCMReadmissionGateService.serve(f.token, false), 'live but not unlocked'
        );
        issueCode(f.token, '123456');
        System.assertEquals(
            null, TCMReadmissionGateService.serve(f.token, false), 'a code sent is not a code entered'
        );
        TCMReadmissionGateService.verify(f.token, '123456');

        Test.startTest();
        TCMReadmissionGateService.Served inline = TCMReadmissionGateService.serve(f.token, false);
        TCMReadmissionGateService.Served download = TCMReadmissionGateService.serve(f.token, true);
        Test.stopTest();

        System.assertNotEquals(null, inline);
        System.assertEquals('%PDF-1.4 gate placeholder', inline.body.toString());
        System.assertEquals('Readmissions-Gate Facility-2026-09-14.pdf', inline.fileName);
        System.assertNotEquals(null, download);
        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals(1, saved.Opens__c, 'streaming inside the window is not another open');
        System.assertEquals(1, saved.Downloads__c, 'the download is counted');

        set(f.linkId, new Readmission_Report_Link__c(
            Unlocked_Until__c = Datetime.now().addSeconds(-1)
        ));
        System.assertEquals(
            null, TCMReadmissionGateService.serve(f.token, false), 'window over, PDF gone'
        );
    }

    @IsTest
    static void downloadIsRefusedWhenConfigSaysNo() {
        config(10, false);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '123456');
        TCMReadmissionGateService.Outcome outcome = TCMReadmissionGateService.verify(f.token, '123456');

        System.assertEquals(false, outcome.downloadAllowed);
        System.assertNotEquals(null, TCMReadmissionGateService.serve(f.token, false), 'inline still fine');
        System.assertEquals(null, TCMReadmissionGateService.serve(f.token, true));
        System.assertEquals(0, row(f.linkId).Downloads__c);
    }

    @IsTest
    static void aPurgedFileIsUnavailableButTheRowSurvives() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '123456');
        TCMReadmissionGateService.verify(f.token, '123456');
        delete new ContentDocument(Id = f.documentId);

        System.assertEquals(null, TCMReadmissionGateService.serve(f.token, false));
        System.assertEquals(1, [SELECT COUNT() FROM Readmission_Report_Link__c WHERE Id = :f.linkId]);
    }

    @IsTest
    static void aRowPointingAtNothingServesNothing() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        issueCode(f.token, '123456');
        TCMReadmissionGateService.verify(f.token, '123456');

        set(f.linkId, new Readmission_Report_Link__c(Content_Version_Id__c = 'not-an-id'));
        System.assertEquals(null, TCMReadmissionGateService.serve(f.token, false), 'malformed id');
        set(f.linkId, new Readmission_Report_Link__c(Content_Version_Id__c = null));
        System.assertEquals(null, TCMReadmissionGateService.serve(f.token, false), 'no id');
    }

    @IsTest
    static void maskingKeepsOneCharacterAndTheDomain() {
        System.assertEquals('j***@example.com', TCMReadmissionGateService.mask('james@example.com'));
        System.assertEquals('a***@x.io', TCMReadmissionGateService.mask('a@x.io'));
        System.assertEquals('***', TCMReadmissionGateService.mask('nonsense'));
        System.assertEquals('***', TCMReadmissionGateService.mask(null));
    }

    // ---- the page controller --------------------------------------------------------------

    @IsTest
    static void theControllerWalksRequestVerifyReport() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        PageReference page = Page.TCMReadmissionReportGate;
        page.getParameters().put('t', f.token);
        Test.setCurrentPage(page);

        Test.startTest();
        TCMReadmissionGateController controller = new TCMReadmissionGateController();
        System.assert(controller.getIsRequest(), controller.status);
        System.assertEquals('Gate Facility', controller.facilityName);
        System.assertEquals('a***@gate.example', controller.maskedEmail);
        System.assertEquals('Monday, September 14, 2026', controller.reportDateLabel);
        System.assert(controller.expiresLabel.contains('2026'), controller.expiresLabel);
        System.assertEquals(10, controller.codeMinutes);

        TCMReadmissionGateService.codeOverride = '123456';
        System.assertEquals(null, controller.requestCode());
        System.assert(controller.getIsVerify(), controller.status);
        System.assert(controller.message.contains('a***@gate.example'), '' + controller.message);

        controller.codeInput = '999999';
        controller.verifyCode();
        System.assert(controller.getIsVerify());
        System.assert(controller.error.contains('not right'), '' + controller.error);
        System.assertEquals(null, controller.codeInput, 'the box is cleared');

        controller.codeInput = '123456';
        controller.verifyCode();
        Test.stopTest();

        System.assert(controller.getIsReport(), controller.status);
        System.assert(controller.unlockedUntilLabel.contains('2026'), controller.unlockedUntilLabel);
        System.assertEquals(true, controller.downloadAllowed);
        System.assert(controller.getPdfUrl().contains('t=' + f.token), controller.getPdfUrl());
        System.assert(controller.getDownloadUrl().endsWith('&dl=1'), controller.getDownloadUrl());
        System.assert(!controller.getIsUnavailable());
    }

    @IsTest
    static void theControllerWithNoTokenIsUnavailable() {
        config(10, true);
        Test.setCurrentPage(Page.TCMReadmissionReportGate);

        TCMReadmissionGateController controller = new TCMReadmissionGateController();

        System.assert(controller.getIsUnavailable());
        System.assertEquals(TCMReadmissionGateService.UNAVAILABLE_MESSAGE, controller.message);
        System.assertEquals(null, controller.facilityName);
        System.assertEquals(null, controller.reportDateLabel);
        System.assertEquals(null, controller.expiresLabel);
    }

    // ---- the REST endpoint ----------------------------------------------------------------

    private static RestResponse callApi(String token, String dl) {
        return callApi(token, dl, null);
    }

    private static RestResponse callApi(String token, String dl, String unlockKey) {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/tcm/report';
        request.httpMethod = 'GET';
        if (token != null) {
            request.params.put('t', token);
        }
        if (dl != null) {
            request.params.put('dl', dl);
        }
        if (unlockKey != null) {
            request.params.put(TCMReadmissionGateService.KEY_PARAM, unlockKey);
        }
        RestContext.request = request;
        RestContext.response = new RestResponse();
        TCMReadmissionReportGateApi.serve();
        return RestContext.response;
    }

    @IsTest
    static void theEndpointStreamsThePdfOnlyWhenUnlocked() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');

        Test.startTest();
        RestResponse locked = callApi(f.token, null);
        RestResponse stranger = callApi(TCMReadmissionAccessToken.mintToken(), null);
        RestResponse noToken = callApi(null, null);

        issueCode(f.token, '123456');
        String key = TCMReadmissionGateService.verify(f.token, '123456').issueBrowserToken;
        System.assert(String.isNotBlank(key), 'a correct code hands the browser its key');
        // The link is unlocked, but these two hold only the emailed URL, not the key the page
        // was given, so the PDF stays shut to them.
        RestResponse noKey = callApi(f.token, null);
        RestResponse wrongKey = callApi(f.token, null, TCMReadmissionAccessToken.mintToken());
        RestResponse inline = callApi(f.token, null, key);
        RestResponse download = callApi(f.token, '1', key);
        Test.stopTest();

        for (RestResponse refused : new List<RestResponse>{
            locked, stranger, noToken, noKey, wrongKey
        }) {
            System.assertEquals(404, refused.statusCode);
            System.assertEquals(
                TCMReadmissionGateService.UNAVAILABLE_MESSAGE, refused.responseBody.toString()
            );
            System.assertEquals('no-store, private', refused.headers.get('Cache-Control'));
        }
        System.assertEquals(200, inline.statusCode);
        System.assertEquals('application/pdf', inline.headers.get('Content-Type'));
        System.assert(inline.headers.get('Content-Disposition').startsWith('inline;'));
        System.assertEquals('%PDF-1.4 gate placeholder', inline.responseBody.toString());
        System.assertEquals('no-store, private', inline.headers.get('Cache-Control'));
        System.assertEquals('nosniff', inline.headers.get('X-Content-Type-Options'));

        System.assertEquals(200, download.statusCode);
        System.assert(
            download.headers.get('Content-Disposition')
                .startsWith('attachment; filename="Readmissions-Gate Facility-2026-09-14.pdf"'),
            download.headers.get('Content-Disposition')
        );
        System.assertEquals(1, row(f.linkId).Downloads__c);
    }

    // ---- the access log -------------------------------------------------------------------

    private static List<Readmission_Report_Access__c> accessLog(Id linkId) {
        return [
            SELECT Event__c, Detail__c, IP_Address__c, User_Agent__c, Occurred_At__c
            FROM Readmission_Report_Access__c
            WHERE Report_Link__c = :linkId
            ORDER BY CreatedDate, Name
        ];
    }

    private static List<String> events(List<Readmission_Report_Access__c> rows) {
        List<String> out = new List<String>();
        for (Readmission_Report_Access__c r : rows) {
            out.add(r.Event__c);
        }
        return out;
    }

    @IsTest
    static void everyStepLeavesAnAccessRowWithTheCallerIpAndBrowser() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        TCMReadmissionGateService.setCaller(new Map<String, String>{
            'X-Salesforce-SIP' => '203.0.113.7',
            'User-Agent' => 'Mozilla/5.0 (test browser)'
        });

        Test.startTest();
        issueCode(f.token, '123456');
        issueCode(f.token, '654321');                              // throttled
        TCMReadmissionGateService.verify(f.token, '000000');       // wrong
        TCMReadmissionGateService.verify(f.token, '123456');       // opened
        TCMReadmissionGateService.serve(f.token, false);           // fetched
        TCMReadmissionGateService.serve(f.token, true);            // downloaded
        set(f.linkId, new Readmission_Report_Link__c(Unlocked_Until__c = Datetime.now().addSeconds(-1)));
        TCMReadmissionGateService.serve(f.token, false);           // refused
        Test.stopTest();

        List<Readmission_Report_Access__c> rows = accessLog(f.linkId);
        System.assertEquals(
            new List<String>{ 'Code sent', 'Code throttled', 'Wrong code', 'Opened', 'PDF fetched',
                              'Downloaded', 'Fetch refused' },
            events(rows), '' + events(rows)
        );
        for (Readmission_Report_Access__c r : rows) {
            System.assertEquals('203.0.113.7', r.IP_Address__c, r.Event__c);
            System.assertEquals('Mozilla/5.0 (test browser)', r.User_Agent__c);
            System.assertNotEquals(null, r.Occurred_At__c);
            System.assert(
                r.Detail__c == null || !r.Detail__c.contains('123456'),
                'a code must never reach the log: ' + r.Detail__c
            );
        }
        // The detail now names the mailbox the code went to, masked. Which address was
        // trusted with a code is the point of letting a Cc'd reader choose, so it belongs on
        // the access row rather than only in the page message.
        System.assert(
            rows[0].Detail__c.startsWith('Code 1 of ' + TCMReadmissionGateService.MAX_CODES),
            'code count still leads the detail: ' + rows[0].Detail__c);
        System.assert(
            rows[0].Detail__c.contains('@'),
            'the masked destination is recorded: ' + rows[0].Detail__c);
        System.assertEquals(
            'Attempt 1 of ' + TCMReadmissionGateService.MAX_FAILED_ATTEMPTS, rows[2].Detail__c);
        System.assertEquals('Open 1 of 10', rows[3].Detail__c);
        System.assertEquals('Download 1', rows[5].Detail__c);
        System.assertEquals('Outside the unlock window', rows[6].Detail__c);
    }

    @IsTest
    static void lockAndCapAreLoggedAndAStrangerLeavesNoTrace() {
        config(1, true);
        Fixture f = fixture('admin@gate.example');
        TCMReadmissionGateService.setCaller(new Map<String, String>{
            'X-Forwarded-For' => '198.51.100.9, 10.0.0.1', 'User-Agent' => 'curl/8'
        });
        set(f.linkId, new Readmission_Report_Link__c(Failed_Attempts__c = 4, Opens__c = 1));
        issueCode(f.token, '123456');

        Test.startTest();
        TCMReadmissionGateService.verify(f.token, '123456');       // cap: refused and closed
        TCMReadmissionGateService.look(TCMReadmissionAccessToken.mintToken());
        TCMReadmissionGateService.serve(TCMReadmissionAccessToken.mintToken(), false);
        Test.stopTest();

        List<Readmission_Report_Access__c> rows = accessLog(f.linkId);
        System.assertEquals(new List<String>{ 'Code sent', 'View limit reached' }, events(rows));
        System.assertEquals('198.51.100.9', rows[1].IP_Address__c, 'first hop of X-Forwarded-For');
        System.assertEquals('curl/8', rows[1].User_Agent__c);
        System.assertEquals(2, [SELECT COUNT() FROM Readmission_Report_Access__c], 'unknown tokens have no row to log against');

        // And the lockout path.
        Fixture g = fixture('don@gate.example');
        issueCode(g.token, '111111');
        TCMReadmissionGateService.setCaller(new Map<String, String>{ 'True-Client-IP' => '192.0.2.4' });
        set(g.linkId, new Readmission_Report_Link__c(Failed_Attempts__c = 4));
        TCMReadmissionGateService.verify(g.token, '000000');
        List<Readmission_Report_Access__c> locked = accessLog(g.linkId);
        System.assertEquals(new List<String>{ 'Code sent', 'Wrong code', 'Locked' }, events(locked), '' + events(locked));
        System.assertEquals('192.0.2.4', locked[2].IP_Address__c);
        System.assertEquals('Too many wrong codes (5)', locked[2].Detail__c);
    }

    @IsTest
    static void theControllerAndTheEndpointCaptureTheCaller() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        PageReference page = Page.TCMReadmissionReportGate;
        page.getParameters().put('t', f.token);
        page.getHeaders().put('X-Salesforce-SIP', '203.0.113.20');
        page.getHeaders().put('User-Agent', 'PageBrowser/1.0');
        Test.setCurrentPage(page);

        Test.startTest();
        TCMReadmissionGateController controller = new TCMReadmissionGateController();
        TCMReadmissionGateService.codeOverride = '123456';
        controller.requestCode();
        controller.codeInput = '123456';
        controller.verifyCode();
        String key = TCMReadmissionGateService.currentBrowserToken();

        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/tcm/report';
        request.httpMethod = 'GET';
        request.params.put('t', f.token);
        request.params.put('dl', '1');
        request.params.put(TCMReadmissionGateService.KEY_PARAM, key);
        request.addHeader('X-Salesforce-SIP', '203.0.113.21');
        request.addHeader('User-Agent', 'ApiBrowser/2.0');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        TCMReadmissionReportGateApi.serve();
        Test.stopTest();

        List<Readmission_Report_Access__c> rows = accessLog(f.linkId);
        System.assertEquals(new List<String>{ 'Code sent', 'Opened', 'Downloaded' }, events(rows), '' + events(rows));
        System.assertEquals('203.0.113.20', rows[0].IP_Address__c);
        System.assertEquals('PageBrowser/1.0', rows[1].User_Agent__c);
        System.assertEquals('203.0.113.21', rows[2].IP_Address__c, 'the endpoint reads its own headers');
        System.assertEquals('ApiBrowser/2.0', rows[2].User_Agent__c);
    }

    // ---- the guest user -------------------------------------------------------------------

    /**
     * The whole flow as the site's guest user, who holds no object permission at all. Only
     * meaningful once the site exists in the org; before that there is no guest user to run as.
     */
    @IsTest
    static void theGuestUserCanRunTheWholeFlowWithNoObjectPermissions() {
        config(10, true);
        Fixture f = fixture('admin@gate.example');
        List<Site> sites = [
            SELECT GuestUserId FROM Site WHERE Name = :TCMReadmissionPortal.SITE_NAME LIMIT 1
        ];
        if (sites.isEmpty() || sites[0].GuestUserId == null) {
            System.debug(LoggingLevel.WARN, 'Site not deployed here; guest flow not exercised.');
            return;
        }
        User guest = [SELECT Id FROM User WHERE Id = :sites[0].GuestUserId];
        TCMReadmissionPortal.baseUrlOverride = null;
        String derived = TCMReadmissionPortal.baseUrl(new TCMReportConfig());
        System.assert(
            derived != null && derived.startsWith('https://') && derived.endsWith('/report'),
            'the site address is derived from the org: ' + derived
        );

        Test.startTest();
        System.runAs(guest) {
            System.assertEquals(
                TCMReadmissionGateService.STATUS_REQUEST, TCMReadmissionGateService.look(f.token).status
            );
            TCMReadmissionGateService.Outcome sent = issueCode(f.token, '123456');
            System.assertEquals(TCMReadmissionGateService.STATUS_VERIFY, sent.status, '' + sent.error);
            TCMReadmissionGateService.Outcome opened = TCMReadmissionGateService.verify(f.token, '123456');
            System.assertEquals(TCMReadmissionGateService.STATUS_REPORT, opened.status, '' + opened.error);
            TCMReadmissionGateService.Served served = TCMReadmissionGateService.serve(f.token, true);
            System.assertNotEquals(null, served, 'the guest can stream the stored PDF');
            System.assertEquals('%PDF-1.4 gate placeholder', served.body.toString());
        }
        Test.stopTest();

        Readmission_Report_Link__c saved = row(f.linkId);
        System.assertEquals(1, saved.Opens__c);
        System.assertEquals(1, saved.Downloads__c);
        System.assertEquals(1, saved.Codes_Sent__c);
        System.assertEquals(
            new List<String>{ 'Code sent', 'Opened', 'Downloaded' }, events(accessLog(f.linkId)),
            'the guest writes the access log too'
        );
    }

    // ---- where the site lives -------------------------------------------------------------

    @IsTest
    static void theSiteAddressComesFromConfigBeforeTheOrg() {
        TCMReadmissionPortal.baseUrlOverride = null;
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true, Portal_Base_Url__c = 'https://reports.lumina.example/report/'
        );
        System.assertEquals(
            'https://reports.lumina.example/report',
            TCMReadmissionPortal.baseUrl(new TCMReportConfig()),
            'trailing slash dropped'
        );
        System.assertEquals(
            'https://reports.lumina.example/report?t=abc',
            TCMReadmissionPortal.linkFor('https://reports.lumina.example/report', 'abc')
        );
        System.assertEquals('/services/apexrest/tcm/report?t=abc', TCMReadmissionPortal.pdfPath('abc', false, null));
        System.assertEquals('/services/apexrest/tcm/report?t=abc&dl=1', TCMReadmissionPortal.pdfPath('abc', true, '  '));
        System.assertEquals(
            '/services/apexrest/tcm/report?t=abc&k=key%2F1',
            TCMReadmissionPortal.pdfPath('abc', false, 'key/1'),
            'the unlock key rides in the query string because Apex REST never sees cookies'
        );
        System.assertEquals(
            '/services/apexrest/tcm/report?t=abc&k=key1&dl=1',
            TCMReadmissionPortal.pdfPath('abc', true, 'key1')
        );

        TCMReadmissionPortal.baseUrlOverride = '';
        System.assertEquals('', TCMReadmissionPortal.baseUrl(new TCMReportConfig()), 'an override wins even when blank');
    }
}