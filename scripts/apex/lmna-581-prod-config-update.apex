/*
 * LMNA-581: update the production recipient lists.
 *
 * Run with:
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-config-update.apex
 *
 * The custom metadata record cannot be edited by a normal deploy in this org, so it goes
 * through the Apex Metadata API. Every value currently on the record is carried over, because
 * this call replaces the record rather than patching it. The write is asynchronous, so give it
 * thirty seconds and then re-query to confirm.
 */
TCM_Report_Config__mdt current = TCM_Report_Config__mdt.getInstance('Default');
Map<String, Object> values = current.getPopulatedFieldsAsMap().clone();

// The daily summary. Kevin joins this later, once sending is proven.
values.put('Digest_Recipients__c', 'chayim@propela.tech; james@propela.tech');

// Lumina staff who get their own copy of every facility report, each with their own link and
// their own one-time code. Just the two of us while this is being proven. Ben's address,
// bzirman@luminacare.com, gets added here once sending is confirmed working.
values.put('Internal_CC_Emails__c', 'james@propela.tech; chayim@propela.tech');

// The true-Cc option Lumina did not choose. Must stay empty.
values.put('Global_CC_Emails__c', null);

Metadata.CustomMetadata record = new Metadata.CustomMetadata();
record.fullName = 'TCM_Report_Config.Default';
record.label = current.Label;
Set<String> skip = new Set<String>{'Id','DeveloperName','MasterLabel','Label','QualifiedApiName',
    'NamespacePrefix','SystemModstamp','Language','attributes'};
for (String field : values.keySet()) {
    if (skip.contains(field)) { continue; }
    Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
    v.field = field;
    v.value = values.get(field);
    record.values.add(v);
}
Metadata.DeployContainer container = new Metadata.DeployContainer();
container.addMetadata(record);
System.debug('Writing ' + record.values.size() + ' values');
Metadata.Operations.enqueueDeployment(container, null);
