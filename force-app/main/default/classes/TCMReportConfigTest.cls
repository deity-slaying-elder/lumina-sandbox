/**
 * Config accessor: defaults, blank-to-null coercion, and placeholder reporting.
 */
@IsTest
private class TCMReportConfigTest {

    @IsTest
    static void blankValuesFallBackToDefaults() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Business_Timezone__c = '   ',
            Subject_Template__c = null,
            NJ_GHC_Parent_Company_Name__c = null
        );
        TCMReportConfig config = new TCMReportConfig();

        System.assertEquals('America/New_York', config.timeZoneName());
        System.assertEquals('GHC', config.njGhcParentCompanyName());
        System.assert(config.subjectTemplate().contains('{0}'));
    }

    @IsTest
    static void blankEmailFieldsResolveToNull() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Internal_CC_Emails__c = '  ',
            From_Org_Wide_Address__c = null,
            Digest_Recipients__c = '',
            Sandbox_Redirect_Email__c = null
        );
        TCMReportConfig config = new TCMReportConfig();

        System.assertEquals(null, config.internalCc(), 'whitespace is not an address');
        System.assertEquals(null, config.orgWideAddress());
        System.assert(config.digestRecipients().isEmpty());
        System.assertEquals(null, config.sandboxRedirect());
    }

    @IsTest
    static void digestRecipientsAcceptsASeparatedList() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Digest_Recipients__c = 'Kevin@luminacare.com; chayim@propela.tech , kevin@luminacare.com'
        );

        System.assertEquals(
            new List<String>{ 'kevin@luminacare.com', 'chayim@propela.tech' },
            new TCMReportConfig().digestRecipients(),
            'both separators handled, trimmed, and case-insensitively deduped'
        );
    }

    @IsTest
    static void valuesAreTrimmed() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Internal_CC_Emails__c = '  kevin@luminacare.com  ',
            Business_Timezone__c = ' America/Chicago '
        );
        TCMReportConfig config = new TCMReportConfig();

        System.assertEquals('kevin@luminacare.com', config.internalCc());
        System.assertEquals('America/Chicago', config.timeZoneName());
    }

    @IsTest
    static void unconfiguredPlaceholdersAreReported() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt();

        List<String> gaps = new TCMReportConfig().unconfiguredPlaceholders();

        System.assertEquals(1, gaps.size(), 'gaps: ' + gaps);
        System.assert(gaps[0].contains('From_Org_Wide_Address__c'), gaps[0]);
        System.assert(
            !gaps[0].contains('Internal_CC_Emails__c'),
            'a blank per-facility CC is intended now that the internal recipient takes the ' +
            'daily summary instead, so it must not be reported as an unfilled placeholder'
        );
    }

    @IsTest
    static void filledPlaceholdersReportNoGaps() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            From_Org_Wide_Address__c = 'readmissions@luminacare.com'
        );

        System.assert(new TCMReportConfig().unconfiguredPlaceholders().isEmpty());
    }

    @IsTest
    static void unsetCheckboxesReadAsFalse() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt();
        TCMReportConfig config = new TCMReportConfig();

        System.assert(!config.isActive(), 'a null checkbox must not read as active');
        System.assert(!config.requireFacilityTcm());
    }

    @IsTest
    static void checkboxesAreReadFromTheRecord() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Is_Active__c = true,
            Require_Facility_TCM__c = true
        );
        TCMReportConfig config = new TCMReportConfig();

        System.assert(config.isActive());
        System.assert(config.requireFacilityTcm());
    }

    @IsTest
    static void severalInternalRecipientsCanBeListedAndTheListWins() {
        // Lumina chose this over a true Cc: each of these addresses gets its own email and its
        // own link, so their one-time code goes to them and never to the facility.
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Internal_CC_Emails__c = 'ben@luminacare.com; kevin@luminacare.com'
        );

        System.assertEquals(
            'ben@luminacare.com; kevin@luminacare.com',
            new TCMReportConfig().internalCc(),
            'one field, separated, so addresses can be added and removed without a deploy'
        );
    }

    @IsTest
    static void aBlankInternalListMeansNobodyIsCopied() {
        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt(
            Internal_CC_Emails__c = '   '
        );
        System.assertEquals(null, new TCMReportConfig().internalCc(), 'whitespace is not an address');

        TCMReportConfig.overrideRecord = new TCM_Report_Config__mdt();
        System.assertEquals(null, new TCMReportConfig().internalCc());
    }
}