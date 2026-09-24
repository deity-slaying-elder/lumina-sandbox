/*
 * LMNA-581 digest test, step 1b of 4. ARM THE CONFIGURATION.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-digest-1b-arm-config.apex
 *
 * Points the required patient class at the marker step 1a put on the test admission, so every
 * genuine facility falls out of scope for the duration of the test.
 *
 * Separate from step 1a because a metadata deployment is a write to a setup object and cannot
 * share a transaction with a write to records.
 *
 * The config write is asynchronous. Wait for step 2 to confirm before running the batch.
 */
String marker = 'ZZSMOKE';

TCM_Report_Config__mdt current = TCM_Report_Config__mdt.getInstance('Default');
Map<String, Object> values = current.getPopulatedFieldsAsMap().clone();
values.put('Required_Patient_Class__c', marker);

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
System.debug('config write queued. Confirm with step 2 before running the batch.');
