/**
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
 */
public with sharing class FacilityMapperTriggerHandler {

    public static void afterUpdate(List<Facility_Mapper__c> newMappers, Map<Id, Facility_Mapper__c> oldMapperMap) {
        deleteFalseLeakedAdmissions(newMappers, oldMapperMap);
    }

    private static void deleteFalseLeakedAdmissions(List<Facility_Mapper__c> newMappers, Map<Id, Facility_Mapper__c> oldMapperMap) {

        // Flow entry criteria: Facility__c changed, and is not null.
        Set<Id> qualifyingMapperIds = new Set<Id>();
        for (Facility_Mapper__c mapper : newMappers) {
            Facility_Mapper__c priorMapper = oldMapperMap == null ? null : oldMapperMap.get(mapper.Id);
            Boolean facilityChanged = priorMapper == null || mapper.Facility__c != priorMapper.Facility__c;

            if (facilityChanged && mapper.Facility__c != null) {
                qualifyingMapperIds.add(mapper.Id);
            }
        }

        // No recursion guard here on purpose - this handler deletes Leaked_Admission__c
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
            WITH USER_MODE
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
            WITH USER_MODE
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
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, toDelete);
            delete decision.getRecords();
        }
    }
}
