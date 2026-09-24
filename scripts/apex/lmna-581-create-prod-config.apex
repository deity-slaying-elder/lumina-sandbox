/*
 * LMNA-581, production step 4: create the TCM_Report_Config__mdt "Default" record.
 *
 * This org rejects a customMetadata record inside a metadata deploy with a bare
 * UNKNOWN_EXCEPTION, proven on 2026-09-16 against the unchanged committed file, so the record
 * is written through the Apex Metadata API instead. Run this once in production, after the
 * stage 1 deploy has created the custom metadata type.
 *
 * Is_Active__c is false on purpose. The scheduler checks it and does nothing while it is false,
 * so nothing sends until someone deliberately turns it on.
 */
Metadata.CustomMetadata record = new Metadata.CustomMetadata();
record.fullName = 'TCM_Report_Config.Default';
record.label = 'Default';

Map<String, Object> values = new Map<String, Object>{
    // Kill switch. Leave false until the whole runbook is finished and verified.
    'Is_Active__c' => false,

    // Clinical scope.
    'Required_Patient_Class__c' => 'Inpatient',
    'Require_Facility_TCM__c' => true,

    // Delivery.
    'Delivery_Mode__c' => 'Link',
    'Link_Expiry_Hours__c' => 24,
    'Max_Opens__c' => 10,
    'Allow_Download__c' => true,
    'Notify_On_Visit__c' => false,
    'Business_Timezone__c' => 'America/New_York',
    'Subject_Template__c' => 'Readmissions Report - {0} - {1}',

    // Addresses. From_Org_Wide_Address__c must exist and be verified in production, and should
    // allow all profiles so the site guest user can send the one-time code from it.
    'From_Org_Wide_Address__c' => 'tcm@luminacare.com',
    'Digest_Recipients__c' => 'chayim@propela.tech; kevingrayson@luminacare.com',

    // Lumina staff who get the same report as the facility. This is the option Lumina chose:
    // each address is issued its own link and therefore its own one-time code, so nobody sees
    // anybody else's code. Semicolon or comma separated, editable in Setup without a deploy.
    'Internal_CC_Emails__c' => null,

    // The true-Cc alternative, which Lumina did not choose. Leave blank. Filling this in would
    // copy these addresses onto the facility's own message, where they get no link of their
    // own and so cannot open the report at all.
    'Global_CC_Emails__c' => null,
    'NJ_GHC_CC_Email__c' => 'chayim@propela.tech',
    'NJ_GHC_Parent_Company_Name__c' => 'GHC',

    // Deliberately blank in production until Lumina supply the internal list. The sandbox
    // redirect fields have no effect outside a sandbox.

    // Optional. Blank means the site address is derived from the TCM_Readmission_Portal site
    // in whichever org the code runs in.
    'Portal_Base_Url__c' => null
};

for (String field : values.keySet()) {
    Metadata.CustomMetadataValue value = new Metadata.CustomMetadataValue();
    value.field = field;
    value.value = values.get(field);
    record.values.add(value);
}

Metadata.DeployContainer container = new Metadata.DeployContainer();
container.addMetadata(record);
System.debug('Enqueuing ' + record.values.size() + ' config values');
Metadata.Operations.enqueueDeployment(container, null);
