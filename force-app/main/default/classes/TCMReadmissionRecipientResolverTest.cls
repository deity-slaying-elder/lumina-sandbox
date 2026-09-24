/**
 * Recipient resolution: Admin/DON fallback, the NJ + GHC rule, and the sandbox guard.
 * No DML -- the config is injected and the Facility graph assembled through JSON.
 */
@IsTest
private class TCMReadmissionRecipientResolverTest {

    private static final String KEVIN = 'internal.cc@luminacare.com';
    private static final String JENNIFER = 'jennifer.bridges1@genesishcc.com';
    private static final String REDIRECT = 'sandbox.test@propela.tech';

    private static TCMReportConfig config() {
        return config(KEVIN, JENNIFER, REDIRECT);
    }

    private static TCMReportConfig config(String internalCc, String njCc, String redirect) {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true,
            Internal_CC_Emails__c = internalCc,
            NJ_GHC_CC_Email__c = njCc,
            Sandbox_Redirect_Email__c = redirect,
            NJ_GHC_Parent_Company_Name__c = 'GHC',
            Business_Timezone__c = 'America/New_York'
        );
        return new TCMReportConfig();
    }

    private static Facility__c facility(
        String adminEmail, String donEmail, String parentName, String state
    ) {
        Facility__c f = new Facility__c(
            Name = 'Test Facility',
            Admin_Email__c = adminEmail,
            DON_Email__c = donEmail
        );
        Map<String, Object> facilityMap =
            (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(f));
        facilityMap.put('Address__StateCode__s', state);
        if (parentName != null) {
            facilityMap.put('Parent_Company__r', new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Account' },
                'Name' => parentName
            });
        }
        return (Facility__c) JSON.deserialize(JSON.serialize(facilityMap), Facility__c.class);
    }

    @IsTest
    static void adminEmailIsPreferred() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('admin@snf.com', 'don@snf.com', 'Infinity', 'AL'));

        System.assert(r.isSendable());
        System.assertEquals(new List<String>{ 'admin@snf.com' }, r.toAddresses);
        System.assertEquals('Admin_Email__c', r.primarySource);
    }

    @IsTest
    static void donIsUsedOnlyWhenAdminIsBlank() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('   ', 'don@snf.com', 'Infinity', 'AL'));

        System.assertEquals(new List<String>{ 'don@snf.com' }, r.toAddresses, 'DON replaces Admin');
        System.assertEquals('DON_Email__c', r.primarySource);
    }

    @IsTest
    static void bothBlankIsSkippedWithAReason() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility(null, null, 'Infinity', 'AL'));

        System.assert(!r.isSendable(), 'nothing to send to');
        System.assert(r.toAddresses.isEmpty());
        System.assert(
            r.skipReason.contains('No Admin_Email__c or DON_Email__c'),
            'skip reason: ' + r.skipReason
        );
    }

    @IsTest
    static void internalCcIsAlwaysAdded() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('admin@snf.com', null, 'Infinity', 'AL'));

        System.assertEquals(new List<String>{ KEVIN }, r.ccAddresses);
    }

    @IsTest
    static void njGhcAlsoCcsTheRegionalContact() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('admin@snf.com', null, 'GHC', 'NJ'));

        System.assertEquals(2, r.ccAddresses.size(), 'CC list: ' + r.ccAddresses);
        System.assert(new Set<String>(r.ccAddresses).contains(JENNIFER), 'CC list: ' + r.ccAddresses);
        System.assert(new Set<String>(r.ccAddresses).contains(KEVIN), 'CC list: ' + r.ccAddresses);
    }

    @IsTest
    static void ghcOutsideNewJerseyDoesNotGetTheRegionalContact() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('admin@snf.com', null, 'GHC', 'AL'));

        System.assertEquals(new List<String>{ KEVIN }, r.ccAddresses, 'state gate must apply');
    }

    @IsTest
    static void newJerseyUnderAnotherParentCompanyDoesNotGetTheRegionalContact() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('admin@snf.com', null, 'Complete Care Management', 'NJ'));

        System.assertEquals(new List<String>{ KEVIN }, r.ccAddresses, 'parent gate must apply');
    }

    @IsTest
    static void similarlyNamedParentCompanyDoesNotMatchGhc() {
        // A real Account named AUGHC exists in this org. A contains-style match would
        // leak a New Jersey facility's patient list to the wrong regional contact.
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('admin@snf.com', null, 'AUGHC', 'NJ'));

        System.assertEquals(
            new List<String>{ KEVIN }, r.ccAddresses,
            'AUGHC must not satisfy the GHC rule'
        );
    }

    @IsTest
    static void facilityWithNoParentCompanyIsHandled() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('admin@snf.com', null, null, 'NJ'));

        System.assert(r.isSendable(), 'a missing parent lookup should not throw');
        System.assertEquals(new List<String>{ KEVIN }, r.ccAddresses);
    }

    @IsTest
    static void multipleAddressesInOneFieldAreSplit() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility('a@snf.com; b@snf.com , c@snf.com', null, 'Infinity', 'AL'));

        System.assertEquals(
            new List<String>{ 'a@snf.com', 'b@snf.com', 'c@snf.com' }, r.toAddresses,
            'both separators handled and values trimmed'
        );
    }

    @IsTest
    static void ccIsNotDuplicatedWhenItMatchesTheToAddress() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), false)
                .resolve(facility(KEVIN.toUpperCase(), null, 'Infinity', 'AL'));

        System.assert(
            r.ccAddresses.isEmpty(),
            'address already on the To line should not be CCd again: ' + r.ccAddresses
        );
    }

    @IsTest
    static void blankInternalCcSimplyYieldsNoCc() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(null, JENNIFER, REDIRECT), false)
                .resolve(facility('admin@snf.com', null, 'Infinity', 'AL'));

        System.assert(r.isSendable(), 'an unfilled placeholder must not block the send');
        System.assert(r.ccAddresses.isEmpty());
    }

    @IsTest
    static void sandboxRedirectsEverythingToTheTestAddress() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(), true)
                .resolve(facility('admin@snf.com', null, 'GHC', 'NJ'));

        System.assert(r.isSendable());
        System.assert(r.redirected, 'should be flagged as redirected');
        System.assertEquals(new List<String>{ REDIRECT }, r.toAddresses, 'real address must not survive');
        System.assert(r.ccAddresses.isEmpty(), 'CCs are dropped in a sandbox');
    }

    @IsTest
    static void sandboxWithoutARedirectAddressRefusesToSend() {
        TCMReadmissionRecipientResolver.Resolution r =
            new TCMReadmissionRecipientResolver(config(KEVIN, JENNIFER, null), true)
                .resolve(facility('admin@snf.com', null, 'Infinity', 'AL'));

        System.assert(!r.isSendable(), 'must not fall through to the real facility address');
        System.assert(r.toAddresses.isEmpty());
        System.assert(
            r.skipReason.contains('Sandbox_Redirect_Email__c'),
            'skip reason: ' + r.skipReason
        );
    }
}