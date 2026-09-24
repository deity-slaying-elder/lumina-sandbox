/*
 * LMNA-581 digest test, step 4 of 4. RESTORE. Run this even if the test failed.
 *
 *   sf apex run --target-org lumProd --file scripts/apex/lmna-581-prod-digest-4-restore.apex
 *
 * Puts the required patient class back to Inpatient. Until this runs, the daily report is
 * scoped to a marker no real admission carries, so it would report nothing.
 */
TCM_Report_Config__mdt current = TCM_Report_Config__mdt.getInstance('Default');
Map<String, Object> values = current.getPopulatedFieldsAsMap().clone();
values.put('Required_Patient_Class__c', 'Inpatient');

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
System.debug('restore queued. Confirm Required_Patient_Class__c reads Inpatient before you leave.');
