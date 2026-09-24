/*
 * LMNA-581, go-live config. Sets the three fields that are wrong or undecided in production,
 * and leaves every other field exactly as it is.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-config-go-live.apex
 *
 * Edit the three values below before running. They are the whole decision:
 *
 *   INTERNAL_CC   who at Lumina gets their own copy of every facility report, with their own link
 *              and their own one-time code. This is the arrangement Lumina asked for. Blank
 *              means only the facility itself receives the report.
 *   GLOBAL_CC     a true Cc on somebody else's email. They see the message but cannot open the
 *              report, because the code goes to the address the link was issued to. Ben is on
 *              this field today, which is why he would receive mail he cannot read.
 *   NJ_GHC_CC     Cc for facilities under the GHC parent company, issued its own link. Empty in
 *              production. The repo copy holds a Propela address, which is a test value and
 *              must not go to production.
 *
 * Is_Active__c is deliberately untouched. Ticking it is the step that starts real mail, and it
 * stays a separate, deliberate action in Setup.
 */
String INTERNAL_CC = 'bzirman@luminacare.com; james@propela.tech; chayim@propela.tech';
String GLOBAL_CC   = null;   // leave empty, a true Cc cannot open the report
String NJ_GHC_CC   = null;   // leave empty, Lumina never supplied an address

TCM_Report_Config__mdt current = TCM_Report_Config__mdt.getInstance('Default');
Map<String, Object> values = current.getPopulatedFieldsAsMap().clone();
values.put('Internal_CC_Emails__c', INTERNAL_CC);
values.put('Global_CC_Emails__c', GLOBAL_CC);
values.put('NJ_GHC_CC_Email__c', NJ_GHC_CC);

Metadata.CustomMetadata record = new Metadata.CustomMetadata();
record.fullName = 'TCM_Report_Config.Default';
record.label = current.Label;
Set<String> skip = new Set<String>{'Id','DeveloperName','MasterLabel','Label','QualifiedApiName',
    'NamespacePrefix','SystemModstamp','Language','attributes'};
for (String field : values.keySet()) {
    if (skip.contains(field)) { continue; }
    Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
    v.field = field; v.value = values.get(field);
    record.values.add(v);
}
Metadata.DeployContainer c = new Metadata.DeployContainer();
c.addMetadata(record);
Metadata.Operations.enqueueDeployment(c, null);

System.debug(LoggingLevel.ERROR, 'queued. Internal=' + INTERNAL_CC
    + ' Global=' + GLOBAL_CC + ' NJ_GHC_CC=' + NJ_GHC_CC);
System.debug(LoggingLevel.ERROR, 'The write is asynchronous. Re-read the record before you '
    + 'tick Is_Active__c.');
