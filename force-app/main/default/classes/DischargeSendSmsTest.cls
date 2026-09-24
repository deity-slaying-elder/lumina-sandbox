/**
 * The gate logic is tested through the @TestVisible helpers, because every gate is a
 * pure function of field values. The end-to-end path is tested through DML with an
 * HttpCalloutMock standing in for Twilio.
 */
@isTest
private class DischargeSendSmsTest {

    /** Records every request so the tests can assert on what would have gone out. */
    private class RecordingCalloutMock implements HttpCalloutMock {
        public Integer calls = 0;
        public HTTPResponse respond(HTTPRequest request) {
            calls++;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(201);
            response.setBody('{"sid":"SM_test"}');
            return response;
        }
    }

    private static Admission_Discharge__c dischargeRecord(String type, String toFrom) {
        return new Admission_Discharge__c(Type__c = type, To_From_Type__c = toFrom);
    }

    // ---------- Gate 1: dischargedHome ----------

    @isTest
    static void dischargedHomeMatchesTheFormula() {
        Assert.isTrue(DischargeSendSms.isDischargedHome(dischargeRecord('Discharge', 'Home')),
            'Plain Home qualifies');
        Assert.isTrue(DischargeSendSms.isDischargedHome(dischargeRecord('Discharge', '  ALF unit ')),
            'ALF qualifies, case-insensitively and trimmed');
        Assert.isTrue(DischargeSendSms.isDischargedHome(dischargeRecord('Discharge', 'Assisted Living')),
            'Assisted qualifies');
        Assert.isFalse(DischargeSendSms.isDischargedHome(dischargeRecord('Discharge', 'Nursing Home')),
            'Nursing Home contains home AND nursing; the exclusion wins, as in the formula');
        Assert.isFalse(DischargeSendSms.isDischargedHome(dischargeRecord('Discharge', 'Home Hospice')),
            'Hospice excludes even alongside home');
        Assert.isFalse(DischargeSendSms.isDischargedHome(dischargeRecord('Discharge', 'Funeral Home')),
            'Funeral excludes');
        Assert.isFalse(DischargeSendSms.isDischargedHome(dischargeRecord('Admission', 'Home')),
            'Only Type__c = Discharge qualifies; the prod formula gates on it');
        Assert.isFalse(DischargeSendSms.isDischargedHome(dischargeRecord('Discharge', null)),
            'A blank To_From_Type__c does not qualify in prod v10');
        Assert.isFalse(DischargeSendSms.isDischargedHome(dischargeRecord('Discharge', 'Skilled Facility')),
            'An unrecognised destination does not qualify');
    }

    // ---------- Gate 2: the inverted recency test ----------

    @isTest
    static void recencyTestIsInvertedExactlyLikeTheFlow() {
        Date today = Date.newInstance(2026, 9, 2);

        Assert.isTrue(DischargeSendSms.textedMoreThanThreeDaysAgo(
            Datetime.newInstanceGmt(2026, 8, 25, 12, 0, 0), today),
            'Eight days ago is more than three: the flow STOPS here, backwards as that is');
        Assert.isFalse(DischargeSendSms.textedMoreThanThreeDaysAgo(
            Datetime.newInstanceGmt(2026, 9, 1, 12, 0, 0), today),
            'Yesterday is within three days: the flow CONTINUES and texts again');
        Assert.isFalse(DischargeSendSms.textedMoreThanThreeDaysAgo(null, today),
            'A never-texted patient made the formula null, read as false, so it continues');
        // Exactly three days is not more than three, so it continues. Boundary matches
        // the formula operator, which is > not >=.
        Assert.isFalse(DischargeSendSms.textedMoreThanThreeDaysAgo(
            Datetime.newInstanceGmt(2026, 8, 30, 12, 0, 0), today),
            'Exactly three days is not more than three');
        // The GMT boundary. 30 Aug 23:30 New York time is 31 Aug 03:30 GMT; DATEVALUE
        // works in GMT so the flow sees 31 Aug, three days, and continues. A port using
        // Datetime.date() in a New York context would see 30 Aug and stop.
        Assert.isFalse(DischargeSendSms.textedMoreThanThreeDaysAgo(
            Datetime.newInstanceGmt(2026, 8, 31, 3, 30, 0), today),
            'The comparison day is the GMT day, exactly as DATEVALUE computes it');
    }

    // ---------- Gate 3: regions ----------

    /**
     * Facility_State__c is a formula, not writable even in memory, so the record is
     * built by deserializing JSON - the one way to hand a formula field a value in a
     * unit test without touching the database.
     */
    private static Patient__c regionPatient(String parentCompany, String state) {
        String payload = '{"attributes":{"type":"Patient__c"}'
            + ',"Facility_State__c":"' + state + '"'
            + ',"Facility__r":{"attributes":{"type":"Facility__c"}'
            + ',"Parent_Company__r":{"attributes":{"type":"Account"},"Name":"' + parentCompany + '"}}}';
        return (Patient__c) JSON.deserialize(payload, Patient__c.class);
    }

    @isTest
    static void regionRoutingMatchesTheFlow() {
        Assert.isTrue(DischargeSendSms.isRegionInScope(regionPatient('GHC Group', 'MD')),
            'GHC in Maryland is in scope');
        Assert.isTrue(DischargeSendSms.isRegionInScope(regionPatient('GHC Group', 'Deleware')),
            'The misspelled Deleware matches, because the flow spells it that way');
        Assert.isFalse(DischargeSendSms.isRegionInScope(regionPatient('GHC Group', 'Delaware')),
            'Correctly spelled Delaware does NOT match: reproduced flow defect');
        Assert.isFalse(DischargeSendSms.isRegionInScope(regionPatient('GHC Group', 'PA')),
            'GHC routes to MD/DE/NJ, not PA');
        Assert.isTrue(DischargeSendSms.isRegionInScope(regionPatient('Complete Care East', 'PA')),
            'Complete Care in Pennsylvania is in scope');
        Assert.isFalse(DischargeSendSms.isRegionInScope(regionPatient('Complete Care East', 'MD')),
            'Complete Care routes to PA/NJ, not MD');
        Assert.isTrue(DischargeSendSms.isRegionInScope(regionPatient('Infinity Healthcare', 'Illinois')),
            'Infinity in Illinois is in scope');
        Assert.isFalse(DischargeSendSms.isRegionInScope(regionPatient('Infinity Healthcare', 'NJ')),
            'Infinity routes to Illinois only');
        Assert.isFalse(DischargeSendSms.isRegionInScope(regionPatient('Some Other Company', 'NJ')),
            'An unrecognised parent company stops at the default outcome');
        Assert.isFalse(DischargeSendSms.isRegionInScope(new Patient__c()),
            'No facility or parent company stops safely');
    }

    // ---------- Gate 4: phone cascade ----------

    @isTest
    static void phoneCascadeFollowsTheFlowOrder() {
        Patient__c patient = new Patient__c(
            Phone_Number__c = '111', Mobile_Number__c = '222', Phone_3__c = '333'
        );
        Assert.areEqual('111', DischargeSendSms.resolvePhoneNumber(patient),
            'Phone_Number__c wins when populated');

        patient.Phone_Number__c = ' ';
        Assert.areEqual('222', DischargeSendSms.resolvePhoneNumber(patient),
            'Blank falls through to Mobile_Number__c');

        patient.Mobile_Number__c = null;
        Assert.areEqual('333', DischargeSendSms.resolvePhoneNumber(patient),
            'The cascade reaches Phone_3__c last');

        Assert.areEqual(null, DischargeSendSms.resolvePhoneNumber(new Patient__c()),
            'No phone anywhere resolves to null, which gate 4 turns into a stop');
    }

    // ---------- End to end ----------

    private static Id setupQualifyingPatient() {
        Account parent = new Account(Name = 'GHC Group');
        insert parent;
        // Facility_State__c on Patient is TEXT(Facility__r.Address__StateCode__s), so
        // the state must go into the compound address field's state code.
        Facility__c facility = new Facility__c(Parent_Company__c = parent.Id);
        facility.put('Address__StateCode__s', 'MD');
        facility.put('Address__CountryCode__s', 'US');
        insert facility;
        Patient__c patient = new Patient__c(
            First_Name__c = 'Sms', Last_Name__c = 'Recipient', Status__c = 'Active',
            Facility__c = facility.Id, Phone_Number__c = '+15555550100'
        );
        insert patient;
        return patient.Id;
    }

    @isTest
    static void qualifyingDischargeSendsAndStamps() {
        Id patientId = setupQualifyingPatient();
        RecordingCalloutMock mock = new RecordingCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        insert new Admission_Discharge__c(
            Patient__c = patientId, Type__c = 'Discharge', To_From_Type__c = 'Home'
        );
        Test.stopTest();

        // The assertion is on the stamp, not on the mock's call count. What the Twilio
        // package does between the invocable and the wire - direct callout, its own
        // queueable, a platform event - is its own business and changes between package
        // versions. The stamp is this port's observable contract: it lands only after
        // sendSMSToNumber returned without throwing.
        Patient__c stamped = [SELECT Last_SMS_Sent_Date__c FROM Patient__c WHERE Id = :patientId];
        Assert.areNotEqual(null, stamped.Last_SMS_Sent_Date__c,
            'Last_SMS_Sent_Date__c is stamped only after a successful send');
    }

    @isTest
    static void nonQualifyingDischargeSendsNothing() {
        Id patientId = setupQualifyingPatient();
        update new Patient__c(Id = patientId, No_Texts__c = true);
        RecordingCalloutMock mock = new RecordingCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        insert new Admission_Discharge__c(
            Patient__c = patientId, Type__c = 'Discharge', To_From_Type__c = 'Home'
        );
        Test.stopTest();

        Patient__c untouched = [SELECT Last_SMS_Sent_Date__c FROM Patient__c WHERE Id = :patientId];
        Assert.areEqual(null, untouched.Last_SMS_Sent_Date__c,
            'No_Texts__c must suppress the send, so nothing may be stamped');
    }

    @isTest
    static void bypassedActionSendsNothing() {
        Id patientId = setupQualifyingPatient();
        MetadataTriggerHandler.bypass('DischargeSendSms');
        RecordingCalloutMock mock = new RecordingCalloutMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        insert new Admission_Discharge__c(
            Patient__c = patientId, Type__c = 'Discharge', To_From_Type__c = 'Home'
        );
        Test.stopTest();

        Patient__c untouched = [SELECT Last_SMS_Sent_Date__c FROM Patient__c WHERE Id = :patientId];
        Assert.areEqual(null, untouched.Last_SMS_Sent_Date__c,
            'The per-action bypass must suppress the send, so nothing may be stamped');
    }
}
