/**
 * Trigger action: delete Leaked_Admission__c rows that are not really leaks.
 *
 * Apex port of the flow Facility_Mapper_TF_Delete_False_Leaked_Admissions.
 *
 * Flow behaviour, preserved exactly:
 *   Entry criteria  - Facility__c IsChanged AND Facility__c is not null
 *   Then            - load every Leaked_Admission__c pointing at this mapper and
 *                     delete the ones whose Patient's Facility rolls up to the SAME
 *                     parent company as the mapper's new Facility.
 *
 * The comparison is on parent company NAME, not Id, because the flow formula
 * compared Names. Two distinct Accounts sharing a name therefore match in both
 * implementations. That is a faithful port, not an endorsement - raised as debt.
 *
 * Bulkified: the flow ran one query and one delete per mapper record. This runs
 * one query and one delete for the whole save, which is the point of the ticket.
 *
 * Registered in Trigger_Action__mdt for the After Update context on
 * Facility_Mapper__c. Deactivate by ticking Bypass Execution
 * on that record in Setup - the framework reads it live - or at runtime with
 * MetadataTriggerHandler.bypass in a test or batch job.
 *
 * SYSTEM MODE, DELIBERATELY. The flow this replaces ran in system context and wrote
 * what it needed regardless of who saved the record. Running-user enforcement here
 * (WITH USER_MODE, stripInaccessible) makes the same save silently drop writes for
 * lower-privilege profiles - in production, Lumina Manager No Edit Access can create
 * discharges without Patient edit, and Latest_Community_Episode__c carries no field
 * permissions for anyone - and a silently dropped TCM timestamp is a billing defect
 * nobody sees. Automation runs as the system, exactly as the flow did. User-facing
 * controllers are different and keep user-mode enforcement.
 */
public without sharing class FacilityMapperDeleteFalseLeaks implements TriggerAction.AfterUpdate {

    public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
        List<Facility_Mapper__c> newMappers = (List<Facility_Mapper__c>) triggerNew;

        // The framework hands over triggerOld as a List, not a Map. Build the map
        // the entry criteria needs.
        Map<Id, Facility_Mapper__c> oldMapperMap = new Map<Id, Facility_Mapper__c>(
            (List<Facility_Mapper__c>) triggerOld
        );

        deleteFalseLeakedAdmissions(newMappers, oldMapperMap);
    }

    private void deleteFalseLeakedAdmissions(List<Facility_Mapper__c> newMappers, Map<Id, Facility_Mapper__c> oldMapperMap) {

        // Flow entry criteria: Facility__c changed, and is not null.
        Set<Id> qualifyingMapperIds = new Set<Id>();
        for (Facility_Mapper__c mapper : newMappers) {
            Facility_Mapper__c priorMapper = oldMapperMap == null ? null : oldMapperMap.get(mapper.Id);
            Boolean facilityChanged = priorMapper == null || mapper.Facility__c != priorMapper.Facility__c;

            if (facilityChanged && mapper.Facility__c != null) {
                qualifyingMapperIds.add(mapper.Id);
            }
        }

        // No recursion guard here on purpose - this action deletes Leaked_Admission__c
        // and never writes Facility_Mapper__c, so it cannot re-enter itself. Guarding
        // would wrongly suppress a second, legitimate update in the same transaction.
        if (qualifyingMapperIds.isEmpty()) {
            return;
        }

        // The mapper's own parent-company name, re-read because the trigger record
        // does not carry the Facility__r relationship.
        Map<Id, String> mapperIdToParentCompanyName = new Map<Id, String>();
        for (Facility_Mapper__c mapper : [
            SELECT Id, Facility__r.Parent_Company__r.Name
            FROM Facility_Mapper__c
            WHERE Id IN :qualifyingMapperIds
        ]) {
            mapperIdToParentCompanyName.put(
                mapper.Id,
                mapper.Facility__r == null ? null : mapper.Facility__r.Parent_Company__r.Name
            );
        }

        List<Leaked_Admission__c> toDelete = new List<Leaked_Admission__c>();
        for (Leaked_Admission__c leaked : [
            SELECT Id, Facility_Mapper__c, Patient__r.Facility__r.Parent_Company__r.Name
            FROM Leaked_Admission__c
            WHERE Facility_Mapper__c IN :qualifyingMapperIds
        ]) {
            String mapperCompany = mapperIdToParentCompanyName.get(leaked.Facility_Mapper__c);
            String leakedCompany = leaked.Patient__r == null || leaked.Patient__r.Facility__r == null
                ? null
                : leaked.Patient__r.Facility__r.Parent_Company__r.Name;

            // The flow's formula returned true only when both sides were equal.
            // Two nulls compare equal in Apex but the flow's `=` on two blank text
            // values also returned true, so null-null is a match in both.
            if (mapperCompany == leakedCompany) {
                toDelete.add(leaked);
            }
        }

        if (!toDelete.isEmpty()) {
        delete toDelete;
        }
    }
}
